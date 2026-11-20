// Version minimale : digest quotidien pour le suivi manuel. Lecture seule :
// aucune ecriture (instantane avec dates de mise a jour), aucun appel Stripe,
// un seul e-mail, aucun e-mail si la liste est vide. Sans cle ni reseau.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const mail = require('../merchant_contract_mail');
const stripeClientModule = require('../stripe_client');
const digest = require('../merchant_contract_digest');

const {db, admin} = h;
const {Timestamp} = admin.firestore;
const ts = (ms) => Timestamp.fromMillis(ms);
const kDay = 24 * 60 * 60 * 1000;
// Mardi 10 novembre 2026, 08:00 a Paris (07:00 UTC).
const kNow = Date.UTC(2026, 10, 10, 7, 0);
let stripeCalls = 0;

/** Instantane avec la date de mise a jour : une reecriture identique se voit aussi. */
async function snapshotWithTimes() {
  const out = {};
  async function walk(collections) {
    for (const collection of collections) {
      const snap = await collection.get();
      for (const doc of snap.docs) {
        out[doc.ref.path] = `${doc.updateTime.toMillis()}|${JSON.stringify(doc.data())}`;
        await walk(await doc.ref.listCollections());
      }
    }
  }
  await walk(await db.listCollections());
  return out;
}

const contract = (id, data) => db.doc(`merchant_contracts/${id}`).set({
  owner_uid: 'merchant', owner_email: `${id}@example.test`, enseigne_id: `e-${id}`, enseigne_name: `Boutique ${id}`,
  offer: {id: 'autonome', label: 'Autonome', renewal_ttc_cents: 43800}, ...data,
});
const mirror = (enseigneId, data) => db.doc(`enseigne_subscriptions/${enseigneId}`).set({
  enseigne_id: enseigneId, owner_uid: 'merchant', stripe_subscription_id: `sub_${enseigneId}`, cancel_at_period_end: false, ...data,
});

async function seedEverything() {
  // Retractation : ecoulee (a lister) et en cours (non).
  await contract('retract-ecoulee', {state: 'withdrawal_pending', origin: {type: 'demarchee'}, withdrawal_deadline: ts(kNow - kDay)});
  await contract('retract-en-cours', {state: 'withdrawal_pending', origin: {type: 'demarchee'}, withdrawal_deadline: ts(kNow + 2 * kDay)});
  // Liens : expire dans 2 jours, expire, dans 5 jours (non).
  await contract('lien-bientot', {state: 'payment_invited', payment_invited_at: ts(kNow - 13 * kDay), payment_link_expires_at: ts(kNow + 2 * kDay)});
  await contract('lien-expire', {state: 'payment_invited', payment_invited_at: ts(kNow - 20 * kDay), payment_link_expires_at: ts(kNow - 5 * kDay)});
  await contract('lien-loin', {state: 'payment_invited', payment_invited_at: ts(kNow - 10 * kDay), payment_link_expires_at: ts(kNow + 5 * kDay)});
  // Renouvellements : 40 jours, 10 jours, 60 jours (non), desactive (non), J-45 depasse (44 jours).
  for (const [id, days, extra] of [['renouv-40', 40, {}], ['renouv-10', 10, {}], ['renouv-60', 60, {}],
    ['renouv-desactive', 30, {cancel_at_period_end: true}], ['renouv-44', 44, {}]]) {
    await contract(id, {state: 'active'});
    await mirror(`e-${id}`, {contract_id: id, status: 'active', current_period_end: ts(kNow + days * kDay), ...extra});
  }
  // Grace : en cours, terminee.
  await contract('grace-en-cours', {state: 'active'});
  await mirror('e-grace-en-cours', {contract_id: 'grace-en-cours', status: 'past_due', grace_until: ts(kNow + 6 * kDay),
    last_failed_invoice_id: 'in_test_1', current_period_end: ts(kNow + 300 * kDay)});
  await contract('grace-finie', {state: 'active'});
  await mirror('e-grace-finie', {contract_id: 'grace-finie', status: 'unpaid', grace_until: ts(kNow - kDay),
    current_period_end: ts(kNow + 300 * kDay)});
  // Alertes : non traitees (a lister) et traitees (non).
  await db.doc('stripe_unmatched_events/evt_test_1').set({event_id: 'evt_test_1', event_type: 'invoice.paid',
    outcome: 'unmatched_contract_payment', reason: 'contrat_inconnu', resolved: false, created_at: ts(kNow - kDay)});
  await db.doc('stripe_unmatched_events/evt_test_2').set({event_id: 'evt_test_2', event_type: 'invoice.paid', resolved: true});
  await db.doc('admin_alerts/a1').set({kind: 'email_echec', detail: 'Echec test', contract_id: 'lien-bientot', resolved: false,
    created_at: ts(kNow - 2 * kDay)});
  await db.doc('admin_alerts/a2').set({kind: 'email_echec', detail: 'Deja traitee', resolved: true});
  // File de reprise : en attente, abandonnee, envoyee (non).
  await db.doc('mail_outbox/o1').set({kind: 'message', key: 'activation', contract_id: 'renouv-10', status: 'pending', attempts: 2,
    last_error: 'smtp', created_at: ts(kNow - kDay)});
  await db.doc('mail_outbox/o2').set({kind: 'message', key: 'withdrawal_ack', status: 'failed', attempts: 6, created_at: ts(kNow - 3 * kDay)});
  await db.doc('mail_outbox/o3').set({kind: 'message', key: 'deja', status: 'sent', attempts: 2});
}

test.beforeEach(async () => {
  await h.clearFirestore();
  stripeCalls = 0;
  stripeClientModule.getStripeClient = () => {
    stripeCalls += 1;
    throw new Error('aucun appel Stripe attendu');
  };
});
test.after(() => mail.setSender(null));

test('liste vide : aucun e-mail, aucune ecriture', async () => {
  await h.setConfig();
  // Rien a traiter : delai en cours, lien loin, renouvellement lointain, alertes traitees, e-mail envoye.
  await contract('retract-en-cours', {state: 'withdrawal_pending', withdrawal_deadline: ts(kNow + 2 * kDay)});
  await contract('actif', {state: 'active'});
  await mirror('e-actif', {contract_id: 'actif', status: 'active', current_period_end: ts(kNow + 200 * kDay)});
  await db.doc('admin_alerts/a2').set({kind: 'x', resolved: true});
  await db.doc('mail_outbox/o3').set({status: 'sent'});
  const sent = h.captureMail(mail);
  const before = await snapshotWithTimes();
  const result = await digest.runMerchantContractDigest({db, nowMs: kNow});
  assert.equal(result.sent, false);
  assert.equal(result.total, 0);
  assert.equal(sent.length, 0);
  assert.deepEqual(await snapshotWithTimes(), before);
  assert.equal(stripeCalls, 0);
});

test('un seul e-mail a l\'adresse des alertes, chaque rubrique ; rien d\'ecrit, aucun appel Stripe', async () => {
  await h.setConfig();
  await seedEverything();
  const sent = h.captureMail(mail);
  const before = await snapshotWithTimes();
  const result = await digest.runMerchantContractDigest({db, nowMs: kNow});
  assert.deepEqual(await snapshotWithTimes(), before, 'aucune ecriture');
  assert.equal(stripeCalls, 0, 'aucun appel Stripe');
  assert.equal(sent.length, 1, 'un seul e-mail');
  assert.equal(sent[0].to, 'alertes@proxiplay.test');
  assert.equal(result.total, 12);
  assert.match(sent[0].subject, /Suivi des souscriptions du 10\/11\/2026 : 12 point\(s\) à traiter/);
  const text = sent[0].text;
  const section = (title) => {
    const start = text.indexOf(`■ ${title}`);
    assert.ok(start >= 0, `rubrique absente : ${title}`);
    const end = text.indexOf('■', start + 1);
    return text.slice(start, end < 0 ? undefined : end);
  };
  assert.match(section('Rétractation écoulée'), /retract-ecoulee/);
  assert.doesNotMatch(text, /retract-en-cours/);
  assert.match(section('Liens de paiement qui expirent dans 3 jours'), /lien-bientot/);
  assert.match(section('Liens de paiement expirés'), /lien-expire/);
  assert.doesNotMatch(text, /lien-loin/);
  const r45 = section('Renouvellements dans 45 jours');
  assert.match(r45, /renouv-40 .*J-40\) · 438,00 € TTC · rappel art\. 9 au plus tard le 05\/11\/2026 · DATE DU RAPPEL DÉPASSÉE/);
  assert.match(r45, /renouv-44 .*J-44/);
  assert.doesNotMatch(r45, /renouv-10/);
  assert.match(section('Renouvellements dans 15 jours'), /renouv-10 .*J-10/);
  assert.doesNotMatch(text, /renouv-60|renouv-desactive/);
  assert.match(section('Délais de régularisation en cours'), /grace-en-cours .*past_due .*16\/11\/2026 · facture in_test_1/);
  assert.match(section('Délais de régularisation terminés'), /grace-finie .*unpaid .*09\/11\/2026/);
  assert.match(section('Événements Stripe non rattachés'), /evt_test_1\) .*unmatched_contract_payment \(contrat_inconnu\)/);
  assert.doesNotMatch(text, /evt_test_2/);
  assert.match(section('Alertes non traitées'), /email_echec · Echec test · demande lien-bientot/);
  assert.doesNotMatch(text, /Deja traitee/);
  const outbox = section('E-mails en file de reprise');
  assert.match(outbox, /« activation » · en attente \(2 tentative\(s\)\)/);
  assert.match(outbox, /« withdrawal_ack » · ABANDONNÉ/);
  assert.doesNotMatch(text, /« deja »/);
  assert.doesNotMatch(text, /checkout\.stripe\.com|buy\.stripe\.com/);
});

test('J-45 dans les temps : date du rappel non depassee ; J-46 liste, J-47 non', async () => {
  await h.setConfig();
  for (const [id, days] of [['j46', 46], ['j47', 47]]) {
    await contract(id, {state: 'active'});
    await mirror(`e-${id}`, {contract_id: id, status: 'active', current_period_end: ts(kNow + days * kDay)});
  }
  const sent = h.captureMail(mail);
  await digest.runMerchantContractDigest({db, nowMs: kNow});
  assert.match(sent[0].text, /j46 .*J-46\) .*rappel art\. 9 au plus tard le 11\/11\/2026/);
  assert.doesNotMatch(sent[0].text, /j46 .*DÉPASSÉE/);
  assert.doesNotMatch(sent[0].text, /j47/);
});

test('independant de l\'interrupteur ; adresse par defaut si aucune adresse d\'alerte', async () => {
  await db.doc('app_config/merchant_contracts').set({enabled: false});
  await contract('lien-expire', {state: 'payment_invited', payment_invited_at: ts(kNow - 20 * kDay), payment_link_expires_at: ts(kNow - 5 * kDay)});
  const sent = h.captureMail(mail);
  const result = await digest.runMerchantContractDigest({db, nowMs: kNow});
  assert.equal(result.sent, true);
  assert.equal(sent[0].to, 'contact@proxiplay.fr');
});

test('echec SMTP : rejete (nouvelle tentative de Cloud Scheduler), toujours aucune ecriture', async () => {
  await h.setConfig();
  await seedEverything();
  h.captureMail(mail, {fail: true});
  const before = await snapshotWithTimes();
  await assert.rejects(digest.runMerchantContractDigest({db, nowMs: kNow}), /smtp indisponible/);
  assert.deepEqual(await snapshotWithTimes(), before);
  assert.equal(stripeCalls, 0);
});

test('tache planifiee : tous les jours a 8 h, heure de Paris, avec nouvelles tentatives ; aucun module Stripe', () => {
  const endpoint = digest.merchantContractDigest.__endpoint;
  assert.equal(endpoint.scheduleTrigger.schedule, '0 8 * * *');
  assert.equal(endpoint.scheduleTrigger.timeZone, 'Europe/Paris');
  assert.equal(endpoint.scheduleTrigger.retryConfig.retryCount, 3);
  const source = fs.readFileSync(path.join(__dirname, '..', 'merchant_contract_digest.js'), 'utf8');
  assert.doesNotMatch(source, /require\(["']\.\/stripe|require\(["']stripe["']\)/);
  assert.doesNotMatch(source, /\.(set|update|add|delete|create)\(/, 'aucune methode d\'ecriture dans le module');
  assert.doesNotMatch(source, /runTransaction|batch\(/);
});

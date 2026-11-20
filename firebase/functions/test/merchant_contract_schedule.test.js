// Phase 1, tranche 2b, lot 1.9 : taches planifiees (heure de Paris,
// idempotentes, inertes interrupteur coupe). Emulateur Firestore, projet
// demo- ; Stripe remplace par un double (aucun reseau, aucune cle).
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const stripeClientModule = require('../stripe_client');
const mail = require('../merchant_contract_mail');
const payment = require('../merchant_contract_payment');
const billing = require('../merchant_contract_billing');
const schedule = require('../merchant_contract_schedule');
const {parisDate, addDays, endOfParisDay} = require('../paris_time');

const {db} = h;
const {Timestamp} = h.admin.firestore;
const kDay = 86400000;
const ts = (ms) => Timestamp.fromMillis(ms);
let sent;
let stripeCalls;
let sessions;

function useStripe() {
  stripeCalls = [];
  sessions = {};
  stripeClientModule.getStripeClient = () => ({
    checkout: {sessions: {retrieve: async (id) => {
      stripeCalls.push(['checkout.sessions.retrieve', id]);
      return sessions[id] || null;
    }}},
  });
}

const offer = {id: 'autonome', label: 'Autonome', currency: 'eur', vat_rate_basis_points: 2000, catalog_ht_cents: 36500,
  discount_ht_cents: 0, first_year_ht_cents: 36500, first_year_ttc_cents: 43800, renewal_ht_cents: 36500,
  renewal_ttc_cents: 43800, duration_months: 12};

async function seedContract(id, fields = {}, internal = {}) {
  await db.doc(`merchant_contracts/${id}`).set({
    owner_uid: 'merchant', owner_email: 'merchant@example.test', state: 'active', state_version: 3,
    enseigne_id: 'e1', enseigne_name: 'Boutique e1', siret: '98896837600018', raison_sociale: 'PROXIPLAY TEST SAS',
    offer, origin: {type: 'spontanee'}, cgv: {version: '2.1', sha256: h.kCgvSha256}, ...fields,
  });
  await db.doc(`merchant_contracts/${id}/internal/record`).set({emails: {}, ...internal});
}

async function seedToken(id, contractId, expiresMs) {
  await db.doc(`payment_tokens/${id}`).set({contract_id: contractId, owner_uid: 'merchant', enseigne_id: 'e1',
    created_at: ts(Date.now() - 10 * kDay), sent_at: ts(Date.now() - 10 * kDay), expires_at: ts(expiresMs),
    revoked_at: null, first_used_at: null, last_session_id: null});
}

async function seedMirror(enseigneId, fields) {
  await db.doc(`enseigne_subscriptions/${enseigneId}`).set({enseigne_id: enseigneId, owner_uid: 'merchant',
    contract_id: 'c1', stripe_subscription_id: 'sub_1', status: 'active', cancel_at_period_end: false, cancel_at: null,
    grace_until: null, grace_started_at: null, ...fields});
}

const contract = async (id = 'c1') => (await db.doc(`merchant_contracts/${id}`).get()).data();
const internal = async (id = 'c1') => (await db.doc(`merchant_contracts/${id}/internal/record`).get()).data();
const alerts = async (kind) => (await db.collection('admin_alerts').where('kind', '==', kind).get()).size;
const run = (nowMs = Date.now()) => schedule.runMerchantContractSchedule({db, nowMs});

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  sent = h.captureMail(mail);
  useStripe();
});
test.after(() => mail.setSender(null));

// --- Interrupteur --------------------------------------------------------------

test('interrupteur coupe (false, absent, "true") : aucune ecriture, aucun e-mail, aucun appel Stripe', async () => {
  const now = Date.now();
  await seedContract('c_retract', {state: 'withdrawal_pending', origin: {type: 'demarchee'}, withdrawal_deadline: ts(now - 3600000)});
  await seedContract('c_rappel', {state: 'payment_invited', payment_invited_at: ts(now - 11 * kDay), payment_link_expires_at: ts(now + 4 * kDay)});
  await seedContract('c_cloture', {state: 'payment_invited', payment_invited_at: ts(now - 16 * kDay), payment_link_expires_at: ts(now - 3600000)},
    {payment_invitation: {reminder_sent_at: ts(now - 6 * kDay)}, checkout: {session_id: 'cs_1'}});
  sessions.cs_1 = {id: 'cs_1', status: 'expired'};
  await seedContract('c1');
  await seedMirror('e1', {current_period_end: ts(now + 40 * kDay)});
  await seedMirror('e2', {contract_id: 'c1', status: 'past_due', last_failed_invoice_id: 'in_1',
    grace_started_at: ts(now - 20 * kDay), grace_until: ts(now - 5 * kDay)});
  for (const config of [{enabled: false}, {enabled: 'true'}, null]) {
    if (config) await h.setConfig(config);
    else await db.doc('app_config/merchant_contracts').delete();
    const before = await h.snapshotAll();
    const result = await run(now);
    assert.deepEqual(result, {skipped: 'disabled'}, JSON.stringify(config));
    assert.deepEqual(await h.snapshotAll(), before, `rien d'ecrit (${JSON.stringify(config)})`);
    assert.equal(sent.length, 0);
    assert.deepEqual(stripeCalls, []);
  }
});

test('la fonction planifiee est de 2e generation, horaire, en heure de Paris', () => {
  const endpoint = schedule.merchantContractSchedule.__endpoint;
  assert.equal(endpoint.platform, 'gcfv2');
  assert.equal(endpoint.scheduleTrigger.schedule, '0 * * * *');
  assert.equal(endpoint.scheduleTrigger.timeZone, 'Europe/Paris');
  assert.deepEqual(endpoint.secretEnvironmentVariables.map((s) => s.key), ['STRIPE_SECRET_KEY']);
});

// --- 1. Fin du delai de retractation -------------------------------------------

test('fin du delai de retractation : invitation une seule fois, pas avant la fin du 14e jour', async () => {
  const now = Date.now();
  await seedContract('c1', {state: 'withdrawal_pending', origin: {type: 'demarchee'}, withdrawal_deadline: ts(now + 3600000)});
  await run(now);
  assert.equal((await contract()).state, 'withdrawal_pending');
  assert.equal(sent.length, 0);
  await db.doc('merchant_contracts/c1').update({withdrawal_deadline: ts(now - 60000)});
  const stats = await run(now);
  assert.equal(stats.withdrawal_end.invited, 1);
  const c = await contract();
  assert.equal(c.state, 'payment_invited');
  assert.ok(c.payment_invited_at && c.payment_link_expires_at);
  assert.equal(sent.filter((m) => /invitation à régler/.test(m.subject)).length, 1);
  await run(now);
  await run(now + 3600000);
  assert.equal(sent.filter((m) => /invitation à régler/.test(m.subject)).length, 1, 'idempotent');
});

// --- 2. Rappel de paiement --------------------------------------------------------

test('rappel de paiement a J+10 (Paris) : nouveau lien, meme expiration, ancien revoque, une seule fois', async () => {
  const now = Date.now();
  const expires = now + 5 * kDay;
  await seedContract('c1', {state: 'payment_invited', payment_invited_at: ts(now - 9 * kDay), payment_link_expires_at: ts(expires)});
  await seedToken('old', 'c1', expires);
  await run(now);
  assert.equal(sent.length, 0, 'J+9 : rien');
  await db.doc('merchant_contracts/c1').update({payment_invited_at: ts(now - 10 * kDay)});
  await run(now);
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /rappel/);
  assert.match(sent[0].text, /\?paiement=[A-Za-z0-9_-]{40,}/);
  assert.equal((await contract()).payment_link_expires_at.toMillis(), expires, 'expiration inchangee');
  assert.ok((await db.doc('payment_tokens/old').get()).data().revoked_at, 'ancien lien remplace');
  const fresh = (await db.collection('payment_tokens').where('revoked_at', '==', null).get()).docs;
  assert.equal(fresh.length, 1);
  assert.equal(fresh[0].data().expires_at.toMillis(), expires);
  assert.ok((await internal()).payment_invitation.reminder_sent_at);
  await run(now + 3600000);
  assert.equal(sent.length, 1, 'idempotent');
});

test('rappel en echec SMTP : file de reprise, aucun renvoi horaire ; lien deja expire : alerte, pas de rappel', async () => {
  const now = Date.now();
  await seedContract('c1', {state: 'payment_invited', payment_invited_at: ts(now - 10 * kDay), payment_link_expires_at: ts(now + 5 * kDay)});
  h.captureMail(mail, {fail: true});
  const stats = await run(now);
  assert.equal(stats.payment_reminders.queued, 1);
  assert.ok((await internal()).payment_invitation.reminder_queued_at);
  const outbox = (await db.collection('mail_outbox').get()).docs.map((d) => d.data());
  assert.deepEqual(outbox.map((o) => [o.kind, o.key]), [['payment_invitation', 'payment_reminder']]);
  await run(now + 3600000);
  assert.equal((await db.collection('mail_outbox').get()).size, 1);
  // La reprise envoie le rappel (gabarit de rappel).
  sent = h.captureMail(mail);
  await mail.runMailOutbox({db, nowMs: now + 3 * 3600000});
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /rappel/);
  assert.ok((await internal()).payment_invitation.reminder_sent_at);

  await seedContract('c2', {state: 'payment_invited', payment_invited_at: ts(now - 20 * kDay), payment_link_expires_at: ts(now - 5 * kDay)});
  sent.length = 0;
  await run(now);
  await run(now + 3600000);
  assert.equal(sent.filter((m) => m.to === 'merchant@example.test').length, 0);
  assert.equal(await alerts('planifie_rappel_paiement'), 1, 'une alerte par jour');
  assert.equal((await contract('c2')).state, 'payment_invited', 'pas de cloture sans rappel');
});

// --- 3. Cloture a 15 jours ---------------------------------------------------------

test('cloture : apres le rappel et l\'expiration de la derniere session relue chez Stripe ; jamais avant', async () => {
  const now = Date.now();
  const expires = now - 3600000;
  await seedContract('c1', {state: 'payment_invited', payment_invited_at: ts(now - 16 * kDay), payment_link_expires_at: ts(expires)},
    {payment_invitation: {reminder_sent_at: ts(now - 6 * kDay)}, checkout: {session_id: 'cs_1'}});
  await seedToken('tok', 'c1', expires);
  for (const status of ['open', 'complete']) {
    sessions.cs_1 = {id: 'cs_1', status};
    const stats = await run(now);
    assert.equal(stats.closures.session_open, 1, status);
    assert.equal((await contract()).state, 'payment_invited', `session ${status} : pas de cloture`);
  }
  // Session en cours de creation (verrou recent) : on attend.
  await db.doc('merchant_contracts/c1/internal/record').set({checkout: {lock_at: ts(now - 10000)}}, {merge: true});
  sessions.cs_1 = {id: 'cs_1', status: 'expired'};
  await run(now);
  assert.equal((await contract()).state, 'payment_invited');
  await db.doc('merchant_contracts/c1/internal/record').set({checkout: {lock_at: h.admin.firestore.FieldValue.delete()}}, {merge: true});
  await run(now);
  const c = await contract();
  assert.equal(c.state, 'closed_unpaid');
  assert.equal(c.closed_at.toMillis(), now);
  assert.ok((await db.doc('payment_tokens/tok').get()).data().revoked_at);
  const closure = sent.filter((m) => /close sans paiement/.test(m.subject));
  assert.equal(closure.length, 1);
  assert.match(closure[0].text, /rien n'est facturé/);
  assert.ok(stripeCalls.every(([name]) => name === 'checkout.sessions.retrieve'), 'seule une lecture Stripe');
  await run(now + 3600000);
  assert.equal(sent.filter((m) => /close sans paiement/.test(m.subject)).length, 1, 'idempotent');
});

test('cloture : sans session, apres le rappel ; sans rappel, alerte et aucune cloture ; lien non expire, rien', async () => {
  const now = Date.now();
  await seedContract('c1', {state: 'payment_invited', payment_invited_at: ts(now - 16 * kDay), payment_link_expires_at: ts(now - 60000)},
    {payment_invitation: {reminder_sent_at: ts(now - 6 * kDay)}});
  await seedContract('c2', {state: 'payment_invited', payment_invited_at: ts(now - 16 * kDay), payment_link_expires_at: ts(now - 60000)});
  await seedContract('c3', {state: 'payment_invited', payment_invited_at: ts(now - 14 * kDay), payment_link_expires_at: ts(now + 60000)},
    {payment_invitation: {reminder_sent_at: ts(now - 4 * kDay)}});
  await run(now);
  assert.equal((await contract('c1')).state, 'closed_unpaid');
  assert.equal((await contract('c2')).state, 'payment_invited');
  assert.equal((await contract('c3')).state, 'payment_invited');
  assert.equal(await alerts('planifie_cloture'), 1);
  assert.deepEqual(stripeCalls, [], 'aucune session : aucune lecture Stripe');
});

test('paiement arrive pendant la marge de 31 min : session encore ouverte, la cloture attend', async () => {
  const now = Date.now();
  await seedContract('c1', {state: 'payment_invited', payment_invited_at: ts(now - 16 * kDay), payment_link_expires_at: ts(now - 20 * 60000)},
    {payment_invitation: {reminder_sent_at: ts(now - 6 * kDay)}, checkout: {session_id: 'cs_1'}});
  sessions.cs_1 = {id: 'cs_1', status: 'open', expires_at: Math.floor((now + 11 * 60000) / 1000)};
  await run(now);
  assert.equal((await contract()).state, 'payment_invited', 'le paiement dans la marge pourra activer le contrat');
});

// --- 4. Rappels de renouvellement -----------------------------------------------------

test('rappels de renouvellement : J-45 (des J-46) puis J-15, une fois chacun ; desactive : aucun', async () => {
  const now = Date.now();
  const renewal = now + 47 * kDay;
  await seedContract('c1');
  await seedMirror('e1', {current_period_end: ts(renewal)});
  await run(now);
  assert.equal(sent.length, 0, 'J-47 : rien');
  const at46 = renewal - 46 * kDay;
  await run(at46);
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /renouvellement de votre abonnement le/);
  assert.match(sent[0].text, /438,00 € TTC/);
  assert.match(sent[0].text, /Désactiver le renouvellement/);
  assert.match(sent[0].text, /quarante-cinq jours avant l'échéance \(CGV art\. 9\)/);
  await run(at46 + 3600000);
  assert.equal(sent.length, 1, 'idempotent');
  const id = schedule.reminderDocId('sub_1', renewal);
  // Echeance du rappel passee : envoye a temps.
  const deadline = schedule.renewalReminderDeadline(renewal, 45);
  await run(deadline + 3600000);
  assert.equal((await db.doc(`renewal_reminders/${id}`).get()).data().j45.missed, false);
  await run(renewal - 15 * kDay);
  assert.equal(sent.length, 2);
  assert.doesNotMatch(sent[1].text, /quarante-cinq/, 'le J-15 ne cite pas les CGV');
  await run(renewal - 15 * kDay + 3600000);
  assert.equal(sent.length, 2);
  // Renouvellement desactive : plus aucun rappel.
  await seedMirror('e1', {current_period_end: ts(now + 46 * kDay), cancel_at_period_end: true, stripe_subscription_id: 'sub_2'});
  await run(now);
  assert.equal(sent.length, 2);
});

test('rappel J-45 envoye en retard ou jamais envoye : missed, alerte admin', async () => {
  const now = Date.now();
  await seedContract('c1');
  await seedMirror('e1', {current_period_end: ts(now + 40 * kDay)});
  await run(now);
  const late = (await db.doc(`renewal_reminders/${schedule.reminderDocId('sub_1', now + 40 * kDay)}`).get()).data().j45;
  assert.equal(late.missed, true);
  assert.equal(late.missed_reason, 'envoye_apres_echeance');
  assert.equal(await alerts('rappel_renouvellement_manque'), 1);

  // SMTP en panne jusqu'apres l'echeance du rappel : missed.
  await h.clearFirestore();
  await h.setConfig();
  await seedContract('c1');
  const renewal = now + 46 * kDay;
  await seedMirror('e1', {current_period_end: ts(renewal)});
  h.captureMail(mail, {fail: true});
  await run(now);
  const id = schedule.reminderDocId('sub_1', renewal);
  assert.equal((await db.doc(`renewal_reminders/${id}`).get()).data().j45.status, 'queued');
  await run(schedule.renewalReminderDeadline(renewal, 45) + 60000);
  assert.equal((await db.doc(`renewal_reminders/${id}`).get()).data().j45.missed, true);
});

test('rappel J-45 parti par la file de reprise avant son echeance : a temps', async () => {
  const now = Date.now();
  const renewal = now + 46 * kDay;
  await seedContract('c1');
  await seedMirror('e1', {current_period_end: ts(renewal)});
  h.captureMail(mail, {fail: true});
  await run(now);
  sent = h.captureMail(mail);
  await mail.runMailOutbox({db, nowMs: now + 3600000});
  assert.equal(sent.length, 1);
  await run(schedule.renewalReminderDeadline(renewal, 45) + 60000);
  assert.equal((await db.doc(`renewal_reminders/${schedule.reminderDocId('sub_1', renewal)}`).get()).data().j45.missed, false);
});

test('aucune trace de rappel a l\'echeance du rappel (ex. interrupteur coupe) : missed « aucun_envoi »', async () => {
  const now = Date.now();
  const renewal = now + 20 * kDay;
  await seedContract('c1');
  await seedMirror('e1', {current_period_end: ts(renewal)});
  await schedule.runMerchantContractSchedule({db, nowMs: now}); // envoie le J-15 ? non : J-20
  const doc = (await db.doc(`renewal_reminders/${schedule.reminderDocId('sub_1', renewal)}`).get()).data();
  // Le J-45 est envoye en retard (missed) a la premiere execution.
  assert.equal(doc.j45.missed, true);
  // Abonnement jamais vu avant l'echeance du rappel et deja a J-15 : trace absente creee.
  await seedMirror('e2', {contract_id: 'c1', stripe_subscription_id: 'sub_9', current_period_end: ts(now + 10 * kDay)});
  await run(now);
  const absent = (await db.doc(`renewal_reminders/${schedule.reminderDocId('sub_9', now + 10 * kDay)}`).get()).data();
  assert.equal(absent.j45.missed, true);
  assert.equal(absent.j45.missed_reason, 'aucun_envoi');
  assert.ok(absent.j15, 'le J-15 part quand meme');
});

// --- 5. Relances de grace et 6. fin de grace -------------------------------------------

test('grace : J0 du webhook, relances J+5 et J+10 une fois, puis fin de grace notifiee une fois', async () => {
  const start = Date.UTC(2027, 2, 1, 10, 0, 0);
  const graceUntil = start + 15 * kDay;
  await seedContract('c1', {}, {renewal_failures: {in_1: {notified_at: ts(start)}}});
  await seedMirror('e1', {status: 'past_due', last_failed_invoice_id: 'in_1', grace_started_at: ts(start), grace_until: ts(graceUntil),
    unpaid_invoice_url: 'https://invoice.stripe.com/i/test'});
  await run(start + 3600000);
  assert.equal(sent.length, 0, 'J0 deja notifie par le webhook');
  await run(start + 5 * kDay);
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /relance, renouvellement impayé/);
  assert.match(sent[0].text, /relance à 5 jours/);
  await run(start + 7 * kDay);
  await run(start + 10 * kDay);
  await run(start + 10 * kDay + 3600000);
  assert.equal(sent.length, 2);
  assert.match(sent[1].text, /relance à 10 jours/);
  await run(graceUntil - 60000);
  assert.equal((await db.doc('enseigne_subscriptions/e1').get()).data().suspended_at ?? null, null);
  await run(graceUntil + 3600000);
  await run(graceUntil + 7200000);
  const mirror = (await db.doc('enseigne_subscriptions/e1').get()).data();
  assert.ok(mirror.suspended_at);
  assert.equal(sent.filter((m) => /délai de régularisation expiré/.test(m.subject)).length, 1);
  assert.equal(await alerts('fin_de_grace'), 1);
  assert.equal((await contract()).state, 'active', 'aucune fin de contrat automatique (art. 11 : mise en demeure)');
});

test('grace sans notification du webhook : J0 envoye par la tache ; regularisation : suspension levee', async () => {
  const start = Date.now() - 3600000;
  await seedContract('c1', {}, {billing: {stripe_subscription_id: 'sub_1'}});
  await seedMirror('e1', {status: 'past_due', last_failed_invoice_id: 'in_2', grace_started_at: ts(start), grace_until: ts(start + 15 * kDay)});
  await run(Date.now());
  assert.equal(sent.length, 1);
  assert.doesNotMatch(sent[0].text, /relance à/);
  await run(Date.now() + 60000);
  assert.equal(sent.length, 1);
  await db.doc('enseigne_subscriptions/e1').update({suspended_at: ts(Date.now())});
  const result = await billing.syncContractSubscription(db, {id: 'sub_1', status: 'active', customer: 'cus_1', livemode: false,
    metadata: {contractId: 'c1', enseigneId: 'e1'}, current_period_start: Math.floor(Date.now() / 1000),
    current_period_end: Math.floor(Date.now() / 1000) + 365 * 86400}, 'evt_paid');
  assert.equal(result.outcome, 'contract_synced');
  assert.equal((await db.doc('enseigne_subscriptions/e1').get()).data().suspended_at, null);
});

test('jours de Paris : J+10 compte en dates de Paris, pas en tranches de 24 h', () => {
  // Invitation le 1er mars a 23 h 30 (Paris) : J+10 = 11 mars des 0 h, heure de Paris.
  const invited = Date.UTC(2027, 2, 1, 22, 30);
  assert.equal(schedule.parisDaysBetween(invited, Date.UTC(2027, 2, 10, 22, 59)), 9);
  assert.equal(schedule.parisDaysBetween(invited, Date.UTC(2027, 2, 10, 23, 1)), 10);
  // Echeance du rappel J-45 : fin du jour de Paris echeance - 45, changement d'heure compris.
  const renewal = Date.UTC(2027, 4, 15, 8, 0);
  assert.equal(schedule.renewalReminderDeadline(renewal, 45), endOfParisDay(addDays(parisDate(renewal), -45)));
});

test('payment.issuePaymentInvitation en rappel garde l\'expiration et n\'est possible qu\'a payment_invited', async () => {
  await seedContract('c1', {state: 'active'});
  await h.rejectsWith(payment.issuePaymentInvitation(db, 'c1', {reminder: true}), 'not_payment_invited');
});

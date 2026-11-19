// Phase 1, tranche 1, lot 1.3 : alertes a un jour ouvre et au-dela de deux.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const paris = require('../paris_time');
const {runMerchantContractAlerts} = require('../merchant_contract_alerts');

const {db, admin} = h;
const {Timestamp} = admin.firestore;
const iso = (ms) => new Date(ms).toISOString();
const parisMs = (y, m, d, hh = 0, mi = 0) => paris.parisLocalToUtc(y, m, d, hh, mi);

test('Paques et jours feries francais', () => {
  assert.deepEqual(paris.easterSunday(2025), {y: 2025, m: 4, d: 20});
  assert.deepEqual(paris.easterSunday(2026), {y: 2026, m: 4, d: 5});
  assert.deepEqual(paris.easterSunday(2027), {y: 2027, m: 3, d: 28});
  const holidays = [...paris.frenchHolidays(2026)].sort();
  assert.deepEqual(holidays, ['2026-01-01', '2026-04-06', '2026-05-01', '2026-05-08', '2026-05-14', '2026-05-25',
    '2026-07-14', '2026-08-15', '2026-11-01', '2026-11-11', '2026-12-25']);
  assert.equal(paris.isBusinessDay({y: 2026, m: 1, d: 5}), true, 'lundi');
  assert.equal(paris.isBusinessDay({y: 2026, m: 1, d: 10}), false, 'samedi');
  assert.equal(paris.isBusinessDay({y: 2026, m: 5, d: 14}), false, 'Ascension');
});

test('jours ouvres : heure de Paris conservee, week-ends, feries, heure d\'ete', () => {
  // Lundi 5 janvier 10 h -> mardi 10 h, mercredi 10 h.
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 1, 5, 10), 1)), iso(parisMs(2026, 1, 6, 10)));
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 1, 5, 10), 2)), iso(parisMs(2026, 1, 7, 10)));
  // Vendredi 9 janvier 15 h -> lundi 12, mardi 13.
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 1, 9, 15), 1)), iso(parisMs(2026, 1, 12, 15)));
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 1, 9, 15), 2)), iso(parisMs(2026, 1, 13, 15)));
  // Samedi 10 janvier : compte a partir de lundi 0 h -> mardi 13 a 0 h.
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 1, 10, 10), 1)), iso(parisMs(2026, 1, 13, 0)));
  // Mercredi 13 mai 9 h (veille de l'Ascension) -> vendredi 15, lundi 18.
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 5, 13, 9), 1)), iso(parisMs(2026, 5, 15, 9)));
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 5, 13, 9), 2)), iso(parisMs(2026, 5, 18, 9)));
  // Jeudi 24 decembre 10 h -> lundi 28 (25 ferie, puis week-end).
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 12, 24, 10), 1)), iso(parisMs(2026, 12, 28, 10)));
  // Vendredi 27 mars 10 h (UTC+1) -> lundi 30 mars 10 h (UTC+2).
  assert.equal(iso(paris.addBusinessDays(parisMs(2026, 3, 27, 10), 1)), '2026-03-30T08:00:00.000Z');
});

const submitted = parisMs(2026, 1, 5, 10); // lundi 5 janvier 2026, 10 h
let sent;

async function seedContract(id, extra = {}) {
  await db.doc(`merchant_contracts/${id}`).set({
    owner_uid: 'merchant', owner_email: 'merchant@example.test', state: 'submitted', state_version: 1,
    enseigne_id: id, enseigne_name: `Boutique ${id}`, offer: {label: 'Autonome'},
    submitted_at: Timestamp.fromMillis(submitted), ...extra,
  });
  await db.doc(`merchant_contracts/${id}/internal/record`).set({alerts: {}, emails: {}});
}

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  sent = h.captureMail(mail);
});
test.after(() => mail.setSender(null));

test('interrupteur coupe : aucune lecture des demandes, aucun e-mail, aucune ecriture', async () => {
  await seedContract('c1');
  await h.setConfig({enabled: false});
  const before = await h.snapshotAll();
  assert.deepEqual(await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 20)}), {skipped: 'contracts_disabled'});
  assert.deepEqual(await h.snapshotAll(), before);
  assert.equal(sent.length, 0);
});

test('avant un jour ouvre : rien ; apres un jour ouvre : alerte une seule fois', async () => {
  await seedContract('c1');
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 9, 59)});
  assert.equal(sent.length, 0);
  const stats = await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 10, 0)});
  assert.equal(stats.first, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'alertes@proxiplay.test');
  assert.match(sent[0].subject, /en attente depuis un jour ouvré/);
  assert.match(sent[0].text, /Aucune validation tacite ni refus automatique/);
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 11)});
  assert.equal(sent.length, 1, 'jamais deux fois');
  const internal = (await db.doc('merchant_contracts/c1/internal/record').get()).data();
  assert.ok(internal.alerts.first.sent_at);
  assert.ok(!('claimed_at' in internal.alerts.first));
});

test('au-dela de deux jours ouvres : alerte prioritaire une seule fois, plus d\'alerte simple ensuite', async () => {
  await seedContract('c1');
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 12)});
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 7, 10, 1)});
  assert.deepEqual(sent.map((m) => /PRIORITAIRE/.test(m.subject)), [false, true]);
  assert.match(sent[1].text, /ni confirmée ni refusée dans le délai maximal de deux jours ouvrés/);
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 8)});
  assert.equal(sent.length, 2);
});

test('demande decouverte en retard : seule l\'alerte prioritaire part', async () => {
  await seedContract('c1');
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 9)});
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 10)});
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /PRIORITAIRE/);
});

test('demande confirmee ou refusee : aucune alerte ; la tache ne decide jamais', async () => {
  await seedContract('conf', {state: 'confirmed'});
  await seedContract('ref', {state: 'refused'});
  await seedContract('pending');
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 20)});
  assert.equal(sent.length, 1);
  assert.match(sent[0].text, /Demande : pending/);
  for (const id of ['conf', 'ref', 'pending']) {
    const state = (await db.doc(`merchant_contracts/${id}`).get()).data().state;
    assert.equal(state, {conf: 'confirmed', ref: 'refused', pending: 'submitted'}[id], 'aucune validation tacite ni refus automatique');
  }
});

test('echec SMTP : trace, puis nouvel essai a l\'execution suivante', async () => {
  await seedContract('c1');
  h.captureMail(mail, {fail: true});
  const failed = await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 10, 30)});
  assert.equal(failed.failed, 1);
  let internal = (await db.doc('merchant_contracts/c1/internal/record').get()).data();
  assert.match(internal.alerts.first.error, /smtp indisponible/);
  sent = h.captureMail(mail);
  await runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 11, 30)});
  assert.equal(sent.length, 1);
  internal = (await db.doc('merchant_contracts/c1/internal/record').get()).data();
  assert.ok(internal.alerts.first.sent_at);
});

test('deux executions simultanees : une seule alerte', async () => {
  await seedContract('c1');
  await Promise.all([
    runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 10, 30)}),
    runMerchantContractAlerts({nowMs: parisMs(2026, 1, 6, 10, 30)}),
  ]);
  assert.equal(sent.length, 1);
});

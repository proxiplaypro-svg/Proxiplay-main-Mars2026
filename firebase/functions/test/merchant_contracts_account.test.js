// Phase 1, tranche 1, lot 1.0 : lecture par le commercant de ses demandes.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const {getMyMerchantContractsHandler} = require('../merchant_contracts_account');

const {db} = h;

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.seedMerchant('merchant');
  await h.seedMerchant('other');
  await h.seedEnseigne('e1', 'merchant');
  await h.seedEnseigne('e2', 'other');
  await db.doc('merchant_contracts/c1').set({
    owner_uid: 'merchant', state: 'refused', enseigne_id: 'e1', enseigne_name: 'Boutique e1',
    public_refusal: {motif: 'activity', detail: 'Activite exclue'},
    submitted_at: h.admin.firestore.Timestamp.fromMillis(1000),
  });
  await db.doc('merchant_contracts/c1/internal/record').set({refusal_reason: 'note interne', acceptance: {ip: '203.0.113.9'}});
  await db.doc('merchant_contracts/c2').set({owner_uid: 'other', state: 'submitted', enseigne_id: 'e2'});
});

test('interrupteur absent ou faux : reponse {enabled:false}, aucune donnee', async () => {
  assert.deepEqual(await getMyMerchantContractsHandler({}, h.merchantContext()), {enabled: false});
  await h.setConfig({enabled: false});
  assert.deepEqual(await getMyMerchantContractsHandler({}, h.merchantContext()), {enabled: false});
  await h.setConfig({enabled: 'true'});
  assert.deepEqual(await getMyMerchantContractsHandler({}, h.merchantContext()), {enabled: false}, 'seul le booleen true active');
});

test('interrupteur actif : ses contrats seulement, vue filtree, ses enseignes, catalogue HT et TTC', async () => {
  await h.setConfig();
  const result = await getMyMerchantContractsHandler({}, h.merchantContext());
  assert.equal(result.enabled, true);
  assert.deepEqual(result.contracts.map((c) => c.id), ['c1']);
  assert.deepEqual(result.contracts[0].refusal, {motif: 'activity', detail: 'Activite exclue'});
  assert.ok(!JSON.stringify(result).includes('note interne'));
  assert.ok(!JSON.stringify(result).includes('203.0.113.9'));
  assert.deepEqual(result.enseignes.map((e) => e.id), ['e1']);
  assert.deepEqual(result.offers.map((o) => [o.id, o.amountHtCents, o.amountTtcCents]),
    [['autonome', 36500, 43800], ['accompagnee', 100000, 120000]]);
  assert.equal(result.cgv.version, '2.1');
});

test('reserve aux comptes commercants connectes', async () => {
  await h.setConfig();
  await h.rejectsWith(getMyMerchantContractsHandler({}, {}), 'unauthenticated');
  await db.doc('users/player').set({user_role: 'joueur'});
  await h.rejectsWith(getMyMerchantContractsHandler({}, h.merchantContext('player')), 'permission-denied');
});

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

test('ventes en pause (interrupteur absent ou faux), aucun contrat : reponse {enabled:false}', async () => {
  await h.seedMerchant('empty');
  assert.deepEqual(await getMyMerchantContractsHandler({}, h.merchantContext('empty')), {enabled: false});
  await h.setConfig({enabled: false});
  assert.deepEqual(await getMyMerchantContractsHandler({}, h.merchantContext('empty')), {enabled: false});
  await h.setConfig({enabled: 'true'});
  assert.deepEqual(await getMyMerchantContractsHandler({}, h.merchantContext('empty')), {enabled: false}, 'seul le booleen true ouvre les ventes');
});

// Correctif t2b : l'interrupteur ne met en pause que les nouvelles ventes.
test('ventes en pause, contrats existants : toujours visibles, sans catalogue ni enseignes (pas de nouvelle demande)', async () => {
  for (const config of [null, {enabled: false}, {enabled: 'true'}]) {
    if (config) await h.setConfig(config);
    const result = await getMyMerchantContractsHandler({}, h.merchantContext());
    assert.equal(result.enabled, true);
    assert.equal(result.salesOpen, false);
    assert.deepEqual(result.contracts.map((c) => c.id), ['c1']);
    assert.deepEqual(result.offers, []);
    assert.deepEqual(result.enseignes, []);
    assert.ok(!JSON.stringify(result).includes('note interne'));
  }
});

test('interrupteur actif : ses contrats seulement, vue filtree, ses enseignes, catalogue HT et TTC', async () => {
  await h.setConfig();
  const result = await getMyMerchantContractsHandler({}, h.merchantContext());
  assert.equal(result.enabled, true);
  assert.equal(result.salesOpen, true);
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

// Tranche 2a, lot 1.8 : abonnement de l'enseigne dans la vue du commercant.
test('vue commercant : echeance et delai de grace de l\'enseigne, sans identifiant Stripe ni miroir d\'un tiers', async () => {
  await h.setConfig();
  await db.doc('merchant_contracts/c3').set({owner_uid: 'merchant', state: 'active', enseigne_id: 'e1',
    submitted_at: h.admin.firestore.Timestamp.fromMillis(2000)});
  await db.doc('enseigne_subscriptions/e1').set({owner_uid: 'merchant', contract_id: 'c3', stripe_subscription_id: 'sub_x',
    stripe_customer_id: 'cus_x', status: 'past_due', current_period_end: h.admin.firestore.Timestamp.fromMillis(Date.UTC(2027, 11, 1)),
    grace_until: h.admin.firestore.Timestamp.fromMillis(Date.UTC(2027, 11, 16)), unpaid_invoice_url: 'https://invoice.stripe.com/i/x',
    suspended_at: h.admin.firestore.Timestamp.fromMillis(Date.UTC(2027, 11, 17))});
  await db.doc('enseigne_subscriptions/e2').set({owner_uid: 'other', contract_id: 'c2', stripe_subscription_id: 'sub_y', status: 'active'});
  const result = await getMyMerchantContractsHandler({}, h.merchantContext());
  const c3 = result.contracts.find((c) => c.id === 'c3');
  assert.deepEqual(c3.subscription, {status: 'past_due', currentPeriodEnd: Date.UTC(2027, 11, 1), cancelAtPeriodEnd: false,
    graceUntil: Date.UTC(2027, 11, 16), unpaidInvoiceUrl: 'https://invoice.stripe.com/i/x', suspendedAt: Date.UTC(2027, 11, 17)});
  assert.ok(!JSON.stringify(result).includes('sub_x') && !JSON.stringify(result).includes('cus_x'));
  assert.ok(!JSON.stringify(result).includes('sub_y'));
});

// Phase 1, tranche 2a, lot 1.7 : session Checkout creee au clic, par enseigne,
// carte seulement. Double du SDK Stripe : aucun reseau, aucune cle.
const {makeContractStripe} = require('./stripe_contract_fake.cjs');
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const stripeClientModule = require('../stripe_client');
const mail = require('../merchant_contract_mail');
const cgvDocument = require('../merchant_cgv_document');
const {submitMerchantSubscriptionRequestHandler, adminUpsertPromoCodeHandler} = require('../merchant_contracts_request');
const review = require('../merchant_contract_review');
const origin = require('../merchant_contract_origin');
const {adminConfirmMerchantContractHandler} = require('../merchant_contract_confirm');
const payment = require('../merchant_contract_payment');
const checkout = require('../merchant_contract_checkout');

const {db, admin} = h;
const {Timestamp} = admin.firestore;
const kUrls = {successUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=success', cancelUrl: 'https://www.proxiplay.fr/espace-commercant/?checkout=cancel'};
let sent;
let stripe;

const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass'}]));

async function invited(overrides = {}, {enseigne = 'e1'} = {}) {
  const {contractId} = await submitMerchantSubscriptionRequestHandler({
    enseigneId: enseigne, siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true, ...overrides,
  }, h.merchantContext());
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
  await adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext());
  const invitation = [...sent].reverse().find((m) => /invitation à régler/.test(m.subject));
  return {contractId, token: /paiement=([A-Za-z0-9_-]+)/.exec(invitation.text)[1]};
}

function useStripe(fake) {
  stripe = fake;
  stripeClientModule.getStripeClient = () => fake;
}

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedMerchant('other');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  await h.seedEnseigne('e2', 'merchant');
  sent = h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);
  useStripe(makeContractStripe());
});
test.after(() => {
  mail.setSender(null);
  cgvDocument.setLoader(null);
});

test('session : prix du catalogue (jamais price_data), carte seulement, TVA du taux verifie, metadonnees, aucun droit ouvert', async () => {
  const {contractId, token} = await invited();
  const result = await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  assert.match(result.checkoutUrl, /^https:\/\/checkout\.stripe\.com\//);
  assert.equal(stripe.calls.sessionsCreate.length, 1);
  const {params, options} = stripe.calls.sessionsCreate[0];
  assert.equal(params.mode, 'subscription');
  assert.deepEqual(params.payment_method_types, ['card']);
  assert.deepEqual(params.line_items, [{price: 'price_test_autonome', quantity: 1, tax_rates: ['txr_test_fixture']}]);
  assert.ok(!JSON.stringify(params).includes('price_data'), 'jamais de prix libre');
  assert.equal(params.allow_promotion_codes, false);
  assert.equal(params.client_reference_id, contractId);
  assert.deepEqual(params.metadata, {contractId, enseigneId: 'e1', merchantUserId: 'merchant', offerId: 'autonome'});
  assert.deepEqual(params.subscription_data.metadata, params.metadata);
  assert.equal(options.idempotencyKey, `checkout-contract-${contractId}-1`);
  // Client Stripe propre a l'enseigne, cree une fois par le serveur.
  assert.equal(stripe.calls.customersCreate.length, 1);
  assert.equal(stripe.calls.customersCreate[0].options.idempotencyKey, 'customer-enseigne-e1-test');
  const mirror = (await db.doc('enseigne_subscriptions/e1').get()).data();
  assert.equal(mirror.owner_uid, 'merchant');
  assert.equal(mirror.stripe_customer_id, params.customer);
  // Apercu de la premiere facture compare a l'instantane : 365 HT + 73 TVA = 438 TTC.
  assert.equal(stripe.calls.upcoming.length, 1);
  assert.equal((await db.doc(`merchant_contracts/${contractId}`).get()).data().state, 'payment_invited', 'aucun droit ouvert ici');
  const tokenDoc = (await db.doc(`payment_tokens/${payment.hashToken(token)}`).get()).data();
  assert.ok(tokenDoc.first_used_at);
  assert.equal(tokenDoc.last_session_id, stripe.calls.sessionsCreate.length ? Object.keys(stripe.store.sessions)[0] : null);
});

test('double clic : la session ouverte est reutilisee ; deux clics simultanes ne creent pas deux sessions', async () => {
  const {token} = await invited();
  const first = await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  const second = await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  assert.equal(second.checkoutUrl, first.checkoutUrl);
  assert.equal(second.reused, true);
  assert.equal(stripe.calls.sessionsCreate.length, 1);
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  useStripe(makeContractStripe());
  const again = await invited();
  const results = await Promise.allSettled([
    checkout.createContractCheckoutSessionHandler({token: again.token, ...kUrls}, h.merchantContext()),
    checkout.createContractCheckoutSessionHandler({token: again.token, ...kUrls}, h.merchantContext()),
  ]);
  assert.equal(stripe.calls.sessionsCreate.length, 1);
  assert.ok(results.some((r) => r.status === 'fulfilled'));
  for (const r of results.filter((x) => x.status === 'rejected')) assert.equal(r.reason.details.reason, 'checkout_in_progress');
});

test('session expiree cote Stripe : une nouvelle est creee (generation suivante)', async () => {
  const {contractId, token} = await invited();
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  Object.values(stripe.store.sessions)[0].status = 'expired';
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  assert.equal(stripe.calls.sessionsCreate.length, 2);
  assert.equal(stripe.calls.sessionsCreate[1].options.idempotencyKey, `checkout-contract-${contractId}-2`);
});

test('echeance de la session : 24 h au plus ; lien qui expire bientot -> 30 min (depassement accepte)', async () => {
  const {token} = await invited();
  const before = Math.floor(Date.now() / 1000);
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  const far = stripe.calls.sessionsCreate[0].params.expires_at;
  assert.ok(far >= before + 24 * 3600 - 5 && far <= before + 24 * 3600 + 5);
  useStripe(makeContractStripe());
  await db.doc(`payment_tokens/${payment.hashToken(token)}`).update({expires_at: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000)});
  const internalRef = (await db.collection('merchant_contracts').get()).docs[0].ref.collection('internal').doc('record');
  await internalRef.set({checkout: {session_id: null}}, {merge: true});
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  const near = stripe.calls.sessionsCreate[0].params.expires_at;
  const now = Math.floor(Date.now() / 1000);
  assert.ok(near >= now + 30 * 60 - 5 && near <= now + 30 * 60 + 5, 'minimum Stripe 30 min, depassement du lien de 20 min au plus');
});

test('code promotionnel : coupon « once » cree par le serveur au montant de l\'instantane, reutilise ensuite', async () => {
  await adminUpsertPromoCodeHandler({code: 'BIENVENUE', kind: 'amount', value: 6500}, h.adminContext());
  const first = await invited({promoCode: 'BIENVENUE'});
  await checkout.createContractCheckoutSessionHandler({token: first.token, ...kUrls}, h.merchantContext());
  assert.equal(stripe.calls.couponsCreate.length, 1);
  assert.deepEqual(stripe.calls.couponsCreate[0].params, {amount_off: 6500, currency: 'eur', duration: 'once',
    name: 'BIENVENUE (première année)', metadata: {promo_code: 'BIENVENUE', offer_id: 'autonome'}});
  const session = stripe.calls.sessionsCreate[0].params;
  assert.deepEqual(session.discounts, [{coupon: Object.keys(stripe.store.coupons)[0]}]);
  assert.ok(!('allow_promotion_codes' in session), 'aucun code saisi chez Stripe');
  const second = await invited({promoCode: 'BIENVENUE'}, {enseigne: 'e2'});
  await checkout.createContractCheckoutSessionHandler({token: second.token, ...kUrls}, h.merchantContext());
  assert.equal(stripe.calls.couponsCreate.length, 1, 'meme coupon reutilise');
});

test('apercu Stripe different de l\'instantane : aucune session, alerte admin', async () => {
  useStripe(makeContractStripe({upcomingOverride: () => ({currency: 'eur', total: 43900, total_excluding_tax: 36583})}));
  const {token} = await invited();
  await h.rejectsWith(checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext()), 'amount_mismatch');
  assert.equal(stripe.calls.sessionsCreate.length, 0);
  const alerts = await db.collection('admin_alerts').where('kind', '==', 'montant_stripe_ecart').get();
  assert.equal(alerts.size, 1);
});

test('prix ou taux existants non conformes : refus avant toute session', async () => {
  const cases = [
    [{price_test_autonome: {id: 'price_test_autonome', active: true, currency: 'eur', unit_amount: 36500, type: 'recurring',
      recurring: {interval: 'year', interval_count: 1}, tax_behavior: 'inclusive', livemode: false}}, null, 'price_tax_behavior'],
    [{price_test_autonome: {id: 'price_test_autonome', active: true, currency: 'eur', unit_amount: 36000, type: 'recurring',
      recurring: {interval: 'year', interval_count: 1}, tax_behavior: 'exclusive', livemode: false}}, null, 'failed-precondition'],
    [{price_test_autonome: {id: 'price_test_autonome', active: true, currency: 'eur', unit_amount: 36500, type: 'recurring',
      recurring: {interval: 'year', interval_count: 1}, tax_behavior: 'exclusive', livemode: true}}, null, 'stripe_mode_mismatch'],
    [undefined, {id: 'txr_test_fixture', active: true, inclusive: false, percentage: 10, livemode: false}, 'tax_rate_mismatch'],
    [undefined, {id: 'txr_test_fixture', active: true, inclusive: true, percentage: 20, livemode: false}, 'tax_rate_mismatch'],
  ];
  const {token} = await invited();
  for (const [prices, taxRate, reason] of cases) {
    useStripe(makeContractStripe({...(prices ? {prices} : {}), ...(taxRate ? {taxRate} : {})}));
    await h.rejectsWith(checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext()), reason);
    assert.equal(stripe.calls.sessionsCreate.length, 0, reason);
  }
});

test('TVA « none » interdite en LIVE (projet hors demo-)', async () => {
  const savedProject = process.env.GCLOUD_PROJECT;
  const savedMode = process.env.STRIPE_TAX_MODE;
  try {
    process.env.STRIPE_TAX_MODE = 'none';
    process.env.GCLOUD_PROJECT = 'projet-production-simule';
    await h.rejectsWith(checkout.verifiedTaxConfig(makeContractStripe()), 'tax_none_forbidden_live');
  } finally {
    process.env.GCLOUD_PROJECT = savedProject;
    process.env.STRIPE_TAX_MODE = savedMode;
  }
  process.env.STRIPE_TAX_MODE = 'none';
  try {
    assert.equal((await checkout.verifiedTaxConfig(makeContractStripe())).mode, 'none', 'TEST : permis (apercu alors refuse)');
  } finally {
    process.env.STRIPE_TAX_MODE = savedMode;
  }
});

test('lien d\'un autre compte, revoque ou expire : refus ; URL de retour hors domaine : refus', async () => {
  const {token} = await invited();
  await h.rejectsWith(checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext('other')), 'token_unknown');
  await h.rejectsWith(checkout.createContractCheckoutSessionHandler({token, successUrl: 'https://ailleurs.example/ok', cancelUrl: kUrls.cancelUrl},
    h.merchantContext()), 'invalid-argument');
  await db.doc(`payment_tokens/${payment.hashToken(token)}`).update({expires_at: Timestamp.fromMillis(Date.now() - 1)});
  await h.rejectsWith(checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext()), 'token_expired');
  assert.equal(stripe.calls.sessionsCreate.length, 0);
});

test('visite signalee apres ouverture de la session : retour au delai de retractation, session Stripe expiree', async () => {
  const {contractId, token} = await invited();
  await checkout.createContractCheckoutSessionHandler({token, ...kUrls}, h.merchantContext());
  await origin.reportMerchantVisitHandler({contractId}, h.merchantContext());
  assert.equal(stripe.calls.sessionsExpire.length, 1);
  assert.equal((await db.doc(`merchant_contracts/${contractId}`).get()).data().state, 'withdrawal_pending');
});

test('garde-fous du code : aucun lien de paiement Stripe, aucun prix libre, aucune creation de prix ou de produit', () => {
  for (const file of ['merchant_contract_checkout.js', 'merchant_contract_payment.js']) {
    const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
    // Appels Stripe interdits (le champ ProxiPlay payment_link_expires_at n'est pas un lien Stripe).
    assert.doesNotMatch(source, /\.paymentLinks\b|buy\.stripe\.com|price_data|prices\.create|products\.create/, file);
  }
});

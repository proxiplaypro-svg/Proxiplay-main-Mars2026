process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-merchant-checkout';
// ID de prix Stripe factice : seul le fait qu'un ID soit configure compte
// ici, jamais sa valeur reelle (le SDK Stripe est mocke dans ce fichier).
process.env.STRIPE_PRICE_PROXIMITE = 'price_test_proximite';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const stripeClientModule = require('../stripe_client');
const {createMerchantCheckoutSessionHandler} = require('../merchant_checkout');
const {generateMerchantReferralCodeHandler} = require('../merchant_referral_engine');

function makeFakeStripe({existingCustomerId} = {}) {
  const calls = {customersCreate: [], checkoutSessionsCreate: []};
  return {
    calls,
    customers: {
      create: async (params) => {
        calls.customersCreate.push(params);
        return {id: existingCustomerId || 'cus_fake_123'};
      },
    },
    checkout: {
      sessions: {
        create: async (params) => {
          calls.checkoutSessionsCreate.push(params);
          return {id: 'cs_fake_123', url: 'https://checkout.stripe.test/cs_fake_123'};
        },
      },
    },
  };
}

async function clearCollections() {
  for (const name of ['enseignes', 'merchant_subscriptions', 'merchant_custom_offers',
    'merchant_referrals', 'merchant_referral_codes', 'users']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

test.beforeEach(async () => {
  await clearCollections();
});

test('unauthenticated call is rejected', async () => {
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {offerId: 'proximite', successUrl: 'https://x', cancelUrl: 'https://x'}, {auth: null}),
    (err) => err.code === 'unauthenticated',
  );
});

test('an unknown offerId is rejected before any Stripe call, when no negotiated offer exists', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {offerId: 'offre_inexistante', successUrl: 'https://x', cancelUrl: 'https://x'},
      {auth: {uid: 'merchant'}},
    ),
    (err) => err.code === 'invalid-argument',
  );
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
});

test('no offerId at all is rejected when there is no negotiated offer', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {successUrl: 'https://x', cancelUrl: 'https://x'}, {auth: {uid: 'merchant'}},
    ),
    (err) => err.code === 'invalid-argument',
  );
});

test('a valid checkout uses the server-resolved catalog price, never a client amount, and persists subscription state keyed by merchant account', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;

  const result = await createMerchantCheckoutSessionHandler(
    {
      offerId: 'proximite',
      successUrl: 'https://proxiplay.fr/success', cancelUrl: 'https://proxiplay.fr/cancel',
      // Un client malveillant tente de transmettre un montant/offre : ignores.
      amountHtCents: 1, offerAmountOverrideCents: 1,
    },
    {auth: {uid: 'merchant'}},
  );

  assert.equal(result.checkoutUrl, 'https://checkout.stripe.test/cs_fake_123');
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 1);
  const sessionParams = fakeStripe.calls.checkoutSessionsCreate[0];
  assert.equal(sessionParams.mode, 'subscription');
  assert.equal(sessionParams.line_items[0].price, 'price_test_proximite');
  assert.equal(sessionParams.client_reference_id, 'merchant');

  const subSnap = await db.doc('merchant_subscriptions/merchant').get();
  assert.equal(subSnap.data().subscription_status, 'incomplete');
  assert.equal(subSnap.data().offer_id, 'proximite');
});

test('a merchant with a negotiated custom offer gets an inline Stripe price, never the catalog offer, even if offerId is sent', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('merchant_custom_offers/merchant').set({
    amount_ht_cents: 250000, label: 'Tarif negocie 5 enseignes',
  });

  await createMerchantCheckoutSessionHandler(
    {offerId: 'proximite', successUrl: 'https://x', cancelUrl: 'https://x'},
    {auth: {uid: 'merchant'}},
  );

  const sessionParams = fakeStripe.calls.checkoutSessionsCreate[0];
  assert.equal(sessionParams.line_items[0].price, undefined);
  assert.equal(sessionParams.line_items[0].price_data.unit_amount, 250000);
  assert.equal(sessionParams.line_items[0].price_data.product_data.name, 'Tarif negocie 5 enseignes');
  const subSnap = await db.doc('merchant_subscriptions/merchant').get();
  assert.equal(subSnap.data().offer_id, 'custom');
});

test('a second checkout is refused once a subscription is already active for this merchant account', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('merchant_subscriptions/merchant').set({subscription_status: 'active'});

  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {offerId: 'proximite', successUrl: 'https://x', cancelUrl: 'https://x'},
      {auth: {uid: 'merchant'}},
    ),
    (err) => err.code === 'already-exists',
  );
});

test('self-referral (using one\'s own code) is rejected', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  const {code} = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'merchant'}});

  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {offerId: 'proximite', successUrl: 'https://x', cancelUrl: 'https://x', referralCode: code},
      {auth: {uid: 'merchant'}},
    ),
    (err) => err.code === 'invalid-argument',
  );
});

test('a nonexistent referral code is rejected', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {offerId: 'proximite', successUrl: 'https://x', cancelUrl: 'https://x', referralCode: 'NOPE0000'},
      {auth: {uid: 'merchant'}},
    ),
    (err) => err.code === 'not-found',
  );
});

test('a valid referral code links the referral exactly once (keyed by merchant account); a second checkout cannot relink to another inviter', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  const {code: codeA} = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'inviter_a'}});
  const {code: codeB} = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'inviter_b'}});

  await createMerchantCheckoutSessionHandler(
    {offerId: 'proximite', successUrl: 'https://x', cancelUrl: 'https://x', referralCode: codeA},
    {auth: {uid: 'merchant'}},
  );
  const referralSnap = await db.doc('merchant_referrals/merchant').get();
  assert.equal(referralSnap.data().status, 'linked');
  assert.equal(referralSnap.data().inviter_user_id.path, 'users/inviter_a');

  // L'abonnement est maintenant "incomplete" (pas actif) : un deuxieme essai
  // de Checkout reste possible tant qu'aucun paiement n'est confirme, mais
  // ne doit JAMAIS re-lier le compte commercant a un autre parrain.
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {offerId: 'proximite', successUrl: 'https://x', cancelUrl: 'https://x', referralCode: codeB},
      {auth: {uid: 'merchant'}},
    ),
    (err) => err.code === 'already-exists',
  );
});

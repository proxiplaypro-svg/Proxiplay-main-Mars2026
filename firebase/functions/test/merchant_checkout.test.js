process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT ||= 'demo-proxiplay-merchant-checkout';
// ID Stripe factices : seul le fait qu'un ID soit configure compte ici,
// jamais sa valeur reelle (le SDK Stripe est mocke dans ce fichier).
process.env.STRIPE_PRICE_AUTONOME = 'price_test_autonome';
process.env.STRIPE_PRICE_ACCOMPAGNEE = 'price_test_accompagnee';
process.env.STRIPE_TAX_MODE = 'tax_rate';
process.env.STRIPE_TAX_RATE_ID = 'txr_test_fixture';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const stripeClientModule = require('../stripe_client');
const {createMerchantCheckoutSessionHandler} = require('../merchant_checkout');
const {
  createMerchantBillingPortalSessionHandler,
  listMerchantInvoicesHandler,
} = require('../merchant_billing_portal');
const {getMerchantBillingAccountHandler} = require('../merchant_billing_account');
const {
  generateMerchantReferralCodeHandler,
  adminSetMerchantManualAccessHandler,
} = require('../merchant_referral_engine');

const kUrls = {successUrl: 'https://www.proxiplay.fr/ok', cancelUrl: 'https://www.proxiplay.fr/ko'};
const kMerchant = {auth: {uid: 'merchant', token: {email: 'merchant@example.test'}}};

const kPrices = {
  price_test_autonome: {id: 'price_test_autonome', active: true, currency: 'eur', unit_amount: 36500,
    type: 'recurring', recurring: {interval: 'year', interval_count: 1}},
  price_test_accompagnee: {id: 'price_test_accompagnee', active: true, currency: 'eur', unit_amount: 100000,
    type: 'recurring', recurring: {interval: 'year', interval_count: 1}},
};

function makeFakeStripe({subscriptions = [], prices = kPrices, invoices = [], customers = {}, promotionCodes = []} = {}) {
  const calls = {customersCreate: [], checkoutSessionsCreate: [], expired: [], portal: [], invoicesList: [], promotionCodesList: []};
  const sessions = {};
  let sessionCounter = 0;
  return {
    calls,
    sessions,
    prices: {retrieve: async (id) => prices[id]},
    // Recherche Stripe insensible a la casse, codes actifs seulement.
    promotionCodes: {list: async (params) => {
      calls.promotionCodesList.push(params);
      return {data: promotionCodes.filter((p) => p.active && p.code.toLowerCase() === params.code.toLowerCase()).slice(0, 1)};
    }},
    customers: {
      // Customer connu en mode TEST (projet demo-), sauf fixture contraire.
      retrieve: async (id) => customers[id] || {id, livemode: false},
      search: async () => ({data: []}),
      create: async (params, options) => {
        calls.customersCreate.push({params, options});
        return {id: 'cus_fake_123'};
      },
    },
    subscriptions: {list: async () => ({data: subscriptions})},
    checkout: {
      sessions: {
        create: async (params, options) => {
          calls.checkoutSessionsCreate.push({...params, _options: options});
          sessionCounter++;
          const session = {id: `cs_fake_${sessionCounter}`, url: `https://checkout.stripe.test/cs_fake_${sessionCounter}`,
            status: 'open', metadata: params.metadata, expires_at: params.expires_at};
          sessions[session.id] = session;
          return session;
        },
        retrieve: async (id) => sessions[id],
        expire: async (id) => { calls.expired.push(id); sessions[id].status = 'expired'; return sessions[id]; },
      },
    },
    billingPortal: {sessions: {create: async (params) => {
      calls.portal.push(params);
      return {url: `https://billing.stripe.test/${params.customer}`};
    }}},
    invoices: {list: async (params) => { calls.invoicesList.push(params); return {data: invoices}; }},
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
  await db.doc('app_config/merchant_referral').delete();
  await db.doc('users/merchant').set({user_role: 'commercant', email: 'merchant@example.test', account_status: 'approved'});
  process.env.STRIPE_TAX_MODE = 'tax_rate';
});

// --- Autorisations -------------------------------------------------------

test('unauthenticated call is rejected', async () => {
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, {auth: null}),
    (err) => err.code === 'unauthenticated',
  );
});

test('a player account, an account without profile or a suspended merchant cannot open a checkout', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('users/player').set({user_role: 'joueur'});
  await db.doc('users/suspended').set({user_role: 'commercant', account_status: 'suspended'});
  for (const uid of ['player', 'ghost', 'suspended']) {
    await assert.rejects(
      () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, {auth: {uid}}),
      (err) => err.code === 'permission-denied',
      uid,
    );
  }
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
});

test('a return URL outside ProxiPlay domains is rejected (no open redirect)', async () => {
  stripeClientModule.getStripeClient = () => makeFakeStripe();
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler(
      {offerId: 'autonome', successUrl: 'https://evil.example/ok', cancelUrl: kUrls.cancelUrl}, kMerchant),
    (err) => err.code === 'invalid-argument',
  );
});

test('a live Stripe key is refused unless live mode is explicitly enabled', () => {
  assert.throws(() => stripeClientModule.assertKeyAllowed('sk_live_fixture'), (err) => err.code === 'failed-precondition');
  assert.doesNotThrow(() => stripeClientModule.assertKeyAllowed('sk_test_fixture'));
});

test('a merchant pending validation sees the offers but cannot open Stripe Checkout', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('users/merchant').set({user_role: 'commercant', account_status: 'pendingValidation'});
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
    (err) => err.code === 'failed-precondition' && err.details.reason === 'pending_validation',
  );
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
  assert.equal(fakeStripe.calls.customersCreate.length, 0);
  assert.equal((await db.doc('merchant_subscriptions/merchant').get()).exists, false);
  const view = await getMerchantBillingAccountHandler({}, kMerchant);
  assert.equal(view.validationPending, true);
  assert.equal(view.canCheckout, false);
  assert.equal(view.offers.length, 2);
});

// --- Offre, prix et fiscalite -------------------------------------------

test('an unknown offerId is rejected before any Stripe call, when no negotiated offer exists', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'proximite', ...kUrls}, kMerchant),
    (err) => err.code === 'invalid-argument',
  );
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({...kUrls}, kMerchant),
    (err) => err.code === 'invalid-argument',
  );
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
});

test('without an explicitly validated tax configuration, no checkout is created', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  delete process.env.STRIPE_TAX_MODE;
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
    (err) => err.code === 'failed-precondition',
  );
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
});

test('a valid checkout uses the server-resolved price, never a client amount, and activates nothing', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;

  const result = await createMerchantCheckoutSessionHandler(
    // Un client malveillant tente de transmettre un montant : ignore.
    {offerId: 'accompagnee', ...kUrls, amountHtCents: 1, price: 'price_hack'},
    kMerchant,
  );

  assert.equal(result.checkoutUrl, 'https://checkout.stripe.test/cs_fake_1');
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 1);
  const params = fakeStripe.calls.checkoutSessionsCreate[0];
  assert.equal(params.mode, 'subscription');
  assert.deepEqual(params.line_items, [{price: 'price_test_accompagnee', quantity: 1, tax_rates: ['txr_test_fixture']}]);
  assert.equal(params.client_reference_id, 'merchant');
  assert.equal(params.customer, 'cus_fake_123');
  assert.equal(params.subscription_data.metadata.merchantUserId, 'merchant');
  assert.equal(params.subscription_data.metadata.offerId, 'accompagnee');
  assert.ok(fakeStripe.calls.customersCreate[0].options.idempotencyKey.startsWith('merchant-customer-merchant-'));

  const data = (await db.doc('merchant_subscriptions/merchant').get()).data();
  assert.equal(data.pending_offer_id, 'accompagnee');
  assert.equal(data.checkout_status, 'open');
  assert.equal(data.stripe_customer_id, 'cus_fake_123');
  assert.equal(data.subscription_status, undefined, 'aucun statut Stripe avant le webhook');
  assert.equal(data.stripe_entitlement, undefined, 'aucun droit ouvert au Checkout');
  assert.equal(data.checkout_lock, undefined);
});

test('a Stripe price that does not match the catalogue (amount or period) is refused', async () => {
  const fakeStripe = makeFakeStripe({prices: {
    ...kPrices,
    price_test_autonome: {...kPrices.price_test_autonome, recurring: {interval: 'month', interval_count: 1}},
  }});
  stripeClientModule.getStripeClient = () => fakeStripe;
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
    (err) => err.code === 'failed-precondition',
  );
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
  const lock = (await db.doc('merchant_subscriptions/merchant').get()).data().checkout_lock;
  assert.equal(lock, undefined, 'le verrou est libere apres un echec');
});

test('a merchant with a negotiated custom offer gets an inline Stripe price, never the catalog offer', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('merchant_custom_offers/merchant').set({amount_ht_cents: 250000, label: 'Tarif negocie 5 enseignes'});

  await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant);

  const params = fakeStripe.calls.checkoutSessionsCreate[0];
  assert.equal(params.line_items[0].price, undefined);
  assert.equal(params.line_items[0].price_data.unit_amount, 250000);
  assert.equal(params.line_items[0].price_data.recurring.interval, 'year');
  assert.equal((await db.doc('merchant_subscriptions/merchant').get()).data().pending_offer_id, 'custom');
});

// --- Prevention des doubles abonnements ---------------------------------

test('a second checkout is refused once the mirror shows an open subscription', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  for (const status of ['active', 'past_due', 'trialing']) {
    await db.doc('merchant_subscriptions/merchant').set({subscription_status: status, stripe_subscription_id: 'sub_1'});
    await assert.rejects(
      () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
      (err) => err.code === 'already-exists',
      status,
    );
  }
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
});

test('an open subscription known only by Stripe (webhook not yet received) blocks a new checkout', async () => {
  const fakeStripe = makeFakeStripe({subscriptions: [{id: 'sub_live_1', status: 'active'}]});
  stripeClientModule.getStripeClient = () => fakeStripe;
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
    (err) => err.code === 'already-exists',
  );
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
});

test('a still-open session for the same offer is reused; another offer expires it first', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;

  const first = await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant);
  const again = await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant);
  assert.equal(again.checkoutUrl, first.checkoutUrl);
  assert.equal(again.reused, true);
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 1);

  const other = await createMerchantCheckoutSessionHandler({offerId: 'accompagnee', ...kUrls}, kMerchant);
  assert.deepEqual(fakeStripe.calls.expired, ['cs_fake_1']);
  assert.notEqual(other.checkoutUrl, first.checkoutUrl);
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 2);
  assert.equal(fakeStripe.calls.customersCreate.length, 1, 'un seul Customer Stripe par commercant');
});

test('two simultaneous checkouts never create two sessions', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  const results = await Promise.allSettled([
    createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
    createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
  ]);
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 1);
  const rejected = results.filter((r) => r.status === 'rejected');
  rejected.forEach((r) => assert.ok(['aborted', 'already-exists'].includes(r.reason.code), r.reason.code));
});

test('an existing Stripe Customer is reused, never duplicated', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('merchant_subscriptions/merchant').set({stripe_customer_id: 'cus_existing', subscription_status: 'canceled'});
  await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant);
  assert.equal(fakeStripe.calls.customersCreate.length, 0);
  assert.equal(fakeStripe.calls.checkoutSessionsCreate[0].customer, 'cus_existing');
});

// --- Parrainage (inchange) -------------------------------------------------

test('self-referral (using one\'s own code) is rejected', async () => {
  stripeClientModule.getStripeClient = () => makeFakeStripe();
  const {code} = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'merchant'}});
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls, referralCode: code}, kMerchant),
    (err) => err.code === 'invalid-argument',
  );
});

test('a nonexistent referral code is rejected', async () => {
  stripeClientModule.getStripeClient = () => makeFakeStripe();
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls, referralCode: 'NOPE0000'}, kMerchant),
    (err) => err.code === 'not-found',
  );
});

test('a valid referral code links the referral exactly once; a second checkout cannot relink to another inviter', async () => {
  stripeClientModule.getStripeClient = () => makeFakeStripe();
  const {code: codeA} = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'inviter_a'}});
  const {code: codeB} = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'inviter_b'}});

  await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls, referralCode: codeA}, kMerchant);
  const referralSnap = await db.doc('merchant_referrals/merchant').get();
  assert.equal(referralSnap.data().status, 'linked');
  assert.equal(referralSnap.data().reward_amount_cents, 5000);
  assert.equal(referralSnap.data().inviter_user_id.path, 'users/inviter_a');

  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls, referralCode: codeB}, kMerchant),
    (err) => err.code === 'already-exists',
  );
});

test('disabled programme blocks a new referral without blocking ordinary checkout', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  const {code} = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'inviter'}});
  await db.doc('app_config/merchant_referral').set({enabled: false});
  await assert.rejects(
    () => createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls, referralCode: code}, kMerchant),
    (err) => err.code === 'failed-precondition',
  );
  assert.equal((await db.doc('merchant_referrals/merchant').get()).exists, false);
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0);
  await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant);
  assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 1);
});

// --- Portail et factures ---------------------------------------------------

test('the billing portal is opened only for the caller\'s own Stripe Customer', async () => {
  const fakeStripe = makeFakeStripe();
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('users/player').set({user_role: 'joueur'});
  await assert.rejects(
    () => createMerchantBillingPortalSessionHandler({returnUrl: kUrls.successUrl}, {auth: {uid: 'player'}}),
    (err) => err.code === 'permission-denied',
  );
  await assert.rejects(
    () => createMerchantBillingPortalSessionHandler({returnUrl: kUrls.successUrl}, kMerchant),
    (err) => err.code === 'failed-precondition',
  );
  await db.doc('merchant_subscriptions/merchant').set({stripe_customer_id: 'cus_mine'});
  const result = await createMerchantBillingPortalSessionHandler(
    {returnUrl: kUrls.successUrl, customer: 'cus_someone_else'}, kMerchant);
  assert.equal(result.portalUrl, 'https://billing.stripe.test/cus_mine');
  assert.equal(fakeStripe.calls.portal[0].customer, 'cus_mine');
});

test('invoices are listed for the caller only, without any card data', async () => {
  const fakeStripe = makeFakeStripe({invoices: [
    {id: 'in_1', number: 'PXP-0001', status: 'paid', created: 1700000000, total: 43800, amount_paid: 43800,
      currency: 'eur', hosted_invoice_url: 'https://invoice.stripe.test/in_1', invoice_pdf: 'https://pdf.stripe.test/in_1',
      charge: {payment_method_details: {card: {last4: '4242'}}}},
    {id: 'in_draft', status: 'draft'},
  ]});
  stripeClientModule.getStripeClient = () => fakeStripe;
  await db.doc('merchant_subscriptions/merchant').set({stripe_customer_id: 'cus_mine'});
  const {invoices} = await listMerchantInvoicesHandler({customer: 'cus_other'}, kMerchant);
  assert.equal(fakeStripe.calls.invoicesList[0].customer, 'cus_mine');
  assert.equal(invoices.length, 1);
  assert.equal(invoices[0].invoicePdfUrl, 'https://pdf.stripe.test/in_1');
  assert.ok(!JSON.stringify(invoices).includes('4242'));
});

// --- Activation manuelle Admin --------------------------------------------

test('manual access is set only by an admin and stored apart from Stripe fields', async () => {
  await db.doc('users/admin').set({user_role: 'admin'});
  await assert.rejects(
    () => adminSetMerchantManualAccessHandler({merchantUserId: 'merchant', enabled: true, reason: 'x'}, kMerchant),
    (err) => err.code === 'permission-denied',
  );
  await adminSetMerchantManualAccessHandler(
    {merchantUserId: 'merchant', enabled: true, reason: 'Paiement par virement 2026'}, {auth: {uid: 'admin'}});
  const data = (await db.doc('merchant_subscriptions/merchant').get()).data();
  assert.equal(data.manual_access.enabled, true);
  assert.equal(data.manual_access.set_by, 'admin');
  assert.equal(data.subscription_status, undefined);
});

// --- Correspondance compte site <-> compte Firebase ------------------------

test('the merchant space only opens for a Firebase merchant profile and lists its enseignes', async () => {
  await db.doc('users/player').set({user_role: 'joueur'});
  for (const uid of ['player', 'ghost']) {
    await assert.rejects(() => getMerchantBillingAccountHandler({}, {auth: {uid}}), (err) => err.code === 'permission-denied');
  }
  await assert.rejects(() => getMerchantBillingAccountHandler({}, {auth: null}), (err) => err.code === 'unauthenticated');

  await db.doc('users/merchant').set({user_role: 'commercant', display_name: 'Boulangerie Test', account_status: 'approved'});
  await db.doc('enseignes/e1').set({name: 'Boulangerie du port', owner: db.doc('users/merchant')});
  await db.doc('enseignes/e2').set({name: 'Boulangerie centre', owner_id: db.doc('users/merchant')});
  await db.doc('enseignes/e3').set({name: 'Autre commerce', owner: db.doc('users/someone')});

  const view = await getMerchantBillingAccountHandler({}, kMerchant);
  assert.equal(view.account.uid, 'merchant');
  assert.equal(view.account.displayName, 'Boulangerie Test');
  assert.deepEqual(view.account.enseignes.map((e) => e.id).sort(), ['e1', 'e2']);
  assert.equal(view.subscription.status, null);
  assert.equal(view.hasPaidAccess, false);
  assert.deepEqual(view.offers.map((o) => [o.id, o.amountHtCents]), [['autonome', 36500], ['accompagnee', 100000]]);
  assert.equal(view.paymentsEnabled, true);
});

test('the merchant space reflects the webhook mirror and manual access, never secrets', async () => {
  await db.doc('merchant_subscriptions/merchant').set({
    subscription_status: 'active', stripe_entitlement: 'active', offer_id: 'autonome',
    stripe_customer_id: 'cus_secretish', stripe_subscription_id: 'sub_x',
    current_period_end: admin.firestore.Timestamp.fromMillis(Date.UTC(2027, 10, 2)),
    stripe_livemode: false, stripe_sandbox: true,
  });
  let view = await getMerchantBillingAccountHandler({}, kMerchant);
  assert.equal(view.subscription.offerLabel, 'Autonome');
  assert.equal(view.subscription.currentPeriodEnd, Date.UTC(2027, 10, 2));
  assert.equal(view.subscription.testMode, true);
  assert.equal(view.hasPaidAccess, true);
  assert.ok(!JSON.stringify(view).includes('cus_secretish'));
  assert.ok(!JSON.stringify(view).includes('sub_x'));

  await db.doc('merchant_subscriptions/merchant').set({manual_access: {enabled: true, reason: 'Historique'}});
  view = await getMerchantBillingAccountHandler({}, kMerchant);
  assert.equal(view.manualAccess.active, true);
  assert.equal(view.hasPaidAccess, true);
});

// --- Tarif preferentiel : code d'offre cree dans le tableau de bord Stripe ---

const kProduct = 'prod_autonome';
const kPricesWithProduct = {
  ...kPrices,
  price_test_autonome: {...kPrices.price_test_autonome, product: kProduct},
};
function promo(overrides = {}) {
  return {
    id: 'promo_malle', code: 'MALLE300', active: true, livemode: false,
    metadata: {merchantUserId: 'merchant'}, customer: null, expires_at: null,
    max_redemptions: 1, times_redeemed: 0,
    coupon: {id: 'coupon_65', valid: true, duration: 'once', amount_off: 6500, currency: 'eur',
      applies_to: {products: [kProduct]}},
    ...overrides,
  };
}
const promoCheckout = (code, extra = {}) =>
  createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls, promotionCode: code, ...extra}, kMerchant);

test('preferential offer: a code reserved to this merchant applies a first-year-only discount, verified server side', async () => {
  const fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: [promo()]});
  stripeClientModule.getStripeClient = () => fakeStripe;

  const result = await promoCheckout('malle300');
  assert.equal(result.reused, false);
  const params = fakeStripe.calls.checkoutSessionsCreate[0];
  assert.deepEqual(params.discounts, [{promotion_code: 'promo_malle'}]);
  assert.equal(params.allow_promotion_codes, undefined, 'aucune saisie libre de code chez Stripe');
  assert.deepEqual(params.line_items, [{price: 'price_test_autonome', quantity: 1, tax_rates: ['txr_test_fixture']}]);
  assert.equal(params.client_reference_id, 'merchant', 'rattachement par le compte authentifie, jamais par e-mail');
  assert.equal(params.subscription_data.metadata.merchantUserId, 'merchant');
  assert.equal(params.subscription_data.metadata.promotionCode, 'MALLE300');
  assert.equal(fakeStripe.calls.promotionCodesList[0].active, true);
  const data = (await db.doc('merchant_subscriptions/merchant').get()).data();
  assert.equal(data.pending_promotion_code, 'MALLE300');
  assert.equal(data.subscription_status, undefined, 'aucun droit avant le paiement confirme par le webhook');
});

test('preferential offer: a code of another merchant, unknown, or from the other Stripe mode is refused with the same message', async () => {
  for (const [label, codes] of [
    ['autre commercant', [promo({metadata: {merchantUserId: 'someone-else'}})]],
    ['sans UID', [promo({metadata: {}})]],
    ['inconnu', []],
    ['inactif', [promo({active: false})]],
    ['autre mode', [promo({livemode: true})]],
    ['client Stripe different', [promo({customer: 'cus_other'})]],
  ]) {
    await clearCollections();
    await db.doc('users/merchant').set({user_role: 'commercant', email: 'merchant@example.test', account_status: 'approved'});
    const fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: codes});
    stripeClientModule.getStripeClient = () => fakeStripe;
    await assert.rejects(promoCheckout('MALLE300'), (err) =>
      err.code === 'failed-precondition' && err.details?.reason === 'invalid_offer_code' &&
      err.message === "Ce code d'offre n'est pas valide pour ce compte.", label);
    assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0, label);
    const mirror = (await db.doc('merchant_subscriptions/merchant').get()).data();
    assert.equal(mirror?.checkout_lock, undefined, `${label} : verrou libere`);
  }
});

test('preferential offer: expired, already used, not first-year-only or wrong product codes are refused', async () => {
  for (const [label, overrides, message] of [
    ['expire', {expires_at: Math.floor(Date.now() / 1000) - 60}, /expire/],
    ['deja utilise', {times_redeemed: 1}, /deja ete utilise/],
    ['remise permanente', {coupon: {...promo().coupon, duration: 'forever'}}, /mal configuree/],
    ['remise sur plusieurs mois', {coupon: {...promo().coupon, duration: 'repeating', duration_in_months: 24}}, /mal configuree/],
    ['coupon invalide', {coupon: {...promo().coupon, valid: false}}, /mal configuree/],
    ['autre devise', {coupon: {...promo().coupon, currency: 'usd'}}, /mal configuree/],
    ['autre produit', {coupon: {...promo().coupon, applies_to: {products: ['prod_accompagnee']}}}, /formule/],
  ]) {
    await clearCollections();
    await db.doc('users/merchant').set({user_role: 'commercant', email: 'merchant@example.test', account_status: 'approved'});
    const fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: [promo(overrides)]});
    stripeClientModule.getStripeClient = () => fakeStripe;
    await assert.rejects(promoCheckout('MALLE300'), (err) =>
      err.code === 'failed-precondition' && err.details?.reason === 'invalid_offer_code' && message.test(err.message), label);
    assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0, label);
  }
});

test('preferential offer: malformed code refused before any Stripe call; no code keeps the normal 365 EUR checkout', async () => {
  const fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: [promo()]});
  stripeClientModule.getStripeClient = () => fakeStripe;
  for (const code of ['a', 'MALLE 300', 'x'.repeat(65), 42, {code: 'MALLE300'}]) {
    await assert.rejects(promoCheckout(code), (err) => err.code === 'invalid-argument', String(code));
  }
  assert.equal(fakeStripe.calls.promotionCodesList.length, 0);
  await promoCheckout('');
  const params = fakeStripe.calls.checkoutSessionsCreate[0];
  assert.equal(params.discounts, undefined);
  assert.equal(params.subscription_data.metadata.promotionCode, '');
});

test('preferential offer: never stacked on a negotiated tarif; an open session is reused only for the same code', async () => {
  await db.doc('merchant_custom_offers/merchant').set({amount_ht_cents: 182500, label: 'Grande enseigne'});
  let fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: [promo()]});
  stripeClientModule.getStripeClient = () => fakeStripe;
  await assert.rejects(promoCheckout('MALLE300'), (err) => err.details?.reason === 'invalid_offer_code');
  assert.equal(fakeStripe.calls.promotionCodesList.length, 0);
  await db.doc('merchant_custom_offers/merchant').delete();

  fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: [promo(), promo({id: 'promo_b', code: 'AUTRE300'})]});
  stripeClientModule.getStripeClient = () => fakeStripe;
  const first = await promoCheckout('MALLE300');
  await db.doc('merchant_subscriptions/merchant').update({checkout_lock: admin.firestore.FieldValue.delete()});
  const again = await promoCheckout('malle300');
  assert.equal(again.reused, true);
  assert.equal(again.checkoutUrl, first.checkoutUrl);
  const other = await promoCheckout('AUTRE300');
  assert.equal(other.reused, false);
  assert.deepEqual(fakeStripe.calls.expired, ['cs_fake_1']);
  const plain = await promoCheckout('');
  assert.equal(plain.reused, false, 'sans code : nouvelle session au tarif normal');
});

// --- Code de campagne partagé (ex. FRIENDS20) ----------------------------------

// Reproduit FRIENDS20 tel que configuré en LIVE (coupon 65 EUR "once" sur
// Autonome, première commande uniquement), plus la métadonnée de campagne.
function campaign(overrides = {}) {
  return promo({
    id: 'promo_friends', code: 'FRIENDS20', metadata: {proxiplay_usage: 'campagne'},
    max_redemptions: null, restrictions: {first_time_transaction: true},
    ...overrides,
  });
}

test('campaign code: usable by any validated merchant for a first subscription, attached to the authenticated UID', async () => {
  const fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: [campaign()]});
  stripeClientModule.getStripeClient = () => fakeStripe;
  await promoCheckout('friends20');
  const params = fakeStripe.calls.checkoutSessionsCreate[0];
  assert.deepEqual(params.discounts, [{promotion_code: 'promo_friends'}]);
  assert.equal(params.client_reference_id, 'merchant');
  assert.equal(params.subscription_data.metadata.merchantUserId, 'merchant');
  assert.equal(params.subscription_data.metadata.promotionCode, 'FRIENDS20');
  assert.equal((await db.doc('merchant_subscriptions/merchant').get()).data().pending_promotion_code, 'FRIENDS20');
});

test('campaign code: refused without the campaign marker, without "first order only", or after a previous subscription', async () => {
  for (const [label, codes, subscriptions, message] of [
    ['sans métadonnée (FRIENDS20 actuel)', [campaign({metadata: {}})], [], /n'est pas valide pour ce compte/],
    ['autre usage', [campaign({metadata: {proxiplay_usage: 'autre'}})], [], /n'est pas valide pour ce compte/],
    ['sans première commande', [campaign({restrictions: {first_time_transaction: false}})], [], /mal configuree/],
    ['abonnement précédent résilié', [campaign()], [{id: 'sub_old', status: 'canceled'}], /premier abonnement/],
    ['coupon permanent', [campaign({coupon: {...promo().coupon, duration: 'forever'}})], [], /mal configuree/],
    ['personnel et campagne : UID prioritaire', [campaign({metadata: {merchantUserId: 'other', proxiplay_usage: 'campagne'}})], [], /n'est pas valide pour ce compte/],
  ]) {
    await clearCollections();
    await db.doc('users/merchant').set({user_role: 'commercant', email: 'merchant@example.test', account_status: 'approved'});
    const fakeStripe = makeFakeStripe({prices: kPricesWithProduct, promotionCodes: codes, subscriptions});
    stripeClientModule.getStripeClient = () => fakeStripe;
    await assert.rejects(promoCheckout('FRIENDS20'), (err) =>
      err.code === 'failed-precondition' && err.details?.reason === 'invalid_offer_code' && message.test(err.message), label);
    assert.equal(fakeStripe.calls.checkoutSessionsCreate.length, 0, label);
  }
});

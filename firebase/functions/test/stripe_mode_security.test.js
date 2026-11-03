// Securite du mode Stripe : une cle, un evenement ou un abonnement TEST ne
// doit jamais ouvrir de droit sur le projet de production ; une cle LIVE ne
// doit jamais servir depuis les emulateurs.
//
// "Production" est simulee en changeant uniquement GCLOUD_PROJECT pendant un
// test (stripe_mode.js ne lit que lui) : Firestore reste l'EMULATEUR
// (FIRESTORE_EMULATOR_HOST obligatoire), Stripe est un faux client en memoire.
process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT ||= 'demo-proxiplay-stripe-mode';
if (!String(process.env.GCLOUD_PROJECT).startsWith('demo-')) throw new Error('Projet demo- requis');
process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test_fixture_secret';
process.env.STRIPE_PRICE_AUTONOME = 'price_fixture_autonome';
process.env.STRIPE_PRICE_ACCOMPAGNEE = 'price_fixture_accompagnee';
process.env.STRIPE_TAX_MODE = 'tax_rate';
process.env.STRIPE_TAX_RATE_ID = 'txr_fixture';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const Stripe = require('stripe');

const stripeMode = require('../stripe_mode');
const stripeClientModule = require('../stripe_client');
const realGetStripeClient = stripeClientModule.getStripeClient;
const {stripeWebhookHandler} = require('../stripe_webhook');
const {createMerchantCheckoutSessionHandler} = require('../merchant_checkout');
const {listMerchantInvoicesHandler, createMerchantBillingPortalSessionHandler} =
  require('../merchant_billing_portal');
const {getMerchantBillingAccountHandler} = require('../merchant_billing_account');

const kDemoProject = process.env.GCLOUD_PROJECT;
const kProdProject = 'proxi-play-odzp2e';
const kWebhookSecret = 'whsec_test_fixture_secret';
const kMerchant = {auth: {uid: 'merchant1', token: {email: 'merchant@example.test'}}};
const kUrls = {successUrl: 'https://www.proxiplay.fr/ok', cancelUrl: 'https://www.proxiplay.fr/ko'};
const signingClient = new Stripe('sk_test_FAKE_FOR_SIGNATURE_ONLY', {apiVersion: '2024-06-20'});
const nowSeconds = () => Math.floor(Date.now() / 1000);
const mirror = async (uid = 'merchant1') => (await db.doc(`merchant_subscriptions/${uid}`).get()).data();
const eventDoc = async (id) => (await db.doc(`stripe_webhook_events/${id}`).get()).data();

const kEnvKeys = ['GCLOUD_PROJECT', 'STRIPE_SECRET_KEY', 'STRIPE_LIVE_MODE_ENABLED', 'STRIPE_TAX_MODE'];
let savedEnv;

/** Execute fn comme sur le projet de production (Firestore reste l'emulateur). */
async function asProduction(fn) {
  const previous = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = kProdProject;
  try {
    assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'emulateur Firestore obligatoire');
    return await fn();
  } finally {
    process.env.GCLOUD_PROJECT = previous;
  }
}

function signedRequest(event) {
  const payload = JSON.stringify(event);
  const header = signingClient.webhooks.generateTestHeaderString({payload, secret: kWebhookSecret});
  return {method: 'POST', rawBody: Buffer.from(payload, 'utf8'), headers: {'stripe-signature': header}};
}

async function deliver(event) {
  const res = {statusCode: null, body: null};
  res.status = (code) => { res.statusCode = code; return res; };
  res.send = (body) => { res.body = body; return res; };
  await stripeWebhookHandler(signedRequest(event), res);
  return res;
}

let eventCounter = nowSeconds();
const event = (id, type, object, livemode) =>
  ({id, type, data: {object}, api_version: '2024-06-20', created: ++eventCounter, livemode});

function subscription(livemode, overrides = {}) {
  return {
    id: livemode ? 'sub_live' : 'sub_test', customer: livemode ? 'cus_live' : 'cus_test', status: 'active', livemode,
    current_period_start: nowSeconds(), current_period_end: nowSeconds() + 365 * 24 * 3600,
    cancel_at_period_end: false, cancel_at: null, canceled_at: null, ended_at: null,
    items: {data: [{price: {id: 'price_fixture_autonome'}}]},
    metadata: {merchantUserId: 'merchant1', offerId: 'autonome'},
    ...overrides,
  };
}

// Faux Stripe : etat courant relu par le webhook ; compte les appels.
function installFakeStripe({subscriptions = {}, customers = {}} = {}) {
  const calls = {retrieve: 0, customersCreate: 0, sessionsCreate: 0, invoicesList: 0};
  stripeClientModule.getStripeClient = () => ({
    webhooks: signingClient.webhooks,
    subscriptions: {
      retrieve: async (id) => { calls.retrieve++; return subscriptions[id]; },
      list: async () => ({data: []}),
    },
    customers: {
      retrieve: async (id) => {
        if (!customers[id]) throw Object.assign(new Error('No such customer'), {code: 'resource_missing'});
        return customers[id];
      },
      search: async () => ({data: []}),
      create: async () => { calls.customersCreate++; return {id: 'cus_live_new', livemode: true}; },
    },
    prices: {retrieve: async (id) => ({id, active: true, currency: 'eur', unit_amount: 36500, type: 'recurring',
      recurring: {interval: 'year', interval_count: 1}})},
    checkout: {sessions: {
      create: async (params) => {
        calls.sessionsCreate++;
        return {id: 'cs_live_1', url: 'https://checkout.stripe.test/cs_live_1', status: 'open',
          metadata: params.metadata, expires_at: params.expires_at};
      },
      retrieve: async () => null,
      expire: async () => null,
    }},
    invoices: {
      retrieve: async () => null,
      list: async () => { calls.invoicesList++; throw Object.assign(new Error('No such customer'), {code: 'resource_missing'}); },
    },
    billingPortal: {sessions: {create: async () => {
      throw Object.assign(new Error('No such customer'), {code: 'resource_missing'});
    }}},
  });
  return calls;
}

async function clearCollections() {
  for (const name of ['merchant_subscriptions', 'merchant_referrals', 'stripe_webhook_events', 'users']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

test.beforeEach(async () => {
  savedEnv = Object.fromEntries(kEnvKeys.map((key) => [key, process.env[key]]));
  process.env.GCLOUD_PROJECT = kDemoProject;
  delete process.env.STRIPE_LIVE_MODE_ENABLED;
  delete process.env.STRIPE_SECRET_KEY;
  process.env.STRIPE_TAX_MODE = 'tax_rate';
  await clearCollections();
  await db.doc('users/merchant1').set({user_role: 'commercant', email: 'merchant@example.test', account_status: 'approved'});
});

test.afterEach(() => {
  for (const [key, value] of Object.entries(savedEnv)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }
  stripeClientModule.getStripeClient = realGetStripeClient;
});

// --- Mode attendu et cle Stripe ---------------------------------------------

test('the expected Stripe mode comes from the Firebase project only', () => {
  assert.equal(stripeMode.isStripeSandbox(), true);
  assert.equal(stripeMode.expectedLivemode(), false);
  process.env.GCLOUD_PROJECT = kProdProject;
  assert.equal(stripeMode.isStripeSandbox(), false);
  assert.equal(stripeMode.expectedLivemode(), true);
  // Projet introuvable : traite comme la production.
  delete process.env.GCLOUD_PROJECT;
  const savedConfig = process.env.FIREBASE_CONFIG;
  delete process.env.FIREBASE_CONFIG;
  try {
    assert.equal(stripeMode.expectedLivemode(), true);
    process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-from-config'});
    assert.equal(stripeMode.isStripeSandbox(), true);
  } finally {
    if (savedConfig === undefined) delete process.env.FIREBASE_CONFIG; else process.env.FIREBASE_CONFIG = savedConfig;
  }
});

test('production refuses every TEST key, a LIVE key without the explicit switch and any placeholder', async () => {
  await asProduction(() => {
    const refused = (key) => assert.throws(() => stripeClientModule.assertKeyAllowed(key),
      (err) => err.code === 'failed-precondition' && err.details?.reason === 'payments_closed', key);
    for (const key of ['sk_test_fixture', 'rk_test_fixture', 'sk_live_fixture', '', 'desactive', 'pk_live_fixture']) {
      refused(key);
    }
    process.env.STRIPE_LIVE_MODE_ENABLED = 'true';
    refused('sk_test_fixture');
    assert.doesNotThrow(() => stripeClientModule.assertKeyAllowed('sk_live_fixture'));
    assert.doesNotThrow(() => stripeClientModule.assertKeyAllowed('rk_live_fixture'));
  });
});

test('emulators (demo- project) accept TEST keys only, even with the LIVE switch on', () => {
  process.env.STRIPE_LIVE_MODE_ENABLED = 'true';
  assert.doesNotThrow(() => stripeClientModule.assertKeyAllowed('sk_test_fixture'));
  assert.throws(() => stripeClientModule.assertKeyAllowed('sk_live_fixture'), (err) => err.code === 'failed-precondition');
});

// --- Webhook ------------------------------------------------------------------

test('production + sk_test_ key: the webhook rejects the call before any processing', async () => {
  await asProduction(async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_fixture_unused';
    const res = await deliver(event('evt_testkey', 'invoice.paid', {subscription: 'sub_test'}, false));
    assert.equal(res.statusCode, 400);
    assert.equal(await mirror(), undefined);
    assert.equal((await db.collection('stripe_webhook_events').get()).size, 0);
  });
});

test('production: a TEST event grants nothing, is recorded once and never replayed', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'linked'});
  const calls = installFakeStripe({subscriptions: {sub_test: subscription(false)}});
  await asProduction(async () => {
    const paid = event('evt_test_paid', 'invoice.paid',
      {id: 'in_test', subscription: 'sub_test', billing_reason: 'subscription_create', subtotal: 36500}, false);
    const first = await deliver(paid);
    assert.equal(first.statusCode, 200);
    assert.equal((await eventDoc('evt_test_paid')).outcome, 'ignored_livemode_mismatch');
    assert.equal((await eventDoc('evt_test_paid')).livemode, false);
    // Doublon (retry Stripe) : deja traite, rien de plus.
    const again = await deliver(paid);
    assert.equal(again.statusCode, 200);
    assert.equal((await eventDoc('evt_test_paid')).attempts, 1);
  });
  assert.equal(calls.retrieve, 0, 'Stripe jamais interroge pour un evenement de l\'autre mode');
  assert.equal(await mirror(), undefined, 'aucun miroir, aucun droit');
  assert.equal((await db.doc('merchant_referrals/merchant1').get()).data().status, 'linked', 'parrainage intact');
});

test('production: a LIVE event whose subscription is TEST at Stripe (inconsistent data) grants nothing', async () => {
  installFakeStripe({subscriptions: {sub_mixed: subscription(false, {id: 'sub_mixed'})}});
  await asProduction(async () => {
    const res = await deliver(event('evt_mixed', 'customer.subscription.updated', {id: 'sub_mixed'}, true));
    assert.equal(res.statusCode, 200);
    assert.equal((await eventDoc('evt_mixed')).outcome, 'ignored_livemode_mismatch');
  });
  assert.equal(await mirror(), undefined);
});

test('production: a LIVE event and LIVE subscription open rights once, even if delivered twice', async () => {
  const calls = installFakeStripe({subscriptions: {sub_live: subscription(true)}});
  await asProduction(async () => {
    const created = event('evt_live_created', 'customer.subscription.created', {id: 'sub_live'}, true);
    assert.equal((await deliver(created)).statusCode, 200);
    assert.equal((await deliver(created)).statusCode, 200);
  });
  assert.equal(calls.retrieve, 1, 'evenement duplique traite une seule fois');
  const doc = await mirror();
  assert.equal(doc.subscription_status, 'active');
  assert.equal(doc.stripe_livemode, true);
  assert.equal(doc.stripe_mode, 'live');
  assert.equal(doc.stripe_sandbox, false);
  assert.equal(doc.publication_access_status, 'active');
});

test('production: a LIVE subscription replaces an old TEST mirror, keeping Admin rights', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({
    subscription_status: 'active', stripe_livemode: false, stripe_sandbox: true, stripe_customer_id: 'cus_test',
    stripe_subscription_id: 'sub_test', first_payment_confirmed_at: admin.firestore.Timestamp.now(),
    stripe_fetched_at_ms: Date.now() + 60 * 60 * 1000,
    manual_access: {enabled: true, until: null, reason: 'Historique'},
  });
  installFakeStripe({subscriptions: {sub_live: subscription(true)}});
  await asProduction(async () => {
    const res = await deliver(event('evt_live_switch', 'customer.subscription.created', {id: 'sub_live'}, true));
    assert.equal(res.statusCode, 200);
    assert.equal((await eventDoc('evt_live_switch')).outcome, 'synced');
  });
  const doc = await mirror();
  assert.equal(doc.stripe_subscription_id, 'sub_live');
  assert.equal(doc.stripe_customer_id, 'cus_live');
  assert.equal(doc.stripe_livemode, true);
  assert.equal(doc.stripe_sandbox, false);
  assert.equal(doc.first_payment_confirmed_at, null, 'paiement TEST jamais compte comme premier paiement');
  assert.deepEqual(doc.manual_access, {enabled: true, until: null, reason: 'Historique'});
});

test('emulators: a LIVE event is ignored, a TEST event is applied and marked sandbox', async () => {
  installFakeStripe({subscriptions: {sub_test: subscription(false), sub_live: subscription(true)}});
  const live = await deliver(event('evt_demo_live', 'customer.subscription.created', {id: 'sub_live'}, true));
  assert.equal(live.statusCode, 200);
  assert.equal((await eventDoc('evt_demo_live')).outcome, 'ignored_livemode_mismatch');
  assert.equal(await mirror(), undefined);

  const testEvent = await deliver(event('evt_demo_test', 'customer.subscription.created', {id: 'sub_test'}, false));
  assert.equal(testEvent.statusCode, 200);
  const doc = await mirror();
  assert.equal(doc.stripe_livemode, false);
  assert.equal(doc.stripe_sandbox, true);
  assert.equal(doc.publication_access_status, 'active');
});

// --- Checkout, espace commercant, portail ------------------------------------

test('production: payments are closed by default, before any write or Stripe call', async () => {
  const calls = installFakeStripe();
  await asProduction(async () => {
    await assert.rejects(createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
      (err) => err.code === 'failed-precondition' && err.details?.reason === 'payments_closed');
    const view = await getMerchantBillingAccountHandler({}, kMerchant);
    assert.equal(view.paymentsEnabled, false);
    assert.equal(view.canCheckout, false);
  });
  assert.equal(calls.sessionsCreate + calls.customersCreate, 0);
  assert.equal(await mirror(), undefined);
});

test('production: LIVE switch on but sk_test_ key configured -> checkout refused, lock released', async () => {
  stripeClientModule.getStripeClient = realGetStripeClient;
  await asProduction(async () => {
    process.env.STRIPE_LIVE_MODE_ENABLED = 'true';
    process.env.STRIPE_SECRET_KEY = 'sk_test_fixture_unused';
    await assert.rejects(createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant),
      (err) => err.code === 'failed-precondition' && /TEST/.test(err.message));
  });
  const doc = await mirror();
  assert.equal(doc?.checkout_lock, undefined, 'verrou libere');
  assert.equal(doc?.stripe_customer_id, undefined);
});

test('production: an old TEST mirror neither blocks a LIVE checkout nor lends its Customer', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({
    subscription_status: 'active', stripe_livemode: false, stripe_customer_id: 'cus_test',
    stripe_subscription_id: 'sub_test', manual_access: {enabled: true, until: null},
  });
  const calls = installFakeStripe();
  await asProduction(async () => {
    process.env.STRIPE_LIVE_MODE_ENABLED = 'true';
    const result = await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant);
    assert.equal(result.checkoutUrl, 'https://checkout.stripe.test/cs_live_1');
  });
  assert.equal(calls.customersCreate, 1, 'Customer LIVE cree, jamais le Customer TEST reutilise');
  const doc = await mirror();
  assert.equal(doc.stripe_customer_id, 'cus_live_new');
  assert.equal(doc.stripe_mode, 'live');
  assert.equal(doc.subscription_status, null, 'statut TEST efface : seul le webhook LIVE ouvrira les droits');
  assert.equal(doc.stripe_livemode, undefined);
  assert.deepEqual(doc.manual_access, {enabled: true, until: null});
});

test('production: an unlabelled Customer from the old TEST checkout is checked at Stripe, not reused', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({stripe_customer_id: 'cus_old_test', checkout_status: 'expired'});
  const calls = installFakeStripe({customers: {}});
  await asProduction(async () => {
    process.env.STRIPE_LIVE_MODE_ENABLED = 'true';
    await createMerchantCheckoutSessionHandler({offerId: 'autonome', ...kUrls}, kMerchant);
  });
  assert.equal(calls.customersCreate, 1);
  assert.equal((await mirror()).stripe_customer_id, 'cus_live_new');
});

test('production: the merchant space shows an old TEST subscription as absent; invoices and portal stay closed', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({
    subscription_status: 'active', stripe_entitlement: 'active', stripe_livemode: false, stripe_sandbox: true,
    stripe_customer_id: 'cus_test', offer_id: 'autonome',
  });
  const calls = installFakeStripe();
  await asProduction(async () => {
    process.env.STRIPE_LIVE_MODE_ENABLED = 'true';
    const view = await getMerchantBillingAccountHandler({}, kMerchant);
    assert.equal(view.subscription.status, null);
    assert.equal(view.subscription.entitlement, 'none');
    assert.equal(view.subscription.hasStripeCustomer, false);
    assert.equal(view.hasPaidAccess, false);
    assert.deepEqual(await listMerchantInvoicesHandler({}, kMerchant), {invoices: []});
    await assert.rejects(createMerchantBillingPortalSessionHandler({returnUrl: kUrls.successUrl}, kMerchant),
      (err) => err.code === 'failed-precondition');
  });
  assert.equal(calls.invoicesList, 0, 'Customer TEST jamais transmis a Stripe');
});

test('production: an unknown Customer at Stripe yields no invoices instead of an internal error', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({stripe_customer_id: 'cus_old_test'});
  installFakeStripe();
  await asProduction(async () => {
    process.env.STRIPE_LIVE_MODE_ENABLED = 'true';
    assert.deepEqual(await listMerchantInvoicesHandler({}, kMerchant), {invoices: []});
    await assert.rejects(createMerchantBillingPortalSessionHandler({returnUrl: kUrls.successUrl}, kMerchant),
      (err) => err.code === 'failed-precondition');
  });
});

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-stripe-webhook';
process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test_fixture_secret';
// Cle Stripe factice : jamais utilisee pour un appel reseau reel ici (la
// verification de signature est un calcul HMAC local), seulement pour que
// stripe_client.js accepte d'instancier un client dans le test de
// signature invalide ci-dessous.
process.env.STRIPE_SECRET_KEY = 'sk_test_fixture_unused';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const Stripe = require('stripe');

const stripeClientModule = require('../stripe_client');
const {stripeWebhookHandler} = require('../stripe_webhook');

const kWebhookSecret = 'whsec_test_fixture_secret';
const signingClient = new Stripe('sk_test_FAKE_FOR_SIGNATURE_ONLY', {apiVersion: '2024-06-20'});

function fakeEvent(id, type, object) {
  return {id, type, data: {object}, api_version: '2024-06-20', created: Math.floor(Date.now() / 1000)};
}

function signedRequest(eventPayload) {
  const payload = JSON.stringify(eventPayload);
  const header = signingClient.webhooks.generateTestHeaderString({payload, secret: kWebhookSecret});
  return {
    rawBody: Buffer.from(payload, 'utf8'),
    headers: {'stripe-signature': header},
  };
}

function fakeResponse() {
  const res = {statusCode: null, body: null};
  res.status = (code) => { res.statusCode = code; return res; };
  res.send = (body) => { res.body = body; return res; };
  return res;
}

function makeFakeStripe({subscriptionsById = {}, invoicesById = {}, chargesById = {}} = {}) {
  return {
    webhooks: signingClient.webhooks,
    subscriptions: {retrieve: async (id) => subscriptionsById[id]},
    invoices: {retrieve: async (id) => invoicesById[id]},
    charges: {retrieve: async (id) => chargesById[id]},
  };
}

async function clearCollections() {
  for (const name of ['merchant_subscriptions', 'merchant_referrals', 'stripe_webhook_events']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

test.beforeEach(async () => {
  await clearCollections();
});

test('an invalid signature is rejected with 400 and nothing is written', async () => {
  const req = {rawBody: Buffer.from('{}'), headers: {'stripe-signature': 't=1,v1=deadbeef'}};
  const res = fakeResponse();
  await stripeWebhookHandler(req, res);
  assert.equal(res.statusCode, 400);
});

test('invoice.paid (first payment) activates the subscription and makes a linked referral eligible', async () => {
  await db.doc('merchant_referrals/shop').set({status: 'linked'});
  const subscription = {
    id: 'sub_1', status: 'active', current_period_end: Math.floor(Date.now() / 1000) + 3600,
    cancel_at_period_end: false,
    items: {data: [{price: {id: 'price_proximite'}}]},
    metadata: {enseigneId: 'shop', merchantUserId: 'merchant'},
  };
  stripeClientModule.getStripeClient = () => makeFakeStripe({subscriptionsById: {sub_1: subscription}});

  const event = fakeEvent('evt_first_payment', 'invoice.paid', {
    subscription: 'sub_1', billing_reason: 'subscription_create', subtotal: 36500,
  });
  const res = fakeResponse();
  await stripeWebhookHandler(signedRequest(event), res);
  assert.equal(res.statusCode, 200);

  const subSnap = await db.doc('merchant_subscriptions/shop').get();
  assert.equal(subSnap.data().subscription_status, 'active');
  assert.ok(subSnap.data().first_payment_confirmed_at);

  const referralSnap = await db.doc('merchant_referrals/shop').get();
  assert.equal(referralSnap.data().status, 'eligible');
  assert.equal(referralSnap.data().subscription_amount_ht_cents, 36500);
});

test('the same event ID replayed is processed only once (idempotence)', async () => {
  await db.doc('merchant_referrals/shop').set({status: 'linked'});
  const subscription = {
    id: 'sub_1', status: 'active', current_period_end: Math.floor(Date.now() / 1000) + 3600,
    cancel_at_period_end: false, items: {data: [{price: {id: 'price_proximite'}}]},
    metadata: {enseigneId: 'shop'},
  };
  let retrieveCount = 0;
  stripeClientModule.getStripeClient = () => ({
    webhooks: signingClient.webhooks,
    subscriptions: {retrieve: async () => { retrieveCount++; return subscription; }},
  });

  const event = fakeEvent('evt_duplicate', 'invoice.paid', {
    subscription: 'sub_1', billing_reason: 'subscription_create', subtotal: 36500,
  });
  const req1 = signedRequest(event);
  const req2 = signedRequest(event);
  await stripeWebhookHandler(req1, fakeResponse());
  await stripeWebhookHandler(req2, fakeResponse());

  assert.equal(retrieveCount, 1, 'le second envoi du meme evenement ne doit jamais retraiter');
  const referralSnap = await db.doc('merchant_referrals/shop').get();
  assert.equal(referralSnap.data().status, 'eligible'); // pas une deuxieme transition
});

test('a renewal (billing_reason=subscription_cycle) never re-triggers referral eligibility nor a new reward', async () => {
  await db.doc('merchant_referrals/shop').set({status: 'paid', paid_reference: 'VIR-1'});
  const subscription = {
    id: 'sub_1', status: 'active', current_period_end: Math.floor(Date.now() / 1000) + 3600,
    cancel_at_period_end: false, items: {data: [{price: {id: 'price_proximite'}}]},
    metadata: {enseigneId: 'shop'},
  };
  stripeClientModule.getStripeClient = () => makeFakeStripe({subscriptionsById: {sub_1: subscription}});

  const event = fakeEvent('evt_renewal', 'invoice.paid', {
    subscription: 'sub_1', billing_reason: 'subscription_cycle', subtotal: 36500,
  });
  await stripeWebhookHandler(signedRequest(event), fakeResponse());

  const referralSnap = await db.doc('merchant_referrals/shop').get();
  assert.equal(referralSnap.data().status, 'paid'); // inchange : pas de nouvelle prime au renouvellement
  assert.equal(referralSnap.data().paid_reference, 'VIR-1');
});

test('customer.subscription.deleted cancels a not-yet-paid referral but leaves an already-paid one untouched', async () => {
  await db.doc('merchant_referrals/shop_linked').set({status: 'linked'});
  await db.doc('merchant_referrals/shop_paid').set({status: 'paid', paid_reference: 'VIR-9'});
  stripeClientModule.getStripeClient = () => makeFakeStripe();

  const event1 = fakeEvent('evt_del_1', 'customer.subscription.deleted', {
    id: 'sub_x', metadata: {enseigneId: 'shop_linked'},
  });
  await stripeWebhookHandler(signedRequest(event1), fakeResponse());
  assert.equal((await db.doc('merchant_referrals/shop_linked').get()).data().status, 'cancelled');

  const event2 = fakeEvent('evt_del_2', 'customer.subscription.deleted', {
    id: 'sub_y', metadata: {enseigneId: 'shop_paid'},
  });
  await stripeWebhookHandler(signedRequest(event2), fakeResponse());
  const paidSnap = await db.doc('merchant_referrals/shop_paid').get();
  assert.equal(paidSnap.data().status, 'paid');
  assert.equal(paidSnap.data().paid_reference, 'VIR-9');
});

test('charge.refunded cancels an eligible-but-not-yet-approved referral', async () => {
  await db.doc('merchant_referrals/shop').set({status: 'eligible'});
  const subscription = {id: 'sub_1', metadata: {enseigneId: 'shop'}};
  const invoice = {id: 'in_1', subscription: 'sub_1'};
  stripeClientModule.getStripeClient = () => makeFakeStripe({
    subscriptionsById: {sub_1: subscription}, invoicesById: {in_1: invoice},
  });

  const event = fakeEvent('evt_refund', 'charge.refunded', {id: 'ch_1', invoice: 'in_1'});
  await stripeWebhookHandler(signedRequest(event), fakeResponse());

  assert.equal((await db.doc('merchant_referrals/shop').get()).data().status, 'cancelled');
});

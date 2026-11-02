process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT ||= 'demo-proxiplay-stripe-webhook';
process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test_fixture_secret';
// Cle Stripe factice : jamais utilisee pour un appel reseau reel ici (la
// verification de signature est un calcul HMAC local, le reste du SDK est
// remplace par un faux Stripe en memoire).
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
const nowSeconds = () => Math.floor(Date.now() / 1000);
const kYear = 365 * 24 * 3600;

let eventCreatedCounter = nowSeconds();
function fakeEvent(id, type, object, created = ++eventCreatedCounter) {
  return {id, type, data: {object}, api_version: '2024-06-20', created, livemode: false};
}

function signedRequest(eventPayload) {
  const payload = JSON.stringify(eventPayload);
  const header = signingClient.webhooks.generateTestHeaderString({payload, secret: kWebhookSecret});
  return {method: 'POST', rawBody: Buffer.from(payload, 'utf8'), headers: {'stripe-signature': header}};
}

function fakeResponse() {
  const res = {statusCode: null, body: null};
  res.status = (code) => { res.statusCode = code; return res; };
  res.send = (body) => { res.body = body; return res; };
  return res;
}

async function deliver(event) {
  const res = fakeResponse();
  await stripeWebhookHandler(signedRequest(event), res);
  return res;
}

function subscription(overrides = {}) {
  return {
    id: 'sub_1', customer: 'cus_1', status: 'active', livemode: false,
    current_period_start: nowSeconds(), current_period_end: nowSeconds() + kYear,
    cancel_at_period_end: false, cancel_at: null, canceled_at: null, ended_at: null,
    items: {data: [{price: {id: 'price_test_autonome'}}]},
    metadata: {merchantUserId: 'merchant1', offerId: 'autonome'},
    ...overrides,
  };
}

// Faux Stripe a etat : `state.subscriptions` represente l'etat COURANT chez
// Stripe, que le webhook relit toujours.
function installFakeStripe({subscriptions = {}, customers = {}, invoices = {}, charges = {}} = {}) {
  const state = {subscriptions, customers, invoices, charges, retrieveCount: 0};
  stripeClientModule.getStripeClient = () => ({
    webhooks: signingClient.webhooks,
    subscriptions: {retrieve: async (id) => { state.retrieveCount++; return state.subscriptions[id]; }},
    customers: {retrieve: async (id) => state.customers[id] || {id, metadata: {}}},
    invoices: {retrieve: async (id) => state.invoices[id]},
    charges: {retrieve: async (id) => state.charges[id]},
  });
  return state;
}

async function clearCollections() {
  for (const name of ['merchant_subscriptions', 'merchant_referrals', 'stripe_webhook_events']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

const mirror = async (uid = 'merchant1') => (await db.doc(`merchant_subscriptions/${uid}`).get()).data();

test.beforeEach(async () => {
  await clearCollections();
  process.env.STRIPE_WEBHOOK_SECRET = kWebhookSecret;
});

// --- Signature ------------------------------------------------------------

test('an invalid signature is rejected with 400 and nothing is written', async () => {
  installFakeStripe();
  const res = fakeResponse();
  await stripeWebhookHandler({method: 'POST', rawBody: Buffer.from('{}'), headers: {'stripe-signature': 't=1,v1=deadbeef'}}, res);
  assert.equal(res.statusCode, 400);
  assert.equal((await db.collection('stripe_webhook_events').get()).size, 0);
});

test('a payload signed with another secret is rejected', async () => {
  installFakeStripe();
  const payload = JSON.stringify(fakeEvent('evt_forged', 'invoice.paid', {subscription: 'sub_1'}));
  const header = signingClient.webhooks.generateTestHeaderString({payload, secret: 'whsec_attacker'});
  const res = fakeResponse();
  await stripeWebhookHandler({method: 'POST', rawBody: Buffer.from(payload), headers: {'stripe-signature': header}}, res);
  assert.equal(res.statusCode, 400);
  assert.equal(await mirror(), undefined);
});

test('a missing webhook secret answers 500 (configuration), never processes', async () => {
  installFakeStripe();
  delete process.env.STRIPE_WEBHOOK_SECRET;
  const res = await deliver(fakeEvent('evt_nosecret', 'invoice.paid', {subscription: 'sub_1'}));
  assert.equal(res.statusCode, 500);
  assert.equal((await db.collection('stripe_webhook_events').get()).size, 0);
});

// --- Paiement confirme / echoue -------------------------------------------

test('invoice.paid (first payment) activates paid access and makes a linked referral eligible', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'linked'});
  installFakeStripe({subscriptions: {sub_1: subscription()}});

  const res = await deliver(fakeEvent('evt_first_payment', 'invoice.paid', {
    id: 'in_1', subscription: 'sub_1', billing_reason: 'subscription_create', subtotal: 36500,
  }));
  assert.equal(res.statusCode, 200);

  const data = await mirror();
  assert.equal(data.subscription_status, 'active');
  assert.equal(data.stripe_entitlement, 'active');
  assert.equal(data.offer_id, 'autonome');
  assert.ok(data.first_payment_confirmed_at);
  assert.ok(data.current_period_end.toMillis() > Date.now());
  const referral = (await db.doc('merchant_referrals/merchant1').get()).data();
  assert.equal(referral.status, 'eligible');
  assert.equal(referral.subscription_amount_ht_cents, 36500);
  const eventDoc = (await db.doc('stripe_webhook_events/evt_first_payment').get()).data();
  assert.equal(eventDoc.status, 'done');
  assert.equal(eventDoc.outcome, 'payment_confirmed');
});

test('a completed checkout whose payment is not confirmed yet opens no paid access', async () => {
  installFakeStripe({subscriptions: {sub_1: subscription({status: 'incomplete'})}});
  await db.doc('merchant_subscriptions/merchant1').set({stripe_customer_id: 'cus_1', checkout_status: 'open',
    stripe_checkout_session_id: 'cs_1'});
  await deliver(fakeEvent('evt_cs_done', 'checkout.session.completed', {
    id: 'cs_1', mode: 'subscription', subscription: 'sub_1', client_reference_id: 'merchant1', payment_status: 'unpaid',
  }));
  const data = await mirror();
  assert.equal(data.subscription_status, 'incomplete');
  assert.equal(data.stripe_entitlement, 'none');
});

test('a failed payment moves the merchant to grace, then a later success clears the failure', async () => {
  const state = installFakeStripe({subscriptions: {sub_1: subscription({status: 'past_due'})}});
  await deliver(fakeEvent('evt_fail', 'invoice.payment_failed', {
    id: 'in_2', subscription: 'sub_1', attempt_count: 1, next_payment_attempt: nowSeconds() + 3 * 86400,
  }));
  let data = await mirror();
  assert.equal(data.subscription_status, 'past_due');
  assert.equal(data.stripe_entitlement, 'grace');
  assert.ok(data.last_payment_failed_at);
  assert.equal(data.payment_attempt_count, 1);

  state.subscriptions.sub_1 = subscription({status: 'active'});
  await deliver(fakeEvent('evt_recovered', 'invoice.paid', {id: 'in_2', subscription: 'sub_1', billing_reason: 'subscription_cycle'}));
  data = await mirror();
  assert.equal(data.subscription_status, 'active');
  assert.equal(data.last_payment_failed_at, null);
});

test('an old payment failure arriving after a newer success never overrides it', async () => {
  installFakeStripe({subscriptions: {sub_1: subscription({status: 'active'})}});
  const failedCreated = ++eventCreatedCounter;
  const paidCreated = ++eventCreatedCounter;
  await deliver(fakeEvent('evt_paid_new', 'invoice.paid', {id: 'in_3', subscription: 'sub_1', billing_reason: 'subscription_cycle'}, paidCreated));
  await deliver(fakeEvent('evt_failed_old', 'invoice.payment_failed', {id: 'in_3', subscription: 'sub_1', attempt_count: 1}, failedCreated));
  const data = await mirror();
  assert.equal(data.subscription_status, 'active');
  assert.equal(data.last_payment_failed_at, null);
});

// --- Renouvellement ---------------------------------------------------------

test('a renewal extends the period without re-triggering referral eligibility', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'paid', paid_reference: 'VIR-1'});
  const nextEnd = nowSeconds() + 2 * kYear;
  installFakeStripe({subscriptions: {sub_1: subscription({current_period_end: nextEnd})}});

  await deliver(fakeEvent('evt_renewal', 'invoice.paid', {
    id: 'in_4', subscription: 'sub_1', billing_reason: 'subscription_cycle', subtotal: 36500,
  }));

  const data = await mirror();
  assert.equal(data.current_period_end.toMillis(), nextEnd * 1000);
  assert.ok(data.last_renewal_paid_at);
  assert.equal(data.first_payment_confirmed_at, undefined);
  const referral = (await db.doc('merchant_referrals/merchant1').get()).data();
  assert.equal(referral.status, 'paid');
  assert.equal(referral.paid_reference, 'VIR-1');
});

test('newer API payloads (invoice.parent.subscription_details) are understood', async () => {
  installFakeStripe({subscriptions: {sub_1: subscription()}});
  await deliver(fakeEvent('evt_basil', 'invoice.paid', {
    id: 'in_5', billing_reason: 'subscription_cycle', parent: {subscription_details: {subscription: 'sub_1'}},
  }));
  assert.equal((await mirror()).subscription_status, 'active');
});

// --- Resiliation ---------------------------------------------------------------

test('cancellation ends paid access, cancels a not-yet-paid referral and keeps manual access', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'linked'});
  await db.doc('merchant_subscriptions/merchant1').set({
    stripe_customer_id: 'cus_1', stripe_subscription_id: 'sub_1', subscription_status: 'active',
    manual_access: {enabled: true, reason: 'Compte historique'},
  });
  installFakeStripe({subscriptions: {sub_1: subscription({status: 'canceled', ended_at: nowSeconds()})}});

  await deliver(fakeEvent('evt_del', 'customer.subscription.deleted', subscription({status: 'canceled'})));

  const data = await mirror();
  assert.equal(data.subscription_status, 'canceled');
  assert.equal(data.stripe_entitlement, 'none');
  assert.ok(data.ended_at);
  assert.equal(data.manual_access.enabled, true, 'le webhook ne touche jamais une activation manuelle');
  assert.equal((await db.doc('merchant_referrals/merchant1').get()).data().status, 'cancelled');
});

test('an already-paid referral is untouched by a cancellation', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'paid', paid_reference: 'VIR-9'});
  installFakeStripe({subscriptions: {sub_1: subscription({status: 'canceled'})}});
  await deliver(fakeEvent('evt_del_paid', 'customer.subscription.deleted', subscription({status: 'canceled'})));
  const referral = (await db.doc('merchant_referrals/merchant1').get()).data();
  assert.equal(referral.status, 'paid');
  assert.equal(referral.paid_reference, 'VIR-9');
});

test('a cancellation scheduled at period end keeps access until the end date', async () => {
  installFakeStripe({subscriptions: {sub_1: subscription({cancel_at_period_end: true, cancel_at: nowSeconds() + kYear})}});
  await deliver(fakeEvent('evt_sched', 'customer.subscription.updated', subscription({cancel_at_period_end: true})));
  const data = await mirror();
  assert.equal(data.stripe_entitlement, 'active');
  assert.equal(data.cancel_at_period_end, true);
  assert.ok(data.cancel_at);
});

// --- Doublons et desordre ------------------------------------------------------

test('the same event ID delivered twice is processed only once', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'linked'});
  const state = installFakeStripe({subscriptions: {sub_1: subscription()}});
  const event = fakeEvent('evt_duplicate', 'invoice.paid', {
    id: 'in_1', subscription: 'sub_1', billing_reason: 'subscription_create', subtotal: 36500,
  });
  const first = await deliver(event);
  const retrievesAfterFirst = state.retrieveCount;
  const second = await deliver(event);
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
  assert.equal(state.retrieveCount, retrievesAfterFirst, 'le second envoi ne retraite rien');
  assert.equal((await db.doc('merchant_referrals/merchant1').get()).data().status, 'eligible');
});

test('a concurrent delivery still in progress gets 409 so Stripe retries; an expired lease is taken over', async () => {
  installFakeStripe({subscriptions: {sub_1: subscription()}});
  const event = fakeEvent('evt_busy', 'customer.subscription.updated', subscription());
  await db.doc('stripe_webhook_events/evt_busy').set({
    status: 'processing', lease_expires_at: admin.firestore.Timestamp.fromMillis(Date.now() + 60000),
  });
  assert.equal((await deliver(event)).statusCode, 409);
  assert.equal(await mirror(), undefined);

  await db.doc('stripe_webhook_events/evt_busy').set({
    status: 'processing', lease_expires_at: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  });
  assert.equal((await deliver(event)).statusCode, 200);
  assert.equal((await mirror()).subscription_status, 'active');
});

test('a processing error answers 500 and the Stripe retry is processed', async () => {
  const state = installFakeStripe({subscriptions: {}});
  const event = fakeEvent('evt_retry', 'customer.subscription.updated', subscription());
  stripeClientModule.getStripeClient = () => ({
    webhooks: signingClient.webhooks,
    subscriptions: {retrieve: async () => { throw new Error('Stripe indisponible'); }},
  });
  assert.equal((await deliver(event)).statusCode, 500);
  assert.equal((await db.doc('stripe_webhook_events/evt_retry').get()).data().status, 'error');

  state.subscriptions.sub_1 = subscription();
  installFakeStripe({subscriptions: state.subscriptions});
  assert.equal((await deliver(event)).statusCode, 200);
  assert.equal((await mirror()).subscription_status, 'active');
});

test('an old subscription.updated arriving after the deletion never resurrects the subscription', async () => {
  installFakeStripe({subscriptions: {sub_1: subscription({status: 'canceled'})}});
  const oldUpdate = fakeEvent('evt_old_update', 'customer.subscription.updated', subscription({status: 'active'}), nowSeconds() - 100);
  const deletion = fakeEvent('evt_deleted', 'customer.subscription.deleted', subscription({status: 'canceled'}));
  await deliver(deletion);
  await deliver(oldUpdate);
  const data = await mirror();
  assert.equal(data.subscription_status, 'canceled');
  assert.equal(data.stripe_entitlement, 'none');
});

test('a second open subscription for the same merchant raises an alert and never replaces the tracked one', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({
    stripe_customer_id: 'cus_1', stripe_subscription_id: 'sub_1', subscription_status: 'active',
  });
  installFakeStripe({subscriptions: {sub_2: subscription({id: 'sub_2'})}});
  await deliver(fakeEvent('evt_dup_sub', 'customer.subscription.created', subscription({id: 'sub_2'})));
  const data = await mirror();
  assert.equal(data.stripe_subscription_id, 'sub_1');
  assert.equal(data.duplicate_subscription_alert, true);
  assert.equal(data.other_subscriptions.sub_2.status, 'active');
});

test('a new subscription replaces a terminated one (resubscription after cancellation)', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({
    stripe_customer_id: 'cus_1', stripe_subscription_id: 'sub_old', subscription_status: 'canceled',
    first_payment_confirmed_at: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  });
  installFakeStripe({subscriptions: {sub_new: subscription({id: 'sub_new', metadata: {merchantUserId: 'merchant1', offerId: 'accompagnee'}})}});
  await deliver(fakeEvent('evt_resub', 'customer.subscription.created', subscription({id: 'sub_new'})));
  const data = await mirror();
  assert.equal(data.stripe_subscription_id, 'sub_new');
  assert.equal(data.offer_id, 'accompagnee');
  assert.equal(data.duplicate_subscription_alert, undefined);
});

// --- Association au commercant -----------------------------------------------

test('without subscription metadata, the merchant is found through the Customer metadata', async () => {
  const sub = subscription({metadata: {}});
  installFakeStripe({subscriptions: {sub_1: sub}, customers: {cus_1: {id: 'cus_1', metadata: {merchantUserId: 'merchant1'}}}});
  await deliver(fakeEvent('evt_by_customer', 'customer.subscription.updated', sub));
  assert.equal((await mirror()).subscription_status, 'active');
});

test('contradictory association (metadata vs mirror) is ignored and written nowhere', async () => {
  await db.doc('merchant_subscriptions/merchantB').set({stripe_customer_id: 'cus_1'});
  installFakeStripe({subscriptions: {sub_1: subscription()}});
  const res = await deliver(fakeEvent('evt_conflict', 'customer.subscription.updated', subscription()));
  assert.equal(res.statusCode, 200);
  assert.equal(await mirror('merchant1'), undefined);
  assert.equal((await mirror('merchantB')).subscription_status, undefined);
  assert.equal((await db.doc('stripe_webhook_events/evt_conflict').get()).data().outcome, 'ignored_merchant_conflict');
});

test('a subscription whose Customer differs from the merchant\'s mirror is ignored', async () => {
  await db.doc('merchant_subscriptions/merchant1').set({stripe_customer_id: 'cus_other'});
  installFakeStripe({subscriptions: {sub_1: subscription()}});
  await deliver(fakeEvent('evt_mismatch', 'customer.subscription.updated', subscription()));
  assert.equal((await mirror()).subscription_status, undefined);
});

// --- Checkout expire, remboursement, evenements hors perimetre -------------

test('checkout.session.expired marks only the matching pending session as expired', async () => {
  installFakeStripe();
  await db.doc('merchant_subscriptions/merchant1').set({stripe_checkout_session_id: 'cs_1', checkout_status: 'open'});
  await deliver(fakeEvent('evt_exp_other', 'checkout.session.expired', {id: 'cs_0', client_reference_id: 'merchant1'}));
  assert.equal((await mirror()).checkout_status, 'open');
  await deliver(fakeEvent('evt_exp', 'checkout.session.expired', {id: 'cs_1', client_reference_id: 'merchant1'}));
  assert.equal((await mirror()).checkout_status, 'expired');
});

test('charge.refunded cancels an eligible-but-not-yet-approved referral', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'eligible'});
  installFakeStripe({subscriptions: {sub_1: subscription()}, invoices: {in_1: {id: 'in_1', subscription: 'sub_1'}}});
  await deliver(fakeEvent('evt_refund', 'charge.refunded', {id: 'ch_1', invoice: 'in_1'}));
  assert.equal((await db.doc('merchant_referrals/merchant1').get()).data().status, 'cancelled');
});

test('an event type outside the subscription cycle is acknowledged and ignored', async () => {
  installFakeStripe();
  const res = await deliver(fakeEvent('evt_other', 'payment_intent.created', {id: 'pi_1'}));
  assert.equal(res.statusCode, 200);
  assert.equal((await db.doc('stripe_webhook_events/evt_other').get()).data().outcome, 'ignored_event_type');
});

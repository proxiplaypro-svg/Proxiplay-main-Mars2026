// Merchant referral at merchant signup (ambassador code), and manual
// confirmation of the first paid subscription. Merchant program only: the
// player referral program (share_promo) is never touched.
// Isolated demo emulators (Firestore + Auth) only.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) throw Error('Isolated demo emulators required');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const {
  createMerchantAccountWithReferralHandler: signupHandler,
  resumeMerchantSignupLinkForUser,
} = require('../merchant_signup_referral');
const {
  adminConfirmMerchantFirstPaymentHandler: confirm,
  adminApproveMerchantReferralHandler: approve,
  adminMarkMerchantReferralPaidHandler: markGiftCardsGiven,
  markReferralEligibleOnFirstPayment,
  kRewardAmountCents,
} = require('../merchant_referral_engine');

const hash = s => crypto.createHash('sha256').update(s).digest('hex');
let ip = 0;
const signup = d => signupHandler(d, {rawRequest: {ip: `10.2.0.${++ip % 250}`}});
const input = (name, code) => ({email: `${name}@shop.test`, password: 'shop-password-1', code,
  requestId: crypto.randomUUID()});
const uidOf = d => 'msu_' + hash(d.requestId).slice(0, 48);
const asAdmin = {auth: {uid: 'admin_uid'}};
const referral = async uid => (await db.doc('merchant_referrals/' + uid).get()).data();
const accountsFor = async email => (await admin.auth().listUsers()).users.filter(u => u.email === email);

test.beforeEach(async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const r = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/accounts`, {method: 'DELETE'});
  assert.ok(r.ok);
  await Promise.all([
    db.doc('users/admin_uid').set({user_role: 'admin'}),
    db.doc('users/player1').set({user_role: 'joueur'}),
    db.doc('users/shop1').set({user_role: 'commercant'}),
    // Existing code, created before `kind` existed: an ambassador code.
    db.doc('merchant_referral_codes/PLAYERA2').set({inviter_user_id: db.doc('users/player1')}),
    db.doc('merchant_referral_codes/SHOPB234').set({kind: 'ambassador', inviter_user_id: db.doc('users/shop1')}),
    db.doc('merchant_referral_codes/UCDUNKERQUE').set({kind: 'partner', partner_id: 'ucd'}),
  ]);
});

test('an existing code without kind links the new merchant to its player ambassador, no reward yet', async () => {
  const d = input('bakery', ' playera2 ');
  assert.deepEqual(await signup(d), {success: true, linked: true});
  const [account] = await accountsFor('bakery@shop.test');
  assert.equal(account.uid, uidOf(d));
  const r = await referral(account.uid);
  assert.equal(r.status, 'linked');
  assert.equal(r.inviter_user_id.path, 'users/player1');
  assert.equal(r.inviter_kind, 'joueur');
  assert.equal(r.source, 'merchant_signup');
  assert.equal(r.reward_amount_cents, kRewardAmountCents);
  assert.equal(r.eligible_at, null);
  // Merchant program only: nothing in the player referral program.
  for (const c of ['referrals', 'referral_reward_pending', 'reward_events']) {
    assert.equal((await db.collection(c).get()).size, 0, c);
  }
  // The operation never stores the password.
  const op = (await db.doc('_merchant_signup_operations/' + hash(d.requestId)).get()).data();
  assert.equal(op.status, 'completed');
  assert.equal(JSON.stringify(op).includes('shop-password-1'), false);
});

test('a merchant can be an ambassador too', async () => {
  const d = input('florist', 'SHOPB234');
  await signup(d);
  const r = await referral(uidOf(d));
  assert.equal(r.inviter_user_id.path, 'users/shop1');
  assert.equal(r.inviter_kind, 'commercant');
});

test('invalid, player or partner codes, unavailable inviter or programme: refused before any account', async () => {
  const cases = [
    ['typo', 'NOPE2345', e => e.code === 'not-found'],
    // A player referral code (share_promo) is never a merchant code.
    ['player-code', 'A1B2C3D4', e => e.code === 'not-found'],
    ['partner', 'UCDUNKERQUE', e => e.code === 'failed-precondition' && e.details?.reason === 'partner_code_unavailable'],
  ];
  await db.doc('referrals/R1').set({inviteCode: 'A1B2C3D4', inviterUid: 'player1', status: 'pending'});
  for (const [name, code, check] of cases) {
    await assert.rejects(signup(input(name, code)), check, name);
    assert.equal((await accountsFor(`${name}@shop.test`)).length, 0, name);
  }
  await db.doc('users/player1').update({account_status: 'suspended'});
  await assert.rejects(signup(input('suspended', 'PLAYERA2')),
    e => e.code === 'failed-precondition' && e.details?.reason === 'code_unavailable');
  await db.doc('users/player1').update({account_status: 'approved'});
  await db.doc('app_config/merchant_referral').set({enabled: false});
  await assert.rejects(signup(input('closed', 'PLAYERA2')),
    e => e.code === 'failed-precondition' && e.details?.reason === 'program_unavailable');
  assert.equal((await accountsFor('suspended@shop.test')).length + (await accountsFor('closed@shop.test')).length, 0);
  assert.equal((await db.collection('merchant_referrals').get()).size, 0);
  assert.equal((await db.doc('referrals/R1').get()).data().status, 'pending');
});

test('an existing address is never linked and keeps its account untouched', async () => {
  const existing = await admin.auth().createUser({email: 'known@shop.test', password: 'other-pass-1'});
  await assert.rejects(signup(input('known', 'PLAYERA2')),
    e => e.code === 'already-exists' && e.details?.reason === 'email_exists' && e.details?.accountCreated === false);
  assert.equal((await accountsFor('known@shop.test'))[0].uid, existing.uid);
  assert.equal((await db.collection('merchant_referrals').get()).size, 0);
});

test('simultaneous and repeated calls create one account and one link', async () => {
  const d = input('race', 'PLAYERA2');
  const results = await Promise.allSettled([signup(d), signup(d), signup(d)]);
  assert.ok(results.some(r => r.status === 'fulfilled'), JSON.stringify(results));
  assert.deepEqual(await signup(d), {success: true, linked: true});
  assert.equal((await accountsFor('race@shop.test')).length, 1);
  assert.equal((await db.collection('merchant_referrals').get()).size, 1);
  // Same request with another code: refused, the link never changes.
  await assert.rejects(signup({...d, code: 'SHOPB234'}), {code: 'failed-precondition'});
  assert.equal((await referral(uidOf(d))).inviter_user_id.path, 'users/player1');
});

test('an interruption after the account creation is completed by a retry or at first sign-in, never lost', async () => {
  // Crash right after the account creation: operation open, no link yet.
  const interrupted = async name => {
    const d = input(name, 'PLAYERA2');
    await db.doc('_merchant_signup_operations/' + hash(d.requestId)).set({uid: uidOf(d),
      email_hash: hash(d.email), code: 'PLAYERA2', inviter_path: 'users/player1', inviter_kind: 'joueur',
      status: 'pending'});
    await admin.auth().createUser({uid: uidOf(d), email: d.email, password: d.password});
    return d;
  };
  const retried = await interrupted('retried');
  const signedIn = await interrupted('signed-in');
  // Incomplete operations are identifiable.
  const open = await db.collection('_merchant_signup_operations').where('status', '!=', 'completed').get();
  assert.equal(open.size, 2);
  // The app retries with the same request.
  assert.deepEqual(await signup(retried), {success: true, linked: true});
  // Or the merchant signs in: the profile creation completes it.
  assert.deepEqual(await resumeMerchantSignupLinkForUser(db, uidOf(signedIn)), {resumed: true});
  for (const d of [retried, signedIn]) assert.equal((await referral(uidOf(d))).status, 'linked');
  // Replays change nothing; a profile without operation is ignored.
  assert.deepEqual(await resumeMerchantSignupLinkForUser(db, uidOf(signedIn)), {resumed: false});
  assert.deepEqual(await resumeMerchantSignupLinkForUser(db, 'player1'), {resumed: false});
  assert.equal((await db.collection('merchant_referrals').get()).size, 2);
  // An operation whose account was never created stays identifiable, nothing linked.
  const abandoned = input('abandoned', 'PLAYERA2');
  await db.doc('_merchant_signup_operations/' + hash(abandoned.requestId)).set({uid: uidOf(abandoned),
    email_hash: hash(abandoned.email), code: 'PLAYERA2', inviter_path: 'users/player1', status: 'pending'});
  assert.deepEqual(await resumeMerchantSignupLinkForUser(db, uidOf(abandoned)), {resumed: false});
  assert.equal(await referral(uidOf(abandoned)), undefined);
});

test('first paid subscription: manual confirmation once, traced, compatible with the Stripe webhook', async () => {
  const d = input('paid', 'PLAYERA2'); await signup(d);
  const uid = uidOf(d);
  // Admin only, with a reference and a past date.
  await assert.rejects(confirm({merchantUserId: uid, paymentReference: 'FAC-1', paidAt: '2026-10-20'},
    {auth: {uid: 'player1'}}), {code: 'permission-denied'});
  await assert.rejects(confirm({merchantUserId: uid, paymentReference: '', paidAt: '2026-10-20'}, asAdmin),
    {code: 'invalid-argument'});
  await assert.rejects(confirm({merchantUserId: uid, paymentReference: 'FAC-1', paidAt: '2999-01-01'}, asAdmin),
    {code: 'invalid-argument'});
  // No reward before the payment: approval is refused while only linked.
  await assert.rejects(approve({merchantUserId: uid}, asAdmin), {code: 'failed-precondition'});

  await confirm({merchantUserId: uid, paymentReference: 'VIR-2026-0042', paidAt: '2026-10-20'}, asAdmin);
  let r = await referral(uid);
  assert.equal(r.status, 'eligible');
  assert.equal(r.payment_confirmation.method, 'manual');
  assert.equal(r.payment_confirmation.reference, 'VIR-2026-0042');
  assert.equal(r.payment_confirmation.confirmed_by, 'admin_uid');
  assert.equal(r.first_payment_confirmed_at.toDate().toISOString(), '2026-10-20T00:00:00.000Z');
  // Never twice: neither by the Admin nor by the Stripe webhook afterwards.
  await assert.rejects(confirm({merchantUserId: uid, paymentReference: 'VIR-2', paidAt: '2026-10-21'}, asAdmin),
    {code: 'failed-precondition'});
  await markReferralEligibleOnFirstPayment(db, {merchantUserId: uid, subscriptionAmountHtCents: 36000,
    stripeSubscriptionId: 'sub_late'});
  r = await referral(uid);
  assert.equal(r.stripe_subscription_id, null);
  assert.equal(r.payment_confirmation.reference, 'VIR-2026-0042');
  // Then approval and gift cards handed over, as before.
  await approve({merchantUserId: uid}, asAdmin);
  await markGiftCardsGiven({merchantUserId: uid, paidReference: 'BONS-0042'}, asAdmin);
  r = await referral(uid);
  assert.equal(r.status, 'paid');
  assert.equal(r.paid_reference, 'BONS-0042');
  assert.equal(r.reward_amount_cents, 5000);
});

test('when the Stripe webhook confirmed the payment first, the manual confirmation is refused', async () => {
  const d = input('stripe', 'PLAYERA2'); await signup(d);
  await markReferralEligibleOnFirstPayment(db, {merchantUserId: uidOf(d), subscriptionAmountHtCents: 36000,
    stripeSubscriptionId: 'sub_1'});
  await assert.rejects(confirm({merchantUserId: uidOf(d), paymentReference: 'FAC-9', paidAt: '2026-10-20'}, asAdmin),
    {code: 'failed-precondition'});
  const r = await referral(uidOf(d));
  assert.equal(r.status, 'eligible');
  assert.equal(r.stripe_subscription_id, 'sub_1');
  assert.equal(r.payment_confirmation, null);
});

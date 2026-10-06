process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-merchant-referral';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const {
  markReferralEligibleOnFirstPayment,
  cancelReferralIfNotYetPaid,
  generateMerchantReferralCodeHandler,
  adminApproveMerchantReferralHandler,
  adminRejectMerchantReferralHandler,
  adminMarkMerchantReferralPaidHandler,
  adminSetMerchantCustomOfferHandler,
} = require('../merchant_referral_engine');

async function clearCollections() {
  for (const name of ['merchant_referrals', 'merchant_referral_codes', 'merchant_custom_offers', 'users']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

test.beforeEach(async () => {
  await clearCollections();
  await db.doc('users/admin_uid').set({user_role: 'admin'});
});

test('generateMerchantReferralCode is idempotent: the same player always gets the same code back', async () => {
  const first = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'player1'}});
  const second = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'player1'}});
  assert.equal(first.code, second.code);
  const codesSnap = await db.collection('merchant_referral_codes')
    .where('inviter_user_id', '==', db.doc('users/player1')).get();
  assert.equal(codesSnap.size, 1);
});

test('two different players never receive the same code', async () => {
  const a = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'player_a'}});
  const b = await generateMerchantReferralCodeHandler({}, {auth: {uid: 'player_b'}});
  assert.notEqual(a.code, b.code);
});

test('markReferralEligibleOnFirstPayment transitions linked -> eligible exactly once (replay-safe)', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'linked'});
  await markReferralEligibleOnFirstPayment(db, {
    merchantUserId: 'merchant1', subscriptionAmountHtCents: 36500, stripeSubscriptionId: 'sub_1',
  });
  let snap = await db.doc('merchant_referrals/merchant1').get();
  assert.equal(snap.data().status, 'eligible');
  assert.ok(snap.data().eligible_at);
  const eligibleAtFirst = snap.data().eligible_at;

  // Replay (ex: retry webhook ou renouvellement N+1) : jamais de nouvelle
  // transition, jamais une deuxieme "eligibilite".
  await markReferralEligibleOnFirstPayment(db, {
    merchantUserId: 'merchant1', subscriptionAmountHtCents: 36500, stripeSubscriptionId: 'sub_1',
  });
  snap = await db.doc('merchant_referrals/merchant1').get();
  assert.equal(snap.data().status, 'eligible');
  assert.deepEqual(snap.data().eligible_at, eligibleAtFirst);
});

test('markReferralEligibleOnFirstPayment is a no-op when there is no linked referral', async () => {
  await markReferralEligibleOnFirstPayment(db, {
    merchantUserId: 'no_referral_here', subscriptionAmountHtCents: 36500, stripeSubscriptionId: 'sub_1',
  });
  const snap = await db.doc('merchant_referrals/no_referral_here').get();
  assert.equal(snap.exists, false);
});

test('cancelReferralIfNotYetPaid cancels a linked/eligible referral but never touches an already-paid one', async () => {
  await db.doc('merchant_referrals/merchant_linked').set({status: 'linked'});
  await cancelReferralIfNotYetPaid(db, 'merchant_linked', 'subscription_cancelled');
  assert.equal((await db.doc('merchant_referrals/merchant_linked').get()).data().status, 'cancelled');

  await db.doc('merchant_referrals/merchant_paid').set({status: 'paid', paid_reference: 'VIR-1'});
  await cancelReferralIfNotYetPaid(db, 'merchant_paid', 'refunded');
  const paidSnap = await db.doc('merchant_referrals/merchant_paid').get();
  assert.equal(paidSnap.data().status, 'paid'); // jamais de recuperation automatique
  assert.equal(paidSnap.data().paid_reference, 'VIR-1');
});

test('admin approve requires status=eligible, and a non-admin caller is rejected', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'eligible'});
  await assert.rejects(
    () => adminApproveMerchantReferralHandler({merchantUserId: 'merchant1'}, {auth: {uid: 'attacker'}}),
    (err) => err.code === 'permission-denied',
  );
  const result = await adminApproveMerchantReferralHandler({merchantUserId: 'merchant1'}, {auth: {uid: 'admin_uid'}});
  assert.equal(result.status, 'approved');

  await db.doc('merchant_referrals/merchant_linked_only').set({status: 'linked'});
  await assert.rejects(
    () => adminApproveMerchantReferralHandler({merchantUserId: 'merchant_linked_only'}, {auth: {uid: 'admin_uid'}}),
    (err) => err.code === 'failed-precondition',
  );
});

test('admin reject requires a reason and works from linked/eligible/approved, never after paid', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'eligible'});
  await assert.rejects(
    () => adminRejectMerchantReferralHandler({merchantUserId: 'merchant1', reason: ''}, {auth: {uid: 'admin_uid'}}),
    (err) => err.code === 'invalid-argument',
  );
  const result = await adminRejectMerchantReferralHandler(
    {merchantUserId: 'merchant1', reason: 'fraude suspectee'}, {auth: {uid: 'admin_uid'}});
  assert.equal(result.status, 'rejected');
  assert.equal((await db.doc('merchant_referrals/merchant1').get()).data().rejected_reason, 'fraude suspectee');

  await db.doc('merchant_referrals/merchant_paid').set({status: 'paid'});
  await assert.rejects(
    () => adminRejectMerchantReferralHandler({merchantUserId: 'merchant_paid', reason: 'trop tard'}, {auth: {uid: 'admin_uid'}}),
    (err) => err.code === 'failed-precondition',
  );
});

test('admin markPaid requires status=approved and a non-empty payment reference', async () => {
  await db.doc('merchant_referrals/merchant1').set({status: 'eligible'});
  await assert.rejects(
    () => adminMarkMerchantReferralPaidHandler(
      {merchantUserId: 'merchant1', paidReference: 'VIR-42'}, {auth: {uid: 'admin_uid'}}),
    (err) => err.code === 'failed-precondition',
  );

  await db.doc('merchant_referrals/merchant1').set({status: 'approved'});
  await assert.rejects(
    () => adminMarkMerchantReferralPaidHandler({merchantUserId: 'merchant1', paidReference: ''}, {auth: {uid: 'admin_uid'}}),
    (err) => err.code === 'invalid-argument',
  );
  const result = await adminMarkMerchantReferralPaidHandler(
    {merchantUserId: 'merchant1', paidReference: 'VIR-42'}, {auth: {uid: 'admin_uid'}});
  assert.equal(result.status, 'paid');
  const snap = await db.doc('merchant_referrals/merchant1').get();
  assert.equal(snap.data().paid_reference, 'VIR-42');
  assert.ok(snap.data().paid_at);
});

test('adminSetMerchantCustomOffer is reserved to admins and rejects a non-positive amount', async () => {
  await assert.rejects(
    () => adminSetMerchantCustomOfferHandler(
      {merchantUserId: 'merchant1', amountHtCents: 250000}, {auth: {uid: 'attacker'}}),
    (err) => err.code === 'permission-denied',
  );
  await assert.rejects(
    () => adminSetMerchantCustomOfferHandler(
      {merchantUserId: 'merchant1', amountHtCents: 0}, {auth: {uid: 'admin_uid'}}),
    (err) => err.code === 'invalid-argument',
  );
  await assert.rejects(
    () => adminSetMerchantCustomOfferHandler(
      {merchantUserId: 'merchant1', amountHtCents: -500}, {auth: {uid: 'admin_uid'}}),
    (err) => err.code === 'invalid-argument',
  );
});

test('adminSetMerchantCustomOffer sets a negotiated price and can later remove it (amountHtCents=null)', async () => {
  const result = await adminSetMerchantCustomOfferHandler(
    {merchantUserId: 'merchant1', amountHtCents: 250000, label: 'Tarif 5 enseignes'},
    {auth: {uid: 'admin_uid'}},
  );
  assert.equal(result.status, 'set');
  const snap = await db.doc('merchant_custom_offers/merchant1').get();
  assert.equal(snap.data().amount_ht_cents, 250000);
  assert.equal(snap.data().label, 'Tarif 5 enseignes');
  assert.equal(snap.data().created_by, 'admin_uid');

  const removal = await adminSetMerchantCustomOfferHandler(
    {merchantUserId: 'merchant1', amountHtCents: null}, {auth: {uid: 'admin_uid'}});
  assert.equal(removal.status, 'removed');
  const afterRemoval = await db.doc('merchant_custom_offers/merchant1').get();
  assert.equal(afterRemoval.exists, false);
});

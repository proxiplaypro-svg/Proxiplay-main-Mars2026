// Google signup with a referral code (createReferralGoogleAccount): Firebase
// decides whether the account is new (signInWithIdp isNewUser). Covers
// existing accounts, concurrent calls, failure then recovery, deleted then
// recreated accounts (new accounts, an accepted trade-off), and reuse of the Google token by the app afterwards.
// Isolated demo emulators (Firestore + Auth) only; the Auth emulator accepts
// an unsigned JSON Google ID token.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) throw Error('Isolated demo emulators required');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const share = require('../lib/share_promo');
const signup = ft.wrap(share.createReferralGoogleAccount);
const retryWorker = ft.wrap(share.retryReferralRewards);
test.after(() => ft.cleanup());

const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
let ip = 0;
const call = (idToken, inviteCode) => signup({idToken, inviteCode}, {rawRequest: {ip: `10.1.0.${++ip % 250}`}});
const googleToken = (sub, email) => JSON.stringify({sub, email, email_verified: true});
const subHash = sub => crypto.createHash('sha256').update(sub).digest('hex');
// What the app does after the server call: Firebase sign-in with the same token.
async function appSignIn(idToken) {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=app-key`, {
    method: 'POST', headers: {'content-type': 'application/json'},
    body: JSON.stringify({requestUri: 'http://localhost', returnSecureToken: true,
      postBody: `id_token=${encodeURIComponent(idToken)}&providerId=google.com`})});
  const body = await r.json();
  assert.equal(r.status, 200, JSON.stringify(body.error));
  return {uid: body.localId, isNewUser: body.isNewUser === true};
}
async function reset() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const r = await fetch(`${AUTH}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/accounts`, {method: 'DELETE'});
  assert.ok(r.ok);
  await db.doc('users/inviter').set({user_role: 'joueur', remaining_part: 3});
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1, maxRewardsPerUser: 20, maxRewardsPerInvitee: 3});
}
async function invitation(code) {
  await db.doc('referrals/' + code).set({inviteCode: code, inviterUid: 'inviter', status: 'pending',
    rewardStatus: 'not_earned', metadata: {}});
}
const referral = async code => (await db.doc('referrals/' + code).get()).data();
const accountsFor = async email => (await admin.auth().listUsers()).users.filter(u => u.email === email);
const pendingRewards = async () => (await db.collection('referral_reward_pending').get()).size;

test('a new Google account is created by Firebase, referred once, and the app signs in with the same token', async () => {
  await reset(); await invitation('NEW');
  const token = googleToken('g-new', 'new.player@gmail.test');
  assert.deepEqual(await call(token, 'NEW'), {status: 'accepted'});
  const [account] = await accountsFor('new.player@gmail.test');
  assert.ok(account);
  assert.equal(account.providerData[0].providerId, 'google.com');
  assert.equal((await referral('NEW')).inviteeUid, account.uid);
  assert.equal(await pendingRewards(), 1);
  assert.ok((await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis() > Date.now());
  // The token used by the server stays usable by the app: same account, not new.
  assert.deepEqual(await appSignIn(token), {uid: account.uid, isNewUser: false});
  // Calling again changes nothing.
  assert.deepEqual(await call(token, 'NEW'), {status: 'accepted'});
  assert.equal(await pendingRewards(), 1);
});

test('an existing Google account, or an address already registered by password, is never referred', async () => {
  await reset(); await invitation('OLD');
  const existing = googleToken('g-old', 'old.player@gmail.test');
  await appSignIn(existing); // Created long before, without code.
  assert.deepEqual(await call(existing, 'OLD'), {status: 'existing_account'});
  await admin.auth().createUser({email: 'password.player@gmail.test', password: 'secret-123'});
  assert.deepEqual(await call(googleToken('g-pw', 'password.player@gmail.test'), 'OLD'), {status: 'existing_account'});
  assert.equal((await referral('OLD')).status, 'pending');
  assert.equal(await pendingRewards(), 0);
  // No signup operation is opened for an existing account.
  assert.equal((await db.collection('_referral_google_signups').get()).size, 0);
});

test('simultaneous calls create one account, one acceptance and one reward', async () => {
  await reset(); await invitation('RACE');
  const token = googleToken('g-race', 'race@gmail.test');
  const results = await Promise.allSettled([...Array(5)].map(() => call(token, 'RACE')));
  assert.ok(results.some(r => r.status === 'fulfilled' && r.value.status === 'accepted'), JSON.stringify(results));
  const accounts = await accountsFor('race@gmail.test');
  assert.equal(accounts.length, 1);
  assert.equal((await referral('RACE')).inviteeUid, accounts[0].uid);
  assert.equal(await pendingRewards(), 1);
  assert.equal((await db.collection('reward_events').get()).size, 1);
});

test('an account created before a crash is completed by a retry or by the worker, never deleted, rewarded once', async () => {
  await reset(); await invitation('RETRY'); await invitation('WORKER');
  // Crash just after Firebase created the account: operation open, no acceptance.
  for (const [code, sub, email] of [['RETRY', 'g-retry', 'retry@gmail.test'], ['WORKER', 'g-worker', 'worker@gmail.test']]) {
    await db.doc('_referral_google_signups/' + subHash(sub)).set({status: 'pending', googleSub: sub,
      referralId: code,
      checkedAbsentAt: Date.now() - 5 * 60000});
    await appSignIn(googleToken(sub, email));
    assert.equal((await referral(code)).status, 'pending');
  }
  // The app retries: the operation is resumed.
  assert.deepEqual(await call(googleToken('g-retry', 'retry@gmail.test'), 'RETRY'), {status: 'accepted'});
  // Nobody retries: the scheduled worker resumes it.
  await retryWorker({});
  const [worker] = await accountsFor('worker@gmail.test');
  assert.equal((await referral('WORKER')).inviteeUid, worker.uid);
  // Running both again is harmless.
  await retryWorker({});
  await call(googleToken('g-retry', 'retry@gmail.test'), 'RETRY');
  assert.equal(await pendingRewards(), 2);
  assert.equal((await accountsFor('retry@gmail.test')).length, 1);
  assert.equal((await accountsFor('worker@gmail.test')).length, 1);
});

test('an operation whose account was never created is closed by the worker, nothing deleted', async () => {
  await reset(); await invitation('GONE');
  await db.doc('_referral_google_signups/' + subHash('g-gave-up')).set({status: 'pending', googleSub: 'g-gave-up',
    referralId: 'GONE', checkedAbsentAt: Date.now() - 2 * 3600000});
  await retryWorker({});
  assert.equal((await db.doc('_referral_google_signups/' + subHash('g-gave-up')).get()).data().outcome, 'abandoned');
  assert.equal((await referral('GONE')).status, 'pending');
});

test('a deleted then recreated Google account is a new account (accepted trade-off)', async () => {
  await reset(); await invitation('FIRST'); await invitation('AGAIN');
  assert.deepEqual(await call(googleToken('g-del', 'del@gmail.test'), 'FIRST'), {status: 'accepted'});
  const [account] = await accountsFor('del@gmail.test');
  await admin.auth().deleteUser(account.uid);
  // New for Firebase: created again, referred again (former lots and history are lost).
  assert.deepEqual(await call(googleToken('g-del-2', 'del@gmail.test'), 'AGAIN'), {status: 'accepted'});
  const [again] = await accountsFor('del@gmail.test');
  assert.notEqual(again.uid, account.uid);
  assert.equal((await referral('AGAIN')).inviteeUid, again.uid);
  assert.equal(await pendingRewards(), 2);
  // No address registry is kept.
  assert.equal((await db.collection('_referral_email_registry').get()).size, 0);
});

test('an unknown or used code stops before any account is created', async () => {
  await reset(); await invitation('USED');
  await db.doc('referrals/USED').update({status: 'accepted', inviteeUid: 'someone'});
  await assert.rejects(call(googleToken('g-typo', 'typo@gmail.test'), 'TYPO'), {code: 'not-found'});
  await assert.rejects(call(googleToken('g-used', 'used@gmail.test'), 'USED'),
    e => e.code === 'failed-precondition' && e.details?.reason === 'referral_unavailable');
  assert.equal((await accountsFor('typo@gmail.test')).length + (await accountsFor('used@gmail.test')).length, 0);
  await assert.rejects(call('not-a-token', 'USED'), {code: 'invalid-argument'});
});

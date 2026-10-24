// Profile of an account created by the server for a signup with a code
// (24/10/2026 Samsung finding: the app signed in without a role, the profile
// had no user_role, the rules refused to add it, the player had 0 chances).
// The server now creates users/{uid} with its role before the referral is
// accepted; the app sign-in and the login page then write nothing forbidden.
// Player program (createReferralEmailAccount, resume in retryReferralRewards)
// and merchant program (createMerchantAccountWithReferral) stay separate:
// "joueur" for one, "commercant" for the other.
// Isolated demo emulators (Firestore + Auth) only.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) throw Error('Isolated demo emulators required');
const root = require('../index'); // Initializes the Admin SDK; real chance triggers.
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const share = require('../lib/share_promo');
const {ensureServerCreatedProfile} = require('../new_account_profile');
const {createMerchantAccountWithReferralHandler, resumeMerchantSignupLinkForUser} = require('../merchant_signup_referral');

const hash = (s) => crypto.createHash('sha256').update(s).digest('hex');
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
let env;
let ip = 0;
test.before(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  env = await initializeTestEnvironment({projectId: process.env.GCLOUD_PROJECT,
    firestore: {host, port: Number(port), rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
});
test.after(async () => { await env.cleanup(); ft.cleanup(); });

async function reset() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const r = await fetch(`${AUTH}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/accounts`, {method: 'DELETE'});
  assert.ok(r.ok);
  await db.doc('users/inviter').set({user_role: 'joueur', remaining_part: 3});
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1});
  await db.doc('referrals/R').set({inviteCode: 'CODE1234', inviterUid: 'inviter', status: 'pending',
    rewardStatus: 'not_earned', metadata: {}});
}
const playerSignup = (email, requestId = crypto.randomUUID()) => ft.wrap(share.createReferralEmailAccount)(
  {email, password: 'secret-123', inviteCode: 'CODE1234', requestId}, {rawRequest: {ip: `10.8.0.${++ip % 250}`}});
const playerUid = (requestId) => 'ref_' + hash(requestId).slice(0, 48);
const user = async (uid) => (await db.doc('users/' + uid).get()).data();
// The real triggers, as Firebase runs them on the written document.
async function runOnCreate(uid) {
  await ft.wrap(root.initializeNewPlayerRemainingParts)(await db.doc('users/' + uid).get(), {params: {uid}});
  await ft.wrap(root.initializeNewMerchantAccountStatus)(await db.doc('users/' + uid).get(), {params: {uid}});
  return user(uid);
}
async function runOnRoleUpdate(uid, before) {
  const change = ft.makeChange(ft.firestore.makeDocumentSnapshot(before, 'users/' + uid),
    await db.doc('users/' + uid).get());
  await ft.wrap(root.initializePlayerRemainingPartsOnRoleAssignment)(change, {params: {uid}});
  return user(uid);
}
const rewardEvents = async () => (await db.collection('reward_events').get()).size;
const client = (uid, email) => env.authenticatedContext(uid, {email}).firestore();
// What the app writes at sign-in on an existing profile (ensureUserDocumentInitialized
// with the role already present: only missing identity fields, never the role).
const appSignInPatch = {display_name: 'Nouveau'};

test('player with a valid code: server profile with the player role, 3 chances, inviter rewarded once', async () => {
  await reset();
  const requestId = crypto.randomUUID();
  assert.deepEqual(await playerSignup('new.player@test.ge', requestId), {success: true});
  const uid = playerUid(requestId);
  const profile = await user(uid);
  assert.equal(profile.user_role, 'joueur');
  assert.equal(profile.uid, uid);
  assert.equal(profile.email, 'new.player@test.ge');
  assert.ok(profile.created_time);
  assert.equal((await runOnCreate(uid)).remaining_part, 3);
  assert.equal((await db.doc('referrals/R').get()).get('inviteeUid'), uid);
  assert.equal(await rewardEvents(), 1);
  // The app signs in with the player role: nothing to write, nothing refused.
  await assertSucceeds(client(uid, 'new.player@test.ge').doc('users/' + uid).set(appSignInPatch, {merge: true}));
  // Retry with the same request: same account, same profile, still one reward.
  assert.deepEqual(await playerSignup('new.player@test.ge', requestId), {success: true});
  assert.equal((await user(uid)).user_role, 'joueur');
  await ft.wrap(share.retryReferralRewards)({});
  assert.equal(await rewardEvents(), 1);
});

test('concurrent calls of the same signup: one account, one profile, one acceptance, one reward', async () => {
  await reset();
  const requestId = crypto.randomUUID();
  const results = await Promise.allSettled([...Array(4)].map(() => playerSignup('race@test.ge', requestId)));
  assert.ok(results.some((r) => r.status === 'fulfilled'), JSON.stringify(results.map((r) => r.reason?.code)));
  const uid = playerUid(requestId);
  assert.equal((await user(uid)).user_role, 'joueur');
  assert.equal((await admin.auth().listUsers()).users.filter((u) => u.email === 'race@test.ge').length, 1);
  assert.equal((await db.doc('referrals/R').get()).get('inviteeUid'), uid);
  await ft.wrap(share.retryReferralRewards)({});
  assert.equal(await rewardEvents(), 1);
});

test('a profile the app created without a role (sign-in before the server) gets only the missing role', async () => {
  await reset();
  const requestId = crypto.randomUUID();
  const uid = playerUid(requestId);
  // Interruption: account created, then the app signed in (no role) before the server profile.
  await admin.auth().createUser({uid, email: 'late@test.ge', password: 'secret-123'});
  await db.doc('_referral_signup_operations/' + hash(requestId)).set({uid, emailHash: hash('late@test.ge'),
    referralId: 'R', status: 'pending', createdAt: admin.firestore.Timestamp.now()});
  await assertSucceeds(client(uid, 'late@test.ge').doc('users/' + uid).set(
    {uid, email: 'late@test.ge', created_time: new Date(), first_name: 'Ana'}, {merge: true}));
  const before = await user(uid);
  assert.equal((await runOnCreate(uid)).remaining_part, undefined, 'no role yet: no chances');
  // The app could never add the role itself.
  await assertFails(client(uid, 'late@test.ge').doc('users/' + uid).set({user_role: 'joueur'}, {merge: true}));
  // The retried signup completes it.
  assert.deepEqual(await playerSignup('late@test.ge', requestId), {success: true});
  const after = await user(uid);
  assert.equal(after.user_role, 'joueur');
  assert.equal(after.first_name, 'Ana', 'nothing else is rewritten');
  assert.equal((await runOnRoleUpdate(uid, before)).remaining_part, 3);
  assert.equal((await db.doc('referrals/R').get()).get('inviteeUid'), uid);
});

test('login page after an interruption: the scheduled resume completes the profile and the referral', async () => {
  await reset();
  const requestId = crypto.randomUUID();
  const uid = playerUid(requestId);
  await admin.auth().createUser({uid, email: 'resume@test.ge', password: 'secret-123'});
  await db.doc('_referral_signup_operations/' + hash(requestId)).set({uid, emailHash: hash('resume@test.ge'),
    referralId: 'R', status: 'pending', createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 5 * 60000)});
  // The login page signs in without a role.
  await assertSucceeds(client(uid, 'resume@test.ge').doc('users/' + uid).set(
    {uid, email: 'resume@test.ge', created_time: new Date()}, {merge: true}));
  const before = await user(uid);
  await ft.wrap(share.retryReferralRewards)({});
  assert.equal((await user(uid)).user_role, 'joueur');
  assert.equal((await runOnRoleUpdate(uid, before)).remaining_part, 3);
  assert.equal((await db.doc('referrals/R').get()).get('inviteeUid'), uid);
  assert.equal((await db.doc('_referral_signup_operations/' + hash(requestId)).get()).get('status'), 'completed');
  assert.equal(await rewardEvents(), 1);
  // Running again changes nothing.
  await ft.wrap(share.retryReferralRewards)({});
  assert.equal(await rewardEvents(), 1);
});

test('an account of another role, or not matching the operation, is never modified', async () => {
  await reset();
  // A profile already holding another role: refused, role kept, referral not accepted.
  const requestId = crypto.randomUUID();
  const uid = playerUid(requestId);
  await db.doc('users/' + uid).set({uid, user_role: 'commercant', email: 'shop@test.ge'});
  await assert.rejects(playerSignup('shop@test.ge', requestId),
    (e) => e.code === 'failed-precondition' && e.details?.reason === 'profile_conflict');
  assert.equal((await user(uid)).user_role, 'commercant');
  assert.equal((await db.doc('referrals/R').get()).get('status'), 'pending');
  // The resume closes it without touching it.
  await db.doc('_referral_signup_operations/' + hash(requestId)).update({createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 5 * 60000)});
  await ft.wrap(share.retryReferralRewards)({});
  assert.equal((await user(uid)).user_role, 'commercant');
  assert.equal((await db.doc('_referral_signup_operations/' + hash(requestId)).get()).get('outcome'), 'refused');
  // An operation whose account address differs: untouched.
  const other = crypto.randomUUID();
  const otherUid = playerUid(other);
  await admin.auth().createUser({uid: otherUid, email: 'someone.else@test.ge', password: 'secret-123'});
  await db.doc('_referral_signup_operations/' + hash(other)).set({uid: otherUid, emailHash: hash('claimed@test.ge'),
    referralId: 'R', status: 'pending', createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 5 * 60000)});
  await ft.wrap(share.retryReferralRewards)({});
  assert.equal(await user(otherUid), undefined);
  assert.equal((await db.doc('_referral_signup_operations/' + hash(other)).get()).get('status'), 'pending');
  // The helper never changes a present role, whichever is asked.
  await db.doc('users/admin1').set({user_role: 'admin'});
  await assert.rejects(ensureServerCreatedProfile(db, {uid: 'admin1', email: 'a@test.ge', role: 'joueur'}),
    (e) => e.details?.reason === 'profile_conflict');
  await assert.rejects(ensureServerCreatedProfile(db, {uid: 'x', email: 'a@test.ge', role: 'admin'}));
  assert.equal((await user('admin1')).user_role, 'admin');
});

test('an operation whose account was never created is abandoned, nothing created', async () => {
  await reset();
  const requestId = crypto.randomUUID();
  const uid = playerUid(requestId);
  await db.doc('_referral_signup_operations/' + hash(requestId)).set({uid, emailHash: hash('ghost@test.ge'),
    referralId: 'R', status: 'pending', createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 2 * 3600000)});
  await ft.wrap(share.retryReferralRewards)({});
  assert.equal((await db.doc('_referral_signup_operations/' + hash(requestId)).get()).get('outcome'), 'abandoned');
  assert.equal(await user(uid), undefined);
  assert.equal((await db.doc('referrals/R').get()).get('status'), 'pending');
});

test('merchant with a code: server profile with the merchant role, merchant status, no player chances', async () => {
  await reset();
  await db.doc('users/ambassador').set({user_role: 'joueur'});
  await db.doc('merchant_referral_codes/AMB-1234').set({inviter_user_id: db.doc('users/ambassador')});
  const requestId = crypto.randomUUID();
  const res = await createMerchantAccountWithReferralHandler({email: 'shop.owner@test.ge', password: 'shop-password-1',
    code: 'AMB-1234', requestId}, {rawRequest: {ip: '10.9.1.1'}});
  assert.equal(res.success, true);
  const uid = 'msu_' + hash(requestId).slice(0, 48);
  const created = await runOnCreate(uid);
  assert.equal(created.user_role, 'commercant');
  assert.equal(created.remaining_part, undefined);
  assert.ok(created.account_status, 'merchant status initialized');
  assert.equal((await db.doc('merchant_referrals/' + uid).get()).get('status'), 'linked');
  await assertSucceeds(client(uid, 'shop.owner@test.ge').doc('users/' + uid).set(appSignInPatch, {merge: true}));
});

test('merchant signed in from the login page before the link: the role is completed, never a player role', async () => {
  await reset();
  await db.doc('users/ambassador').set({user_role: 'joueur'});
  const uid = 'msu_' + hash('interrupted').slice(0, 48);
  await admin.auth().createUser({uid, email: 'late.shop@test.ge', password: 'shop-password-1'});
  await db.doc('_merchant_signup_operations/op1').set({uid, email_hash: hash('late.shop@test.ge'), code: 'AMB-1234',
    inviter_path: 'users/ambassador', inviter_kind: 'joueur', status: 'pending'});
  await assertSucceeds(client(uid, 'late.shop@test.ge').doc('users/' + uid).set(
    {uid, email: 'late.shop@test.ge', created_time: new Date()}, {merge: true}));
  assert.deepEqual(await resumeMerchantSignupLinkForUser(db, uid), {resumed: true});
  assert.equal((await user(uid)).user_role, 'commercant');
  assert.equal((await db.doc('merchant_referrals/' + uid).get()).get('status'), 'linked');
  // A profile already holding the player role: never changed, never linked.
  const uid2 = 'msu_' + hash('conflict').slice(0, 48);
  await admin.auth().createUser({uid: uid2, email: 'player.shop@test.ge', password: 'shop-password-1'});
  await db.doc('_merchant_signup_operations/op2').set({uid: uid2, email_hash: hash('player.shop@test.ge'),
    code: 'AMB-1234', inviter_path: 'users/ambassador', inviter_kind: 'joueur', status: 'pending'});
  await db.doc('users/' + uid2).set({uid: uid2, user_role: 'joueur'});
  assert.deepEqual(await resumeMerchantSignupLinkForUser(db, uid2), {resumed: false});
  assert.equal((await user(uid2)).user_role, 'joueur');
  assert.equal((await db.doc('merchant_referrals/' + uid2).get()).exists, false);
  assert.equal((await db.doc('_merchant_signup_operations/op2').get()).get('outcome'), 'profile_conflict');
});

// Transition for app 1.1.1, which creates the account itself and sends the
// code afterwards (registerReferralAcceptance). Only the session that created
// the account, before any game, while the transition is open; never an
// existing account, never twice. Isolated demo emulators (Firestore + Auth).
process.env.REFERRAL_EMAIL_HMAC_KEY ||= 'test-only-referral-email-hmac-key-0123456789';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) throw Error('Isolated demo emulators required');
// index.js initializes the default app itself: load it first.
const {onUserDeleted} = require('../index.js');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const share = require('../lib/share_promo');
const accept = ft.wrap(share.registerReferralAcceptance);
const deleteTrigger = ft.wrap(onUserDeleted);
const deleted = user => deleteTrigger(ft.auth.makeUserRecord(user));
test.after(() => ft.cleanup());

async function reset() {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const {users} = await admin.auth().listUsers();
  if (users.length) await admin.auth().deleteUsers(users.map(u => u.uid));
  await db.doc('users/inviter').set({user_role: 'joueur'});
}
async function invitation(code) {
  await db.doc('referrals/' + code).set({inviteCode: code, inviterUid: 'inviter', status: 'pending',
    rewardStatus: 'not_earned', metadata: {}});
}
const creationSeconds = async uid =>
  Math.floor(Date.parse((await admin.auth().getUser(uid)).metadata.creationTime) / 1000);
// The session that created the account: its sign-in time is the creation time.
async function newAccount(uid, profile = {}) {
  await admin.auth().createUser({uid, email: uid + '@example.test'});
  await db.doc('users/' + uid).set({user_role: 'joueur', ...profile});
  return {auth: {uid, token: {auth_time: await creationSeconds(uid)}}};
}
// An existing account signing in today.
async function oldAccount(uid, daysAgo) {
  await admin.auth().importUsers([{uid, email: uid + '@example.test', metadata: {
    creationTime: new Date(Date.now() - daysAgo * 86400000).toUTCString(),
    lastSignInTime: new Date().toUTCString()}}]);
  await db.doc('users/' + uid).set({user_role: 'joueur'});
  return {auth: {uid, token: {auth_time: Math.floor(Date.now() / 1000)}}};
}
const status = async code => (await db.doc('referrals/' + code).get()).data();
const publishedDaysAgo = days => db.doc('app_config/referral_signup').set({
  app_1_1_2_published_at: admin.firestore.Timestamp.fromMillis(Date.now() - days * 86400000)});

test('a new account, in the session that created it, is credited to its inviter once', async () => {
  await reset(); await invitation('NEW');
  const fresh = await newAccount('fresh');
  await accept({inviteCode: 'NEW'}, fresh);
  assert.equal((await status('NEW')).status, 'accepted');
  assert.equal((await status('NEW')).inviteeUid, 'fresh');
  // Retrying is harmless, and the account cannot use a second code.
  await accept({inviteCode: 'NEW'}, fresh);
  await invitation('SECOND');
  await assert.rejects(accept({inviteCode: 'SECOND'}, fresh), {code: 'already-exists'});
  assert.equal((await status('SECOND')).status, 'pending');
  assert.equal((await db.collection('referral_reward_pending').get()).size, 1);
});

test('an existing account never counts, without any time window', async () => {
  await reset();
  // Created yesterday, never played: still an existing account.
  const yesterday = await oldAccount('yesterday', 1); await invitation('OLD');
  await assert.rejects(accept({inviteCode: 'OLD'}, yesterday), {code: 'failed-precondition'});
  // Created just now but signing in again later in the day: not the creation session.
  const later = await newAccount('later');
  later.auth.token.auth_time += 120; await invitation('LATER');
  await assert.rejects(accept({inviteCode: 'LATER'}, later), {code: 'failed-precondition'});
  // A new account that already played or was active is not a new player.
  const played = await newAccount('played', {games_played_count: 1}); await invitation('PLAYED');
  await assert.rejects(accept({inviteCode: 'PLAYED'}, played), {code: 'failed-precondition'});
  const active = await newAccount('active', {last_real_activity_at: admin.firestore.Timestamp.now()});
  await invitation('ACTIVE');
  await assert.rejects(accept({inviteCode: 'ACTIVE'}, active), {code: 'failed-precondition'});
  // No Auth record at all.
  await db.doc('users/ghost').set({user_role: 'joueur'}); await invitation('GHOST');
  await assert.rejects(accept({inviteCode: 'GHOST'}, {auth: {uid: 'ghost', token: {}}}), {code: 'failed-precondition'});
  for (const code of ['OLD', 'LATER', 'PLAYED', 'ACTIVE', 'GHOST']) assert.equal((await status(code)).status, 'pending', code);
  assert.equal((await db.collection('referral_reward_pending').get()).size, 0);
});

test('self-referral never counts', async () => {
  await reset();
  await admin.auth().createUser({uid: 'inviter', email: 'inviter@example.test'});
  await invitation('SELF');
  const self = {auth: {uid: 'inviter', token: {auth_time: await creationSeconds('inviter')}}};
  await assert.rejects(accept({inviteCode: 'SELF'}, self), {code: 'failed-precondition'});
  assert.equal((await status('SELF')).status, 'pending');
});

test('a deleted then recreated account with the same address is not referred again', async () => {
  await reset(); await invitation('FIRST'); await invitation('AGAIN');
  const first = await newAccount('first');
  await accept({inviteCode: 'FIRST'}, first);
  await admin.auth().deleteUser('first');
  await deleted({uid: 'first', email: 'first@example.test'});
  // Same address, new Firebase account: refused.
  await admin.auth().createUser({uid: 'first-again', email: 'first@example.test'});
  await db.doc('users/first-again').set({user_role: 'joueur'});
  const again = {auth: {uid: 'first-again', token: {auth_time: await creationSeconds('first-again')}}};
  await assert.rejects(accept({inviteCode: 'AGAIN'}, again), e => e.code === 'failed-precondition' &&
    e.details?.reason === 'email_not_eligible');
  assert.equal((await status('AGAIN')).status, 'pending');
  // Even an account deleted without ever being referred is remembered.
  await invitation('NEVER');
  await deleted({uid: 'gone', email: 'Gone@Example.test'});
  await admin.auth().createUser({uid: 'gone-again', email: 'gone@example.test'});
  await db.doc('users/gone-again').set({user_role: 'joueur'});
  const goneAgain = {auth: {uid: 'gone-again', token: {auth_time: await creationSeconds('gone-again')}}};
  await assert.rejects(accept({inviteCode: 'NEVER'}, goneAgain), {code: 'failed-precondition'});
  // The registry holds HMACs with a 2-year expiry, never the address.
  const entries = (await db.collection('_referral_email_registry').get()).docs.map(d => d.data());
  assert.equal(JSON.stringify(entries).includes('example.test'), false);
  const years = (entries[0].expires_at.toMillis() - entries[0].created_at.toMillis()) / (365 * 86400000);
  assert.ok(years >= 2 && years < 2.01);
});

test('the transition closes 4 weeks after the real 1.1.2 publication date', async () => {
  await reset(); await invitation('OPEN'); await invitation('CLOSED');
  // Published 27 days ago: still open.
  await publishedDaysAgo(27);
  await accept({inviteCode: 'OPEN'}, await newAccount('in-time'));
  assert.equal((await status('OPEN')).status, 'accepted');
  // Published 29 days ago: closed, even for a brand-new account.
  await publishedDaysAgo(29);
  await assert.rejects(accept({inviteCode: 'CLOSED'}, await newAccount('too-late')),
    e => e.code === 'failed-precondition' && e.details?.reason === 'update_required');
  assert.equal((await status('CLOSED')).status, 'pending');
});

test('simultaneous calls for one new account give a single acceptance and reward', async () => {
  await reset(); await invitation('RACE');
  const racer = await newAccount('racer');
  const results = await Promise.allSettled([...Array(5)].map(() => accept({inviteCode: 'RACE'}, racer)));
  assert.ok(results.some(r => r.status === 'fulfilled'));
  assert.equal((await status('RACE')).inviteeUid, 'racer');
  assert.equal((await db.collection('referral_reward_pending').get()).size, 1);
});

test('a code during a referral game gives the inviter one ticket only', async () => {
  await reset(); await invitation('GAME');
  const now = Date.now();
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1});
  await db.doc('referral_games/live').set({status: 'active', ticket_count: 0,
    start_date: admin.firestore.Timestamp.fromMillis(now - 60000),
    end_date: admin.firestore.Timestamp.fromMillis(now + 3600000)});
  await accept({inviteCode: 'GAME'}, await newAccount('game-player'));
  const entries = await db.collection('referral_games/live/entries').get();
  assert.equal(entries.size, 1);
  assert.equal(entries.docs[0].data().inviter_uid, 'inviter');
  assert.equal((await db.doc('referral_games/live').get()).data().ticket_count, 1);
  assert.equal((await db.doc('users/inviter').get()).data().allGamesAccessUntil, undefined);
  assert.equal((await db.doc('referral_reward_pending/GAME').get()).data().status, 'granted');
});

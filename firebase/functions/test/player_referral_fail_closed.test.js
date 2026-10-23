// Referral codes entered outside the e-mail signup (e.g. before a Google
// signup) only count for an account Firebase created moments ago and that
// has not played yet. Isolated demo emulators (Firestore + Auth) only.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) throw Error('Isolated demo emulators required');
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const accept = ft.wrap(require('../lib/share_promo').registerReferralAcceptance);
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
async function newAccount(uid, profile = {}) {
  await admin.auth().createUser({uid});
  await db.doc('users/' + uid).set({user_role: 'joueur', ...profile});
}
async function oldAccount(uid, minutesAgo) {
  await admin.auth().importUsers([{uid, metadata: {
    creationTime: new Date(Date.now() - minutesAgo * 60000).toUTCString(),
    lastSignInTime: new Date().toUTCString()}}]);
  await db.doc('users/' + uid).set({user_role: 'joueur'});
}
const status = async code => (await db.doc('referrals/' + code).get()).data();

test('a brand-new account (e.g. Google signup) is credited to its inviter once', async () => {
  await reset(); await invitation('NEW'); await newAccount('fresh');
  await accept({inviteCode: 'NEW'}, {auth: {uid: 'fresh'}});
  assert.equal((await status('NEW')).status, 'accepted');
  assert.equal((await status('NEW')).inviteeUid, 'fresh');
  // Retrying is harmless, and the account cannot use a second code.
  await accept({inviteCode: 'NEW'}, {auth: {uid: 'fresh'}});
  await invitation('SECOND');
  await assert.rejects(accept({inviteCode: 'SECOND'}, {auth: {uid: 'fresh'}}), {code: 'already-exists'});
  assert.equal((await status('SECOND')).status, 'pending');
});

test('an existing account never counts, whatever its profile says', async () => {
  await reset();
  await oldAccount('old', 31); await invitation('OLD');
  await assert.rejects(accept({inviteCode: 'OLD'}, {auth: {uid: 'old'}}), {code: 'failed-precondition'});
  // A fresh account that already played is not a new player either.
  await newAccount('played', {games_played_count: 1}); await invitation('PLAYED');
  await assert.rejects(accept({inviteCode: 'PLAYED'}, {auth: {uid: 'played'}}), {code: 'failed-precondition'});
  await newAccount('active', {last_real_activity_at: admin.firestore.Timestamp.now()}); await invitation('ACTIVE');
  await assert.rejects(accept({inviteCode: 'ACTIVE'}, {auth: {uid: 'active'}}), {code: 'failed-precondition'});
  // No Auth record at all.
  await db.doc('users/ghost').set({user_role: 'joueur'}); await invitation('GHOST');
  await assert.rejects(accept({inviteCode: 'GHOST'}, {auth: {uid: 'ghost'}}), {code: 'failed-precondition'});
  for (const code of ['OLD', 'PLAYED', 'ACTIVE', 'GHOST']) assert.equal((await status(code)).status, 'pending', code);
  assert.equal((await db.collection('reward_events').get()).size, 0);
});

test('an account created just inside the window counts, self-referral never', async () => {
  await reset();
  await oldAccount('recent', 25); await invitation('RECENT');
  await accept({inviteCode: 'RECENT'}, {auth: {uid: 'recent'}});
  assert.equal((await status('RECENT')).status, 'accepted');
  await admin.auth().createUser({uid: 'inviter'}); await invitation('SELF');
  await assert.rejects(accept({inviteCode: 'SELF'}, {auth: {uid: 'inviter'}}), {code: 'failed-precondition'});
});

test('a Google signup with a code during a referral game gives the inviter one ticket only', async () => {
  await reset(); await invitation('GAME');
  const now = Date.now();
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1});
  await db.doc('referral_games/live').set({status: 'active', ticket_count: 0,
    start_date: admin.firestore.Timestamp.fromMillis(now - 60000),
    end_date: admin.firestore.Timestamp.fromMillis(now + 3600000)});
  await newAccount('google-player');
  await accept({inviteCode: 'GAME'}, {auth: {uid: 'google-player'}});
  const entries = await db.collection('referral_games/live/entries').get();
  assert.equal(entries.size, 1);
  assert.equal(entries.docs[0].data().inviter_uid, 'inviter');
  assert.equal((await db.doc('referral_games/live').get()).data().ticket_count, 1);
  assert.equal((await db.doc('users/inviter').get()).data().allGamesAccessUntil, undefined);
  assert.equal((await db.doc('referral_reward_pending/GAME').get()).data().status, 'granted');
});

// Scheduled jobs of the player referral program: the recovery worker runs
// every 10 minutes (rewards are granted in the signup call itself), and the
// former expiry job never expires an invitation nor needs a Firestore index.
// Isolated demo emulators only.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST || !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw Error('Isolated demo emulators required');
}
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const share = require('../lib/share_promo');
test.after(() => ft.cleanup());

test('the recovery worker runs every 10 minutes', () => {
  assert.equal(share.retryReferralRewards.__endpoint.scheduleTrigger.schedule, 'every 10 minutes');
});

test('the expiry job leaves every invitation as it is, even very old ones', async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const old = admin.firestore.Timestamp.fromMillis(Date.now() - 400 * 86400000);
  await db.doc('referrals/OLD').set({inviteCode: 'OLD', inviterUid: 'inviter', status: 'pending', createdAt: old});
  await db.doc('referrals/GONE').set({inviteCode: 'GONE', inviterUid: 'inviter', status: 'expired', createdAt: old});
  assert.equal(await ft.wrap(share.expireOldReferrals)({}), null);
  assert.equal((await db.doc('referrals/OLD').get()).data().status, 'pending');
  assert.equal((await db.doc('referrals/GONE').get()).data().status, 'expired');
});

test('a pending reward is still granted once by the worker', async () => {
  for (const c of await db.listCollections()) await db.recursiveDelete(c);
  const now = admin.firestore.Timestamp.now();
  await db.doc('users/inviter').set({user_role: 'joueur'});
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1});
  await db.doc('referrals/R').set({inviteCode: 'R', inviterUid: 'inviter', inviteeUid: 'invitee',
    status: 'accepted', acceptedAt: now, rewardStatus: 'available', rewardType: 'all_games_until_midnight',
    rewardValue: 1, metadata: {playerRewardRuleVersion: 2}});
  await db.doc('referral_reward_pending/R').set({referral_id: 'R', inviter_uid: 'inviter', accepted_at: now,
    game_id: null, mode: 'classic', status: 'pending'});
  const worker = ft.wrap(share.retryReferralRewards);
  await Promise.all([worker({}), worker({})]);
  await worker({});
  assert.equal((await db.doc('referral_reward_pending/R').get()).data().status, 'granted');
  assert.equal((await db.doc('referrals/R').get()).data().rewardStatus, 'granted');
  assert.equal((await db.collection('reward_events').get()).size, 1);
  assert.ok((await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis() > Date.now());
});

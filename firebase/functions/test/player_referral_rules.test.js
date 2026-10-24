// Run only against a Firestore emulator and disposable demo project.
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST ||
    !String(process.env.GCLOUD_PROJECT || '').startsWith('demo-')) {
  throw new Error('An isolated demo Firestore emulator is required');
}
if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const ft = require('firebase-functions-test')({projectId: process.env.GCLOUD_PROJECT});
const share = require('../lib/share_promo');
const accept = ft.wrap(share.registerReferralAcceptance);
const grant = ft.wrap(share.grantReferralReward);
const {getNextMidnightTimestamp} = require('../lib/share_promo/firestore');
const t = value => admin.firestore.Timestamp.fromDate(new Date(value));

test.beforeEach(async () => {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false,
    rewardType: 'all_games_until_midnight', rewardValue: 1,
    maxRewardsPerUser: 20, maxRewardsPerInvitee: 3, requireInviteeSignup: true});
  await Promise.all([
    db.doc('users/inviter').set({user_role: 'joueur', remaining_part: 3}),
    db.doc('users/invitee').set({user_role: 'joueur', profile_completed: false}),
    db.doc('users/other').set({user_role: 'joueur', profile_completed: false}),
    db.doc('users/admin').set({user_role: 'admin'}),
    db.doc('referrals/r').set({inviterUid: 'inviter', inviteCode: 'TESTCODE',
      status: 'pending', rewardStatus: 'not_earned', rewardType: 'all_games_until_midnight',
      rewardValue: 1, metadata: {}, createdAt: t('2020-01-01T00:00:00Z')}),
  ]);
});
test.after(() => ft.cleanup());

test('old invitation remains pending and the legacy endpoint rejects acceptance', async () => {
  assert.equal((await db.doc('referrals/r').get()).data().status, 'pending');
  await assert.rejects(accept({inviteCode: 'TESTCODE'}, {auth: {uid: 'invitee'}}), {code: 'failed-precondition'});
  assert.equal((await db.doc('referrals/r').get()).data().status, 'pending');
  assert.equal((await db.collection('reward_events').get()).size, 0);
});

test('legacy endpoint rejects existing users regardless of profile completion', async () => {
  await assert.rejects(accept({inviteCode: 'TESTCODE'}, {auth: {uid: 'invitee'}}), {code: 'failed-precondition'});
  await db.doc('users/invitee').update({profile_completed: true});
  await assert.rejects(accept({inviteCode: 'TESTCODE'}, {auth: {uid: 'invitee'}}), {code: 'failed-precondition'});
});

test('unsupported historical reward is not marked granted', async () => {
  await db.doc('referrals/r').update({status: 'accepted', inviteeUid: 'invitee',
    rewardStatus: 'available', rewardType: 'extra_play'});
  const result = await grant({referralId: 'r'}, {auth: {uid: 'admin', token: {admin: true}}});
  assert.equal(result.reason, 'unsupported_reward');
  assert.equal((await db.doc('referrals/r').get()).data().rewardStatus, 'available');
});

test('a delayed reward ends on the acceptance day without shortening older access', async () => {
  const accepted = t('2026-03-29T20:30:00Z');
  await db.doc('referrals/r').update({status: 'accepted', inviteeUid: 'invitee',
    rewardStatus: 'available', acceptedAt: accepted,
    metadata: {playerRewardRuleVersion: 2}});
  await grant({referralId: 'r'}, {auth: {uid: 'admin', token: {admin: true}}});
  assert.equal((await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis(),
    t('2026-03-29T22:00:00Z').toMillis());
  await db.doc('referrals/s').set({inviterUid: 'inviter', inviteeUid: 'other',
    status: 'accepted', rewardStatus: 'available', rewardType: 'all_games_until_midnight',
    rewardValue: 1, acceptedAt: accepted, metadata: {playerRewardRuleVersion: 2}});
  const existing = t('2030-01-01T00:00:00Z');
  await db.doc('users/inviter').update({allGamesAccessUntil: existing});
  await grant({referralId: 's'}, {auth: {uid: 'admin', token: {admin: true}}});
  assert.equal((await db.doc('users/inviter').get()).data().allGamesAccessUntil.toMillis(), existing.toMillis());
  assert.equal((await db.doc('users/inviter').get()).data().referralBonusExpiresAt.toMillis(),
    t('2026-03-29T22:00:00Z').toMillis());
});

test('blocked rewards are not granted', async () => {
  await db.doc('referrals/r').update({status: 'accepted', inviteeUid: 'invitee', rewardStatus: 'blocked'});
  assert.equal((await grant({referralId: 'r'}, {auth: {uid: 'admin', token: {admin: true}}})).reason, 'reward_blocked');
  assert.equal((await db.collection('reward_events').get()).size, 0);
});

test('Paris midnight follows the acceptance day across DST and year end', () => {
  for (const [input, expected] of [
    ['2026-03-28T23:30:00Z', '2026-03-29T22:00:00.000Z'],
    ['2026-10-24T22:30:00Z', '2026-10-25T23:00:00.000Z'],
    ['2026-12-31T22:59:00Z', '2026-12-31T23:00:00.000Z'],
  ]) assert.equal(getNextMidnightTimestamp(t(input)).toDate().toISOString(), expected);
});

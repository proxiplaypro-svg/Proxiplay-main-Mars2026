process.env.REFERRAL_EMAIL_HMAC_KEY ||= 'test-only-referral-email-hmac-key-0123456789';
process.env.LIFECYCLE_REFERRAL_ONLY = 'true';
const crypto = require('node:crypto');
const {test, assert, db, ft, time, verifyPrize, game, participate} = require('./lifecycle_helpers.cjs');
const queue = require('../referral_reward_queue');
const worker = queue.processReferralReward;
let failWorker = false;
queue.processReferralReward = (...args) => failWorker
  ? Promise.reject(Error('Injected worker outage')) : worker(...args);
const share = require('../lib/share_promo');
const {drawReferralGame} = require('../referral_game_engine');
const {getNextMidnightTimestamp} = require('../lib/share_promo/firestore');
const create = ft.wrap(share.createReferral), accept = ft.wrap(share.registerReferralAcceptance);
const signupCall = ft.wrap(share.createReferralEmailAccount), retry = ft.wrap(share.retryReferralRewards);
let ip = 0;
const signupInput = inviteCode => ({email: crypto.randomUUID() + '@example.test',
  password: 'test-password-123', inviteCode, requestId: crypto.randomUUID()});
const signup = input => signupCall(input, {rawRequest: {ip: '10.40.0.' + (++ip)}});
async function campaign() {
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false, rewardType: 'all_games_until_midnight', rewardValue: 1});
}
async function acceptedAt(referralId) {
  return (await db.doc('referrals/' + referralId).get()).data().acceptedAt;
}
test('referral: invitation -> acceptance outage -> durable event -> two workers -> ticket -> draw -> operator claim', async () => {
  await campaign();
  await db.doc('referral_games/ref_game').set({status: 'active', start_date: time('2020-01-01'), end_date: time('2030-01-01'), prize_description: 'Lot parrainage'});
  const invitation = await create({}, {auth: {uid: 'player'}});
  await assert.rejects(accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'player'}}), {code: 'failed-precondition'});
  const input = signupInput(invitation.inviteCode);
  failWorker = true;
  try {
    await signup(input);
    await signup(input);
  } finally { failWorker = false; }
  assert.equal((await db.doc('referral_reward_pending/' + invitation.referralId).get()).data().status, 'pending');
  assert.equal((await drawReferralGame('ref_game', {now: time('2031-01-01')})).status, 'manual_review_required');
  await Promise.all([retry({}), retry({})]);
  assert.equal((await db.doc('referral_reward_pending/' + invitation.referralId).get()).data().status, 'granted');
  assert.equal((await db.collection('referral_games/ref_game/entries').get()).size, 1);
  // During an active referral game the ticket replaces the classic reward.
  assert.equal((await db.collection('reward_events').get()).size, 0);
  assert.equal((await db.doc('users/player').get()).data().allGamesAccessUntil, undefined);
  assert.equal((await drawReferralGame('ref_game', {now: time('2031-01-01')})).status, 'completed');
  await verifyPrize('referral_game_ref_game', {platform: true});
  assert.equal((await drawReferralGame('ref_game', {now: time('2031-01-01')})).status, 'already_finalized');
});
test('classic referral reward grants access instead of physical prize and is idempotent', async () => {
  await campaign();
  const invitation = await create({}, {auth: {uid: 'player'}});
  const input = signupInput(invitation.inviteCode);
  await signup(input);
  const first = (await db.doc('users/player').get()).data().allGamesAccessUntil;
  assert.ok(first && first.toMillis() > Date.now());
  assert.equal(first.toMillis(), getNextMidnightTimestamp(await acceptedAt(invitation.referralId)).toMillis());
  await signup(input);
  assert.equal((await db.doc('users/player').get()).data().allGamesAccessUntil.toMillis(), first.toMillis());
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.collection('reward_events').get()).size, 1);
  await game('game', {start_date: time('2020-01-01'), end_date: time('2030-01-01')});
  process.env.LIFECYCLE_TEST_NOW = new Date(first.toMillis() - 3600000).toISOString();
  await participate();
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 30);
  process.env.LIFECYCLE_TEST_NOW = new Date(first.toMillis() + 3600000).toISOString();
  await participate();
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 29);
});
test('a legacy play-credit campaign still grants unlimited access, not credits', async () => {
  await campaign(); await db.doc('app_config/share_promo').update({rewardType: 'play_credit', rewardValue: 3});
  const invitation = await create({}, {auth: {uid: 'player'}});
  const input = signupInput(invitation.inviteCode);
  await signup(input);
  await signup(input);
  const user = (await db.doc('users/player').get()).data();
  assert.equal(user.remaining_part, 30);
  assert.equal(user.allGamesAccessUntil.toMillis(),
    getNextMidnightTimestamp(await acceptedAt(invitation.referralId)).toMillis());
  assert.equal((await db.collection('reward_events').get()).size, 1);
  assert.equal((await db.collection('prizes').get()).size, 0);
});

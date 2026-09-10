process.env.LIFECYCLE_REFERRAL_ONLY = 'true';
const {test, assert, db, ft, time, verifyPrize, game, participate} = require('./lifecycle_helpers.cjs');
const queue = require('../referral_reward_queue');
const worker = queue.processReferralReward;
let failWorker = false;
queue.processReferralReward = (...args) => failWorker
  ? Promise.reject(Error('Injected worker outage')) : worker(...args);
const share = require('../lib/share_promo');
const {drawReferralGame} = require('../referral_game_engine');
const create = ft.wrap(share.createReferral), accept = ft.wrap(share.registerReferralAcceptance);
async function campaign() {
  await db.doc('app_config/share_promo').set({enabled: true, isDraft: false, rewardType: 'all_games_until_midnight', rewardValue: 1});
}
test('referral: invitation -> acceptance outage -> durable event -> two workers -> ticket -> draw -> operator claim', async () => {
  await campaign();
  await db.doc('referral_games/ref_game').set({status: 'active', start_date: time('2020-01-01'), end_date: time('2030-01-01'), prize_description: 'Lot parrainage'});
  const invitation = await create({}, {auth: {uid: 'player'}});
  await assert.rejects(accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'player'}}), {code: 'failed-precondition'});
  failWorker = true;
  try {
    await accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'other'}});
    await accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'other'}});
  } finally { failWorker = false; }
  assert.equal((await db.doc('referral_reward_pending/' + invitation.referralId).get()).data().status, 'pending');
  assert.equal((await drawReferralGame('ref_game', {now: time('2031-01-01')})).status, 'manual_review_required');
  await Promise.all([worker(invitation.referralId), worker(invitation.referralId)]);
  assert.equal((await db.collection('referral_games/ref_game/entries').get()).size, 1);
  assert.equal((await drawReferralGame('ref_game', {now: time('2031-01-01')})).status, 'completed');
  await verifyPrize('referral_game_ref_game', {platform: true});
  assert.equal((await drawReferralGame('ref_game', {now: time('2031-01-01')})).status, 'already_finalized');
});
test('classic referral reward grants access instead of physical prize and is idempotent', async () => {
  await campaign();
  const invitation = await create({}, {auth: {uid: 'player'}});
  await accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'other'}});
  const first = (await db.doc('users/player').get()).data().allGamesAccessUntil;
  assert.ok(first && first.toMillis() > Date.now());
  await accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'other'}});
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
test('referral play-credit variant grants once and is consumed by the game engine', async () => {
  await campaign(); await db.doc('app_config/share_promo').update({rewardType: 'play_credit', rewardValue: 3});
  const invitation = await create({}, {auth: {uid: 'player'}});
  await accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'other'}});
  await accept({inviteCode: invitation.inviteCode}, {auth: {uid: 'other'}});
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 33);
  await game(); await participate();
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 32);
  assert.equal((await db.collection('prizes').get()).size, 0);
});

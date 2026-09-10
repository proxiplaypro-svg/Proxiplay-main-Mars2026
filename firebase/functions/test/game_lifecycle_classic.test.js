const {test, assert, db, time, game, participate, verifyPrize} = require('./lifecycle_helpers.cjs');
const {drawMainPrize} = require('../main_prize_draw');
const afterEnd = {now: time('2026-10-01')};
test('midnight Europe/Paris permits a new ticket exactly at the day boundary', async () => {
  await game();
  process.env.LIFECYCLE_TEST_NOW = '2026-09-09T21:59:59Z'; await participate();
  assert.equal((await participate()).alreadyParticipatedToday, true);
  process.env.LIFECYCLE_TEST_NOW = '2026-09-09T22:00:00Z';
  assert.equal((await participate()).alreadyParticipatedToday, false);
  const tickets = await db.collection('games/game/participants').get();
  assert.deepEqual(tickets.docs.map(d => d.id), ['20260909_player', '20260910_player']);
});
test('every tenth game participation grants exactly three credits, not a prize or extra daily ticket', async () => {
  await game('game', {participations: 9, hasMainPrize: false});
  await participate(); await participate();
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 32);
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.collection('games/game/participants').get()).size, 1);
});
test('classic: participation -> daily tickets -> concurrent final draw -> player/merchant visibility -> claim -> closed', async () => {
  await game();
  await participate();
  assert.equal((await participate()).alreadyParticipatedToday, true);
  process.env.EMULATOR_TEST_DATE = '2026-09-10';
  await participate();
  assert.equal((await db.collection('games/game/participants').get()).size, 2);
  const results = await Promise.all([drawMainPrize('game', afterEnd), drawMainPrize('game', afterEnd)]);
  assert.equal(results.filter(r => r.status === 'completed').length, 1);
  const prizes = await db.collection('prizes').get();
  assert.equal(prizes.size, 1);
  const p = await verifyPrize(prizes.docs[0].id);
  assert.equal(p.usage_deadline.toMillis(), time('2030-01-01').toMillis());
  assert.equal((await db.doc('games/game').get()).data().status, 'ended');
  assert.equal((await drawMainPrize('game', afterEnd)).status, 'already_finalized');
});
test('no final prize: participation survives and game closes without a phantom winner', async () => {
  await game('game', {hasMainPrize: false}); await participate();
  assert.equal((await drawMainPrize('game', afterEnd)).status, 'no_main_prize');
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.doc('games/game').get()).data().status, 'ended');
  assert.equal((await drawMainPrize('game', afterEnd)).status, 'already_finalized');
});
for (const excluded of ['none', 'deleted', 'suspended']) test('classic closes with no eligible winner: ' + excluded, async () => {
  await game();
  if (excluded !== 'none') {
    await participate();
    if (excluded === 'deleted') await db.doc('users/player').delete();
    else await db.doc('users/player').update({account_status: 'suspended'});
  }
  assert.equal((await drawMainPrize('game', afterEnd)).status, 'no_eligible_entries');
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await drawMainPrize('game', afterEnd)).status, 'already_finalized');
});
test('final draw cannot announce a gain whose configured withdrawal deadline has already passed', async () => {
  await game('game', {prize_usage_deadline: time('2000-01-01')}); await participate();
  const result = await drawMainPrize('game', afterEnd);
  assert.equal(result.status, 'manual_review_required');
  assert.equal(result.reason, 'invalid_or_expired_prize_deadline');
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.doc('games/game').get()).data().hasWinner, false);
  await db.doc('games/game').update({prize_usage_deadline: 'invalid-date'});
  assert.equal((await drawMainPrize('game', afterEnd)).reason, 'invalid_or_expired_prize_deadline');
});

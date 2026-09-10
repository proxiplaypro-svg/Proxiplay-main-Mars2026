const {test, assert, db, game, instant, participate, verifyPrize, client, assertFails, time, ft, functions} = require('./lifecycle_helpers.cjs');
test('instant provisioning -> idempotent schedule -> two distinct awarded lots -> merchant claims', async () => {
  const start = new Date(Date.now() + 86400000).toISOString();
  const end = new Date(Date.now() + 7 * 86400000).toISOString();
  await game('game', {start_date: time(start), end_date: time(end),
    prize_usage_deadline: time(new Date(Date.now() + 40 * 86400000).toISOString()),
    secondary_prizes: [{name: 'Lot prévu', presentation: 'Fixture', count: 2}]});
  const provision = ft.wrap(functions.generateInstantWinnersForGame);
  assert.equal((await provision({gameId: 'game'}, {auth: {uid: 'merchant'}})).createdCount, 2);
  assert.equal((await provision({gameId: 'game'}, {auth: {uid: 'merchant'}})).createdCount, 0);
  process.env.LIFECYCLE_TEST_NOW = end;
  const first = await participate();
  const second = await participate('game', 'other');
  assert.equal(first.isWin, true); assert.equal(second.isWin, true);
  assert.notEqual(first.prize_id, second.prize_id);
  await verifyPrize(first.prize_id.split('/').at(-1));
  // The second fixture is a winner too; use the same access/claim contract.
  const prize = (await db.doc(second.prize_id).get()).data();
  assert.ok(prize.claim_code);
  assert.notEqual(prize.claim_code, (await db.doc(first.prize_id).get()).data().claim_code);
  await client('other').doc(second.prize_id).get();
  await client('merchant').doc(second.prize_id).update({claimed: true});
  assert.equal((await db.doc(second.prize_id).get()).data().claimed, true);
});
test('instant: committed gain survives app loss/retry, one prize/link/code, legitimate claim only', async () => {
  await game(); await instant();
  const outcomes = await Promise.all([participate(), participate()]);
  assert.ok(outcomes.every(o => o.isWin));
  assert.equal(new Set(outcomes.map(o => o.prize_id)).size, 1);
  const id = outcomes[0].prize_id.split('/').at(-1);
  assert.equal((await db.collection('prizes').get()).size, 1);
  assert.equal((await db.collection('games/game/participants').get()).size, 1);
  assert.equal((await participate()).prize_id, outcomes[0].prize_id);
  await verifyPrize(id);
  assert.equal((await db.doc('games/game/instant_winners/instant').get()).data().hasWinner, true);
  assert.equal((await db.doc('games/game').get()).data().hasWinner, false);
});
test('instant prize expiry blocks claim while winner retains visibility', async () => {
  await game(); await instant();
  const result = await participate();
  assert.equal(result.isWin, true);
  await db.doc(result.prize_id).update({usage_deadline: time('2000-01-01')});
  await client('player').doc(result.prize_id).get();
  await assertFails(client('merchant').doc(result.prize_id).update({claimed: true}));
});
test('interrupted award transaction leaves no partial gain; retry then completes once', async () => {
  await game(); await instant();
  const original = db.runTransaction;
  db.runTransaction = function(callback, options) {
    return original.call(this, async tx => {await callback(tx); throw Error('Injected before commit');}, options);
  };
  try { await assert.rejects(participate()); } finally { db.runTransaction = original; }
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.collection('users/player/my_lots').get()).size, 0);
  assert.equal((await db.doc('games/game/instant_winners/instant').get()).data().hasWinner, false);
  const result = await participate();
  await verifyPrize(result.prize_id.split('/').at(-1));
});
test('due instants are consumed once each, with remaining lots available to the next player', async () => {
  await game(); await instant('game', 'old', '2026-09-09T09:00:00Z'); await instant('game', 'new');
  await participate();
  const second = await participate('game', 'other');
  assert.equal(second.isWin, true);
  assert.equal((await db.collection('prizes').get()).size, 2);
  const slots = await db.collection('games/game/instant_winners').get();
  assert.deepEqual(slots.docs.map(d => d.data().player_id.id).sort(), ['other', 'player']);
});
for (const state of ['suspended', 'deleted', 'cancelled', 'disabled']) test('no instant awarded from invalid lifecycle state: ' + state, async () => {
  await game(); await instant();
  if (state === 'suspended') await db.doc('users/player').update({account_status: 'suspended'});
  else if (state === 'deleted') await db.doc('users/player').update({deleted: true});
  else await db.doc('games/game').update({status: state});
  await assert.rejects(participate(), {code: 'failed-precondition'});
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 30);
});
test('invalid configured withdrawal deadline refuses the award before spending a part', async () => {
  await game('game', {prize_usage_deadline: time('2000-01-01')}); await instant();
  await assert.rejects(participate(), {code: 'failed-precondition'});
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.doc('users/player').get()).data().remaining_part, 30);
  assert.equal((await db.doc('games/game/instant_winners/instant').get()).data().hasWinner, false);
});

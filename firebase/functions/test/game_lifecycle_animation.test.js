const {test, assert, db, time, game, participate, verifyPrize, client, assertSucceeds} = require('./lifecycle_helpers.cjs');
const {drawWinnerForAnimation} = require('../draw_animation_winner');
async function animation() {
  await db.doc('animations/animation').set({name: 'Animation fixture', prize_description: 'Lot plateforme',
    status: 'active', threshold: 2, start_date: time('2026-09-01'), end_date: time('2026-09-30')});
  await db.doc('enseignes/second_shop').set({owner: db.doc('users/merchant')});
  await game('first', {animation_id: 'animation', hasMainPrize: false});
  await game('second', {animation_id: 'animation', enseigne_id: db.doc('enseignes/second_shop'), hasMainPrize: false});
}
test('animation: two shops of same owner -> unique qualification -> final prize/public projection -> operator claim', async () => {
  await animation();
  await participate('first');
  await participate('first');
  assert.equal((await db.doc('animations/animation/entries/player').get()).data().threshold_reached, false);
  await participate('second');
  const entry = (await db.doc('animations/animation/entries/player').get()).data();
  assert.equal(entry.threshold_reached, true);
  assert.equal(entry.visited_count, 2);
  const results = await Promise.all([1, 2].map(() => drawWinnerForAnimation('animation', {now: time('2026-10-01')})));
  assert.equal(results.filter(r => r.status === 'completed').length, 1);
  await assertSucceeds(client('player').doc('animations/animation/public_winner/current').get());
  await verifyPrize('animation_animation', {platform: true});
  assert.equal((await db.doc('animations/animation').get()).data().status, 'ended');
});
test('animation with no qualified player closes once without a prize', async () => {
  await animation(); await participate('first');
  assert.equal((await drawWinnerForAnimation('animation', {now: time('2026-10-01')})).status, 'no_qualified_entries');
  assert.equal((await db.doc('animations/animation').get()).data().status, 'ended');
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await drawWinnerForAnimation('animation', {now: time('2026-10-01')})).status, 'already_finalized');
});

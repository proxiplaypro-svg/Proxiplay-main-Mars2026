const {test, assert, db, time, game, participate, verifyPrize} = require('./lifecycle_helpers.cjs');
const {drawWinnerForMonthlyChallenge} = require('../monthly_challenge');
async function config(type) {
  const id = type === 'attendance' ? '2026-09' : type + '_2026-09';
  const data = {challenge_id: id, type, enabled: true, month: '2026-09', title: 'Fixture', description: 'Assiduité',
    target_days: 2, prize_title: 'Lot mensuel', prize_description: 'Lot fixture', prize_value: 50,
    draw_date: time('2026-10-01T09:00:00Z'),
    ...(type === 'merchant' ? {enseigne_ref: db.doc('enseignes/shop'), enseigne_name: 'Fixture'} : {}),
    ...(type === 'restaurant' ? {restaurant_ref: db.doc('enseignes/shop'), restaurant_name: 'Fixture'} : {})};
  await db.doc('monthly_challenges/' + id).set(data);
  return data;
}
for (const type of ['attendance', 'merchant', 'restaurant']) test('monthly ' + type + ': real participation -> two Paris days -> entry -> draw -> operator withdrawal', async () => {
  const c = await config(type);
  await game(); await participate(); await participate();
  assert.equal((await db.doc(`users/player/monthly_challenges/${c.challenge_id}`).get()).data().active_days_count, 1);
  process.env.EMULATOR_TEST_DATE = '2026-09-10'; await participate();
  assert.equal((await db.doc(`monthly_challenge_entries/${c.challenge_id}_player`).get()).data().status, 'qualified');
  process.env.EMULATOR_TEST_DATE = '2026-10-01';
  const result = await drawWinnerForMonthlyChallenge(c, 'lifecycle_test');
  assert.equal(result.status, 'completed');
  await verifyPrize('monthly_challenge_' + c.challenge_id, {platform: true});
  assert.equal((await drawWinnerForMonthlyChallenge(c, 'retry')).status, 'already_completed');
  assert.equal((await db.doc('monthly_challenge_draws/' + c.challenge_id).get()).data().status, 'completed');
});
test('two monthly variants stay independent and no qualified entry closes without a prize', async () => {
  const c = await config('attendance'); await config('merchant');
  await game(); await participate();
  process.env.EMULATOR_TEST_DATE = '2026-10-01';
  assert.equal((await drawWinnerForMonthlyChallenge(c, 'lifecycle_test')).status, 'no_eligible_users');
  assert.equal((await db.collection('prizes').get()).size, 0);
  assert.equal((await db.doc('monthly_challenge_draws/merchant_2026-09').get()).exists, false);
});

// Monthly attendance challenge and free shop QR plays: a valid participation
// counts as an active day whether it consumed a chance or not; a refused
// play never counts; one Paris day counts once; a new month starts over.
// Isolated demo emulators only (lifecycle harness).
const {test, assert, db, ft, time, game, participate} = require('./lifecycle_helpers.cjs');
const issue = ft.wrap(require('../game_qr_access').issueGameQrAccess);
const mint = async (id) => (await issue({gameId: id}, {auth: {uid: 'merchant'}})).token;
const state = async () => (await db.doc('users/player/monthly_challenges/2026-09').get()).data() || {};
const balance = async () => (await db.doc('users/player').get()).data().remaining_part;

async function attendanceChallenge() {
  await db.doc('monthly_challenges/2026-09').set({challenge_id: '2026-09', type: 'attendance', enabled: true,
    month: '2026-09', title: 'Fixture', description: 'Assiduité', target_days: 2, prize_title: 'Lot mensuel',
    prize_description: 'Lot fixture', prize_value: 50, draw_date: time('2026-10-01T09:00:00Z')});
}

test('a free shop QR play at zero chances counts as an active day, once per Paris day', async () => {
  await attendanceChallenge();
  await game('shop_a');
  await game('shop_b');
  await db.doc('users/player').update({remaining_part: 0});

  // Day 1: free QR play, no chance consumed, the day counts.
  await participate('shop_a', 'player', {from_qr: true, qr_token: await mint('shop_a')});
  assert.equal(await balance(), 0);
  assert.equal((await state()).active_days_count, 1);
  // Same day, another free QR play elsewhere: still one day.
  await participate('shop_b', 'player', {from_qr: true, qr_token: await mint('shop_b')});
  assert.equal((await state()).active_days_count, 1);

  // Day 2: a paid play at zero chances is refused and never counts...
  process.env.EMULATOR_TEST_DATE = '2026-09-10';
  await assert.rejects(participate('shop_a'), {code: 'failed-precondition'});
  // ...nor does a forged token.
  await assert.rejects(participate('shop_b', 'player', {from_qr: true, qr_token: 'f'.repeat(64)}));
  assert.equal((await state()).active_days_count, 1);
  // A valid free QR play the same day counts and qualifies (target 2 days).
  await participate('shop_b', 'player', {from_qr: true, qr_token: await mint('shop_b')});
  const s = await state();
  assert.equal(s.active_days_count, 2);
  assert.deepEqual(s.active_dates, ['2026-09-09', '2026-09-10']);
  assert.equal(s.qualified, true);
  assert.equal((await db.doc('monthly_challenge_entries/2026-09_player').get()).data().status, 'qualified');
  assert.equal(await balance(), 0);
});

test('a QR play in the next month does not change the closed month', async () => {
  await attendanceChallenge();
  await game('october', {end_date: time('2026-10-31T20:00:00Z')});
  await participate('october', 'player', {from_qr: true, qr_token: await mint('october')});
  assert.equal((await state()).active_days_count, 1);
  process.env.EMULATOR_TEST_DATE = '2026-10-01';
  await participate('october', 'player', {from_qr: true, qr_token: await mint('october')});
  const s = await state();
  assert.equal(s.active_days_count, 1);
  assert.deepEqual(s.active_dates, ['2026-09-09']);
});

test('simultaneous free QR plays the same day give one participation and one active day', async () => {
  await attendanceChallenge();
  await game('race');
  await db.doc('users/player').update({remaining_part: 0});
  const token = await mint('race');
  await Promise.allSettled([1, 2, 3].map(() => participate('race', 'player', {from_qr: true, qr_token: token})));
  assert.equal((await state()).active_days_count, 1);
  assert.equal(await balance(), 0);
});

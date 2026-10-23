// A game must be drawn as soon as it ends, not at the next nightly sweep.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-draw-on-end';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const ft = require('firebase-functions-test')();
const exportedFunctions = require('../index'); // initializes the admin app
const draw = require('../main_prize_draw');
const db = admin.firestore();
const ago = ms => admin.firestore.Timestamp.fromMillis(Date.now() - ms);
const MINUTE = 60000;
test.after(() => ft.cleanup());
test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
  await db.doc('users/merchant').set({user_role: 'commercant'});
  await db.doc('enseignes/shop').set({owner: db.doc('users/merchant'), email: 'shop@example.com'});
  await db.doc('users/winner').set({user_role: 'joueur', first_name: 'Camille', city: 'Lyon'});
});
async function seedGame(id, endDate) {
  await db.doc(`games/${id}`).set({hasWinner: false, hasMainPrize: true, name: 'Lot', status: 'active',
    enseigne_id: db.doc('enseignes/shop'), end_date: endDate});
  await db.doc(`games/${id}/participants/t1`).set({user_id: db.doc('users/winner')});
}

test('the frequent job is exported and runs every minute in Paris time', () => {
  const exported = exportedFunctions.pickEndedMainPrizeWinners;
  assert.equal(exported, draw.pickEndedMainPrizeWinners);
  assert.equal(exported.__endpoint.scheduleTrigger.schedule, 'every 1 minutes');
  assert.equal(exported.__endpoint.scheduleTrigger.timeZone, 'Europe/Paris');
  // The nightly catch-up sweep is unchanged.
  assert.equal(exportedFunctions.pickMainPrizeWinners.__endpoint.scheduleTrigger.schedule, '0 0 * * *');
});

test('a game that just ended is drawn and exposes the winner first name', async () => {
  await seedGame('just_ended', ago(MINUTE));
  await seedGame('running', admin.firestore.Timestamp.fromMillis(Date.now() + 60 * MINUTE));
  await ft.wrap(draw.pickEndedMainPrizeWinners)({});
  const game = (await db.doc('games/just_ended').get()).data();
  assert.equal(game.hasWinner, true);
  assert.equal(game.draw_status, 'completed');
  assert.equal(game.winner_first_name, 'Camille');
  assert.equal(game.main_prize_winner.path, 'users/winner');
  assert.equal((await db.doc('games/running').get()).data().hasWinner, false);
  const prizes = await db.collection('prizes').where('prize_type', '==', 'principal').get();
  assert.equal(prizes.size, 1);
});

test('a winner without first_name is still named from display_name or pseudo', async () => {
  await db.doc('users/winner').set({user_role: 'joueur', display_name: 'Lou Martin', city: 'Nantes'});
  await seedGame('display', ago(MINUTE));
  await ft.wrap(draw.pickEndedMainPrizeWinners)({});
  assert.equal((await db.doc('games/display').get()).data().winner_first_name, 'Lou');
  await db.doc('users/winner').set({user_role: 'joueur', pseudo: 'Zed'});
  await seedGame('pseudo', ago(MINUTE));
  await ft.wrap(draw.pickEndedMainPrizeWinners)({});
  assert.equal((await db.doc('games/pseudo').get()).data().winnerFirstName, 'Zed');
});

// Same dates as the real game of 18/10/2026: closing at 12:00 Paris and a
// prize deadline at 23:59:59 the same day.
test('a same-day prize deadline is drawn at closing but refused by the midnight-only sweep', async () => {
  const closing = admin.firestore.Timestamp.fromDate(new Date('2026-10-18T10:00:00Z'));
  const deadline = admin.firestore.Timestamp.fromDate(new Date('2026-10-18T21:59:59Z'));
  const atClosing = admin.firestore.Timestamp.fromDate(new Date('2026-10-18T10:01:00Z'));
  const atMidnight = admin.firestore.Timestamp.fromDate(new Date('2026-10-18T22:00:00Z'));
  for (const id of ['frequent', 'nightly']) {
    await seedGame(id, closing);
    await db.doc(`games/${id}`).update({prize_usage_deadline: deadline});
  }
  // Previous behavior: only the midnight run, two seconds after the deadline.
  const late = await draw.drawMainPrize('nightly', {now: atMidnight});
  assert.equal(late.status, 'manual_review_required');
  assert.equal(late.reason, 'invalid_or_expired_prize_deadline');
  const untouched = (await db.doc('games/nightly').get()).data();
  assert.equal(untouched.hasWinner, false);
  assert.equal(untouched.draw_status, undefined);
  // New behavior: the per-minute job sees the game right after closing.
  const candidates = await draw.loadRecentlyEndedDrawCandidates(atClosing);
  assert.ok(candidates.some(d => d.id === 'frequent'));
  assert.equal((await draw.drawMainPrize('frequent', {now: atClosing})).status, 'completed');
  const drawn = (await db.doc('games/frequent').get()).data();
  assert.equal(drawn.winner_first_name, 'Camille');
  assert.equal(drawn.winner_city, 'Lyon');
});

test('an old ended game without winner is left to the nightly sweep, which draws it', async () => {
  await seedGame('old', ago(draw.RECENT_DRAW_LOOKBACK_MS + 60 * MINUTE));
  const candidates = await draw.loadRecentlyEndedDrawCandidates(admin.firestore.Timestamp.now());
  assert.deepEqual(candidates.map(d => d.id), []);
  await ft.wrap(draw.pickMainPrizeWinners)({});
  assert.equal((await db.doc('games/old').get()).data().winner_first_name, 'Camille');
});

test('frequent and nightly runs at the same time produce a single winner', async () => {
  await seedGame('race', ago(MINUTE));
  await Promise.all([
    ft.wrap(draw.pickEndedMainPrizeWinners)({}),
    ft.wrap(draw.pickEndedMainPrizeWinners)({}),
    ft.wrap(draw.pickMainPrizeWinners)({}),
  ]);
  assert.equal((await db.collection('prizes').get()).size, 1);
  assert.equal((await db.collection('users/winner/my_lots').get()).size, 1);
  // A later run leaves the finalized game alone.
  assert.deepEqual((await draw.loadRecentlyEndedDrawCandidates(admin.firestore.Timestamp.now())).map(d => d.id), []);
});

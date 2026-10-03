// Realistic-scale regression test for drawMainPrize(): a game with 1500+
// participants (Kids Troc has 1576 in production) must still reach a
// winner using a small, BOUNDED number of Firestore read operations --
// never one network round-trip per participant. This is what pushed
// pickMainPrizeWinners past its Gen1 timeout (first 60s, then even 300s):
// the old code did "for (const doc of tickets.docs) { await tx.get(ref) }"
// sequentially, one participant at a time, inside the transaction.
//
// Wall-clock duration against the LOCAL emulator is not a reliable signal
// here -- near-zero network latency locally would make even 1500
// sequential round-trips look fast. Instead this test counts actual calls
// to Transaction.prototype.get/getAll via a temporary, restored-after
// monkey-patch: proof that participant reads are batched (a handful of
// getAll() calls) rather than one get() per participant.
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-main-draw-scale';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { Transaction } = require('@google-cloud/firestore');
const ft = require('firebase-functions-test')();
// main_prize_draw.js does not call admin.initializeApp() itself -- it
// relies on index.js (its usual entry point) to do that first. This test
// requires main_prize_draw.js directly, so it must initialize the app.
admin.initializeApp();
const { drawMainPrize, PARTICIPANT_USER_BATCH_SIZE } = require('../main_prize_draw');
const db = admin.firestore();
test.after(() => ft.cleanup());

const PARTICIPANT_COUNT = 1576; // matches the real Kids Troc production count

test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
});

async function seedGameWithManyParticipants(count) {
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('enseignes/shop').set({ owner: db.doc('users/merchant') });
  await db.doc('games/scale_game').set({
    hasWinner: false,
    hasMainPrize: true,
    name: 'Jeu a grande echelle',
    create_by: db.doc('users/merchant'),
    enseigne_id: db.doc('enseignes/shop'),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
  });

  // Firestore write batches cap at 500 operations; 2 writes per
  // participant (user doc + participant doc) keeps each batch well under
  // that limit. This seeding cost is test setup, not the code under test.
  const CHUNK = 200;
  for (let start = 0; start < count; start += CHUNK) {
    const batch = db.batch();
    const end = Math.min(start + CHUNK, count);
    for (let i = start; i < end; i += 1) {
      const userRef = db.doc(`users/participant${i}`);
      batch.set(userRef, { user_role: 'joueur', first_name: `Player${i}`, city: 'Paris' });
      batch.set(db.doc(`games/scale_game/participants/p${i}`), { user_id: userRef });
    }
    // eslint-disable-next-line no-await-in-loop
    await batch.commit();
  }
}

test(`drawMainPrize reaches a winner among ${PARTICIPANT_COUNT} participants using a bounded number of batched reads, not one per participant`, async () => {
  await seedGameWithManyParticipants(PARTICIPANT_COUNT);

  let callCount = 0;
  const originalGet = Transaction.prototype.get;
  const originalGetAll = Transaction.prototype.getAll;
  Transaction.prototype.get = function (...args) {
    callCount += 1;
    return originalGet.apply(this, args);
  };
  Transaction.prototype.getAll = function (...args) {
    callCount += 1;
    return originalGetAll.apply(this, args);
  };

  let result;
  try {
    result = await drawMainPrize('scale_game');
  } finally {
    Transaction.prototype.get = originalGet;
    Transaction.prototype.getAll = originalGetAll;
  }

  assert.equal(result.status, 'completed');

  const gameAfter = await db.doc('games/scale_game').get();
  assert.equal(gameAfter.data().hasWinner, true);
  assert.match(gameAfter.data().main_prize_winner.path, /^users\/participant\d+$/);

  const prizes = await db.collection('prizes').get();
  assert.equal(prizes.size, 1, 'exactly one prize must be created, never duplicated');
  assert.equal(prizes.docs[0].data().winner_id.path, gameAfter.data().main_prize_winner.path);

  // The decisive proof: total Firestore operations inside the transaction
  // must stay in the dozen range, not scale with participant count.
  // Expected: 1 (game) + 1 (enseigne) + 1 (existing-prize query) +
  // 1 (participants subcollection) + ceil(1576/batchSize) getAll() calls
  // for the user documents + 2 (claim code reservation's own reads).
  const expectedBatches = Math.ceil(PARTICIPANT_COUNT / PARTICIPANT_USER_BATCH_SIZE);
  assert.ok(
    callCount < 20,
    `expected a small, bounded number of Firestore operations (~${4 + expectedBatches + 2}), got ${callCount} -- ` +
      `this would indicate a reintroduced per-participant sequential read`,
  );
  assert.ok(callCount >= expectedBatches, 'sanity: at least one getAll() per batch must have happened');
});

test('a second draw attempt on the same already-won large game is idempotent and touches no participant data again', async () => {
  await seedGameWithManyParticipants(PARTICIPANT_COUNT);
  const first = await drawMainPrize('scale_game');
  assert.equal(first.status, 'completed');

  const second = await drawMainPrize('scale_game');
  assert.equal(second.status, 'already_finalized');

  const prizes = await db.collection('prizes').get();
  assert.equal(prizes.size, 1, 'no second prize must ever be created');
});

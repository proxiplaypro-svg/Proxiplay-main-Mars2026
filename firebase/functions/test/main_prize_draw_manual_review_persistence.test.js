// manual_review_required must now leave a PERSISTENT, explicit marker on
// the game document (draw_status + draw_review_reason + draw_review_at),
// so needsMainPrizeDraw() stops re-opening a game with a genuine
// business-data problem every single night -- exactly the "ever-growing
// graveyard" pattern that caused the original timeout incident, just for
// AWARD_MANUAL_REVIEW_REQUIRED/DRAW_FAILED noise instead of a timeout.
//
// review() itself (prize_integrity.js) is shared by several other
// modules (referral games, monthly challenge, animation draws, prize/
// my_lots repair) and is NOT touched here -- the persistence is local to
// main_prize_draw.js's own 5 review() call sites, via
// finalizeWithManualReview() (Phase 1, no transaction open yet) and
// reviewInTransaction() (Phase 3, already inside one).
//
// The marker must be reversible: clearing draw_status (and
// draw_review_reason/draw_review_at) is enough to make the game an
// ordinary candidate again, with no other state to reset.
//
// It must NEVER be written for retry_needed, a transient Firestore
// error, or two concurrent executions racing on already_finalized --
// those are not business-data problems and must keep being retried
// automatically. retry_needed's own "never falsely finalized" guarantee
// is already covered by main_prize_draw_phase_engine.test.js; this file
// only re-asserts it is not mistaken for manual_review_required.
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-proxiplay-manual-review-persistence';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const ft = require('firebase-functions-test')();
admin.initializeApp();
const { drawMainPrize, needsMainPrizeDraw, MANUAL_REVIEW_DRAW_STATUS } = require('../main_prize_draw');
const db = admin.firestore();
test.after(() => ft.cleanup());

test.beforeEach(async () => {
  for (const col of await db.listCollections()) await db.recursiveDelete(col);
});

async function seedBaseGame(overrides = {}) {
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('users/player').set({ user_role: 'joueur', first_name: 'Alice', city: 'Lille' });
  await db.doc('enseignes/shop').set({ owner: db.doc('users/merchant'), email: 'shop@example.test' });
  await db.doc('games/g').set({
    hasWinner: false, hasMainPrize: true, name: 'Lot',
    enseigne_id: db.doc('enseignes/shop'),
    end_date: admin.firestore.Timestamp.fromDate(new Date('2020-01-01')),
    ...overrides,
  });
  await db.doc('games/g/participants/t1').set({ user_id: db.doc('users/player') });
}

async function assertPersistedReview(reason, { expectedPrizeCount = 0 } = {}) {
  const game = (await db.doc('games/g').get()).data();
  assert.equal(game.draw_status, MANUAL_REVIEW_DRAW_STATUS);
  assert.equal(game.draw_review_reason, reason);
  assert.ok(game.draw_review_at, 'draw_review_at must be set');
  assert.equal(needsMainPrizeDraw(game), false, 'a marked game must no longer be a candidate');
  assert.equal(game.hasWinner, false, 'a review marker must never imply a winner');
  // For every reason except prize_exists_without_final_draw, no prize
  // should exist at all. That one reason is specifically triggered BY a
  // pre-existing prize (the scenario itself seeds it) -- the requirement
  // there is that drawMainPrize() never creates a SECOND one, not that
  // none exists.
  assert.equal((await db.collection('prizes').get()).size, expectedPrizeCount, 'review must never create or duplicate a prize');
}

const scenarios = [
  {
    reason: 'invalid_or_expired_prize_deadline',
    setup: () => seedBaseGame({ prize_usage_deadline: admin.firestore.Timestamp.fromDate(new Date('2019-01-01')) }),
  },
  {
    reason: 'missing_enseigne',
    setup: () => seedBaseGame({ enseigne_id: null, enseigne_ref: null }),
  },
  {
    reason: 'invalid_merchant_owner',
    setup: async () => {
      await db.doc('users/someone_else').set({ user_role: 'commercant' });
      await seedBaseGame({ owner_id: db.doc('users/someone_else') });
    },
  },
  {
    reason: 'invalid_prize_fulfillment',
    setup: () => seedBaseGame({ fulfillment_type: 'partner' }),
  },
  {
    reason: 'prize_exists_without_final_draw',
    expectedPrizeCount: 1,
    setup: async () => {
      await seedBaseGame();
      await db.collection('prizes').add({ game_id: db.doc('games/g'), prize_type: 'principal' });
    },
  },
];

for (const { reason, setup, expectedPrizeCount } of scenarios) {
  test(`review reason '${reason}' is persisted on the game and excludes it from needsMainPrizeDraw()`, async () => {
    await setup();
    const result = await drawMainPrize('g');
    assert.equal(result.status, 'manual_review_required');
    assert.equal(result.reason, reason);
    await assertPersistedReview(reason, { expectedPrizeCount });
  });
}

// ---------------------------------------------------------------------
// Reversibility: once the underlying data problem is corrected and the
// marker cleared, the game must draw normally again -- no other
// residual state blocks it.
// ---------------------------------------------------------------------
test('clearing draw_status/draw_review_reason after fixing the data problem lets the game draw normally again', async () => {
  await db.doc('users/merchant').set({ user_role: 'commercant' });
  await db.doc('users/someone_else').set({ user_role: 'commercant' });
  await db.doc('users/player').set({ user_role: 'joueur', first_name: 'Alice', city: 'Lille' });
  await db.doc('enseignes/shop').set({ owner: db.doc('users/merchant'), email: 'shop@example.test' });
  await seedBaseGame({ owner_id: db.doc('users/someone_else') }); // invalid ownership

  const first = await drawMainPrize('g');
  assert.equal(first.status, 'manual_review_required');
  assert.equal(first.reason, 'invalid_merchant_owner');
  const marked = (await db.doc('games/g').get()).data();
  assert.equal(needsMainPrizeDraw(marked), false);

  // Operator fixes the data (owner_id now matches the shop) and clears
  // the marker -- the two steps a human (or a dedicated admin action,
  // left out of this change's scope) would perform.
  await db.doc('games/g').update({
    owner_id: db.doc('users/merchant'),
    draw_status: admin.firestore.FieldValue.delete(),
    draw_review_reason: admin.firestore.FieldValue.delete(),
    draw_review_at: admin.firestore.FieldValue.delete(),
  });
  const cleared = (await db.doc('games/g').get()).data();
  assert.equal(needsMainPrizeDraw(cleared), true, 'clearing the marker alone must restore candidacy');

  const second = await drawMainPrize('g');
  assert.equal(second.status, 'completed');
  const finalGame = (await db.doc('games/g').get()).data();
  assert.equal(finalGame.hasWinner, true);
  assert.equal(finalGame.draw_status, 'completed');
});

// ---------------------------------------------------------------------
// Negative: retry_needed must never be persisted as manual_review_required.
// ---------------------------------------------------------------------
test('retry_needed is never persisted as manual_review_required', async () => {
  const crypto = require('crypto');
  const { MAX_CANDIDATE_ATTEMPTS } = require('../main_prize_draw');
  await seedBaseGame();
  await db.doc('games/g/participants/t1').delete();
  const TOTAL = MAX_CANDIDATE_ATTEMPTS + 2;
  for (let i = 0; i < TOTAL; i += 1) {
    const id = String(i).padStart(3, '0');
    await db.doc(`users/u${id}`).set({ user_role: 'joueur', first_name: `U${id}` });
    await db.doc(`games/g/participants/t${id}`).set({ user_id: db.doc(`users/u${id}`) });
  }
  const ticketsSnap = await db.collection('games/g/participants').get();
  const orderedUserPaths = ticketsSnap.docs.map(d => d.data().user_id.path);
  const toBan = orderedUserPaths.slice(0, MAX_CANDIDATE_ATTEMPTS);

  const originalRandomInt = crypto.randomInt;
  crypto.randomInt = () => 0;
  const originalRunTransaction = db.runTransaction.bind(db);
  let patched = false;
  db.runTransaction = async function (updateFunction) {
    if (!patched) {
      patched = true;
      const batch = db.batch();
      for (const path of toBan) batch.update(db.doc(path), { account_status: 'suspended' });
      await batch.commit();
    }
    return originalRunTransaction(updateFunction);
  };

  let result;
  try {
    result = await drawMainPrize('g');
  } finally {
    crypto.randomInt = originalRandomInt;
    db.runTransaction = originalRunTransaction;
  }

  assert.equal(result.status, 'retry_needed');
  const game = (await db.doc('games/g').get()).data();
  assert.notEqual(game.draw_status, MANUAL_REVIEW_DRAW_STATUS);
  assert.equal(game.draw_status, undefined);
  assert.equal(needsMainPrizeDraw(game), true, 'retry_needed must leave the game as an ordinary candidate');
});

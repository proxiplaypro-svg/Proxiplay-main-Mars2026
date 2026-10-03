// Pure unit tests for needsMainPrizeDraw(), exported from
// main_prize_draw.js. Regression coverage for the pickMainPrizeWinners
// timeout incident: the old load() query
// (where('hasWinner','==',false).where('end_date','<=',now)) kept
// matching every game ever finalized via no_main_prize/no_eligible_entries
// forever, since those paths never set hasWinner to true. That
// ever-growing set of already-settled games had to be re-opened in a
// transaction every single night before genuinely pending games were
// ever reached, which is what pushed the Gen1 function past its 60s
// timeout (confirmed in production logs: DRAW_RUN_STARTED, dozens of
// DRAW_SKIPPED, then "finished with status: 'timeout'" every night since
// 01/10). needsMainPrizeDraw() is the in-memory pre-filter applied to the
// broader end_date<=now query result, before any transaction is opened.
//
// A first version of this filter only covered the draw_status pair and
// missed drawMainPrize()'s OTHER no-write branch: status in
// draft/cancelled/canceled/disabled returns {status:'inactive'} with no
// tx.update() at all (confirmed by reading drawMainPrize() itself).
// After redeploying the first fix, production logs still showed dozens
// of DRAW_SKIPPED -- this second gap is a real, demonstrated reason why.
const test = require("node:test");
const assert = require("node:assert/strict");
// main_prize_draw.js calls admin.firestore() at module load time; this
// test never performs any Firestore I/O, but an app must exist for that
// call to succeed.
const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({ projectId: "demo-main-prize-draw-candidate-filter" });
const { needsMainPrizeDraw } = require("../main_prize_draw");

test("hasWinner:true -> already has a result, never needs a draw", () => {
  assert.equal(needsMainPrizeDraw({ hasWinner: true }), false);
});

test("draw_status:'no_main_prize' -> permanently settled without a winner, must not be re-opened", () => {
  assert.equal(needsMainPrizeDraw({ hasWinner: false, draw_status: "no_main_prize" }), false);
});

test("draw_status:'no_eligible_entries' -> permanently settled without a winner, must not be re-opened", () => {
  assert.equal(needsMainPrizeDraw({ hasWinner: false, draw_status: "no_eligible_entries" }), false);
});

test("hasWinner:false, no draw_status -> a real, never-finalized candidate", () => {
  assert.equal(needsMainPrizeDraw({ hasWinner: false }), true);
});

test("hasWinner entirely absent, no draw_status -> still a candidate (the legacy equality-filter blind spot)", () => {
  const game = { hasMainPrize: true, end_date: {} };
  assert.equal("hasWinner" in game, false);
  assert.equal(needsMainPrizeDraw(game), true);
});

test("draw_status:'completed' alone (hasWinner somehow not yet true) is not treated as permanently settled -- only the two no-winner terminal statuses are", () => {
  // completed games always have hasWinner:true written atomically in the
  // same transaction, so this case shouldn't occur in practice; the
  // filter deliberately only special-cases the two statuses that never
  // set hasWinner, matching drawMainPrize()'s own already_finalized check
  // exactly rather than inventing a broader rule.
  assert.equal(needsMainPrizeDraw({ hasWinner: false, draw_status: "completed" }), true);
});

for (const status of ["draft", "cancelled", "canceled", "disabled"]) {
  test(`status:'${status}' -> drawMainPrize()'s inactive branch never writes anything, must not be re-opened either`, () => {
    assert.equal(needsMainPrizeDraw({ hasWinner: false, status }), false);
  });
}

test("status:'ended' or 'actif' (anything outside the inactive set) remains a candidate", () => {
  assert.equal(needsMainPrizeDraw({ hasWinner: false, status: "ended" }), true);
  assert.equal(needsMainPrizeDraw({ hasWinner: false, status: "actif" }), true);
  assert.equal(needsMainPrizeDraw({ hasWinner: false }), true);
});

test("main_prize_winner set (hasWinner somehow not yet true) is still treated as already finalized, matching drawMainPrize()'s own already_finalized OR condition exactly", () => {
  assert.equal(needsMainPrizeDraw({ hasWinner: false, main_prize_winner: { path: "users/winner" } }), false);
});

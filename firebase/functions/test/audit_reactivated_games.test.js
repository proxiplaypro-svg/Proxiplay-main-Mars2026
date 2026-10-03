// Pure unit tests for scripts/audit_reactivated_games.js (same convention
// as test/game_integrity_audit.test.js: the audit logic is exported as
// plain, Firestore-free functions and tested directly -- no emulator
// needed, no Firestore access happens anywhere in this file).
//
// Fixtures model the 4 cases asked for in the mini-audit review:
// 1. a normal, currently active game (never finalized);
// 2. a normally-ended game (finalized once, never touched again);
// 3. an ended game reactivated the "Memphis" way (finalized, then
//    end_date pushed into the future and republished on the SAME
//    document);
// 4. a correctly duplicated game (brand-new document, not finalized,
//    even though its own end_date is in the future).
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isGameFinalized,
  computeSuspicionSignals,
  classifySuspicion,
  buildCandidateReport,
} = require("../scripts/audit_reactivated_games");

const ref = (path) => ({ path });
const ts = (iso) => ({ toMillis: () => new Date(iso).getTime() });

const NOW = new Date("2026-10-03T12:00:00Z").getTime();

test("1. jeu normal actif : jamais finalise, aucun signal, pas un candidat", () => {
  const game = {
    name: "Jeu normal",
    status: "actif",
    visible_public: true,
    end_date: ts("2026-12-31T00:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: null,
    drawn_at: null,
  };
  // The real pipeline (main()) only ever calls computeSuspicionSignals
  // for a game that isGameFinalized() already flagged true -- a never-
  // finalized game is skipped before that, regardless of its own dates
  // or status, so the only contract to test here is isGameFinalized
  // itself staying false.
  assert.equal(isGameFinalized(game), false);
});

test("2. jeu normalement termine : finalise mais aucun signal de reactivation", () => {
  const game = {
    name: "Jeu termine normalement",
    status: "expire",
    visible_public: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: ts("2026-09-30T20:05:00Z"),
  };
  assert.equal(isGameFinalized(game), true);
  const signals = computeSuspicionSignals(game, NOW);
  assert.deepEqual(signals, []);
  assert.equal(classifySuspicion(signals), "NONE");
});

test("3. jeu termine puis reactive (Memphis) : finalise + tous les signaux + HIGH", () => {
  const game = {
    name: "Memphis",
    status: "actif",
    visible_public: true,
    end_date: ts("2026-11-03T00:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: ts("2026-09-30T20:00:00Z"),
  };
  assert.equal(isGameFinalized(game), true);
  const signals = computeSuspicionSignals(game, NOW);
  assert.ok(signals.includes("end_date_after_drawn_at"));
  assert.ok(signals.includes("end_date_in_future"));
  assert.ok(signals.includes("visible_public_true"));
  assert.ok(signals.includes("status_active"));
  assert.equal(classifySuspicion(signals), "HIGH");

  const report = buildCandidateReport({
    gameId: "memphis_like",
    data: game,
    nowMs: NOW,
    participantsCount: 42,
    instantWinnerDocs: [
      { hasWinner: true, date: ts("2026-05-11T05:20:00Z"), player_id: ref("users/winner1") },
      { hasWinner: false, date: ts("2026-05-12T05:20:00Z") },
      { hasWinner: false, date: ts("2026-12-01T00:00:00Z") },
    ],
    prizesCount: 1,
  });
  assert.equal(report.suspicion, "HIGH");
  assert.equal(report.instantWinnersCount, 3);
  assert.equal(report.instantWinnersAssigned, 1);
  // Only the second doc is both unassigned AND already past due; the
  // third is unassigned but its date (01/12/2026) is still in the
  // future relative to NOW, so it must not be counted here.
  assert.equal(report.instantWinnersUnassignedPastDue, 1);
  assert.equal(report.participantsCount, 42);
  assert.equal(report.prizesCount, 1);
});

test("4. jeu duplique correctement : nouveau gameId, jamais finalise meme avec une end_date future", () => {
  const duplicatedGame = {
    name: "Memphis",
    status: "brouillon",
    visible_public: false,
    end_date: ts("2027-01-01T00:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: null,
    drawn_at: null,
  };
  // Same reasoning as test 1: main() gates on isGameFinalized() first,
  // so a freshly-duplicated draft (status:brouillon, visible_public:
  // false, no finalization marker at all -- see duplicateGameDocument()
  // in both gamesQueries.ts and gamesQueriesFixed.ts) is excluded before
  // signals/suspicion are ever computed, whatever its own end_date is.
  assert.equal(isGameFinalized(duplicatedGame), false);
});

test("normal closure lag: drawn_at legerement posterieur a end_date (cron quotidien) " +
  "n'est jamais classe comme reactivation", () => {
  // pickMainPrizeWinners runs once a day: a game whose end_date is
  // 30/09 at 20:00 is realistically drawn some hours later, here
  // 01/10 at 00:05 -- drawn_at > end_date, the opposite direction of the
  // Memphis pattern (end_date > drawn_at). Must never produce
  // end_date_after_drawn_at nor any suspicion.
  const game = {
    name: "Jeu termine normalement (cron du lendemain)",
    status: "ended",
    visible_public: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: ts("2026-10-01T00:05:00Z"),
  };
  assert.equal(isGameFinalized(game), true);
  const signals = computeSuspicionSignals(game, NOW);
  assert.ok(!signals.includes("end_date_after_drawn_at"));
  assert.deepEqual(signals, []);
  assert.equal(classifySuspicion(signals), "NONE");
});

test("MEDIUM: end_date pushed into the future without (yet) being republished visible/actif", () => {
  const game = {
    name: "Jeu a verifier",
    status: "brouillon",
    visible_public: false,
    end_date: ts("2026-11-03T00:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: ts("2026-09-30T20:00:00Z"),
  };
  const signals = computeSuspicionSignals(game, NOW);
  assert.equal(classifySuspicion(signals), "MEDIUM");
});

test("isGameFinalized recognizes each of the 4 signals independently", () => {
  assert.equal(isGameFinalized({ hasWinner: true }), true);
  assert.equal(isGameFinalized({ main_prize_winner: ref("users/a") }), true);
  assert.equal(isGameFinalized({ draw_status: "completed" }), true);
  assert.equal(isGameFinalized({ draw_status: "no_eligible_entries" }), true);
  assert.equal(isGameFinalized({ drawn_at: ts("2026-01-01T00:00:00Z") }), true);
  assert.equal(isGameFinalized({ draw_status: "some_other_unknown_value" }), false);
  assert.equal(isGameFinalized({}), false);
});

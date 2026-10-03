// Pure unit tests for scripts/audit_missed_main_prize_draws.js (same
// convention as test/audit_reactivated_games.test.js and
// test/game_integrity_audit.test.js: the audit logic is plain,
// Firestore-free functions, exercised directly with fixtures -- no
// emulator, no Firestore access anywhere in this file).
//
// Fixtures cover exactly what the Kids Troc audit needs distinguished:
// 1. a normal merchant-owned shop with no fulfillment_type -- must still
//    draw, via the ownerPath -> 'merchant' fallback in prizeFulfillment();
// 2. an admin-managed, ownerless shop with no fulfillment_type -- must be
//    blocked as INVALID_FULFILLMENT (the commit 752fb37 hypothesis);
// 3. the same shop but with fulfillment_type:'platform' explicitly set on
//    the game -- must pass that validation and reach READY_TO_DRAW;
// 4. hasWinner entirely absent from the document -- must still be
//    detected as a candidate (the equality-filter blind spot);
// 5. hasWinner:false -- the ordinary candidate shape;
// 6. zero eligible participants -- NO_ELIGIBLE_ENTRIES;
// 7. an existing "principal" prize with no finalization on the game --
//    PRIZE_EXISTS_WITHOUT_FINAL_DRAW.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertReadOnlySource,
  describeType,
  buildRawFieldDump,
  isMissedDrawCandidate,
  simulateMainPrizeDraw,
  buildMissedDrawReport,
  KIDS_TROC_GAME_ID,
} = require("../scripts/audit_missed_main_prize_draws");

const ref = (p) => ({ path: p });
const ts = (iso) => ({ toMillis: () => new Date(iso).getTime() });
const NOW = ts("2026-10-03T12:00:00Z");
const NOW_MS = NOW.toMillis();

const eligibleParticipant = { validRef: true, userExists: true, userData: { first_name: "Alice", city: "Paris" } };

test("KIDS_TROC_GAME_ID matches the real production id from the user's report", () => {
  assert.equal(KIDS_TROC_GAME_ID, "poq44UWwkSvKa9N3lbUj");
});

test("le fichier du script lui-meme ne contient aucun pattern d'ecriture Firestore", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "scripts", "audit_missed_main_prize_draws.js"),
    "utf8",
  );
  assert.doesNotThrow(() => assertReadOnlySource(source));
});

test("assertReadOnlySource detecte un .update( reel et ignore les commentaires qui en parlent", () => {
  assert.doesNotThrow(() =>
    assertReadOnlySource("// this script never calls .update( or .set( on purpose\nconst x = 1;"),
  );
  assert.throws(() => assertReadOnlySource("tx.update(ref, {hasWinner: true});"), /READ-ONLY VIOLATION/);
  assert.throws(() => assertReadOnlySource("db.collection('x').doc('y').set({});"), /READ-ONLY VIOLATION/);
  assert.throws(() => assertReadOnlySource("db.runTransaction(async () => {});"), /READ-ONLY VIOLATION/);
});

test("candidat detecte meme quand hasWinner est totalement absent du document (trou du filtre d'egalite)", () => {
  const game = { hasMainPrize: true, end_date: ts("2026-09-30T20:00:00Z") };
  assert.equal("hasWinner" in game, false);
  assert.equal(isMissedDrawCandidate(game, NOW_MS), true);
});

test("candidat detecte avec hasWinner:false explicite", () => {
  const game = { hasMainPrize: true, hasWinner: false, end_date: ts("2026-09-30T20:00:00Z") };
  assert.equal(isMissedDrawCandidate(game, NOW_MS), true);
});

test("hasWinner:true n'est jamais un candidat (deja gagne)", () => {
  const game = { hasMainPrize: true, hasWinner: true, end_date: ts("2026-09-30T20:00:00Z") };
  assert.equal(isMissedDrawCandidate(game, NOW_MS), false);
});

test("end_date future n'est jamais un candidat", () => {
  const game = { hasMainPrize: true, end_date: ts("2027-01-01T00:00:00Z") };
  assert.equal(isMissedDrawCandidate(game, NOW_MS), false);
});

test("1. marchand normal avec owner mais sans fulfillment_type herite 'merchant' et est READY_TO_DRAW", () => {
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    enseigne_id: ref("enseignes/normal_shop"),
  };
  const shop = { owner_id: ref("users/merchant") };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop,
    shopExists: true,
    participants: [eligibleParticipant],
    existingPrincipalPrizeExists: false,
  });
  assert.equal(decision.category, "READY_TO_DRAW");
  assert.equal(decision.fulfillment, "merchant");
  assert.equal(decision.ownership.ownerPath, "users/merchant");
});

test("2. enseigne managed_by_admin:true, sans owner et sans fulfillment_type -> INVALID_FULFILLMENT", () => {
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    enseigne_id: ref("enseignes/kids_troc"),
  };
  const shop = { managed_by_admin: true };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop,
    shopExists: true,
    participants: [eligibleParticipant],
    existingPrincipalPrizeExists: false,
  });
  assert.equal(decision.category, "INVALID_FULFILLMENT");
  assert.equal(decision.reason, "invalid_prize_fulfillment");
  assert.match(decision.fulfillmentError, /Remise du lot non configuree/);
  // Ownership itself was fine -- it's specifically fulfillment that blocks.
  assert.equal(decision.ownership.valid, true);
});

test("3. meme enseigne mais fulfillment_type:'platform' explicite sur le jeu -> passe la validation (READY_TO_DRAW)", () => {
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    enseigne_id: ref("enseignes/kids_troc"),
    fulfillment_type: "platform",
  };
  const shop = { managed_by_admin: true };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop,
    shopExists: true,
    participants: [eligibleParticipant],
    existingPrincipalPrizeExists: false,
  });
  assert.equal(decision.category, "READY_TO_DRAW");
  assert.equal(decision.fulfillment, "platform");
});

test("6. aucun participant eligible -> NO_ELIGIBLE_ENTRIES", () => {
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    enseigne_id: ref("enseignes/normal_shop"),
  };
  const shop = { owner_id: ref("users/merchant") };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop,
    shopExists: true,
    participants: [{ validRef: true, userExists: true, userData: { deleted: true } }],
    existingPrincipalPrizeExists: false,
  });
  assert.equal(decision.category, "NO_ELIGIBLE_ENTRIES");
});

test("7. un prize 'principal' existe deja sans finalisation du jeu -> PRIZE_EXISTS_WITHOUT_FINAL_DRAW", () => {
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    enseigne_id: ref("enseignes/normal_shop"),
  };
  const shop = { owner_id: ref("users/merchant") };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop,
    shopExists: true,
    participants: [eligibleParticipant],
    existingPrincipalPrizeExists: true,
  });
  assert.equal(decision.category, "PRIZE_EXISTS_WITHOUT_FINAL_DRAW");
});

test("deja finalise (hasWinner:true) -> ALREADY_FINALIZED, meme avec d'autres champs incoherents", () => {
  const game = { hasMainPrize: true, hasWinner: true, end_date: ts("2026-09-30T20:00:00Z") };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop: {},
    shopExists: false,
    participants: [],
    existingPrincipalPrizeExists: false,
  });
  assert.equal(decision.category, "ALREADY_FINALIZED");
});

test("enseigne absente ou mal formee -> MISSING_ENSEIGNE", () => {
  const game = { hasMainPrize: true, hasWinner: false, end_date: ts("2026-09-30T20:00:00Z") };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop: null,
    shopExists: false,
    participants: [eligibleParticipant],
    existingPrincipalPrizeExists: false,
  });
  assert.equal(decision.category, "MISSING_ENSEIGNE");
});

test("ownership invalide (owner du jeu incoherent avec l'enseigne) -> INVALID_OWNERSHIP", () => {
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T20:00:00Z"),
    enseigne_id: ref("enseignes/normal_shop"),
    owner_id: ref("users/someone_else"),
  };
  const shop = { owner_id: ref("users/merchant") };
  const decision = simulateMainPrizeDraw({
    game,
    now: NOW,
    shop,
    shopExists: true,
    participants: [eligibleParticipant],
    existingPrincipalPrizeExists: false,
  });
  assert.equal(decision.category, "INVALID_OWNERSHIP");
});

test("buildMissedDrawReport assemble une ligne de rapport complete pour Kids Troc (scenario invalid_prize_fulfillment)", () => {
  const data = {
    name: "jeu de Xbox one",
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T00:00:00Z"),
    enseigne_id: ref("enseignes/kids_troc"),
  };
  const report = buildMissedDrawReport({
    gameId: KIDS_TROC_GAME_ID,
    data,
    now: NOW,
    participants: [eligibleParticipant],
    existingPrizeId: null,
    shopInfo: { exists: true, data: { name: "Kids Troc", managed_by_admin: true }, enseigneRefPath: "enseignes/kids_troc" },
  });
  assert.equal(report.gameId, KIDS_TROC_GAME_ID);
  assert.equal(report.hasWinner, "false");
  assert.equal(report.managed_by_admin, true);
  assert.equal(report.category, "INVALID_FULFILLMENT");
  assert.ok(report.fulfillmentError);
  assert.equal(report.participantsCount, 1);
  assert.equal(report.eligibleParticipantsCount, 1);
});

test("buildMissedDrawReport : hasWinner absent est rapporte comme 'absent', pas confondu avec false", () => {
  const report = buildMissedDrawReport({
    gameId: "some_game",
    data: { hasMainPrize: true, end_date: ts("2026-09-30T00:00:00Z") },
    now: NOW,
    participants: [],
    existingPrizeId: null,
    shopInfo: { exists: false, data: null, enseigneRefPath: null },
  });
  assert.equal(report.hasWinner, "absent");
});

test("describeType distingue Timestamp, DocumentReference, string, et absence", () => {
  assert.equal(describeType(ts("2026-09-30T00:00:00Z")), "Firestore Timestamp (has toMillis)");
  assert.equal(describeType(ref("users/a")), "DocumentReference");
  assert.equal(describeType("30/09/2026"), "string");
  assert.equal(describeType(null), "null");
  assert.equal(describeType(undefined), "undefined");
  assert.equal(describeType(true), "boolean");
});

test("buildRawFieldDump sur un document forme exactement comme Kids Troc (Timestamp reel, hasWinner:false) : candidat detectable", () => {
  const dump = buildRawFieldDump({
    exists: true,
    id: KIDS_TROC_GAME_ID,
    data: {
      hasMainPrize: true,
      hasWinner: false,
      end_date: ts("2026-09-30T00:00:00Z"),
      status: "ended",
    },
  });
  assert.equal(dump.exists, true);
  assert.equal(dump.hasMainPrize_present, true);
  assert.equal(dump.hasMainPrize_strictlyTrue, true);
  assert.equal(dump.hasWinner_present, true);
  assert.equal(dump.hasWinner, false);
  assert.equal(dump.end_date_present, true);
  assert.equal(dump.end_date_has_toMillis, true);
  assert.equal(dump.end_date_resolved_iso, "2026-09-30T00:00:00.000Z");
  assert.equal(dump.main_prize_winner, null);
});

test("buildRawFieldDump expose le cas piege : end_date stocke comme une chaine plutot qu'un Timestamp", () => {
  const dump = buildRawFieldDump({
    exists: true,
    id: "legacy_game",
    data: { hasMainPrize: true, hasWinner: false, end_date: "30/09/2026" },
  });
  assert.equal(dump.end_date_type, "string");
  assert.equal(dump.end_date_has_toMillis, false);
  assert.equal(dump.end_date_resolved_iso, null, "une chaine non-ISO ne doit pas etre interpretee silencieusement comme une date valide");
  // C'est exactement ce qui ferait echouer isMissedDrawCandidate silencieusement :
  assert.equal(isMissedDrawCandidate({ hasMainPrize: true, hasWinner: false, end_date: "30/09/2026" }, NOW_MS), false);
});

test("buildRawFieldDump expose le cas piege : hasMainPrize non strictement booleen (ex. la chaine 'true')", () => {
  const dump = buildRawFieldDump({
    exists: true,
    id: "legacy_game_2",
    data: { hasMainPrize: "true", hasWinner: false, end_date: ts("2026-09-30T00:00:00Z") },
  });
  assert.equal(dump.hasMainPrize_type, "string");
  assert.equal(dump.hasMainPrize_strictlyTrue, false);
});

test("buildRawFieldDump sur document absent : exists:false, tous les champs a leur valeur neutre", () => {
  const dump = buildRawFieldDump({ exists: false, id: "missing_game", data: null });
  assert.equal(dump.exists, false);
  assert.equal(dump.hasMainPrize, null);
  assert.equal(dump.hasMainPrize_present, false);
  assert.equal(dump.end_date_present, false);
});

test("buildMissedDrawReport ne mute jamais les objets source passes en entree (lecture pure)", () => {
  const data = { hasMainPrize: true, hasWinner: false, end_date: ts("2026-09-30T00:00:00Z") };
  const snapshot = JSON.parse(JSON.stringify({ hasMainPrize: true, hasWinner: false }));
  buildMissedDrawReport({
    gameId: "g",
    data,
    now: NOW,
    participants: [],
    existingPrizeId: null,
    shopInfo: { exists: false, data: null, enseigneRefPath: null },
  });
  assert.deepEqual({ hasMainPrize: data.hasMainPrize, hasWinner: data.hasWinner }, snapshot);
});

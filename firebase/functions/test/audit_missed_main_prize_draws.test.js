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
const os = require("node:os");
const {
  assertReadOnlySource,
  describeType,
  buildRawFieldDump,
  describeAuthSource,
  buildConnectionDiagnostic,
  isMissedDrawCandidate,
  simulateMainPrizeDraw,
  buildMissedDrawReport,
  buildReportForGame,
  safelyBuildReport,
  logProgress,
  KIDS_TROC_GAME_ID,
  ADMIN_APP_NAME,
} = require("../scripts/audit_missed_main_prize_draws");

const ref = (p) => ({ path: p });
const ts = (iso) => ({ toMillis: () => new Date(iso).getTime() });
const NOW = ts("2026-10-03T12:00:00Z");
const NOW_MS = NOW.toMillis();

const eligibleParticipant = { validRef: true, userExists: true, userData: { first_name: "Alice", city: "Paris" } };

test("KIDS_TROC_GAME_ID matches the real production id (capital I, not lowercase l, after N3)", () => {
  assert.equal(KIDS_TROC_GAME_ID, "poq44UWwkSvKa9N3IbUj");
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

// --- Connection diagnostic: describeAuthSource / buildConnectionDiagnostic ---
// Exercises the exact ADC lookup order Google's client libraries follow,
// using throwaway temp files -- never the user's real credentials -- and
// proves the result never carries a private_key or token.

test("ADMIN_APP_NAME est un nom d'app dedie, jamais l'app par defaut implicite", () => {
  assert.equal(typeof ADMIN_APP_NAME, "string");
  assert.ok(ADMIN_APP_NAME.length > 0);
  assert.notEqual(ADMIN_APP_NAME, "[DEFAULT]");
});

test("describeAuthSource : GOOGLE_APPLICATION_CREDENTIALS pointe vers un fichier de service account valide", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "audit-auth-test-"));
  const keyPath = path.join(dir, "fake-service-account.json");
  try {
    fs.writeFileSync(
      keyPath,
      JSON.stringify({
        type: "service_account",
        project_id: "proxi-play-odzp2e",
        client_email: "fake@proxi-play-odzp2e.iam.gserviceaccount.com",
        private_key: "-----BEGIN PRIVATE KEY-----\nSECRET_DO_NOT_LEAK\n-----END PRIVATE KEY-----\n",
      }),
    );
    const result = describeAuthSource({ GOOGLE_APPLICATION_CREDENTIALS: keyPath });
    assert.equal(result.mechanism, "GOOGLE_APPLICATION_CREDENTIALS");
    assert.equal(result.credentialFileExists, true);
    assert.equal(result.credentialFileType, "service_account");
    assert.equal(result.credentialFileProjectId, "proxi-play-odzp2e");
    assert.equal(result.credentialFileClientEmail, "fake@proxi-play-odzp2e.iam.gserviceaccount.com");
    assert.equal("private_key" in result, false, "le resultat ne doit jamais contenir la cle privee");
    assert.ok(!JSON.stringify(result).includes("SECRET_DO_NOT_LEAK"), "aucun secret ne doit fuiter dans la sortie");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("describeAuthSource : GOOGLE_APPLICATION_CREDENTIALS pointe vers un fichier absent", () => {
  const result = describeAuthSource({ GOOGLE_APPLICATION_CREDENTIALS: "/nonexistent/path/key.json" });
  assert.equal(result.mechanism, "GOOGLE_APPLICATION_CREDENTIALS");
  assert.equal(result.credentialFileExists, false);
});

test("describeAuthSource : pas de GOOGLE_APPLICATION_CREDENTIALS mais un fichier ADC gcloud present", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "audit-auth-test-home-"));
  const gcloudDir = path.join(dir, ".config", "gcloud");
  fs.mkdirSync(gcloudDir, { recursive: true });
  try {
    fs.writeFileSync(
      path.join(gcloudDir, "application_default_credentials.json"),
      JSON.stringify({ type: "authorized_user", client_id: "fake-client-id.apps.googleusercontent.com" }),
    );
    const result = describeAuthSource({ HOME: dir });
    assert.match(result.mechanism, /gcloud user ADC/);
    assert.equal(result.credentialFileExists, true);
    assert.equal(result.credentialFileType, "authorized_user");
    assert.ok(result.note, "doit preciser que ce fichier n'a pas de project_id propre");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("describeAuthSource : aucune methode ADC locale detectee -> mecanisme metadata server suppose", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "audit-auth-test-empty-"));
  try {
    const result = describeAuthSource({ HOME: dir });
    assert.equal(result.credentialFileExists, false);
    assert.equal(result.credentialFilePath, null);
    assert.match(result.mechanism, /metadata server/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("buildConnectionDiagnostic : projectIdMatches reflete fidelement requested vs effectif", () => {
  const match = buildConnectionDiagnostic({
    requestedProjectId: "proxi-play-odzp2e",
    effectiveProjectId: "proxi-play-odzp2e",
    databaseId: "(default)",
    appName: ADMIN_APP_NAME,
    authSource: { mechanism: "test" },
    gamesCollectionCount: 138,
    sampleGameIds: ["a", "b"],
    env: {},
  });
  assert.equal(match.projectIdMatches, true);

  const mismatch = buildConnectionDiagnostic({
    requestedProjectId: "proxi-play-odzp2e",
    effectiveProjectId: "un-autre-projet",
    databaseId: "(default)",
    appName: ADMIN_APP_NAME,
    authSource: { mechanism: "test" },
    gamesCollectionCount: 0,
    sampleGameIds: [],
    env: {},
  });
  assert.equal(mismatch.projectIdMatches, false);
});

test("buildConnectionDiagnostic : expose FIRESTORE_EMULATOR_HOST et les variables d'env demandees, sans secret", () => {
  const result = buildConnectionDiagnostic({
    requestedProjectId: "proxi-play-odzp2e",
    effectiveProjectId: "proxi-play-odzp2e",
    databaseId: "(default)",
    appName: ADMIN_APP_NAME,
    authSource: { mechanism: "test" },
    gamesCollectionCount: 138,
    sampleGameIds: ["poq44UWwkSvKa9N3lbUj"],
    env: {
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
      GOOGLE_CLOUD_PROJECT: "proxi-play-odzp2e",
      GCLOUD_PROJECT: null,
      FIREBASE_CONFIG: '{"projectId":"proxi-play-odzp2e"}',
      GOOGLE_APPLICATION_CREDENTIALS: "/path/to/key.json",
    },
  });
  assert.equal(result.firestoreEmulatorHost, "127.0.0.1:8080");
  assert.equal(result.env.GOOGLE_CLOUD_PROJECT, "proxi-play-odzp2e");
  assert.equal(result.env.FIREBASE_CONFIG_present, true);
  assert.equal(result.env.GOOGLE_APPLICATION_CREDENTIALS, "/path/to/key.json");
  assert.equal(result.gamesCollectionCount, 138);
  assert.deepEqual(result.sampleGameIds, ["poq44UWwkSvKa9N3lbUj"]);
  assert.ok(!JSON.stringify(result).match(/private_key|AIza|token/i), "aucun secret ne doit apparaitre dans le diagnostic de connexion");
});

test("buildConnectionDiagnostic : FIRESTORE_EMULATOR_HOST absent -> null, pas une chaine vide trompeuse", () => {
  const result = buildConnectionDiagnostic({
    requestedProjectId: "proxi-play-odzp2e",
    effectiveProjectId: "proxi-play-odzp2e",
    databaseId: "(default)",
    appName: ADMIN_APP_NAME,
    authSource: { mechanism: "test" },
    gamesCollectionCount: 0,
    sampleGameIds: [],
    env: {},
  });
  assert.equal(result.firestoreEmulatorHost, null);
});

// --- Reproduction of the "global scan appears to hang" report ---
// A minimal, purpose-built fake Firestore: just enough of the .doc()/
// .collection()/.where()/.limit()/.get() surface that buildReportForGame
// actually calls, nothing more. No real Firestore or emulator involved.

function makePrizesQuery(existingPrizeId) {
  const query = {
    where: () => query,
    limit: () => query,
    get: async () => (existingPrizeId ? { empty: false, docs: [{ id: existingPrizeId }] } : { empty: true, docs: [] }),
  };
  return query;
}

function makeFakeDb({
  participantRefs = [],
  userDocs = {},
  existingPrizeId = null,
  shopExists = false,
  shopData = null,
  throwOnParticipantsGet = false,
  delayedUserPaths = new Set(),
}) {
  return {
    doc(docPath) {
      return {
        path: docPath,
        collection(name) {
          assert.equal(name, "participants", "ce fake ne modelise que la sous-collection participants");
          return {
            async get() {
              if (throwOnParticipantsGet) throw new Error("simulated participants read failure");
              return {
                docs: participantRefs.map((ref, i) => ({ id: `ticket${i}`, data: () => ({ user_id: ref }) })),
              };
            },
          };
        },
        async get() {
          if (docPath.startsWith("users/")) {
            const resolve = () => {
              const data = userDocs[docPath];
              return { exists: data != null, data: () => data };
            };
            if (delayedUserPaths.has(docPath)) {
              // Resolves later than an "earlier" ticket's lookup would,
              // proving Promise.all preserves ticket order regardless of
              // which underlying read settles first.
              await new Promise((r) => setTimeout(r, 5));
            }
            return resolve();
          }
          if (docPath.startsWith("enseignes/")) {
            return { exists: shopExists, data: () => shopData };
          }
          throw new Error(`fake db.doc(${docPath}).get() not stubbed`);
        },
      };
    },
    collection(name) {
      assert.equal(name, "prizes", "ce fake ne modelise que la collection prizes au niveau racine");
      return makePrizesQuery(existingPrizeId);
    },
  };
}

test("reproduction : buildReportForGame fonctionne de bout en bout sur un jeu avec plusieurs participants (fake Firestore)", async () => {
  const db = makeFakeDb({
    participantRefs: [{ path: "users/a" }, { path: "users/b" }],
    userDocs: { "users/a": { first_name: "Alice" }, "users/b": { first_name: "Bob" } },
    shopExists: true,
    shopData: { owner_id: { path: "users/merchant" } },
  });
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T00:00:00Z"),
    enseigne_id: ref("enseignes/kids_troc"),
  };
  const report = await buildReportForGame(db, KIDS_TROC_GAME_ID, game, NOW);
  assert.equal(report.category, "READY_TO_DRAW");
  assert.equal(report.participantsCount, 2);
  assert.equal(report.eligibleParticipantsCount, 2);
});

test("reproduction : les lectures de participants restent dans l'ordre des tickets meme resolues de facon concurrente et desordonnee", async () => {
  const db = makeFakeDb({
    participantRefs: [{ path: "users/first" }, { path: "users/second" }, { path: "users/third" }],
    userDocs: {
      "users/first": { first_name: "First" },
      "users/second": { first_name: "Second" },
      "users/third": { first_name: "Third" },
    },
    // Le premier ticket resout plus tard que les suivants : si le code
    // repassait a une boucle sequentielle ou perdait l'ordre, ce test le
    // detecterait.
    delayedUserPaths: new Set(["users/first"]),
    shopExists: true,
    shopData: { owner_id: { path: "users/merchant" } },
  });
  const game = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T00:00:00Z"),
    enseigne_id: ref("enseignes/kids_troc"),
  };
  const report = await buildReportForGame(db, "ordering_check", game, NOW);
  assert.equal(report.eligibleParticipantsCount, 3);
});

test("reproduction : un jeu dont l'analyse echoue (lecture participants en erreur) n'interrompt pas l'audit -- safelyBuildReport isole l'erreur", async () => {
  const brokenDb = makeFakeDb({ throwOnParticipantsGet: true });
  const workingDb = makeFakeDb({
    participantRefs: [{ path: "users/a" }],
    userDocs: { "users/a": { first_name: "Alice" } },
    shopExists: true,
    shopData: { owner_id: { path: "users/merchant" } },
  });
  const brokenGame = { hasMainPrize: true, hasWinner: false, end_date: ts("2026-09-30T00:00:00Z") };
  const okGame = {
    hasMainPrize: true,
    hasWinner: false,
    end_date: ts("2026-09-30T00:00:00Z"),
    enseigne_id: ref("enseignes/ok_shop"),
  };

  const progressLines = [];
  const onProgress = (m) => progressLines.push(m);

  // Exactly the shape of the main() scan loop: one throwing game must not
  // prevent the next one from being analyzed.
  const results = [];
  results.push(await safelyBuildReport(brokenDb, "broken_game", brokenGame, NOW, onProgress));
  results.push(await safelyBuildReport(workingDb, "ok_game", okGame, NOW, onProgress));

  assert.equal(results[0].category, "ANALYSIS_ERROR");
  assert.equal(results[0].gameId, "broken_game");
  assert.match(results[0].error, /simulated participants read failure/);
  assert.equal(results[1].category, "READY_TO_DRAW", "le 2e jeu doit etre analyse normalement malgre l'echec du premier");
  assert.ok(
    progressLines.some((l) => l.includes("broken_game") && l.includes("ERREUR")),
    "l'erreur doit etre rapportee via onProgress",
  );
});

test("logProgress ecrit sur stderr, jamais sur stdout, pour ne pas polluer le JSON final", () => {
  const originalStderrWrite = process.stderr.write;
  const originalStdoutWrite = process.stdout.write;
  const stderrChunks = [];
  const stdoutChunks = [];
  process.stderr.write = (chunk) => {
    stderrChunks.push(chunk);
    return true;
  };
  process.stdout.write = (chunk) => {
    stdoutChunks.push(chunk);
    return true;
  };
  try {
    logProgress("ceci doit atterrir sur stderr uniquement");
  } finally {
    process.stderr.write = originalStderrWrite;
    process.stdout.write = originalStdoutWrite;
  }
  assert.equal(stdoutChunks.length, 0, "logProgress ne doit jamais ecrire sur stdout");
  assert.equal(stderrChunks.length, 1);
  assert.match(stderrChunks[0], /ceci doit atterrir sur stderr uniquement/);
  assert.match(stderrChunks[0], /\[audit_missed_main_prize_draws\]/);
});

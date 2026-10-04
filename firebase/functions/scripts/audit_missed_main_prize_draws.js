#!/usr/bin/env node
"use strict";

// STRICTLY READ-ONLY. Simulates, without writing anything, the exact
// decision chain main_prize_draw.js's drawMainPrize() applies -- using
// the SAME pure helpers it imports (gameOwnership, prizeFulfillment,
// excluded) -- to classify every "games" document whose main prize draw
// should already have happened but never produced a finalization result.
//
// Context: games/poq44UWwkSvKa9N3IbUj ("jeu de Xbox one", Kids Troc) is
// hasMainPrize:true, end_date 30/09/2026 passed, 1576 participations,
// 289 unique players -- yet hasWinner:false with no main_prize_winner,
// draw_status or drawn_at at all. The leading hypothesis is that commit
// 752fb37 ("feat: support admin-managed game ownership and fulfillment",
// 28/09/2026) added prizeFulfillment() as a new, non-backfilled
// requirement that can silently abort the draw via review() -- which only
// logs AWARD_MANUAL_REVIEW_REQUIRED and writes nothing to Firestore. But
// a merchant-owned shop would get fulfillment_type:'merchant' for free
// via the ownerPath fallback, so the real cause must be verified per
// game, not assumed.
//
// Candidate selection deliberately does NOT rely on a single
// where('hasWinner','==','false') query: Firestore's equality filter
// excludes any document where the field is entirely absent, which would
// silently hide exactly this kind of legacy/schema-inconsistent game.
// Instead this script paginates the WHOLE "games" collection (same
// technique as audit_reactivated_games.js) and filters in memory for
// hasMainPrize===true, a passed end_date, and hasWinner either false or
// missing.
//
// Never selects a winner, never calls drawMainPrize(), never writes to
// games/prizes/participants/enseignes/users or any other collection.
// assertReadOnlySource() below statically checks this file's own source
// for forbidden write-method patterns before main() touches Firestore.
//
// Usage:
//   node scripts/audit_missed_main_prize_draws.js --project <firebase-project-id> \
//     [--page-size 200] [--json-out report.json] [--game-id <id>] [--connection-diagnostic]
//
// --game-id switches to a single-document diagnostic mode: it fetches
// that one games/{id} document DIRECTLY (db.doc().get(), no collection
// scan at all) and prints the raw field values actually read --
// exists, id, hasMainPrize (+ its JS type), hasWinner (+ presence and
// type), end_date (+ presence, type, whether it exposes toMillis, and
// the ISO string that resolves to), status, draw_status and
// main_prize_winner -- BEFORE isMissedDrawCandidate() or
// simulateMainPrizeDraw() ever run on it. This is the fastest way to
// see exactly why a specific document (e.g. Kids Troc) was or wasn't
// picked up by the general scan below, without guessing at its schema.
//
// --connection-diagnostic answers a more basic question first: is this
// script even connected to the same project/database the person is
// looking at in Firebase Console? It prints the requested vs. effective
// project id, the Firestore database id actually opened, whether
// FIRESTORE_EMULATOR_HOST is set, which ADC mechanism is in use (by file
// path and non-secret identity fields only -- never a token or private
// key), a live count() of the "games" collection, and a handful of real
// document ids to cross-check against the console. This block is also
// included in every other mode's output, so any run can be checked for
// consistency after the fact.
//
// Progress: every mode writes timestamped progress lines to STDERR
// (never stdout, which stays clean JSON) -- the games scanned so far,
// each candidate as it's found ([scanned/total] gameId - name), and
// each sub-step of a candidate's analysis (participants/prizes/
// enseigne). A full scan used to run completely silent until the very
// end, which with hundreds or thousands of participants to check per
// candidate (sequential, one Firestore round-trip at a time, before this
// change) could take long enough to look indistinguishable from a hang.
// Participant reads are now fetched concurrently (Promise.all) instead
// of one at a time, and one candidate's analysis throwing an error no
// longer aborts the whole run: it is caught, reported as an
// ANALYSIS_ERROR row, and the scan continues with the next candidate.
const fs = require("node:fs");
const path = require("node:path");
const { gameOwnership } = require("../merchant_ownership");
const { prizeFulfillment } = require("../prize_fulfillment");
const { excluded } = require("../prize_integrity");

// Capital I (not lowercase l) after "N3" -- confirmed via
// search_games_by_keyword.js against production after the lowercase-l
// version returned document_not_found / NOT_FOUND here. The two
// characters are visually indistinguishable in most fonts; if this ID
// is ever retyped by hand, re-verify it the same way rather than
// trusting a visual read.
const KIDS_TROC_GAME_ID = "poq44UWwkSvKa9N3IbUj";

// Dedicated, explicitly-named Firebase app for this script. The old code
// did `if (!admin.apps.length) admin.initializeApp(...)` -- if ANY
// default app already existed in the Node process for any reason, that
// check would silently skip initialization and --project would be
// ignored entirely, reusing whatever project/credential that other app
// was bound to. A uniquely-named app removes that ambiguity: this
// script's Firestore connection is never shared with, or silently
// inherited from, another app.
const ADMIN_APP_NAME = "audit_missed_main_prize_draws";

// Any match here means this file is no longer read-only and must not run
// against a real project. Deliberately avoids native Map.set()/Set.add()
// anywhere else in this file so the check stays a true read-only proof,
// not something worked around by using different objects for the same
// write-shaped calls.
function assertReadOnlySource(sourceText) {
  const stripped = sourceText
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
  const forbidden = /\.(set|update|delete|create|add)\s*\(|\.batch\s*\(|\.runTransaction\s*\(/;
  const match = stripped.match(forbidden);
  if (match) {
    throw new Error(
      `READ-ONLY VIOLATION: forbidden pattern "${match[0]}" found in audit_missed_main_prize_draws.js -- refusing to run.`,
    );
  }
}

function toMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function toIso(value) {
  const ms = toMillis(value);
  return ms === null ? null : new Date(ms).toISOString();
}

function refPath(value) {
  return typeof value?.path === "string" ? value.path : "";
}

/** Pure. Describes the actual JS shape of a field's raw value, without
 * assuming it is the Firestore type the engine expects -- this is what
 * lets the diagnostic mode show e.g. "end_date is a string, not a
 * Timestamp" instead of silently treating it as absent. */
function describeType(value) {
  if (value === null) return "null";
  if (value === undefined) return "undefined";
  if (Array.isArray(value)) return "array";
  if (typeof value === "object") {
    if (typeof value.toMillis === "function") return "Firestore Timestamp (has toMillis)";
    if (typeof value.path === "string") return "DocumentReference";
    return value.constructor?.name || "object";
  }
  return typeof value;
}

/** Pure. Raw, unfiltered read of the exact fields drawMainPrize()'s
 * candidate selection and decision chain depend on -- built straight
 * from an already-fetched {exists, id, data}, no Firestore access here.
 * Deliberately reports presence and JS type separately from the value
 * itself, since "false" vs "absent" vs "the string 'false'" are three
 * different things this script must never conflate. */
function buildRawFieldDump({ exists, id, data }) {
  const d = data || {};
  const has = (key) => Object.prototype.hasOwnProperty.call(d, key);
  return {
    exists,
    id,
    hasMainPrize: d.hasMainPrize ?? null,
    hasMainPrize_present: has("hasMainPrize"),
    hasMainPrize_type: describeType(d.hasMainPrize),
    hasMainPrize_strictlyTrue: d.hasMainPrize === true,
    hasWinner: d.hasWinner ?? null,
    hasWinner_present: has("hasWinner"),
    hasWinner_type: describeType(d.hasWinner),
    end_date_present: has("end_date"),
    end_date_type: describeType(d.end_date),
    end_date_has_toMillis: typeof d.end_date?.toMillis === "function",
    end_date_resolved_iso: toIso(d.end_date),
    status: d.status ?? null,
    draw_status: d.draw_status ?? null,
    main_prize_winner_present: has("main_prize_winner"),
    main_prize_winner: refPath(d.main_prize_winner) || d.main_prize_winner || null,
  };
}

/** Pure. Mirrors the hasMain derivation inside drawMainPrize() exactly. */
function deriveHasMainPrize(game) {
  return typeof game.hasMainPrize === "boolean"
    ? game.hasMainPrize
    : !!(
        game.prize_value != null ||
        (typeof game.main_prize_title === "string" && game.main_prize_title.trim()) ||
        (typeof game.main_prize_description === "string" && game.main_prize_description.trim())
      );
}

/** Pure. A game whose main prize draw should already have run but shows
 * no finalization result -- deliberately checks hasWinner===false OR
 * entirely absent, never a single equality-filter query. */
function isMissedDrawCandidate(data, nowMs) {
  const endMs = toMillis(data?.end_date);
  if (data?.hasMainPrize !== true) return false;
  if (endMs === null || endMs > nowMs) return false;
  const hasWinnerAbsent = !Object.prototype.hasOwnProperty.call(data || {}, "hasWinner");
  return data.hasWinner === false || hasWinnerAbsent;
}

/** Pure. Same validity check drawMainPrize() applies to a participant's
 * user_id before trusting it. */
function isValidUserRef(ref) {
  return /^users\/[^/]+$/.test(ref?.path || "");
}

/** Pure. Reproduces drawMainPrize()'s decision chain, in the exact same
 * order, using the exact same imported helpers -- but only ever reads
 * its inputs, never selects a winner and never returns anything meant to
 * be written. `participants` is an array of {validRef, userExists,
 * userData} already resolved by the caller (loadParticipantsContext()
 * below is the only place that reads Firestore for this). */
function simulateMainPrizeDraw({
  game,
  now,
  shop,
  shopExists,
  participants,
  existingPrincipalPrizeExists,
}) {
  if (
    game.hasWinner ||
    game.main_prize_winner ||
    ["no_eligible_entries", "no_main_prize"].includes(game.draw_status)
  ) {
    return { category: "ALREADY_FINALIZED", reason: "already_finalized" };
  }
  if (!game.end_date?.toMillis || game.end_date.toMillis() > now.toMillis()) {
    return { category: "NOT_DUE", reason: "not_due" };
  }
  if (["draft", "cancelled", "canceled", "disabled"].includes(game.status)) {
    return { category: "INACTIVE", reason: "inactive" };
  }
  const hasMain = deriveHasMainPrize(game);
  if (!hasMain) {
    return { category: "NO_MAIN_PRIZE", reason: "no_main_prize" };
  }
  const eligible = (participants || []).filter(
    (p) => p.validRef && p.userExists && !excluded(p.userData),
  );
  if (existingPrincipalPrizeExists) {
    return { category: "PRIZE_EXISTS_WITHOUT_FINAL_DRAW", reason: "prize_exists_without_final_draw" };
  }
  if (!eligible.length) {
    return { category: "NO_ELIGIBLE_ENTRIES", reason: "no_eligible_entries" };
  }
  if (
    game.prize_usage_deadline != null &&
    (typeof game.prize_usage_deadline.toMillis !== "function" ||
      game.prize_usage_deadline.toMillis() <= now.toMillis())
  ) {
    return { category: "INVALID_PRIZE_DEADLINE", reason: "invalid_or_expired_prize_deadline" };
  }
  const enseigneRef = game.enseigne_id || game.enseigne_ref;
  if (!/^enseignes\/[^/]+$/.test(enseigneRef?.path || "")) {
    return { category: "MISSING_ENSEIGNE", reason: "missing_enseigne" };
  }
  const ownership = gameOwnership(game, shop || {});
  if (!shopExists || !ownership.valid) {
    return { category: "INVALID_OWNERSHIP", reason: "invalid_merchant_owner", ownership };
  }
  try {
    const fulfillment = prizeFulfillment(game, shop || {});
    return {
      category: "READY_TO_DRAW",
      reason: "ready_to_draw",
      ownership,
      fulfillment,
      eligibleCount: eligible.length,
    };
  } catch (error) {
    return {
      category: "INVALID_FULFILLMENT",
      reason: "invalid_prize_fulfillment",
      ownership,
      fulfillmentError: error.message,
    };
  }
}

function hasWinnerDisplay(data) {
  if (!Object.prototype.hasOwnProperty.call(data, "hasWinner")) return "absent";
  return data.hasWinner === true ? "true" : data.hasWinner === false ? "false" : String(data.hasWinner);
}

/** Pure. Assembles one full report row for a candidate game -- all
 * inputs already fetched read-only by the caller. */
function buildMissedDrawReport({ gameId, data, now, participants, existingPrizeId, shopInfo }) {
  const decision = simulateMainPrizeDraw({
    game: data,
    now,
    shop: shopInfo?.data || {},
    shopExists: !!shopInfo?.exists,
    participants,
    existingPrincipalPrizeExists: existingPrizeId != null,
  });

  const eligibleCount = (participants || []).filter(
    (p) => p.validRef && p.userExists && !excluded(p.userData),
  ).length;

  return {
    gameId,
    name: data.name || data.title || null,
    enseigne: shopInfo?.data?.name || data.enseigne_name || shopInfo?.enseigneRefPath || null,
    end_date: toIso(data.end_date),
    hasMainPrize: data.hasMainPrize ?? null,
    hasWinner: hasWinnerDisplay(data),
    status: data.status ?? null,
    draw_status: data.draw_status ?? null,
    drawn_at: toIso(data.drawn_at),
    main_prize_winner: refPath(data.main_prize_winner) || null,
    fulfillment_type: data.fulfillment_type ?? null,
    managed_by_admin: shopInfo?.data?.managed_by_admin ?? null,
    owner: refPath(shopInfo?.data?.owner) || shopInfo?.data?.owner || null,
    owner_id: refPath(shopInfo?.data?.owner_id) || shopInfo?.data?.owner_id || null,
    ownership: decision.ownership
      ? { valid: decision.ownership.valid, ownerPath: decision.ownership.ownerPath }
      : null,
    fulfillment: decision.fulfillment ?? null,
    fulfillmentError: decision.fulfillmentError ?? null,
    participantsCount: (participants || []).length,
    eligibleParticipantsCount: eligibleCount,
    prize_usage_deadline: toIso(data.prize_usage_deadline),
    existingPrincipalPrizeId: existingPrizeId ?? null,
    category: decision.category,
    reason: decision.reason,
  };
}

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    pageSize: 200,
    jsonOut: "",
    gameId: "",
    connectionDiagnostic: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project" && i + 1 < argv.length) {
      args.project = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--page-size" && i + 1 < argv.length) {
      args.pageSize = Math.max(1, Math.min(300, Number(argv[i + 1]) || 200));
      i += 1;
    } else if (arg === "--json-out" && i + 1 < argv.length) {
      args.jsonOut = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--game-id" && i + 1 < argv.length) {
      args.gameId = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--connection-diagnostic") {
      args.connectionDiagnostic = true;
    }
  }
  return args;
}

function ensureFirestore(admin, projectId) {
  if (!projectId) {
    throw new Error("Project id manquant. Utilisez --project <firebase-project-id>.");
  }
  const existing = admin.apps.find((a) => a && a.name === ADMIN_APP_NAME);
  const app =
    existing ||
    admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId }, ADMIN_APP_NAME);
  return { app, db: admin.firestore(app) };
}

/** Pure (takes env as a plain object, no Firestore access). Identifies
 * which ADC mechanism firebase-admin will actually use, following the
 * same lookup order Google's client libraries document, without ever
 * reading or returning a private_key or any token. Only non-secret
 * identity fields (project_id, client_email, client_id, credential
 * type) are surfaced -- exactly enough to tell whether the credential
 * in use is plausibly tied to the intended project. */
function describeAuthSource(env = process.env) {
  const gacPath = env.GOOGLE_APPLICATION_CREDENTIALS || "";
  if (gacPath) {
    const resolved = path.resolve(gacPath);
    const result = {
      mechanism: "GOOGLE_APPLICATION_CREDENTIALS",
      credentialFilePath: resolved,
      credentialFileExists: fs.existsSync(resolved),
      credentialFileType: null,
      credentialFileProjectId: null,
      credentialFileClientEmail: null,
      readError: null,
    };
    if (result.credentialFileExists) {
      try {
        const raw = JSON.parse(fs.readFileSync(resolved, "utf8"));
        result.credentialFileType = raw.type || null;
        result.credentialFileProjectId = raw.project_id || null;
        result.credentialFileClientEmail = raw.client_email || null;
      } catch (error) {
        result.readError = error.message;
      }
    }
    return result;
  }
  const gcloudAdcPath = path.join(
    env.HOME || env.USERPROFILE || "",
    ".config",
    "gcloud",
    "application_default_credentials.json",
  );
  if (fs.existsSync(gcloudAdcPath)) {
    const result = {
      mechanism: "gcloud user ADC (application_default_credentials.json)",
      credentialFilePath: gcloudAdcPath,
      credentialFileExists: true,
      credentialFileType: null,
      credentialFileClientId: null,
      note:
        "Identifiants utilisateur gcloud : pas de project_id propre dans ce fichier -- le routage vers un projet vient de --project (passe explicitement a initializeApp), pas de ce fichier.",
    };
    try {
      const raw = JSON.parse(fs.readFileSync(gcloudAdcPath, "utf8"));
      result.credentialFileType = raw.type || null;
      result.credentialFileClientId = raw.client_id || null;
    } catch (_) {
      // Non bloquant pour ce diagnostic -- la presence du fichier suffit a identifier le mecanisme.
    }
    return result;
  }
  return {
    mechanism:
      "aucun fichier ADC local detecte (GOOGLE_APPLICATION_CREDENTIALS absent, pas de fichier gcloud ADC) -- un service account de metadata server (GCE/Cloud Run/Cloud Functions) est probable si la connexion a reussi malgre tout",
    credentialFilePath: null,
    credentialFileExists: false,
  };
}

/** Pure. Assembles the connection-proof block from already-resolved
 * values -- no Firestore access happens inside this function itself.
 * Never includes a token, a private key, or any secret: only project
 * ids, the database id actually opened, which ADC mechanism was used
 * (by file path and non-secret identity fields), and whether the
 * requested and effective project ids actually match. */
function buildConnectionDiagnostic({
  requestedProjectId,
  effectiveProjectId,
  databaseId,
  appName,
  authSource,
  gamesCollectionCount,
  sampleGameIds,
  env = process.env,
}) {
  return {
    requestedProjectId,
    effectiveProjectId,
    projectIdMatches: requestedProjectId === effectiveProjectId,
    databaseId,
    appName,
    firestoreEmulatorHost: env.FIRESTORE_EMULATOR_HOST || null,
    authSource,
    env: {
      GOOGLE_CLOUD_PROJECT: env.GOOGLE_CLOUD_PROJECT || null,
      GCLOUD_PROJECT: env.GCLOUD_PROJECT || null,
      FIREBASE_CONFIG_present: Boolean(env.FIREBASE_CONFIG),
      GOOGLE_APPLICATION_CREDENTIALS: env.GOOGLE_APPLICATION_CREDENTIALS || null,
    },
    gamesCollectionCount,
    sampleGameIds,
  };
}

function writeIfRequested(filePath, content) {
  if (!filePath) return;
  const resolved = path.resolve(process.cwd(), filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, content);
}

function noopProgress() {}

// Writes to stderr, never stdout -- stdout must stay clean, parseable
// JSON (the final summary, optionally piped to --json-out). This is the
// single progress sink every mode funnels through below.
function logProgress(message) {
  process.stderr.write(`[audit_missed_main_prize_draws] ${new Date().toISOString()} ${message}\n`);
}

// The only Firestore-touching helpers below -- each is a plain read
// (.get()), nothing else. All decision logic they feed into is pure and
// lives above.
//
// loadParticipantsContext used to fetch each participant's user document
// ONE AT A TIME in a sequential for-loop. A game with hundreds or
// thousands of participants (Kids Troc alone has 1576) turned this into
// that many sequential network round-trips with zero progress output --
// easily tens of minutes of real work that looks exactly like a hang
// from the outside. Fetching them concurrently via Promise.all fixes the
// performance problem without changing the result: eligibility is still
// computed the same way, in the same order, over the same data.
async function loadParticipantsContext(db, gameRef, onProgress = noopProgress) {
  const ticketsSnap = await gameRef.collection("participants").get();
  onProgress(`participants: ${ticketsSnap.docs.length} ticket(s) a verifier`);
  const participants = await Promise.all(
    ticketsSnap.docs.map(async (doc) => {
      const ref = doc.data().user_id;
      const validRef = isValidUserRef(ref);
      if (!validRef) return { validRef, userExists: false, userData: null };
      const userSnap = await db.doc(ref.path).get();
      return { validRef, userExists: userSnap.exists, userData: userSnap.exists ? userSnap.data() : null };
    }),
  );
  onProgress(`participants: ${participants.length} lecture(s) terminee(s)`);
  return participants;
}

async function loadExistingPrincipalPrizeId(db, gameRef, onProgress = noopProgress) {
  onProgress("prizes: verification d'un prize 'principal' existant...");
  const snap = await db
    .collection("prizes")
    .where("game_id", "==", gameRef)
    .where("prize_type", "==", "principal")
    .limit(1)
    .get();
  onProgress(`prizes: ${snap.empty ? "aucun" : "un"} prize 'principal' existant`);
  return snap.empty ? null : snap.docs[0].id;
}

async function loadShopInfo(db, game, onProgress = noopProgress) {
  const enseigneRef = game.enseigne_id || game.enseigne_ref;
  const refPathValue = enseigneRef?.path || "";
  if (!/^enseignes\/[^/]+$/.test(refPathValue)) {
    onProgress("enseigne: reference absente ou mal formee");
    return { enseigneRefPath: refPathValue || null, exists: false, data: null };
  }
  onProgress(`enseigne: verification de ${refPathValue}...`);
  const snap = await db.doc(refPathValue).get();
  onProgress(`enseigne: ${snap.exists ? "trouvee" : "introuvable"}`);
  return { enseigneRefPath: refPathValue, exists: snap.exists, data: snap.exists ? snap.data() : null };
}

async function buildReportForGame(db, gameId, data, nowTimestamp, onProgress = noopProgress) {
  const gameRef = db.doc(`games/${gameId}`);
  const tagged = (message) => onProgress(`[${gameId}] ${message}`);
  const [participants, existingPrizeId, shopInfo] = await Promise.all([
    loadParticipantsContext(db, gameRef, tagged),
    loadExistingPrincipalPrizeId(db, gameRef, tagged),
    loadShopInfo(db, data, tagged),
  ]);
  return buildMissedDrawReport({
    gameId,
    data,
    now: nowTimestamp,
    participants,
    existingPrizeId,
    shopInfo,
  });
}

// Isolates one game's analysis from all the others: if anything above
// throws (a bad reference, a transient network error, a permission
// issue on one specific document...), this catches it, reports it as an
// ANALYSIS_ERROR row instead of a simulated category, and lets the
// caller move on to the next candidate instead of losing the entire
// audit run to a single bad document.
async function safelyBuildReport(db, gameId, data, nowTimestamp, onProgress = noopProgress) {
  try {
    return await buildReportForGame(db, gameId, data, nowTimestamp, onProgress);
  } catch (error) {
    onProgress(`[${gameId}] ERREUR pendant l'analyse : ${error.message} -- jeu ignore, poursuite de l'audit`);
    return {
      gameId,
      name: data.name || data.title || null,
      category: "ANALYSIS_ERROR",
      reason: "analysis_threw",
      error: error.message,
    };
  }
}

async function main() {
  assertReadOnlySource(fs.readFileSync(__filename, "utf8"));

  // Required only for a real run against Firestore -- never touched by
  // the unit tests, which exercise the pure functions above directly
  // with fixtures.
  const admin = require("firebase-admin");
  const args = parseArgs(process.argv.slice(2));
  const { app, db } = ensureFirestore(admin, args.project);
  const nowTimestamp = admin.firestore.Timestamp.now();
  const nowMs = nowTimestamp.toMillis();

  logProgress(`demarrage -- project=${args.project} app=${app.name} mode=${args.connectionDiagnostic ? "connection-diagnostic" : args.gameId ? "single-game" : "full-scan"}`);

  // Computed once, on every mode: this is the proof the user asked for
  // that the script opens exactly <requestedProjectId>/(default) and not
  // some other project/database -- a cheap aggregate count() plus a
  // 5-document sample, never the full collection.
  logProgress("verification de connexion : count() sur 'games'...");
  const countSnap = await db.collection("games").count().get();
  logProgress(`verification de connexion : ${countSnap.data().count} document(s) 'games' au total`);
  const sampleSnap = await db
    .collection("games")
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(5)
    .get();
  const connection = buildConnectionDiagnostic({
    requestedProjectId: args.project,
    effectiveProjectId: app.options.projectId || null,
    databaseId: db.databaseId || "(default)",
    appName: app.name,
    authSource: describeAuthSource(),
    gamesCollectionCount: countSnap.data().count,
    sampleGameIds: sampleSnap.docs.map((d) => d.id),
  });

  if (args.connectionDiagnostic) {
    const kidsTrocSnap = await db.doc(`games/${KIDS_TROC_GAME_ID}`).get();
    const summary = {
      generatedAt: new Date().toISOString(),
      readOnly: true,
      mode: "connection-diagnostic",
      connection,
      kidsTrocDirectLookup: {
        path: `games/${KIDS_TROC_GAME_ID}`,
        exists: kidsTrocSnap.exists,
      },
    };
    writeIfRequested(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  if (args.gameId) {
    // Single-document diagnostic mode: direct db.doc().get(), no
    // collection scan, no candidate filter applied before the raw dump.
    logProgress(`mode single-game-diagnostic : lecture directe de games/${args.gameId}`);
    const snap = await db.doc(`games/${args.gameId}`).get();
    const diagnostic = buildRawFieldDump({
      exists: snap.exists,
      id: args.gameId,
      data: snap.exists ? snap.data() : null,
    });
    const report = snap.exists
      ? await safelyBuildReport(db, args.gameId, snap.data() || {}, nowTimestamp, logProgress)
      : null;
    const summary = {
      generatedAt: new Date().toISOString(),
      readOnly: true,
      mode: "single-game-diagnostic",
      project: args.project,
      gameId: args.gameId,
      connection,
      diagnostic,
      wouldBeCandidate: snap.exists ? isMissedDrawCandidate(snap.data() || {}, nowMs) : false,
      report,
    };
    writeIfRequested(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const reports = [];
  let scanned = 0;
  let candidateIndex = 0;
  let lastDoc = null;
  const totalGames = connection.gamesCollectionCount;

  logProgress(
    `scan complet demarre -- ${totalGames} document(s) 'games' attendu(s) au total (count() live), page-size=${args.pageSize}`,
  );

  while (true) {
    let query = db.collection("games").orderBy(admin.firestore.FieldPath.documentId()).limit(args.pageSize);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    logProgress(`page recue : ${snapshot.docs.length} document(s)`);

    for (const doc of snapshot.docs) {
      scanned += 1;
      const data = doc.data() || {};
      if (!isMissedDrawCandidate(data, nowMs)) continue;
      candidateIndex += 1;
      logProgress(`[${scanned}/${totalGames}] candidat #${candidateIndex} : ${doc.id} - ${data.name || data.title || "(sans nom)"}`);
      // eslint-disable-next-line no-await-in-loop
      reports.push(await safelyBuildReport(db, doc.id, data, nowTimestamp, logProgress));
    }
  }

  logProgress(`scan complet termine : ${scanned} jeu(x) scanne(s), ${candidateIndex} candidat(s) detecte(s)`);

  // Kids Troc always gets a direct, unconditional lookup -- independent
  // of whether the generic candidate filter above matched it -- so
  // "kidsTroc" in the output is never silently null: it is either the
  // full simulated report, or an explicit NOT_FOUND row, and
  // kidsTrocDiagnostic always shows the raw values actually read.
  logProgress(`verification directe de games/${KIDS_TROC_GAME_ID} (Kids Troc)`);
  const kidsTrocSnap = await db.doc(`games/${KIDS_TROC_GAME_ID}`).get();
  const kidsTrocDiagnostic = buildRawFieldDump({
    exists: kidsTrocSnap.exists,
    id: KIDS_TROC_GAME_ID,
    data: kidsTrocSnap.exists ? kidsTrocSnap.data() : null,
  });
  let kidsTroc = reports.find((r) => r.gameId === KIDS_TROC_GAME_ID) || null;
  if (!kidsTroc) {
    kidsTroc = kidsTrocSnap.exists
      ? await safelyBuildReport(db, KIDS_TROC_GAME_ID, kidsTrocSnap.data() || {}, nowTimestamp, logProgress)
      : { gameId: KIDS_TROC_GAME_ID, category: "NOT_FOUND", reason: "document_not_found" };
  }

  reports.sort((a, b) => (a.gameId === KIDS_TROC_GAME_ID ? -1 : b.gameId === KIDS_TROC_GAME_ID ? 1 : 0));

  const byCategory = {};
  for (const r of reports) byCategory[r.category] = (byCategory[r.category] || 0) + 1;

  const summary = {
    generatedAt: new Date().toISOString(),
    readOnly: true,
    connection,
    scannedGames: scanned,
    candidateCount: reports.length,
    byCategory,
    kidsTroc,
    kidsTrocDiagnostic,
    candidates: reports,
  };

  writeIfRequested(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`[audit_missed_main_prize_draws] FATAL ${error.message || error}`);
    process.exitCode = 1;
  });
}

module.exports = {
  assertReadOnlySource,
  describeType,
  buildRawFieldDump,
  describeAuthSource,
  buildConnectionDiagnostic,
  deriveHasMainPrize,
  isMissedDrawCandidate,
  isValidUserRef,
  simulateMainPrizeDraw,
  buildMissedDrawReport,
  buildReportForGame,
  safelyBuildReport,
  logProgress,
  KIDS_TROC_GAME_ID,
  ADMIN_APP_NAME,
};

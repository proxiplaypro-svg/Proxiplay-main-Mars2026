#!/usr/bin/env node
"use strict";

// STRICTLY READ-ONLY. Simulates, without writing anything, the exact
// decision chain main_prize_draw.js's drawMainPrize() applies -- using
// the SAME pure helpers it imports (gameOwnership, prizeFulfillment,
// excluded) -- to classify every "games" document whose main prize draw
// should already have happened but never produced a finalization result.
//
// Context: games/poq44UWwkSvKa9N3lbUj ("jeu de Xbox one", Kids Troc) is
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
//     [--page-size 200] [--json-out report.json] [--game-id <id>]
const fs = require("node:fs");
const path = require("node:path");
const { gameOwnership } = require("../merchant_ownership");
const { prizeFulfillment } = require("../prize_fulfillment");
const { excluded } = require("../prize_integrity");

const KIDS_TROC_GAME_ID = "poq44UWwkSvKa9N3lbUj";

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
    }
  }
  return args;
}

function ensureFirestore(admin, projectId) {
  if (!projectId) {
    throw new Error("Project id manquant. Utilisez --project <firebase-project-id>.");
  }
  if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });
  }
  return admin.firestore();
}

function writeIfRequested(filePath, content) {
  if (!filePath) return;
  const resolved = path.resolve(process.cwd(), filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, content);
}

// The only Firestore-touching helpers below -- each is a plain read
// (.get()), nothing else. All decision logic they feed into is pure and
// lives above.
async function loadParticipantsContext(db, gameRef) {
  const ticketsSnap = await gameRef.collection("participants").get();
  const participants = [];
  for (const doc of ticketsSnap.docs) {
    const ref = doc.data().user_id;
    const validRef = isValidUserRef(ref);
    let userExists = false;
    let userData = null;
    if (validRef) {
      const userSnap = await db.doc(ref.path).get();
      userExists = userSnap.exists;
      userData = userSnap.exists ? userSnap.data() : null;
    }
    participants.push({ validRef, userExists, userData });
  }
  return participants;
}

async function loadExistingPrincipalPrizeId(db, gameRef) {
  const snap = await db
    .collection("prizes")
    .where("game_id", "==", gameRef)
    .where("prize_type", "==", "principal")
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0].id;
}

async function loadShopInfo(db, game) {
  const enseigneRef = game.enseigne_id || game.enseigne_ref;
  const refPathValue = enseigneRef?.path || "";
  if (!/^enseignes\/[^/]+$/.test(refPathValue)) {
    return { enseigneRefPath: refPathValue || null, exists: false, data: null };
  }
  const snap = await db.doc(refPathValue).get();
  return { enseigneRefPath: refPathValue, exists: snap.exists, data: snap.exists ? snap.data() : null };
}

async function buildReportForGame(db, gameId, data, nowTimestamp) {
  const gameRef = db.doc(`games/${gameId}`);
  const [participants, existingPrizeId, shopInfo] = await Promise.all([
    loadParticipantsContext(db, gameRef),
    loadExistingPrincipalPrizeId(db, gameRef),
    loadShopInfo(db, data),
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

async function main() {
  assertReadOnlySource(fs.readFileSync(__filename, "utf8"));

  // Required only for a real run against Firestore -- never touched by
  // the unit tests, which exercise the pure functions above directly
  // with fixtures.
  const admin = require("firebase-admin");
  const args = parseArgs(process.argv.slice(2));
  const db = ensureFirestore(admin, args.project);
  const nowTimestamp = admin.firestore.Timestamp.now();
  const nowMs = nowTimestamp.toMillis();

  const reports = [];
  let scanned = 0;
  let lastDoc = null;
  let kidsTrocHandledInScan = false;

  while (true) {
    let query = db.collection("games").orderBy(admin.firestore.FieldPath.documentId()).limit(args.pageSize);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    for (const doc of snapshot.docs) {
      scanned += 1;
      const data = doc.data() || {};
      if (args.gameId && doc.id !== args.gameId) continue;
      if (!args.gameId && !isMissedDrawCandidate(data, nowMs)) continue;

      if (doc.id === KIDS_TROC_GAME_ID) kidsTrocHandledInScan = true;
      // eslint-disable-next-line no-await-in-loop
      reports.push(await buildReportForGame(db, doc.id, data, nowTimestamp));
    }
  }

  // Kids Troc must get a definitive answer even if some unexpected field
  // shape kept it out of the generic candidate filter above.
  let kidsTroc = reports.find((r) => r.gameId === KIDS_TROC_GAME_ID) || null;
  if (!kidsTroc && !kidsTrocHandledInScan && !args.gameId) {
    const snap = await db.doc(`games/${KIDS_TROC_GAME_ID}`).get();
    kidsTroc = snap.exists
      ? await buildReportForGame(db, KIDS_TROC_GAME_ID, snap.data() || {}, nowTimestamp)
      : { gameId: KIDS_TROC_GAME_ID, category: "NOT_FOUND", reason: "document_not_found" };
  }

  reports.sort((a, b) => (a.gameId === KIDS_TROC_GAME_ID ? -1 : b.gameId === KIDS_TROC_GAME_ID ? 1 : 0));

  const byCategory = {};
  for (const r of reports) byCategory[r.category] = (byCategory[r.category] || 0) + 1;

  const summary = {
    generatedAt: new Date().toISOString(),
    readOnly: true,
    scannedGames: scanned,
    candidateCount: reports.length,
    byCategory,
    kidsTroc,
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
  deriveHasMainPrize,
  isMissedDrawCandidate,
  isValidUserRef,
  simulateMainPrizeDraw,
  buildMissedDrawReport,
  KIDS_TROC_GAME_ID,
};

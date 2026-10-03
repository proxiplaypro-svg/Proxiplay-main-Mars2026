#!/usr/bin/env node
"use strict";

// STRICTLY READ-ONLY. No .set()/.update()/.delete() call anywhere in this
// file. Detects games that carry a real finalization result (hasWinner,
// main_prize_winner, draw_status, drawn_at -- the 4 signals
// main_prize_draw.js writes together, once, as the irreversible outcome
// of a real draw -- see isGameFinalized() in firestore.rules) and show
// signs of having been pushed back into an active/visible state on the
// SAME document afterwards, instead of through Dupliquer (a new gameId).
//
// This is exactly the "Memphis" incident: created 24/04/2026, drawn
// 30/09/2026 (draw_status:no_main_prize), then end_date pushed to
// 03/11/2026 and republished, with its original instant_winners/
// participants from the first edition left untouched.
//
// Usage:
//   node scripts/audit_reactivated_games.js --project <firebase-project-id> \
//     [--page-size 200] [--json-out report.json] [--csv-out report.csv]
//
// Never purges or modifies instant_winners, participants, prizes, or any
// historical winner. Never resets any existing game. Read-only, always.
const fs = require("node:fs");
const path = require("node:path");

// Mirrors isGameFinalized() in firestore.rules exactly: the 4 signals
// main_prize_draw.js writes together as a real draw result. Any one of
// them present means this game has already been drawn/finalized once.
const kFinalizedDrawStatuses = new Set(["completed", "no_main_prize", "no_eligible_entries"]);

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

function isGameFinalized(data) {
  return (
    data.hasWinner === true ||
    data.main_prize_winner != null ||
    (typeof data.draw_status === "string" && kFinalizedDrawStatuses.has(data.draw_status)) ||
    data.drawn_at != null
  );
}

/** Suspicion signals, independent of each other -- a candidate can match
 * several at once. Named so the report explains itself without needing
 * this script open. Pure: takes the game's raw field values and "now" as
 * a plain number, no Firestore access. */
function computeSuspicionSignals(data, nowMs) {
  const endDateMs = toMillis(data.end_date);
  const drawnAtMs = toMillis(data.drawn_at);
  const signals = [];

  // The single strongest signal: the end date is later than the draw
  // that already happened. A draw only ever runs once end_date has
  // passed (main_prize_draw.js), so a later end_date than drawn_at can
  // only mean the document was edited post-finalization.
  if (endDateMs !== null && drawnAtMs !== null && endDateMs > drawnAtMs) {
    signals.push("end_date_after_drawn_at");
  }

  // A finalized game should never have a future end_date under normal
  // operation (it would have been excluded from the draw query, or the
  // draw itself would not have run yet).
  if (endDateMs !== null && endDateMs > nowMs) {
    signals.push("end_date_in_future");
  }

  if (data.visible_public === true) {
    signals.push("visible_public_true");
  }

  // Admin dashboard statuses that present the game as live/orderable
  // (see types/dashboard.ts GameStatus in proxiplay-admin).
  if (typeof data.status === "string" && ["actif", "active"].includes(data.status)) {
    signals.push("status_active");
  }

  return signals;
}

function classifySuspicion(signals) {
  if (
    signals.includes("end_date_after_drawn_at") &&
    (signals.includes("visible_public_true") || signals.includes("status_active"))
  ) {
    return "HIGH";
  }
  if (signals.includes("end_date_after_drawn_at") || signals.includes("end_date_in_future")) {
    return "MEDIUM";
  }
  if (signals.length > 0) {
    return "LOW";
  }
  return "NONE";
}

function readOwnerLabel(data) {
  const name = data.enseigne_name || data.merchantName || "";
  const ref = refPath(data.enseigne_id) || refPath(data.enseigne_ref) || refPath(data.owner_id);
  if (name && ref) return `${name} (${ref})`;
  return name || ref || null;
}

/** Pure: builds the full candidate report row from already-fetched raw
 * data (the game's fields, the raw instant_winners docs, and the
 * already-counted participants/prizes totals). No Firestore access
 * inside -- all fetching happens in main() below, which is the only
 * Firestore-touching part of this file. */
function buildCandidateReport({
  gameId,
  data,
  nowMs,
  participantsCount,
  instantWinnerDocs,
  prizesCount,
}) {
  let assignedInstantWinners = 0;
  let unassignedPastDueInstantWinners = 0;
  (instantWinnerDocs || []).forEach((instant) => {
    if (instant.hasWinner === true) {
      assignedInstantWinners += 1;
      return;
    }
    const dateMs = toMillis(instant.date);
    if (dateMs !== null && dateMs <= nowMs) {
      unassignedPastDueInstantWinners += 1;
    }
  });

  const signals = computeSuspicionSignals(data, nowMs);
  const suspicion = classifySuspicion(signals);

  return {
    gameId,
    name: data.name || data.title || null,
    owner: readOwnerLabel(data),
    created_time: toIso(data.created_time),
    start_date: toIso(data.start_date),
    end_date: toIso(data.end_date),
    status: data.status ?? null,
    visible_public: data.visible_public ?? null,
    draw_status: data.draw_status ?? null,
    drawn_at: toIso(data.drawn_at),
    hasWinner: data.hasWinner === true,
    main_prize_winner: refPath(data.main_prize_winner) || null,
    participantsCount,
    instantWinnersCount: (instantWinnerDocs || []).length,
    instantWinnersAssigned: assignedInstantWinners,
    instantWinnersUnassignedPastDue: unassignedPastDueInstantWinners,
    prizesCount,
    suspicion,
    signals,
  };
}

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    pageSize: 200,
    jsonOut: "",
    csvOut: "",
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
    } else if (arg === "--csv-out" && i + 1 < argv.length) {
      args.csvOut = String(argv[i + 1] || "").trim();
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
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
  }
  return admin.firestore();
}

function writeIfRequested(filePath, content) {
  if (!filePath) {
    return;
  }
  const resolved = path.resolve(process.cwd(), filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, content);
}

function toCsv(candidates) {
  const header = [
    "suspicion",
    "gameId",
    "name",
    "owner",
    "created_time",
    "start_date",
    "end_date",
    "status",
    "visible_public",
    "draw_status",
    "drawn_at",
    "hasWinner",
    "main_prize_winner",
    "participantsCount",
    "instantWinnersCount",
    "instantWinnersAssigned",
    "instantWinnersUnassignedPastDue",
    "prizesCount",
    "signals",
  ].join(",");
  const lines = candidates.map((c) =>
    [
      c.suspicion,
      c.gameId,
      JSON.stringify(c.name ?? ""),
      JSON.stringify(c.owner ?? ""),
      c.created_time ?? "",
      c.start_date ?? "",
      c.end_date ?? "",
      c.status ?? "",
      c.visible_public,
      c.draw_status ?? "",
      c.drawn_at ?? "",
      c.hasWinner,
      c.main_prize_winner ?? "",
      c.participantsCount,
      c.instantWinnersCount,
      c.instantWinnersAssigned,
      c.instantWinnersUnassignedPastDue,
      c.prizesCount,
      JSON.stringify(c.signals.join("|")),
    ].join(","),
  );
  return [header, ...lines].join("\n");
}

async function main() {
  // Required only for a real run against Firestore -- never touched by
  // the unit tests, which exercise the pure functions above directly.
  const admin = require("firebase-admin");
  const args = parseArgs(process.argv.slice(2));
  const db = ensureFirestore(admin, args.project);
  const nowMs = Date.now();

  const candidates = [];
  let scanned = 0;
  let finalizedCount = 0;
  let lastDoc = null;

  while (true) {
    let query = db
      .collection("games")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(args.pageSize);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }
    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    for (const gameDoc of snapshot.docs) {
      scanned += 1;
      const data = gameDoc.data() || {};
      if (!isGameFinalized(data)) {
        continue;
      }
      finalizedCount += 1;

      const signals = computeSuspicionSignals(data, nowMs);
      if (signals.length === 0) {
        // Normal, undisturbed finalized game: drawn once, never touched
        // again. Not a candidate -- excluded to keep the report to
        // actual suspects, not every game that ever ended.
        continue;
      }

      const gameRef = gameDoc.ref;
      const [participantsSnap, instantWinnersSnap, prizesSnap] = await Promise.all([
        gameRef.collection("participants").count().get(),
        gameRef.collection("instant_winners").get(),
        db.collection("prizes").where("game_id", "==", gameRef).count().get(),
      ]);

      candidates.push(
        buildCandidateReport({
          gameId: gameRef.id,
          data,
          nowMs,
          participantsCount: participantsSnap.data().count,
          instantWinnerDocs: instantWinnersSnap.docs.map((doc) => doc.data() || {}),
          prizesCount: prizesSnap.data().count,
        }),
      );
    }
  }

  candidates.sort((a, b) => {
    const order = { HIGH: 0, MEDIUM: 1, LOW: 2, NONE: 3 };
    return order[a.suspicion] - order[b.suspicion];
  });

  const summary = {
    generatedAt: new Date().toISOString(),
    readOnly: true,
    scannedGames: scanned,
    finalizedGames: finalizedCount,
    candidates,
    bySuspicion: {
      HIGH: candidates.filter((c) => c.suspicion === "HIGH").length,
      MEDIUM: candidates.filter((c) => c.suspicion === "MEDIUM").length,
      LOW: candidates.filter((c) => c.suspicion === "LOW").length,
    },
  };

  writeIfRequested(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`);
  writeIfRequested(args.csvOut, `${toCsv(candidates)}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`[audit_reactivated_games] FATAL ${error.message || error}`);
    process.exitCode = 1;
  });
}

module.exports = {
  isGameFinalized,
  computeSuspicionSignals,
  classifySuspicion,
  buildCandidateReport,
};

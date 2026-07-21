#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");
const {
  expandSecondaryPrizes,
  toMillis,
} = require("../lib/instant_winners_core");

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    pageSize: 100,
    gameId: "",
    jsonOut: "",
    csvOut: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project" && i + 1 < argv.length) {
      args.project = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--page-size" && i + 1 < argv.length) {
      args.pageSize = Math.max(1, Math.min(300, Number(argv[i + 1]) || 100));
      i += 1;
    } else if (arg === "--game-id" && i + 1 < argv.length) {
      args.gameId = String(argv[i + 1] || "").trim();
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

function ensureFirestore(projectId) {
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
  fs.mkdirSync(path.dirname(resolved), {recursive: true});
  fs.writeFileSync(resolved, content);
}

function auditGame({gameDoc, instantWinnersSnap, prizesSnap, userLotPresence}) {
  const gameData = gameDoc.data() || {};
  const desiredOccurrences = expandSecondaryPrizes(gameData.secondary_prizes);
  const desiredCount = desiredOccurrences.length;
  const startDateMs = toMillis(gameData.start_date);
  const endDateMs = toMillis(gameData.end_date);
  const instantDocs = instantWinnersSnap.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  const instantByLotKey = new Map();
  const instantByDateKey = new Map();
  const findings = [];

  instantDocs.forEach((doc) => {
    const lotKey = `${doc.secondary_prize_index}:${doc.secondary_prize_occurrence_index}`;
    const dateMs = toMillis(doc.date);
    const sameLot = instantByLotKey.get(lotKey) || [];
    sameLot.push(doc.id);
    instantByLotKey.set(lotKey, sameLot);

    const sameDate = instantByDateKey.get(String(dateMs)) || [];
    sameDate.push(doc.id);
    instantByDateKey.set(String(dateMs), sameDate);

    if (!Number.isFinite(dateMs)) {
      findings.push(`instant_without_valid_date:${doc.id}`);
    } else if (
      Number.isFinite(startDateMs) &&
      Number.isFinite(endDateMs) &&
      (dateMs < startDateMs || dateMs > endDateMs)
    ) {
      findings.push(`instant_out_of_window:${doc.id}`);
    }

    if ((doc.hasWinner === true) !== !!doc.player_id) {
      findings.push(`winner_state_mismatch:${doc.id}`);
    }
  });

  if (desiredCount > 1 && instantDocs.length === 1) {
    findings.push("multiple_secondary_prizes_but_single_instant");
  }
  if (instantDocs.length < desiredCount) {
    findings.push(`missing_instants:${desiredCount - instantDocs.length}`);
  }

  desiredOccurrences.forEach((_, index) => {
    const sourceIndex = desiredOccurrences[index].sourceIndex;
    const occurrenceIndex = desiredOccurrences[index].occurrenceIndex;
    const lotKey = `${sourceIndex}:${occurrenceIndex}`;
    const matching = instantByLotKey.get(lotKey) || [];
    if (matching.length === 0) {
      findings.push(`missing_lot_occurrence:${lotKey}`);
    }
    if (matching.length > 1) {
      findings.push(`duplicate_lot_occurrence:${lotKey}`);
    }
  });

  const identicalInstantGroups = [];
  instantByDateKey.forEach((docIds, dateKey) => {
    if (docIds.length > 1) {
      identicalInstantGroups.push({dateMs: Number(dateKey), docIds});
      findings.push(`identical_instants:${dateKey}:${docIds.length}`);
    }
  });

  const wonButStillOpen = instantDocs
    .filter((doc) => doc.hasWinner === false && !!doc.player_id)
    .map((doc) => doc.id);
  if (wonButStillOpen.length > 0) {
    findings.push(`won_but_still_open:${wonButStillOpen.length}`);
  }

  const prizes = prizesSnap.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    ...doc.data(),
  }));
  const secondaryPrizes = prizes.filter(
    (prize) => String(prize.prize_type || "").toLowerCase() === "secondaire",
  );

  secondaryPrizes.forEach((prize) => {
    const winnerPath = prize.winner_id && prize.winner_id.path;
    if (!winnerPath) {
      findings.push(`secondary_prize_without_winner:${prize.id}`);
      return;
    }
    const lotKey = `${winnerPath}/${prize.id}`;
    if (!userLotPresence.has(lotKey)) {
      findings.push(`missing_user_lot_link:${prize.id}`);
    }
  });

  return {
    gameId: gameDoc.id,
    desiredSecondaryPrizeOccurrences: desiredCount,
    instantWinnerCount: instantDocs.length,
    secondaryPrizeCount: secondaryPrizes.length,
    identicalInstantGroups,
    findings,
  };
}

async function loadUserLotPresence(prizes) {
  const presence = new Set();
  for (const prize of prizes) {
    if (!prize.winner_id || typeof prize.winner_id.collection !== "function") {
      continue;
    }
    const userLotSnap = await prize.winner_id.collection("my_lots").doc(prize.id).get();
    if (userLotSnap.exists) {
      presence.add(`${prize.winner_id.path}/${prize.id}`);
    }
  }
  return presence;
}

async function processGame(db, gameDoc) {
  const [instantWinnersSnap, prizesSnap] = await Promise.all([
    gameDoc.ref.collection("instant_winners").get(),
    db.collection("prizes").where("game_id", "==", gameDoc.ref).get(),
  ]);
  const prizes = prizesSnap.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
  const presence = await loadUserLotPresence(prizes);
  return auditGame({
    gameDoc,
    instantWinnersSnap,
    prizesSnap,
    userLotPresence: presence,
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const db = ensureFirestore(args.project);
  const results = [];
  let scanned = 0;

  if (args.gameId) {
    const gameDoc = await db.collection("games").doc(args.gameId).get();
    if (!gameDoc.exists) {
      throw new Error(`Jeu introuvable: ${args.gameId}`);
    }
    results.push(await processGame(db, gameDoc));
    scanned = 1;
  } else {
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
        results.push(await processGame(db, gameDoc));
        scanned += 1;
      }
    }
  }

  const summary = {
    generatedAt: new Date().toISOString(),
    scanned,
    flaggedGames: results.filter((result) => result.findings.length > 0).length,
    results,
  };

  const csvLines = [
    "gameId,desiredSecondaryPrizeOccurrences,instantWinnerCount,secondaryPrizeCount,findings",
    ...results.map((result) =>
      [
        result.gameId,
        result.desiredSecondaryPrizeOccurrences,
        result.instantWinnerCount,
        result.secondaryPrizeCount,
        `"${result.findings.join(" | ")}"`,
      ].join(","),
    ),
  ];

  writeIfRequested(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`);
  writeIfRequested(args.csvOut, `${csvLines.join("\n")}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(`[audit_instant_winners] FATAL ${error.message || error}`);
  process.exit(1);
});

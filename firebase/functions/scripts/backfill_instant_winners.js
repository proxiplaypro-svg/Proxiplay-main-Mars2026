#!/usr/bin/env node

const admin = require("firebase-admin");
const {
  expandSecondaryPrizes,
  planInstantWinnerReconciliation,
  toMillis,
} = require("../lib/instant_winners_core");

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    pageSize: 100,
    dryRun: true,
    confirm: false,
    gameId: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project" && i + 1 < argv.length) {
      args.project = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--page-size" && i + 1 < argv.length) {
      const parsed = Number(argv[i + 1]);
      if (Number.isFinite(parsed)) {
        args.pageSize = Math.max(1, Math.min(300, Math.trunc(parsed)));
      }
      i += 1;
    } else if (arg === "--game-id" && i + 1 < argv.length) {
      args.gameId = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--apply") {
      args.dryRun = false;
    } else if (arg === "--dry-run") {
      args.dryRun = true;
    } else if (arg === "--confirm") {
      args.confirm = true;
    } else if (arg === "--help" || arg === "-h") {
      args.help = true;
    }
  }

  return args;
}

function showHelp() {
  console.log(`
Backfill des instant_winners manquants

Usage:
  node scripts/backfill_instant_winners.js --project <firebase-project-id> --dry-run
  node scripts/backfill_instant_winners.js --project <firebase-project-id> --game-id <gameId> --apply --confirm

Options:
  --project <id>     Firebase project id
  --game-id <id>     Cible un jeu precis
  --page-size <n>    Taille de page Firestore (defaut: 100)
  --dry-run          Simulation sans ecriture
  --apply            Applique les creations
  --confirm          Requis avec --apply pour autoriser les ecritures
  --help             Affiche cette aide
`);
}

function ensureFirebase(projectId) {
  if (!projectId) {
    throw new Error(
      "Project id manquant. Utilisez --project <firebase-project-id>."
    );
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
  }

  return admin.firestore();
}

async function createInstantWinnersIfMissing(gameDoc, dryRun) {
  const gameData = gameDoc.data() || {};
  const expandedSecondaryPrizes = expandSecondaryPrizes(gameData.secondary_prizes);
  const desiredCount = expandedSecondaryPrizes.length;
  if (desiredCount === 0) {
    return { status: "skip_no_secondary_prizes", desiredCount, existingCount: 0 };
  }

  const startDateMs = toMillis(gameData.start_date);
  const endDateMs = toMillis(gameData.end_date);
  if (!Number.isFinite(startDateMs) || !Number.isFinite(endDateMs)) {
    return { status: "skip_missing_dates", desiredCount, existingCount: 0 };
  }
  if (startDateMs > endDateMs) {
    return { status: "skip_invalid_dates", desiredCount, existingCount: 0 };
  }

  const instantWinnersRef = gameDoc.ref.collection("instant_winners");
  const instantWinnersSnap = await instantWinnersRef.get();
  const plan = planInstantWinnerReconciliation({
    gameId: gameDoc.id,
    startDateMs,
    endDateMs,
    secondaryPrizes: gameData.secondary_prizes,
    existingEntries: instantWinnersSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    })),
  });

  if (plan.missingPayloads.length === 0 && plan.staleTextEntries.length === 0) {
    return {
      status: "skip_already_complete",
      desiredCount,
      existingCount: instantWinnersSnap.size,
      duplicateExistingKeys: plan.duplicateExistingKeys,
      unexpectedExistingCount: plan.unexpectedExistingEntries.length,
    };
  }

  if (dryRun) {
    return {
      status:
        plan.missingPayloads.length > 0
          ? instantWinnersSnap.size > 0
            ? "would_complete_missing_occurrences"
            : "would_create"
          : "would_refresh_stale_text",
      desiredCount,
      existingCount: instantWinnersSnap.size,
      missingCount: plan.missingPayloads.length,
      staleTextCount: plan.staleTextEntries.length,
      duplicateExistingKeys: plan.duplicateExistingKeys,
      unexpectedExistingCount: plan.unexpectedExistingEntries.length,
    };
  }

  const batch = gameDoc.ref.firestore.batch();
  plan.missingPayloads.forEach(({docId, payload}) => {
    console.log("[HAS_WINNER WRITE]", {
      gameId: gameDoc.id,
      previousValue: null,
      newValue: false,
      sourceFunction: "backfill_instant_winners",
      winnerType: "gain-instantane",
      hasMainPrize:
        Object.prototype.hasOwnProperty.call(gameData || {}, "hasMainPrize")
          ? gameData.hasMainPrize === true
          : null,
      endDate:
        gameData.end_date?.toDate?.()?.toISOString?.() ||
        gameData.end_date ||
        null,
      now: new Date().toISOString(),
    });
    batch.set(instantWinnersRef.doc(docId), {
      date: admin.firestore.Timestamp.fromMillis(payload.dateMs),
      hasWinner: false,
      claimed: false,
      secondary_prize_index: payload.secondary_prize_index,
      secondary_prize_occurrence_index:
        payload.secondary_prize_occurrence_index,
      secondary_prize_name: payload.secondary_prize_name,
      ...(payload.secondary_prize_presentation
        ? {
            secondary_prize_presentation:
              payload.secondary_prize_presentation,
          }
        : {}),
    });
  });

  plan.staleTextEntries.forEach(({docId, patch}) => {
    batch.update(instantWinnersRef.doc(docId), patch);
  });

  await batch.commit();
  return {
    status:
      plan.missingPayloads.length > 0
        ? instantWinnersSnap.size > 0
          ? "completed_missing_occurrences"
          : "created"
        : "refreshed_stale_text",
    desiredCount,
    existingCount: instantWinnersSnap.size,
    missingCount: plan.missingPayloads.length,
    staleTextCount: plan.staleTextEntries.length,
    duplicateExistingKeys: plan.duplicateExistingKeys,
    unexpectedExistingCount: plan.unexpectedExistingEntries.length,
  };
}

async function processGameDoc(gameDoc, args, stats) {
  const result = await createInstantWinnersIfMissing(gameDoc, args.dryRun);
  stats.scanned += 1;

  if (
    result.status === "would_create" ||
    result.status === "would_complete_missing_occurrences"
  ) {
    stats.wouldCreate += 1;
  } else if (
    result.status === "created" ||
    result.status === "completed_missing_occurrences"
  ) {
    stats.created += 1;
  } else if (result.status.startsWith("skip_")) {
    stats.skipped += 1;
  }

  console.log(
    `[backfill_instant_winners] game=${gameDoc.id} status=${result.status} desired=${result.desiredCount} existing=${result.existingCount} missing=${result.missingCount || 0} duplicates=${(result.duplicateExistingKeys || []).length} unexpected=${result.unexpectedExistingCount || 0}`,
  );
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    showHelp();
    return;
  }

  if (!args.dryRun && !args.confirm) {
    throw new Error(
      "Refus d'executer en mode ecriture sans --confirm. Relancez avec --apply --confirm."
    );
  }

  const db = ensureFirebase(args.project);
  const stats = {
    scanned: 0,
    created: 0,
    wouldCreate: 0,
    skipped: 0,
  };

  console.log(
    `[backfill_instant_winners] START project=${args.project} dryRun=${args.dryRun} pageSize=${args.pageSize} gameId=${args.gameId || "-"}`,
  );

  if (args.gameId) {
    const gameDoc = await db.collection("games").doc(args.gameId).get();
    if (!gameDoc.exists) {
      throw new Error(`Jeu introuvable: ${args.gameId}`);
    }
    await processGameDoc(gameDoc, args, stats);
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
        await processGameDoc(gameDoc, args, stats);
      }
    }
  }

  console.log(
    `[backfill_instant_winners] DONE scanned=${stats.scanned} created=${stats.created} wouldCreate=${stats.wouldCreate} skipped=${stats.skipped}`,
  );
}

main().catch((error) => {
  console.error(
    `[backfill_instant_winners] FATAL message=${error.message || error}`,
  );
  process.exit(1);
});

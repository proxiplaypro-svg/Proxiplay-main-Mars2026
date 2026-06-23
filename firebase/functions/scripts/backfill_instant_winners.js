#!/usr/bin/env node

const admin = require("firebase-admin");

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

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeInteger(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(getTrimmedString(value), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function toMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function expandSecondaryPrizes(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  const expanded = [];
  value.forEach((entry, index) => {
    if (!entry || typeof entry !== "object") {
      return;
    }

    const name = getTrimmedString(entry.name);
    const presentation = getTrimmedString(entry.presentation);
    const count = normalizeInteger(entry.count) || 0;
    if (count <= 0) {
      return;
    }

    for (let occurrence = 0; occurrence < count; occurrence += 1) {
      expanded.push({
        sourceIndex: index,
        occurrenceIndex: occurrence,
        name,
        presentation,
      });
    }
  });

  return expanded;
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
  if (instantWinnersSnap.size > 0) {
    return {
      status:
        instantWinnersSnap.size === desiredCount
          ? "skip_already_present"
          : "skip_existing_non_empty",
      desiredCount,
      existingCount: instantWinnersSnap.size,
    };
  }

  if (dryRun) {
    return {
      status: "would_create",
      desiredCount,
      existingCount: 0,
    };
  }

  const batch = gameDoc.ref.firestore.batch();
  const totalRangeMs = endDateMs - startDateMs;
  expandedSecondaryPrizes.forEach((prizePayload, index) => {
    const ratio = (index + 0.5) / desiredCount;
    const candidateMs = startDateMs + Math.round(totalRangeMs * ratio);
    const boundedMs = Math.min(endDateMs, Math.max(startDateMs, candidateMs));
    const winnerRef = instantWinnersRef.doc();

    batch.set(winnerRef, {
      date: admin.firestore.Timestamp.fromMillis(boundedMs),
      hasWinner: false,
      claimed: false,
      secondary_prize_index: prizePayload.sourceIndex,
      secondary_prize_occurrence_index: prizePayload.occurrenceIndex,
      secondary_prize_name: prizePayload.name,
      ...(prizePayload.presentation
        ? {
            secondary_prize_presentation: prizePayload.presentation,
          }
        : {}),
    });
  });

  await batch.commit();
  return {
    status: "created",
    desiredCount,
    existingCount: 0,
  };
}

async function processGameDoc(gameDoc, args, stats) {
  const result = await createInstantWinnersIfMissing(gameDoc, args.dryRun);
  stats.scanned += 1;

  if (result.status === "would_create") {
    stats.wouldCreate += 1;
  } else if (result.status === "created") {
    stats.created += 1;
  } else if (result.status.startsWith("skip_")) {
    stats.skipped += 1;
  }

  console.log(
    `[backfill_instant_winners] game=${gameDoc.id} status=${result.status} desired=${result.desiredCount} existing=${result.existingCount}`,
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

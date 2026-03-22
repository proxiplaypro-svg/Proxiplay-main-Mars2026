#!/usr/bin/env node

const admin = require("firebase-admin");

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    pageSize: 300,
    dryRun: true,
    confirm: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project" && i + 1 < argv.length) {
      args.project = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--page-size" && i + 1 < argv.length) {
      const parsed = Number(argv[i + 1]);
      if (Number.isFinite(parsed)) {
        args.pageSize = Math.max(1, Math.min(500, Math.trunc(parsed)));
      }
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
Backfill one-shot de player_status_cached

Usage:
  node scripts/backfill_player_status_cached.js --project <firebase-project-id> --dry-run
  node scripts/backfill_player_status_cached.js --project <firebase-project-id> --apply

Options:
  --project <id>     Firebase project id
  --page-size <n>    Taille de page Firestore (defaut: 300)
  --dry-run          Simulation sans ecriture
  --apply            Applique les mises a jour
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

function toMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return null;
}

function calculatePlayerStatusForBackfill(userData, nowMs) {
  if (!userData) {
    return "statut_inconnu";
  }

  const createdMs = toMillis(userData.created_time);
  if (createdMs === null) {
    return "statut_inconnu";
  }

  const referenceMs = toMillis(userData.last_real_activity_at) ?? createdMs;
  const gamesPlayed =
    typeof userData.games_played_count === "number" &&
    Number.isFinite(userData.games_played_count)
      ? Math.max(0, Math.trunc(userData.games_played_count))
      : 0;

  const accountAgeDays = Math.floor((nowMs - createdMs) / 86400000);
  const daysSinceReference = Math.floor((nowMs - referenceMs) / 86400000);

  if (daysSinceReference < 0 || accountAgeDays < 0) {
    return "statut_inconnu";
  }

  if (accountAgeDays > 60 && gamesPlayed === 0) {
    return "mort_probable";
  }
  if (daysSinceReference > 90) {
    return "mort_probable";
  }
  if (accountAgeDays > 30 && gamesPlayed <= 1) {
    return "dormant";
  }
  if (daysSinceReference >= 31 && daysSinceReference <= 90) {
    return "dormant";
  }
  if (daysSinceReference >= 8 && daysSinceReference <= 30) {
    return "a_relancer";
  }
  if (accountAgeDays > 7 && gamesPlayed <= 2) {
    return "a_relancer";
  }
  if (daysSinceReference <= 7) {
    return "actif";
  }
  if (daysSinceReference <= 14 && gamesPlayed >= 3) {
    return "actif";
  }

  return "statut_inconnu";
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
  const nowMs = Date.now();

  console.log(
    `[backfill_player_status_cached] START project=${args.project} dryRun=${args.dryRun} pageSize=${args.pageSize}`
  );

  let totalScanned = 0;
  let totalUpdated = 0;
  let totalWouldUpdate = 0;
  let totalIgnored = 0;
  let totalErrors = 0;
  let lastDoc = null;

  while (true) {
    let query = db
      .collection("users")
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

    for (const doc of snapshot.docs) {
      totalScanned += 1;
      const data = doc.data() || {};

      if (data.player_status_cached !== undefined && data.player_status_cached !== null) {
        totalIgnored += 1;
        continue;
      }

      try {
        const nextStatus = calculatePlayerStatusForBackfill(data, nowMs);

        if (args.dryRun) {
          totalWouldUpdate += 1;
          console.log(
            `[backfill_player_status_cached] DRY-RUN uid=${doc.id} player_status_cached=${nextStatus}`
          );
          continue;
        }

        await doc.ref.update({
          player_status_cached: nextStatus,
        });

        totalUpdated += 1;
        console.log(
          `[backfill_player_status_cached] UPDATE uid=${doc.id} player_status_cached=${nextStatus}`
        );
      } catch (error) {
        totalErrors += 1;
        console.error(
          `[backfill_player_status_cached] ERROR uid=${doc.id} message=${error.message || error}`
        );
      }
    }
  }

  console.log(
    `[backfill_player_status_cached] DONE scanned=${totalScanned} updated=${totalUpdated} wouldUpdate=${totalWouldUpdate} ignored=${totalIgnored} errors=${totalErrors}`
  );

  if (totalErrors > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(
    `[backfill_player_status_cached] FATAL message=${error.message || error}`
  );
  process.exit(1);
});

#!/usr/bin/env node

const admin = require("firebase-admin");

const kAutomationSeeds = [
  {
    id: "inactive_players_7d",
    data: {
      type: "inactive_player",
      name: "Inactive players 7d",
      channel: "push",
      isActive: true,
      cooldownDays: 7,
      frequency: "once",
      sendHour: 18,
      filters: {
        remainingPartsOnly: false,
      },
      targetStatuses: ["a_relancer", "dormant", "mort_probable"],
      messagesByStatus: {
        a_relancer: {
          title: "Revenez jouer !",
          body: "Continuez à jouer pour accumuler vos prochaines victoires !",
        },
        dormant: {
          title: "Ça fait longtemps !",
          body: "Retrouvez les jeux ProxiPlay et vos lots récompenses.",
        },
        mort_probable: {
          title: "Nous vous manquons ?",
          body: "Revenez tenter votre chance et gagner des lots !",
        },
        default: {
          title: "Revenez jouer !",
          body: "Nous vous avons beaucoup manqué !",
        },
      },
    },
  },
  {
    id: "birthday",
    data: {
      type: "birthday",
      name: "Anniversaire",
      channel: "push",
      isActive: true,
      frequency: "once",
      sendHour: 9,
      filters: {
        remainingPartsOnly: false,
      },
      messagesByStatus: {
        default: {
          title: "Joyeux anniversaire {firstName} 🎉",
          body: "Profitez de vos avantages du jour et tentez votre chance !",
        },
      },
      reward: {
        type: "all_games_until_midnight",
        value: 1,
        grantedBy: "birthday",
      },
    },
  },
  {
    id: "remaining_parts",
    data: {
      type: "remaining_parts",
      name: "Parties restantes",
      channel: "push",
      isActive: true,
      frequency: "repeat",
      cooldownHours: 6,
      sendHour: 18,
      filters: {
        remainingPartsOnly: true,
      },
      messagesByStatus: {
        default: {
          title: "Il vous reste des parties 🎯",
          body: "Ne laissez pas vos chances expirer, venez jouer maintenant !",
        },
      },
    },
  },
  {
    id: "favorite_merchant_new_game",
    data: {
      type: "favorite_merchant_new_game",
      name: "Nouveau jeu favori",
      channel: "push",
      isActive: true,
      frequency: "instant",
      filters: {},
      messagesByStatus: {
        default: {
          title: "Nouveau jeu disponible 🎉",
          body: "{merchantName} vient d’ajouter un nouveau jeu !",
        },
      },
    },
  },
  {
    id: "game_end_reminder",
    data: {
      type: "game_end_reminder",
      name: "Fin de jeu imminente",
      channel: "push",
      isActive: true,
      frequency: "once",
      triggerBeforeHours: 72,
      filters: {
        remainingPartsOnly: true,
      },
      messagesByStatus: {
        default: {
          title: "Plus que quelques jours ⏳",
          body:
            "Un jeu se termine bientôt, tentez votre chance avant qu’il ne soit trop tard !",
        },
      },
    },
  },
];

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    dryRun: true,
    confirm: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project" && i + 1 < argv.length) {
      args.project = String(argv[i + 1] || "").trim();
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
Seed Firestore pour notification_automations

Usage:
  node scripts/seed_notification_automations.js --project <firebase-project-id> --dry-run
  node scripts/seed_notification_automations.js --project <firebase-project-id> --apply --confirm

Options:
  --project <id>     Firebase project id
  --dry-run          Simulation sans écriture
  --apply            Applique les écritures
  --confirm          Requis avec --apply
  --help             Affiche cette aide

Auth:
  - Si GOOGLE_APPLICATION_CREDENTIALS est défini, le script l'utilise via ADC.
  - Sinon, il tente d'utiliser les credentials ADC locaux
    (ex: gcloud auth application-default login).
`);
}

function ensureFirebase(projectId) {
  if (!projectId) {
    throw new Error("Project id manquant. Utilisez --project <firebase-project-id>.");
  }

  const credentialsPath = String(process.env.GOOGLE_APPLICATION_CREDENTIALS || "").trim();
  if (credentialsPath) {
    console.log(
      `[seed_notification_automations] auth=GOOGLE_APPLICATION_CREDENTIALS path=${credentialsPath}`,
    );
  } else {
    console.log(
      "[seed_notification_automations] auth=applicationDefault (gcloud ADC ou environnement local)",
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

function buildWriteData(seedData, docExists) {
  const writeData = {
    ...seedData,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!docExists) {
    writeData.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  if (
    docExists &&
    seedData.filters &&
    typeof seedData.filters === "object" &&
    Object.keys(seedData.filters).length === 0
  ) {
    delete writeData.filters;
  }

  return writeData;
}

async function upsertAutomation(firestore, seed, dryRun) {
  const ref = firestore.collection("notification_automations").doc(seed.id);
  const snapshot = await ref.get();
  const action = snapshot.exists ? "update" : "create";
  const writeData = buildWriteData(seed.data, snapshot.exists);

  if (dryRun) {
    console.log(
      `[seed_notification_automations] DRY-RUN action=would-${action} docId=${seed.id} payload=${JSON.stringify(seed.data)}`,
    );
    return;
  }

  await ref.set(writeData, {merge: true});
  console.log(
    `[seed_notification_automations] OK action=${action} docId=${seed.id} merge=true`,
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
      "Refus d'exécuter en mode écriture sans --confirm. Relancez avec --apply --confirm.",
    );
  }

  const firestore = ensureFirebase(args.project);
  console.log(
    `[seed_notification_automations] START project=${args.project} dryRun=${args.dryRun} count=${kAutomationSeeds.length}`,
  );

  for (const seed of kAutomationSeeds) {
    await upsertAutomation(firestore, seed, args.dryRun);
  }

  console.log("[seed_notification_automations] DONE");
}

main().catch((error) => {
  console.error(
    `[seed_notification_automations] FATAL message=${error.message || error}`,
  );
  process.exit(1);
});

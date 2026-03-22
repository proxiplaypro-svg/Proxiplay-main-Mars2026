#!/usr/bin/env node

const admin = require("firebase-admin");
const {kDefaultAutomations} = require("./default_automations");

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
Seed notification_automations

Usage:
  node lib/notifications/seed/seed_notification_automations.js --project <firebase-project-id> --dry-run
  node lib/notifications/seed/seed_notification_automations.js --project <firebase-project-id> --apply --confirm

Options:
  --project <id>     Firebase project id
  --dry-run          Simulation sans ecriture
  --apply            Applique les ecritures
  --confirm          Requis avec --apply
  --help             Affiche cette aide
`);
}

function ensureFirebase(projectId) {
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

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    showHelp();
    return;
  }

  if (!args.dryRun && !args.confirm) {
    throw new Error(
      "Refus d'executer en mode ecriture sans --confirm. Relancez avec --apply --confirm.",
    );
  }

  const firestore = ensureFirebase(args.project);
  console.log(
    `[seed_notification_automations] START project=${args.project} dryRun=${args.dryRun} automations=${kDefaultAutomations.length}`,
  );

  for (const automation of kDefaultAutomations) {
    const ref = firestore.collection("notification_automations").doc(automation.id);
    if (args.dryRun) {
      console.log(
        `[seed_notification_automations] DRY-RUN id=${automation.id} payload=${JSON.stringify(automation.data)}`,
      );
      continue;
    }

    const existing = await ref.get();
    await ref.set(
      {
        ...automation.data,
        ...(existing.exists
          ? {}
          : {createdAt: admin.firestore.FieldValue.serverTimestamp()}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    console.log(`[seed_notification_automations] UPSERT id=${automation.id}`);
  }

  console.log("[seed_notification_automations] DONE");
}

main().catch((error) => {
  console.error(
    `[seed_notification_automations] FATAL message=${error.message || error}`,
  );
  process.exit(1);
});

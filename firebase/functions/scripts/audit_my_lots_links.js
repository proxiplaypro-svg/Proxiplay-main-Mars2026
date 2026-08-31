#!/usr/bin/env node

// Audit (et, sur demande explicite, reparation) des liens
// users/{uid}/my_lots/{prizeId} manquants -- voir prize_my_lots_repair.js
// pour la logique et firebase/functions/test/prize_my_lots_repair.test.js
// pour les tests. Parcourt TOUTE la collection "prizes" (tous moteurs :
// gain instantane, grand tirage, parrainage, defi/animation), pas seulement
// les jeux avec instant_winners (contrairement a audit_instant_winners.js).
//
// Par defaut : lecture seule, aucune ecriture. Necessite --apply --confirm
// pour creer reellement les liens my_lots manquants (creation uniquement,
// jamais d'ecrasement ni de suppression -- voir prize_my_lots_repair.js).
//
// Usage:
//   node scripts/audit_my_lots_links.js --project <firebase-project-id>
//   node scripts/audit_my_lots_links.js --project <firebase-project-id> --apply --confirm

const admin = require("firebase-admin");

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    pageSize: 200,
    apply: false,
    confirm: false,
    jsonOut: "",
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
      args.apply = true;
    } else if (arg === "--confirm") {
      args.confirm = true;
    } else if (arg === "--json-out" && i + 1 < argv.length) {
      args.jsonOut = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--help" || arg === "-h") {
      args.help = true;
    }
  }

  return args;
}

function showHelp() {
  console.log(`
Audit et reparation des liens users/{uid}/my_lots/{prizeId} manquants

Usage:
  node scripts/audit_my_lots_links.js --project <firebase-project-id>
  node scripts/audit_my_lots_links.js --project <firebase-project-id> --apply --confirm

Options:
  --project <id>     Firebase project id
  --page-size <n>    Taille de page Firestore (defaut: 200)
  --apply            Cree reellement les liens manquants (creation uniquement)
  --confirm          Requis avec --apply pour autoriser les ecritures
  --json-out <path>  Ecrit le rapport complet en JSON dans ce fichier
  --help             Affiche cette aide
`);
}

function ensureFirebase(projectId) {
  if (!projectId) {
    throw new Error(
      "Project id manquant. Utilisez --project <firebase-project-id>.",
    );
  }
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    showHelp();
    return;
  }
  if (args.apply && !args.confirm) {
    throw new Error("--apply necessite aussi --confirm (garde-fou volontaire).");
  }

  ensureFirebase(args.project);
  // Require APRES admin.initializeApp() : prize_my_lots_repair.js appelle
  // admin.firestore() a l'import.
  const {findMissingMyLotsLinks, repairMissingMyLotsLink} = require("../prize_my_lots_repair");

  const allMissing = [];
  const allSkipped = [];
  let scanned = 0;
  let startAfterId = "";

  for (;;) {
    // eslint-disable-next-line no-await-in-loop
    const page = await findMissingMyLotsLinks({pageSize: args.pageSize, startAfterId});
    allMissing.push(...page.missing);
    allSkipped.push(...page.skippedNoWinner);
    scanned += page.scanned;
    console.log(
      `[audit_my_lots_links] page scannee (jusqu'a prizeId=${page.lastId || "?"}) : `
      + `${page.scanned} lots, ${page.missing.length} lien(s) manquant(s) sur cette page`,
    );
    if (!page.hasMore) break;
    startAfterId = page.lastId;
  }

  console.log(
    `\n[audit_my_lots_links] TOTAL : ${scanned} lots scannes, `
    + `${allMissing.length} lien(s) my_lots manquant(s), `
    + `${allSkipped.length} winner_id non exploitable(s) (format incompatible, journalise separement).`,
  );

  const repaired = [];
  if (args.apply) {
    console.log(`\n[audit_my_lots_links] --apply --confirm : reparation de ${allMissing.length} lot(s)...`);
    for (const entry of allMissing) {
      // eslint-disable-next-line no-await-in-loop
      const outcome = await repairMissingMyLotsLink(entry.prizeId);
      repaired.push(outcome);
      console.log(`  - ${entry.prizeId} -> ${outcome.status}`);
    }
  } else if (allMissing.length > 0) {
    console.log(
      "\n[audit_my_lots_links] Mode lecture seule (par defaut). "
      + "Relancer avec --apply --confirm pour creer les liens manquants ci-dessus.",
    );
  }

  const report = {
    generatedAt: new Date().toISOString(),
    project: args.project,
    scanned,
    missingCount: allMissing.length,
    missing: allMissing,
    skippedNoWinner: allSkipped,
    applied: args.apply,
    repaired,
  };

  if (args.jsonOut) {
    const fs = require("node:fs");
    const path = require("node:path");
    const resolved = path.resolve(process.cwd(), args.jsonOut);
    fs.mkdirSync(path.dirname(resolved), {recursive: true});
    fs.writeFileSync(resolved, `${JSON.stringify(report, null, 2)}\n`);
    console.log(`\n[audit_my_lots_links] Rapport ecrit dans ${resolved}`);
  }
}

main().catch((error) => {
  console.error(`[audit_my_lots_links] FATAL ${error.message || error}`);
  process.exit(1);
});

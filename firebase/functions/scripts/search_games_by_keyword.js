#!/usr/bin/env node
"use strict";

// ONE-OFF, STRICTLY READ-ONLY. Not part of the audit tooling, not meant
// to be committed -- ad hoc search requested to find every "games"
// document whose name, enseigne_name or description mentions "kids
// troc", "xbox" or "jagged alliance" (case-insensitive substring match),
// so they can be cross-checked against the Kids Troc / "jeu de Xbox one"
// missed-draw investigation.
//
// Only ever calls .get() -- never .set()/.update()/.delete()/.create()/
// .add()/.batch()/.runTransaction(). Uses its own explicitly-named
// Firebase app (never the implicit default app), exactly like
// audit_missed_main_prize_draws.js, so --project can never be silently
// ignored by a pre-existing default app.
//
// Usage:
//   node scripts/search_games_by_keyword.js --project proxi-play-odzp2e
const KEYWORDS = ["kids troc", "xbox", "jagged alliance"];
const APP_NAME = "search_games_by_keyword_one_off";

function parseArgs(argv) {
  const args = { project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "", pageSize: 200 };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--project" && i + 1 < argv.length) {
      args.project = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (argv[i] === "--page-size" && i + 1 < argv.length) {
      args.pageSize = Math.max(1, Math.min(300, Number(argv[i + 1]) || 200));
      i += 1;
    }
  }
  return args;
}

function toIso(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return new Date(value.toMillis()).toISOString();
  return null;
}

function matchesKeyword(data) {
  const haystack = [data.name, data.enseigne_name, data.description]
    .filter((v) => typeof v === "string")
    .join(" ␟ ") // unlikely separator, avoids accidental cross-field matches
    .toLowerCase();
  return KEYWORDS.some((kw) => haystack.includes(kw));
}

async function main() {
  const admin = require("firebase-admin");
  const args = parseArgs(process.argv.slice(2));
  if (!args.project) throw new Error("Project id manquant. Utilisez --project <firebase-project-id>.");

  const existing = admin.apps.find((a) => a && a.name === APP_NAME);
  const app =
    existing ||
    admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: args.project }, APP_NAME);
  const db = admin.firestore(app);

  console.log(`[search_games_by_keyword] project=${args.project} databaseId=${db.databaseId}`);

  const matches = [];
  let scanned = 0;
  let lastDoc = null;
  while (true) {
    let query = db.collection("games").orderBy(admin.firestore.FieldPath.documentId()).limit(args.pageSize);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    for (const doc of snapshot.docs) {
      scanned += 1;
      const data = doc.data() || {};
      if (!matchesKeyword(data)) continue;
      matches.push({
        id: doc.id,
        name: data.name ?? null,
        enseigne_name: data.enseigne_name ?? null,
        end_date: toIso(data.end_date),
        hasMainPrize: data.hasMainPrize ?? null,
        hasWinner: Object.prototype.hasOwnProperty.call(data, "hasWinner") ? data.hasWinner : "absent",
      });
    }
  }

  console.log(`[search_games_by_keyword] scanned=${scanned} matches=${matches.length}`);
  console.table ? console.table(matches) : console.log(JSON.stringify(matches, null, 2));
}

main().catch((error) => {
  console.error(`[search_games_by_keyword] FATAL ${error.message || error}`);
  process.exitCode = 1;
});

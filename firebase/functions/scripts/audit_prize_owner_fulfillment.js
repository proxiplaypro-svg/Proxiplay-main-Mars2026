#!/usr/bin/env node
"use strict";

// STRICTLY READ-ONLY. No .set()/.update()/.delete()/.create() call anywhere
// in this file, against any collection, under any circumstance.
//
// FAILLE 2 (audit global, phase 2) : gamePrizeOwnership() (merchant_
// ownership.js) posait owner_id == marchand des qu'une enseigne avait un
// proprietaire, quel que soit fulfillment_type -- corrige pour que seul
// fulfillment_type:'merchant' recoive desormais un owner_id marchand. Ce
// correctif ne s'applique qu'aux NOUVEAUX prizes ; les documents deja
// crees avant lui peuvent encore porter un owner_id incorrect pour un lot
// partner/platform. Ce script liste ces documents, SANS RIEN MODIFIER, pour
// permettre une decision humaine separee sur un eventuel nettoyage cible
// (jamais un backfill global sans revue).
//
// Critere : prizes.fulfillment_type IN ('partner','platform')
//           ET prizes.owner_id != null
//
// Ne journalise JAMAIS claim_code, meme en cas d'erreur -- uniquement les
// champs d'identification et d'etat necessaires a la decision de
// nettoyage. Ne pas executer contre un projet de production dans le cadre
// de cette passe : lecture seule preparee, pas lancee.
//
// Usage :
//   node scripts/audit_prize_owner_fulfillment.js --project <firebase-project-id> \
//     [--page-size 200] [--json-out report.json] [--csv-out report.csv]
const fs = require("node:fs");
const path = require("node:path");

function refPath(value) {
  return typeof value?.path === "string" ? value.path : "";
}

function toIso(timestampLike) {
  if (!timestampLike) return null;
  if (typeof timestampLike.toDate === "function") return timestampLike.toDate().toISOString();
  if (timestampLike instanceof Date) return timestampLike.toISOString();
  return null;
}

// Pure: takes the already-fetched prize data (+ its document creation time
// and whether a partner-delivery job references it), never touches
// Firestore itself. Never reads or returns claim_code.
function buildFinding({ prizeId, data, createTime, hasPartnerDeliveryJob }) {
  const claimed = data.claimed === true;
  const hasWinner = typeof refPath(data.winner_id) === "string" && refPath(data.winner_id) !== "";
  // Recommandation indicative seulement -- jamais appliquee par ce script,
  // jamais un ordre de nettoyage automatique : un humain tranche ensuite.
  // "safe_to_review" : rien n'indique encore un usage actif de owner_id
  // pour ce document (pas reclame, pas de job partenaire en cours).
  // "needs_manual_review" : un etat actif existe, a examiner avant toute
  // decision de nettoyage.
  const cleanupSignal = claimed || hasPartnerDeliveryJob ? "needs_manual_review" : "safe_to_review";
  return {
    prize_id: prizeId,
    fulfillment_type: data.fulfillment_type ?? null,
    game_id: refPath(data.game_id) || null,
    owner_id: refPath(data.owner_id) || null,
    enseigne_id: refPath(data.enseigne_id) || null,
    created_at: toIso(createTime),
    claimed,
    has_winner: hasWinner,
    has_partner_delivery_job: hasPartnerDeliveryJob,
    cleanup_signal: cleanupSignal,
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
  if (!filePath) return;
  const resolved = path.resolve(process.cwd(), filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, content);
}

function toCsv(findings) {
  const header = [
    "prize_id", "fulfillment_type", "game_id", "owner_id", "enseigne_id",
    "created_at", "claimed", "has_winner", "has_partner_delivery_job", "cleanup_signal",
  ].join(",");
  const lines = findings.map((f) => [
    f.prize_id, f.fulfillment_type ?? "", f.game_id ?? "", f.owner_id ?? "", f.enseigne_id ?? "",
    f.created_at ?? "", f.claimed, f.has_winner, f.has_partner_delivery_job, f.cleanup_signal,
  ].join(","));
  return [header, ...lines].join("\n");
}

// Jamais appele contre la production dans cette passe : seule la lecture
// par lot (pagination par documentId) + un collectionGroup read-only sur
// _partner_delivery_jobs/*/items, pour verifier un eventuel job en cours.
// Aucune ecriture nulle part.
async function main() {
  const admin = require("firebase-admin");
  const args = parseArgs(process.argv.slice(2));
  const db = ensureFirestore(admin, args.project);

  const findings = [];
  let scanned = 0;
  let lastDoc = null;

  while (true) {
    let query = db
      .collection("prizes")
      .where("fulfillment_type", "in", ["partner", "platform"])
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(args.pageSize);
    if (lastDoc) query = query.startAfter(lastDoc);
    // eslint-disable-next-line no-await-in-loop
    const snapshot = await query.get();
    if (snapshot.empty) break;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    for (const prizeDoc of snapshot.docs) {
      scanned += 1;
      const data = prizeDoc.data() || {};
      if (data.owner_id == null) continue; // deja correct, rien a signaler

      // eslint-disable-next-line no-await-in-loop
      const jobItems = await db
        .collectionGroup("items")
        .where("prize_id", "==", prizeDoc.ref)
        .limit(1)
        .get();

      findings.push(
        buildFinding({
          prizeId: prizeDoc.id,
          data,
          createTime: prizeDoc.createTime,
          hasPartnerDeliveryJob: !jobItems.empty,
        }),
      );
    }
  }

  const summary = {
    generatedAt: new Date().toISOString(),
    readOnly: true,
    scannedPrizes: scanned,
    malformedCount: findings.length,
    byFulfillmentType: {
      partner: findings.filter((f) => f.fulfillment_type === "partner").length,
      platform: findings.filter((f) => f.fulfillment_type === "platform").length,
    },
    byCleanupSignal: {
      safe_to_review: findings.filter((f) => f.cleanup_signal === "safe_to_review").length,
      needs_manual_review: findings.filter((f) => f.cleanup_signal === "needs_manual_review").length,
    },
    findings,
  };

  writeIfRequested(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`);
  writeIfRequested(args.csvOut, `${toCsv(findings)}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`[audit_prize_owner_fulfillment] FATAL ${error.message || error}`);
    process.exitCode = 1;
  });
}

module.exports = { buildFinding };

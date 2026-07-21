#!/usr/bin/env node

const admin = require("firebase-admin");

function parseArgs(argv) {
  const flags = new Set(argv.slice(2));
  const getValue = (name, fallback = "") => {
    const prefix = `${name}=`;
    const arg = argv.find((entry) => entry.startsWith(prefix));
    return arg ? arg.slice(prefix.length) : fallback;
  };

  return {
    apply: flags.has("--apply"),
    confirm: flags.has("--confirm"),
    dryRun: flags.has("--dry-run") || !flags.has("--apply"),
    projectId: getValue("--project"),
    batchSize: Math.min(
      450,
      Math.max(1, Number.parseInt(getValue("--batch-size", "450"), 10) || 450),
    ),
  };
}

function hasRemainingPartField(data) {
  return Object.prototype.hasOwnProperty.call(data || {}, "remaining_part");
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.apply && !args.confirm) {
    throw new Error("Pass --confirm with --apply to write changes.");
  }

  admin.initializeApp(
    args.projectId
      ? {
          projectId: args.projectId,
        }
      : undefined,
  );

  const firestore = admin.firestore();
  let lastDoc = null;
  let scanned = 0;
  let patched = 0;
  let page = 0;

  while (true) {
    let query = firestore
      .collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(args.batchSize);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    page += 1;
    const batch = firestore.batch();
    let pagePatched = 0;

    for (const doc of snapshot.docs) {
      scanned += 1;
      const data = doc.data() || {};
      const hasField = hasRemainingPartField(data);
      const shouldPatch = !hasField || data.remaining_part == null;

      if (!shouldPatch) {
        continue;
      }

      pagePatched += 1;
      patched += 1;

      if (args.apply) {
        batch.set(
          doc.ref,
          {
            remaining_part: 3,
            part_last_update: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }

    if (args.apply && pagePatched > 0) {
      await batch.commit();
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    console.log(
      `[backfill_remaining_part] page=${page} scanned=${scanned} patched=${patched} mode=${args.apply ? "apply" : "dry-run"}`,
    );

    if (snapshot.size < args.batchSize) {
      break;
    }
  }

  console.log(
    `[backfill_remaining_part] completed scanned=${scanned} patched=${patched} mode=${args.apply ? "apply" : "dry-run"}`,
  );
}

main().catch((error) => {
  console.error("[backfill_remaining_part] failed", error);
  process.exitCode = 1;
});

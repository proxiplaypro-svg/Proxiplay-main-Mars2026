#!/usr/bin/env node

// One-off backfill: writes winnerFirstName/winner_first_name/winnerCity/
// winner_city on already-existing `prizes` docs (all prize_type) and on
// `games` docs that already have a main_prize_winner, so that winners drawn
// before this fix keep their display (prenom/ville) once the users/{doc}
// Firestore rule is tightened to isSelf(document) || isAdmin().
//
// Usage (from firebase/functions):
//   node scripts/backfill_winner_denormalized_fields.js --project=proxi-play-odzp2e
//   node scripts/backfill_winner_denormalized_fields.js --project=proxi-play-odzp2e --apply --confirm

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
    projectId: getValue("--project"),
    batchSize: Math.min(
      450,
      Math.max(1, Number.parseInt(getValue("--batch-size", "450"), 10) || 450),
    ),
  };
}

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function toDocRef(firestore, value) {
  if (!value) {
    return null;
  }
  if (typeof value.path === "string") {
    return firestore.doc(value.path);
  }
  return null;
}

async function computeDenormalizedFields(firestore, winnerRef, userCache) {
  if (!winnerRef) {
    return null;
  }
  if (!userCache.has(winnerRef.path)) {
    userCache.set(winnerRef.path, winnerRef.get());
  }
  const userSnap = await userCache.get(winnerRef.path);
  const userData = userSnap.exists ? userSnap.data() || {} : {};
  const winnerFirstName =
    getTrimmedString(userData.first_name || userData.firstName).split(/\s+/)[0] ||
    "";
  const winnerCity = getTrimmedString(userData.city);

  if (!winnerFirstName && !winnerCity) {
    return null;
  }

  return {
    ...(winnerFirstName
      ? { winnerFirstName, winner_first_name: winnerFirstName }
      : {}),
    ...(winnerCity ? { winnerCity, winner_city: winnerCity } : {}),
  };
}

async function backfillCollection({
  firestore,
  collectionName,
  winnerRefFieldGetter,
  args,
  userCache,
}) {
  let lastDoc = null;
  let scanned = 0;
  let patched = 0;
  let skippedAlreadyDenormalized = 0;
  let skippedNoWinner = 0;
  let page = 0;

  while (true) {
    let query = firestore
      .collection(collectionName)
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

      if (data.winnerFirstName || data.winner_first_name) {
        skippedAlreadyDenormalized += 1;
        continue;
      }

      const winnerRef = winnerRefFieldGetter(firestore, data);
      if (!winnerRef) {
        skippedNoWinner += 1;
        continue;
      }

      const fields = await computeDenormalizedFields(
        firestore,
        winnerRef,
        userCache,
      );
      if (!fields) {
        continue;
      }

      pagePatched += 1;
      patched += 1;

      if (args.apply) {
        batch.set(doc.ref, fields, { merge: true });
      }
    }

    if (args.apply && pagePatched > 0) {
      await batch.commit();
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    console.log(
      `[backfill_winner_denormalized_fields] collection=${collectionName} page=${page} scanned=${scanned} patched=${patched} mode=${args.apply ? "apply" : "dry-run"}`,
    );

    if (snapshot.size < args.batchSize) {
      break;
    }
  }

  console.log(
    `[backfill_winner_denormalized_fields] collection=${collectionName} completed scanned=${scanned} patched=${patched} skippedAlreadyDenormalized=${skippedAlreadyDenormalized} skippedNoWinner=${skippedNoWinner} mode=${args.apply ? "apply" : "dry-run"}`,
  );
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
  const userCache = new Map();

  await backfillCollection({
    firestore,
    collectionName: "prizes",
    winnerRefFieldGetter: (fs, data) => toDocRef(fs, data.winner_id),
    args,
    userCache,
  });

  await backfillCollection({
    firestore,
    collectionName: "games",
    winnerRefFieldGetter: (fs, data) => toDocRef(fs, data.main_prize_winner),
    args,
    userCache,
  });
}

main().catch((error) => {
  console.error("[backfill_winner_denormalized_fields] failed", error);
  process.exitCode = 1;
});

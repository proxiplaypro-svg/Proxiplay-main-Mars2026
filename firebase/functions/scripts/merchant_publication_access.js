// Transition non destructive vers les droits de publication payants.
//
// Par defaut tout est en SIMULATION (aucune ecriture). Ajouter --apply pour
// ecrire, et --confirm=<projectId> hors emulateur.
//
//   node scripts/merchant_publication_access.js backfill-legacy [--include-pending] [--apply]
//       Marque legacy_access sur les commercants existants (compte valide
//       ET role commercant ou proprietaire d'une enseigne). N'ecrit qu'un
//       champ additionnel (merge) ; ne touche ni abonnement, ni jeu, ni compte.
//   node scripts/merchant_publication_access.js report
//       Lecture seule : statuts de publication, et commercants sans droit
//       ayant encore des jeux en cours (cas a arbitrer, rien n'est arrete).
//   node scripts/merchant_publication_access.js enforce on|off [--apply] [--force]
//       Active/desactive le controle. "on" est refuse tant qu'un commercant
//       valide proprietaire d'une enseigne n'a aucun droit (sauf --force).
//
// Ordre recommande : backfill-legacy --apply, report, enforce on --apply.

const admin = require("firebase-admin");
const {computePublicationAccess, kBillingConfigPath} = require("../merchant_publication_access");
const {isForeignModeMirror} = require("../stripe_mode");

const kLegacySource = "transition-abonnement-2026-11";

function roleOf(user) {
  return String(user?.user_role || user?.userRole || "").trim().toLowerCase();
}

async function ownersOfEnseignes(db) {
  const owners = new Set();
  const snap = await db.collection("enseignes").get();
  snap.docs.forEach((doc) => {
    const data = doc.data();
    for (const key of ["owner", "owner_id"]) {
      const value = data[key];
      const path = typeof value === "string" ? value : value?.path;
      if (path) owners.add(path.replace(/^\/?users\//, ""));
    }
  });
  return owners;
}

/**
 * Commercants dont le droit actuel de creer des jeux doit etre conserve :
 * compte valide (critere actuel de firestore.rules) et role commercant ou
 * proprietaire d'une enseigne. --include-pending ajoute les comptes en
 * attente de validation (qui ne publient pas aujourd'hui).
 */
async function planLegacyBackfill(db, {includePending = false} = {}) {
  const [usersSnap, owners, subsSnap] = await Promise.all([
    db.collection("users").get(),
    ownersOfEnseignes(db),
    db.collection("merchant_subscriptions").get(),
  ]);
  const subs = new Map(subsSnap.docs.map((doc) => [doc.id, doc.data()]));
  const toGrant = [];
  const alreadyCovered = [];
  usersSnap.docs.forEach((doc) => {
    const user = doc.data();
    const status = String(user.account_status || "");
    const eligibleStatus = status === "approved" || (includePending && status === "pendingValidation");
    const isMerchant = roleOf(user) === "commercant" || owners.has(doc.id);
    if (!eligibleStatus || !isMerchant || user.deleted === true) return;
    if (subs.get(doc.id)?.legacy_access?.enabled === true) {
      alreadyCovered.push(doc.id);
    } else {
      toGrant.push({uid: doc.id, accountStatus: status});
    }
  });
  return {toGrant, alreadyCovered};
}

async function applyLegacyBackfill(db, plan) {
  let written = 0;
  for (const {uid, accountStatus} of plan.toGrant) {
    await db.collection("merchant_subscriptions").doc(uid).set({
      merchant_user_id: db.doc(`users/${uid}`),
      legacy_access: {
        enabled: true,
        source: kLegacySource,
        account_status_at_grant: accountStatus,
        granted_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    written++;
  }
  return written;
}

async function runningGamesOf(db, uid, nowMs) {
  const ownerRef = db.doc(`users/${uid}`);
  const snap = await db.collection("games").where("owner_id", "==", ownerRef).get();
  return snap.docs.filter((doc) => {
    const game = doc.data();
    const endMs = game.end_date?.toMillis?.() ?? 0;
    return endMs > nowMs && game.visible_public !== false;
  }).map((doc) => doc.id);
}

/**
 * Rapport lecture seule : repartition des statuts, et commercants sans
 * droit de publication qui ont encore des jeux en cours (decision metier).
 */
async function buildReport(db, nowMs = Date.now()) {
  const [usersSnap, owners, subsSnap, configSnap] = await Promise.all([
    db.collection("users").get(), ownersOfEnseignes(db), db.collection("merchant_subscriptions").get(),
    db.doc(kBillingConfigPath).get(),
  ]);
  const subs = new Map(subsSnap.docs.map((doc) => [doc.id, doc.data()]));
  const byStatus = {};
  const withoutAccess = [];
  const needsDecision = [];
  // Miroirs Stripe de l'autre mode (ex. abonnements TEST en production) :
  // ignores pour les droits, listes pour verification.
  const foreignModeMirrors = subsSnap.docs.filter((doc) => isForeignModeMirror(doc.data())).map((doc) => doc.id);
  for (const doc of usersSnap.docs) {
    const user = doc.data();
    if (!(roleOf(user) === "commercant" || owners.has(doc.id)) || user.deleted === true) continue;
    const access = computePublicationAccess(subs.get(doc.id), nowMs);
    byStatus[access.status] = (byStatus[access.status] || 0) + 1;
    if (access.canPublish) continue;
    const approvedOwner = user.account_status === "approved" && owners.has(doc.id);
    if (approvedOwner) withoutAccess.push({uid: doc.id, status: access.status});
    const running = await runningGamesOf(db, doc.id, nowMs);
    if (running.length) needsDecision.push({uid: doc.id, status: access.status, runningGames: running});
  }
  return {
    enforced: configSnap.exists && configSnap.data().enforce_publication_access === true,
    byStatus, withoutAccess, needsDecision, foreignModeMirrors,
  };
}

async function setEnforcement(db, enabled, {force = false} = {}) {
  if (enabled && !force) {
    const report = await buildReport(db);
    if (report.withoutAccess.length) {
      const error = new Error(
        `${report.withoutAccess.length} commercant(s) valide(s) proprietaire(s) d'une enseigne n'ont aucun droit : ` +
        "lancer backfill-legacy --apply d'abord (ou --force).",
      );
      error.withoutAccess = report.withoutAccess;
      throw error;
    }
  }
  await db.doc(kBillingConfigPath).set({
    enforce_publication_access: enabled,
    enforce_publication_access_updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

module.exports = {planLegacyBackfill, applyLegacyBackfill, buildReport, setEnforcement, kLegacySource};

if (require.main === module) {
  const args = process.argv.slice(2);
  const flag = (name) => args.includes(`--${name}`);
  const option = (name) => (args.find((arg) => arg.startsWith(`--${name}=`)) || "").split("=")[1] || "";
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
  const isEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  const apply = flag("apply");
  if (apply && !isEmulator && option("confirm") !== projectId) {
    console.error(`Ecriture hors emulateur : ajouter --confirm=${projectId || "<projectId>"}`);
    process.exit(1);
  }
  admin.initializeApp(projectId ? {projectId} : undefined);
  const db = admin.firestore();
  (async () => {
    const [command, value] = args.filter((arg) => !arg.startsWith("--"));
    if (command === "backfill-legacy") {
      const plan = await planLegacyBackfill(db, {includePending: flag("include-pending")});
      console.log(`A marquer legacy : ${plan.toGrant.length} ; deja couverts : ${plan.alreadyCovered.length}`);
      plan.toGrant.forEach((row) => console.log(`  ${row.uid} (${row.accountStatus})`));
      if (apply) console.log(`Ecrits : ${await applyLegacyBackfill(db, plan)}`);
      else console.log("Simulation : rien n'a ete ecrit (ajouter --apply).");
    } else if (command === "report") {
      console.log(JSON.stringify(await buildReport(db), null, 2));
    } else if (command === "enforce" && ["on", "off"].includes(value)) {
      if (!apply) {
        console.log(`Simulation : le controle passerait a ${value} (ajouter --apply).`);
        if (value === "on") console.log(JSON.stringify((await buildReport(db)).withoutAccess, null, 2));
      } else {
        await setEnforcement(db, value === "on", {force: flag("force")});
        console.log(`Controle des droits de publication : ${value}`);
      }
    } else {
      console.error("Commandes : backfill-legacy | report | enforce on|off");
      process.exit(1);
    }
  })().catch((err) => {
    console.error(err.message);
    if (err.withoutAccess) console.error(JSON.stringify(err.withoutAccess, null, 2));
    process.exit(1);
  });
}

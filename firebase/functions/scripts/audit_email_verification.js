#!/usr/bin/env node

// Audit en LECTURE SEULE de la verification email des comptes Auth
// existants -- chiffre l'impact d'une eventuelle reactivation de
// _playerEmailVerificationEnabled (actuellement hardcode a false dans
// login_page_widget.dart) avant de decider quoi que ce soit.
//
// AUCUNE ECRITURE : pas de mode --apply, pas d'appel a
// admin.auth().updateUser() ou a quelque ecriture Firestore que ce soit,
// nulle part dans ce fichier. Volontaire -- ne pas en ajouter un.
//
// Usage:
//   node scripts/audit_email_verification.js --project <firebase-project-id>
//   node scripts/audit_email_verification.js --project <id> --json-out rapport.json

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "",
    jsonOut: "",
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const entry = argv[i];
    if (entry === "--project" && i + 1 < argv.length) {
      args.project = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (entry.startsWith("--project=")) {
      args.project = entry.slice("--project=".length).trim();
    } else if (entry === "--json-out" && i + 1 < argv.length) {
      args.jsonOut = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (entry.startsWith("--json-out=")) {
      args.jsonOut = entry.slice("--json-out=".length).trim();
    } else if (entry === "--help" || entry === "-h") {
      args.help = true;
    }
  }

  return args;
}

function showHelp() {
  console.log(`
Audit lecture seule : verification email des comptes Auth existants.

Ne fait AUCUNE ecriture -- aucun mode --apply n'existe dans ce script,
volontairement. Sert uniquement a chiffrer l'impact d'une eventuelle
reactivation de la verification email joueur avant de decider quoi que
ce soit (voir _playerEmailVerificationEnabled dans login_page_widget.dart).

Usage:
  node scripts/audit_email_verification.js --project <firebase-project-id>
  node scripts/audit_email_verification.js --project <id> --json-out rapport.json

Options:
  --project <id>     Firebase project id (ou GCLOUD_PROJECT/GOOGLE_CLOUD_PROJECT)
  --json-out <path>  Ecrit aussi le rapport complet (avec le detail par
                      compte) en JSON a ce chemin
  --help             Affiche cette aide
`);
}

const AGE_BUCKETS = [
  {label: "<7 jours", maxDays: 7},
  {label: "7-30 jours", maxDays: 30},
  {label: "30-90 jours", maxDays: 90},
  {label: ">90 jours", maxDays: Infinity},
];

function ageBucketLabel(ageDays) {
  for (const bucket of AGE_BUCKETS) {
    if (ageDays <= bucket.maxDays) return bucket.label;
  }
  return AGE_BUCKETS[AGE_BUCKETS.length - 1].label;
}

function hasPasswordProvider(userRecord) {
  return (userRecord.providerData || []).some(
    (p) => p.providerId === "password",
  );
}

function primaryProviderLabel(userRecord) {
  const providers = (userRecord.providerData || []).map((p) => p.providerId);
  if (providers.length === 0) return "anonymous_or_none";
  return providers.join("+");
}

function normalizeRole(rawValue) {
  const normalized = String(rawValue || "").trim().toLowerCase();
  switch (normalized) {
    case "joueur":
    case "player":
    case "participant":
      return "joueur";
    case "commercant":
    case "merchant":
    case "professional":
    case "pro":
      return "commercant";
    case "admin":
      return "admin";
    default:
      return "inconnu";
  }
}

async function fetchAllAuthUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const result = await auth.listUsers(1000, pageToken);
    users.push(...result.users);
    pageToken = result.pageToken;
  } while (pageToken);
  return users;
}

async function fetchUserRoles(firestore) {
  // uid -> role normalise, lu directement depuis Firestore (la meme
  // source que resolveAuthenticatedHome), pas depuis les custom claims Auth.
  const roleByUid = new Map();
  let lastDoc = null;

  while (true) {
    let query = firestore
      .collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(500);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const rawRole =
        data.user_role ?? data.userRole ?? data.role ?? data.user_type ?? data.accountType;
      roleByUid.set(doc.id, normalizeRole(rawRole));
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  return roleByUid;
}

function daysBetween(fromMs, toMs) {
  return Math.max(0, Math.floor((toMs - fromMs) / 86400000));
}

function createRoleBucket() {
  return {total: 0, emailPassword: 0, verified: 0, unverified: 0};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    showHelp();
    return;
  }

  if (!args.project) {
    throw new Error("Project id manquant. Utilisez --project <firebase-project-id>.");
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: args.project,
    });
  }

  const auth = admin.auth();
  const firestore = admin.firestore();

  console.log(`[audit_email_verification] START project=${args.project}`);
  console.log("[audit_email_verification] Lecture seule -- aucune ecriture, aucun --apply.");

  const [authUsers, roleByUid] = await Promise.all([
    fetchAllAuthUsers(auth),
    fetchUserRoles(firestore),
  ]);

  const now = Date.now();

  const summary = {
    totalAuthAccounts: authUsers.length,
    byProvider: {},
    emailPasswordAccounts: 0,
    emailPasswordVerified: 0,
    emailPasswordUnverified: 0,
    byRole: {
      joueur: createRoleBucket(),
      commercant: createRoleBucket(),
      admin: createRoleBucket(),
      inconnu: createRoleBucket(),
    },
    unverifiedPlayersByAccountAge: {
      "<7 jours": 0,
      "7-30 jours": 0,
      "30-90 jours": 0,
      ">90 jours": 0,
    },
    unverifiedPlayersByActivity: {
      activeLast30Days: 0,
      inactive30To90Days: 0,
      inactiveOver90Days: 0,
      neverSignedInAgain: 0,
    },
    unverifiedPlayersDetail: [],
  };

  for (const user of authUsers) {
    const providerLabel = primaryProviderLabel(user);
    summary.byProvider[providerLabel] = (summary.byProvider[providerLabel] || 0) + 1;

    const isEmailPassword = hasPasswordProvider(user);
    const role = roleByUid.get(user.uid) || "inconnu";
    const roleBucket = summary.byRole[role] || summary.byRole.inconnu;

    roleBucket.total += 1;

    if (!isEmailPassword) {
      continue;
    }

    summary.emailPasswordAccounts += 1;
    roleBucket.emailPassword += 1;

    if (user.emailVerified) {
      summary.emailPasswordVerified += 1;
      roleBucket.verified += 1;
      continue;
    }

    summary.emailPasswordUnverified += 1;
    roleBucket.unverified += 1;

    if (role !== "joueur") {
      continue;
    }

    const createdMs = user.metadata.creationTime
      ? new Date(user.metadata.creationTime).getTime()
      : null;
    const lastSignInMs = user.metadata.lastSignInTime
      ? new Date(user.metadata.lastSignInTime).getTime()
      : null;
    const ageDays = createdMs !== null ? daysBetween(createdMs, now) : null;
    const daysSinceLastSignIn = lastSignInMs !== null ? daysBetween(lastSignInMs, now) : null;

    summary.unverifiedPlayersByAccountAge[ageDays !== null ? ageBucketLabel(ageDays) : ">90 jours"] += 1;

    // lastSignInTime == creationTime signifie "jamais reconnecte depuis
    // l'inscription" (Firebase pose lastSignInTime des la premiere
    // connexion) : on le traite comme distinct de "reconnecte recemment".
    if (daysSinceLastSignIn === null) {
      summary.unverifiedPlayersByActivity.neverSignedInAgain += 1;
    } else if (daysSinceLastSignIn <= 30) {
      summary.unverifiedPlayersByActivity.activeLast30Days += 1;
    } else if (daysSinceLastSignIn <= 90) {
      summary.unverifiedPlayersByActivity.inactive30To90Days += 1;
    } else {
      summary.unverifiedPlayersByActivity.inactiveOver90Days += 1;
    }

    summary.unverifiedPlayersDetail.push({
      uid: user.uid,
      email: user.email || "",
      createdAt: user.metadata.creationTime || null,
      lastSignInAt: user.metadata.lastSignInTime || null,
      ageDays,
      daysSinceLastSignIn,
    });
  }

  printReport(summary);

  if (args.jsonOut) {
    const resolvedPath = path.resolve(args.jsonOut);
    fs.mkdirSync(path.dirname(resolvedPath), {recursive: true});
    fs.writeFileSync(resolvedPath, JSON.stringify(summary, null, 2), "utf8");
    console.log(`[audit_email_verification] Rapport JSON ecrit: ${resolvedPath}`);
  }

  console.log("[audit_email_verification] DONE (lecture seule, aucune donnee modifiee)");
}

function printReport(summary) {
  const line = () => console.log("-".repeat(64));

  line();
  console.log("COMPTES AUTH -- TOTAL:", summary.totalAuthAccounts);
  line();
  console.log("Par provider:");
  for (const [provider, count] of Object.entries(summary.byProvider).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${provider.padEnd(24)} ${count}`);
  }

  line();
  console.log("Comptes email/mot de passe:", summary.emailPasswordAccounts);
  console.log(`  verifies    : ${summary.emailPasswordVerified}`);
  console.log(`  non verifies: ${summary.emailPasswordUnverified}`);

  line();
  console.log("Par role (email/mot de passe uniquement):");
  console.log("  role         total  email/pwd  verifies  non-verifies");
  for (const [role, bucket] of Object.entries(summary.byRole)) {
    console.log(
      `  ${role.padEnd(12)} ${String(bucket.total).padStart(5)}  ` +
      `${String(bucket.emailPassword).padStart(9)}  ${String(bucket.verified).padStart(8)}  ` +
      `${String(bucket.unverified).padStart(12)}`,
    );
  }

  line();
  console.log("Joueurs email non verifies -- par anciennete du compte:");
  for (const [bucket, count] of Object.entries(summary.unverifiedPlayersByAccountAge)) {
    console.log(`  ${bucket.padEnd(14)} ${count}`);
  }

  line();
  console.log("Joueurs email non verifies -- par activite recente (lastSignInTime):");
  console.log(`  actifs (connexion <= 30j)        : ${summary.unverifiedPlayersByActivity.activeLast30Days}`);
  console.log(`  inactifs (30-90j)                : ${summary.unverifiedPlayersByActivity.inactive30To90Days}`);
  console.log(`  inactifs (>90j)                  : ${summary.unverifiedPlayersByActivity.inactiveOver90Days}`);
  console.log(`  jamais reconnectes depuis inscript.: ${summary.unverifiedPlayersByActivity.neverSignedInAgain}`);
  line();
}

main().catch((error) => {
  console.error(`[audit_email_verification] FATAL: ${error.message || error}`);
  process.exit(1);
});

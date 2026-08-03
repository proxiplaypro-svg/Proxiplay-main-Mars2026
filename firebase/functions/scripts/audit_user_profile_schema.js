#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PLAYER_ROLE = "joueur";
const MERCHANT_ROLE = "commercant";
const ADMIN_ROLE = "admin";
const CURRENT_PROFILE_SCHEMA_VERSION = 1;
const DEFAULT_PROJECT =
  process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";

function parseArgs(argv) {
  const args = {
    projectId: DEFAULT_PROJECT,
    pageSize: 250,
    dryRun: true,
    confirm: false,
    uid: "",
    serviceAccount: "",
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const entry = argv[i];
    if (entry === "--project" && i + 1 < argv.length) {
      args.projectId = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (entry.startsWith("--project=")) {
      args.projectId = entry.slice("--project=".length).trim();
    } else if (entry === "--page-size" && i + 1 < argv.length) {
      const parsed = Number(argv[i + 1]);
      if (Number.isFinite(parsed)) {
        args.pageSize = Math.max(1, Math.min(1000, Math.trunc(parsed)));
      }
      i += 1;
    } else if (entry.startsWith("--page-size=")) {
      const parsed = Number(entry.slice("--page-size=".length));
      if (Number.isFinite(parsed)) {
        args.pageSize = Math.max(1, Math.min(1000, Math.trunc(parsed)));
      }
    } else if (entry === "--uid" && i + 1 < argv.length) {
      args.uid = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (entry.startsWith("--uid=")) {
      args.uid = entry.slice("--uid=".length).trim();
    } else if (entry === "--service-account" && i + 1 < argv.length) {
      args.serviceAccount = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (entry.startsWith("--service-account=")) {
      args.serviceAccount = entry.slice("--service-account=".length).trim();
    } else if (entry === "--apply") {
      args.dryRun = false;
    } else if (entry === "--dry-run") {
      args.dryRun = true;
    } else if (entry === "--confirm") {
      args.confirm = true;
    } else if (entry === "--help" || entry === "-h") {
      args.help = true;
    }
  }

  return args;
}

function showHelp() {
  console.log(`
Audit et migration prudente du schema de profil utilisateur

Usage:
  node scripts/audit_user_profile_schema.js --project <firebase-project-id> --dry-run
  node scripts/audit_user_profile_schema.js --project <firebase-project-id> --apply --confirm

Options:
  --project <id>          Firebase project id
  --uid <uid>             Audite/repare un seul document users/{uid}
  --page-size <n>         Taille de lot Firestore (defaut: 250)
  --service-account       Chemin vers un JSON de compte de service
  --dry-run               Rapport uniquement, sans ecriture
  --apply                 Applique uniquement les corrections sures
  --confirm               Requis avec --apply
  --help                  Affiche cette aide
`);
}

function ensureFirebase(projectId) {
  if (!projectId) {
    throw new Error(
      "Project id manquant. Utilisez --project <firebase-project-id>."
    );
  }
}

function initializeFirebase(args) {
  ensureFirebase(args.projectId);

  let appOptions;
  if (args.serviceAccount) {
    const serviceAccountPath = path.resolve(args.serviceAccount);
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
    appOptions = {
      credential: admin.credential.cert(serviceAccount),
      projectId: args.projectId || serviceAccount.project_id,
    };
  } else {
    appOptions = {
      projectId: args.projectId,
      credential: admin.credential.applicationDefault(),
    };
  }

  if (!admin.apps.length) {
    admin.initializeApp(appOptions);
  }

  return {
    firestore: admin.firestore(),
    auth: admin.auth(),
  };
}

function normalizeString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function hasOwn(data, key) {
  return Object.prototype.hasOwnProperty.call(data || {}, key);
}

function hasMeaningfulText(value) {
  return normalizeString(value).length > 0;
}

function hasMeaningfulValue(data, key) {
  if (!hasOwn(data, key)) {
    return false;
  }
  const value = data[key];
  if (value === null || value === undefined) {
    return false;
  }
  if (typeof value === "string") {
    return hasMeaningfulText(value);
  }
  return true;
}

function normalizeRole(rawValue) {
  const normalized = normalizeString(rawValue).toLowerCase();
  switch (normalized) {
    case PLAYER_ROLE:
    case "player":
    case "participant":
      return PLAYER_ROLE;
    case MERCHANT_ROLE:
    case "merchant":
    case "professional":
    case "pro":
      return MERCHANT_ROLE;
    case ADMIN_ROLE:
      return ADMIN_ROLE;
    default:
      return "";
  }
}

function readTimestampDate(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toDate === "function") {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  return null;
}

function buildDisplayName(firstName, lastName) {
  return [normalizeString(firstName), normalizeString(lastName)]
    .filter(Boolean)
    .join(" ")
    .trim();
}

function getProviderIds(userRecord) {
  return (userRecord?.providerData || [])
    .map((provider) => normalizeString(provider.providerId))
    .filter(Boolean);
}

function extractRole(data) {
  for (const key of ["user_role", "userRole", "role", "user_type", "accountType"]) {
    const normalized = normalizeRole(data[key]);
    if (normalized) {
      return normalized;
    }
  }
  return "";
}

function isProfileCompleteForRole({ role, data }) {
  if (!role || role === ADMIN_ROLE) {
    return true;
  }

  const hasFirstName = hasMeaningfulText(data.first_name);
  const hasLastName = hasMeaningfulText(data.last_name);
  const hasPhoneNumber = hasMeaningfulText(data.phone_number);
  const hasCity = hasMeaningfulText(data.city);
  const hasBirthday = role === PLAYER_ROLE ? !!readTimestampDate(data.birthday) : true;

  return hasFirstName && hasLastName && hasPhoneNumber && hasCity && hasBirthday;
}

function listMissingProfileFields(role, data) {
  const fields = ["uid", "email", "user_role", "first_name", "last_name", "display_name", "phone_number", "city", "photo_url", "created_time"];
  if (role === PLAYER_ROLE) {
    fields.push("birthday");
  }

  return fields.filter((field) => {
    if (field === "birthday") {
      return !readTimestampDate(data.birthday);
    }
    return !hasMeaningfulValue(data, field);
  });
}

function buildFinding({ uid, data, authRecord }) {
  const role = extractRole(data);
  const providerIds = getProviderIds(authRecord);
  const profileComplete = isProfileCompleteForRole({ role, data });
  const composedDisplayName = buildDisplayName(data.first_name, data.last_name);
  const currentDisplayName = normalizeString(data.display_name);
  const missingFields = listMissingProfileFields(role, data);
  const displayNameOnly =
    currentDisplayName.length > 0 &&
    !hasMeaningfulText(data.first_name) &&
    !hasMeaningfulText(data.last_name);
  const displayNameMismatch =
    composedDisplayName.length > 0 &&
    currentDisplayName.length > 0 &&
    currentDisplayName !== composedDisplayName;
  const missingCreatedTime = !hasMeaningfulValue(data, "created_time");
  const missingRole = !role;
  const profileSchemaVersion =
    hasOwn(data, "profile_schema_version") &&
    Number.isFinite(Number(data.profile_schema_version))
      ? Number(data.profile_schema_version)
      : null;
  const explicitProfileCompleted =
    typeof data.profile_completed === "boolean" ? data.profile_completed : null;
  const likelyGoogleAccount = providerIds.includes("google.com");

  const patch = {};
  const patchReasons = [];

  if (profileSchemaVersion !== CURRENT_PROFILE_SCHEMA_VERSION) {
    patch.profile_schema_version = CURRENT_PROFILE_SCHEMA_VERSION;
    patchReasons.push("profile_schema_version<-1");
  }

  if (explicitProfileCompleted !== profileComplete) {
    patch.profile_completed = profileComplete;
    patchReasons.push(`profile_completed<-${profileComplete}`);
    if (!profileComplete && !hasOwn(data, "profile_completed_at")) {
      patch.profile_completed_at = null;
      patchReasons.push("profile_completed_at<-null");
    }
  }

  if (!currentDisplayName && composedDisplayName) {
    patch.display_name = composedDisplayName;
    patchReasons.push("display_name<-first_name+last_name");
  }

  return {
    uid,
    role,
    authProviders: providerIds,
    email: normalizeString(data.email) || normalizeString(authRecord?.email),
    profileComplete,
    missingFields,
    displayNameOnly,
    displayNameMismatch,
    missingCreatedTime,
    missingRole,
    likelyGoogleAccount,
    currentDisplayName,
    composedDisplayName,
    patch,
    patchFieldNames: Object.keys(patch),
    patchReasons,
  };
}

async function listUserDocs(firestore, pageSize, singleUid) {
  if (singleUid) {
    const snap = await firestore.collection("users").doc(singleUid).get();
    return snap.exists ? [snap] : [];
  }

  const docs = [];
  let lastDocId = "";

  while (true) {
    let query = firestore
      .collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(pageSize);
    if (lastDocId) {
      query = query.startAfter(lastDocId);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    docs.push(...snapshot.docs);
    lastDocId = snapshot.docs[snapshot.docs.length - 1].id;
    if (snapshot.size < pageSize) {
      break;
    }
  }

  return docs;
}

async function getAuthRecordOrNull(auth, uid) {
  try {
    return await auth.getUser(uid);
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      return null;
    }
    throw error;
  }
}

function createSummary() {
  return {
    totalUsers: 0,
    completeProfiles: 0,
    incompleteProfiles: 0,
    onlyDisplayName: 0,
    displayNameMismatches: 0,
    withoutCreatedTime: 0,
    withoutRole: 0,
    likelyGoogleAccounts: 0,
    writableFindings: 0,
  };
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

  const { firestore, auth } = initializeFirebase(args);
  const summary = createSummary();
  const docs = await listUserDocs(firestore, args.pageSize, args.uid);

  for (const doc of docs) {
    summary.totalUsers += 1;
    const data = doc.data() || {};
    const authRecord = await getAuthRecordOrNull(auth, doc.id);
    const finding = buildFinding({
      uid: doc.id,
      data,
      authRecord,
    });

    if (finding.profileComplete) {
      summary.completeProfiles += 1;
    } else {
      summary.incompleteProfiles += 1;
    }
    if (finding.displayNameOnly) {
      summary.onlyDisplayName += 1;
    }
    if (finding.displayNameMismatch) {
      summary.displayNameMismatches += 1;
    }
    if (finding.missingCreatedTime) {
      summary.withoutCreatedTime += 1;
    }
    if (finding.missingRole) {
      summary.withoutRole += 1;
    }
    if (finding.likelyGoogleAccount) {
      summary.likelyGoogleAccounts += 1;
    }
    if (finding.patchFieldNames.length > 0) {
      summary.writableFindings += 1;
    }

    if (!args.dryRun && finding.patchFieldNames.length > 0) {
      await doc.ref.set(finding.patch, { merge: true });
      console.log(
        `[audit_user_profile_schema] APPLY uid=${finding.uid} fields=${finding.patchFieldNames.join(",")}`
      );
    }

    console.log(
      JSON.stringify({
        uid: finding.uid,
        email: finding.email,
        role: finding.role || "<missing>",
        profileComplete: finding.profileComplete,
        missingFields: finding.missingFields,
        displayNameOnly: finding.displayNameOnly,
        displayNameMismatch: finding.displayNameMismatch,
        missingCreatedTime: finding.missingCreatedTime,
        missingRole: finding.missingRole,
        likelyGoogleAccount: finding.likelyGoogleAccount,
        authProviders: finding.authProviders,
        patch: finding.patch,
        patchFieldNames: finding.patchFieldNames,
        patchReasons: finding.patchReasons,
      })
    );
  }

  console.log(
    `[audit_user_profile_schema] DONE project=${args.projectId} mode=${args.dryRun ? "dry-run" : "apply"} totalUsers=${summary.totalUsers} completeProfiles=${summary.completeProfiles} incompleteProfiles=${summary.incompleteProfiles} onlyDisplayName=${summary.onlyDisplayName} displayNameMismatches=${summary.displayNameMismatches} withoutCreatedTime=${summary.withoutCreatedTime} withoutRole=${summary.withoutRole} likelyGoogleAccounts=${summary.likelyGoogleAccounts} writableFindings=${summary.writableFindings}`
  );
}

main().catch((error) => {
  if (
    String(error?.message || "").includes("metadata.google.internal") ||
    String(error?.message || "").includes("GOOGLE_APPLICATION_CREDENTIALS")
  ) {
    console.error(
      "[audit_user_profile_schema] hint=Local execution requires ADC or --service-account <path-to-json>"
    );
  }
  console.error(
    `[audit_user_profile_schema] FATAL message=${error.message || error}`
  );
  process.exit(1);
});

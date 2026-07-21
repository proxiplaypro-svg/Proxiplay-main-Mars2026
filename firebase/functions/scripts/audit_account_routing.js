#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

function parseArgs(argv) {
  const flags = new Set(argv.slice(2).filter((entry) => entry.startsWith("--")));
  const getValue = (name, fallback = "") => {
    const prefix = `${name}=`;
    const arg = argv.find((entry) => entry.startsWith(prefix));
    return arg ? arg.slice(prefix.length) : fallback;
  };

  return {
    projectId: getValue("--project"),
    uid: getValue("--uid"),
    all: flags.has("--all"),
    batchSize: Math.min(
      500,
      Math.max(1, Number.parseInt(getValue("--batch-size", "100"), 10) || 100),
    ),
    jsonOut: getValue("--json-out"),
    csvOut: getValue("--csv-out"),
  };
}

function trimString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeRole(rawValue) {
  const normalized = trimString(rawValue).toLowerCase();
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
      return "";
  }
}

function normalizeBooleanRole(value) {
  return value === true ? "commercant" : "";
}

function extractRoleSources(data) {
  return {
    user_role: data.user_role,
    userRole: data.userRole,
    role: data.role,
    user_type: data.user_type,
    accountType: data.accountType,
    isProfessional: data.isProfessional,
  };
}

function extractExplicitRoleFields(roleSources) {
  const entries = [];
  for (const key of ["user_role", "userRole", "role", "user_type", "accountType"]) {
    const rawValue = trimString(roleSources[key]);
    if (!rawValue) {
      continue;
    }
    entries.push({
      field: key,
      rawValue,
      normalizedRole: normalizeRole(rawValue),
    });
  }

  if (roleSources.isProfessional === true) {
    entries.push({
      field: "isProfessional",
      rawValue: "true",
      normalizedRole: normalizeBooleanRole(roleSources.isProfessional),
    });
  }

  return entries;
}

function firstRoleCandidate(roleSources) {
  for (const key of ["user_role", "userRole", "role", "user_type", "accountType"]) {
    const value = trimString(roleSources[key]);
    if (value) {
      return value;
    }
  }
  return "";
}

function collectPlayerSignals(data) {
  const signals = [];
  if (Object.prototype.hasOwnProperty.call(data, "remaining_part")) {
    signals.push("remaining_part");
  }
  if (Object.prototype.hasOwnProperty.call(data, "part_last_update")) {
    signals.push("part_last_update");
  }
  if (Object.prototype.hasOwnProperty.call(data, "allGamesAccessUntil")) {
    signals.push("allGamesAccessUntil");
  }
  return signals;
}

function collectMerchantSignals(data, hasEnseigne) {
  const signals = [];
  if (hasEnseigne) {
    signals.push("enseigne_owner");
  }
  if (trimString(data.professional_category)) {
    signals.push("professional_category");
  }
  if (trimString(data.account_status) === "pendingValidation") {
    signals.push("pendingValidation");
  }
  if (data.isProfessional === true) {
    signals.push("isProfessional=true");
  }
  return signals;
}

function csvEscape(value) {
  const stringValue = value == null ? "" : String(value);
  if (/[",\n]/.test(stringValue)) {
    return `"${stringValue.replace(/"/g, '""')}"`;
  }
  return stringValue;
}

function listNormalizedRoles(roleEntries) {
  return [...new Set(roleEntries.map((entry) => entry.normalizedRole).filter(Boolean))];
}

function listRawRoleValues(roleEntries) {
  return [...new Set(roleEntries.map((entry) => entry.rawValue).filter(Boolean))];
}

function findRoleFieldContradictions(roleEntries) {
  const normalizedRoles = listNormalizedRoles(roleEntries);
  return normalizedRoles.length > 1;
}

function buildFinding({ uid, data, hasEnseigne }) {
  const roleSources = extractRoleSources(data);
  const roleEntries = extractExplicitRoleFields(roleSources);
  const rawRole = firstRoleCandidate(roleSources);
  const normalizedRole = normalizeRole(rawRole);
  const playerSignals = collectPlayerSignals(data);
  const merchantSignals = collectMerchantSignals(data, hasEnseigne);
  const explicitNormalizedRoles = listNormalizedRoles(roleEntries);
  const explicitRawRoleValues = listRawRoleValues(roleEntries);
  const findings = [];
  let recommendedAction = "";

  const missingRole = !rawRole;
  const invalidRole = !!rawRole && !normalizedRole;
  const contradictoryRoleFields = findRoleFieldContradictions(roleEntries);
  const joueurWithMerchantSignals =
    normalizedRole === "joueur" && merchantSignals.length > 0;
  const commercantWithPlayerSignals =
    normalizedRole === "commercant" && playerSignals.length > 0;

  if (missingRole) {
    findings.push("missing_role");
  }
  if (invalidRole) {
    findings.push("invalid_role_value");
  }
  if (contradictoryRoleFields) {
    findings.push("contradictory_role_fields");
  }
  if (commercantWithPlayerSignals) {
    findings.push("merchant_role_with_player_signals");
  }
  if (joueurWithMerchantSignals) {
    findings.push("player_role_with_merchant_signals");
  }
  if (!normalizedRole && playerSignals.length > 0 && merchantSignals.length === 0) {
    findings.push("missing_or_invalid_role_with_player_signals");
  }

  if (!normalizedRole && playerSignals.length > 0 && merchantSignals.length === 0) {
    recommendedAction = "safe_candidate_for_user_role_joueur";
  } else if (
    contradictoryRoleFields ||
    joueurWithMerchantSignals ||
    commercantWithPlayerSignals ||
    invalidRole
  ) {
    recommendedAction = "manual_role_review";
  } else if (missingRole) {
    recommendedAction = "manual_role_review";
  }

  return {
    uid,
    email: trimString(data.email),
    rawRole,
    normalizedRole,
    explicitRoleValues: explicitRawRoleValues,
    explicitNormalizedRoles,
    accountStatus: trimString(data.account_status),
    hasEnseigne,
    playerSignals,
    merchantSignals,
    remainingPart: Object.prototype.hasOwnProperty.call(data, "remaining_part")
      ? data.remaining_part
      : "<absent>",
    roleSources,
    roleEntries,
    findings,
    recommendedAction,
    flags: {
      missingRole,
      invalidRole,
      contradictoryRoleFields,
      joueurWithMerchantSignals,
      commercantWithPlayerSignals,
    },
  };
}

async function hasOwnedEnseigne(firestore, uid) {
  const userRef = firestore.doc(`users/${uid}`);
  const snapshot = await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .limit(1)
    .get();
  return !snapshot.empty;
}

function createSummary() {
  return {
    scanned: 0,
    emitted: 0,
    usersByResolvedRole: {
      joueur: 0,
      commercant: 0,
      admin: 0,
      unresolved: 0,
    },
    missingRoleCount: 0,
    invalidRoleCount: 0,
    contradictoryRoleFieldCount: 0,
    joueurWithMerchantSignalsCount: 0,
    commercantWithPlayerSignalsCount: 0,
    findingCounts: {},
    uids: {
      missingRole: [],
      invalidRole: [],
      contradictoryRoleFields: [],
      joueurWithMerchantSignals: [],
      commercantWithPlayerSignals: [],
    },
  };
}

function pushUnique(list, value) {
  if (!list.includes(value)) {
    list.push(value);
  }
}

function applySummary(summary, finding) {
  summary.scanned += 1;

  switch (finding.normalizedRole) {
    case "joueur":
      summary.usersByResolvedRole.joueur += 1;
      break;
    case "commercant":
      summary.usersByResolvedRole.commercant += 1;
      break;
    case "admin":
      summary.usersByResolvedRole.admin += 1;
      break;
    default:
      summary.usersByResolvedRole.unresolved += 1;
      break;
  }

  for (const findingCode of finding.findings) {
    summary.findingCounts[findingCode] =
      (summary.findingCounts[findingCode] || 0) + 1;
  }

  if (finding.flags.missingRole) {
    summary.missingRoleCount += 1;
    pushUnique(summary.uids.missingRole, finding.uid);
  }
  if (finding.flags.invalidRole) {
    summary.invalidRoleCount += 1;
    pushUnique(summary.uids.invalidRole, finding.uid);
  }
  if (finding.flags.contradictoryRoleFields) {
    summary.contradictoryRoleFieldCount += 1;
    pushUnique(summary.uids.contradictoryRoleFields, finding.uid);
  }
  if (finding.flags.joueurWithMerchantSignals) {
    summary.joueurWithMerchantSignalsCount += 1;
    pushUnique(summary.uids.joueurWithMerchantSignals, finding.uid);
  }
  if (finding.flags.commercantWithPlayerSignals) {
    summary.commercantWithPlayerSignalsCount += 1;
    pushUnique(summary.uids.commercantWithPlayerSignals, finding.uid);
  }
}

function buildCsv(findings) {
  const headers = [
    "uid",
    "email",
    "rawRole",
    "normalizedRole",
    "explicitRoleValues",
    "explicitNormalizedRoles",
    "accountStatus",
    "hasEnseigne",
    "playerSignals",
    "merchantSignals",
    "remainingPart",
    "findings",
    "recommendedAction",
  ];

  const rows = findings.map((finding) => [
    finding.uid,
    finding.email,
    finding.rawRole,
    finding.normalizedRole,
    finding.explicitRoleValues.join("|"),
    finding.explicitNormalizedRoles.join("|"),
    finding.accountStatus,
    finding.hasEnseigne,
    finding.playerSignals.join("|"),
    finding.merchantSignals.join("|"),
    typeof finding.remainingPart === "object"
      ? JSON.stringify(finding.remainingPart)
      : finding.remainingPart,
    finding.findings.join("|"),
    finding.recommendedAction,
  ]);

  return [headers, ...rows]
    .map((row) => row.map(csvEscape).join(","))
    .join("\n");
}

function ensureParentDir(filePath) {
  if (!filePath) {
    return;
  }
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

async function main() {
  const args = parseArgs(process.argv);
  admin.initializeApp(
    args.projectId
      ? {
          projectId: args.projectId,
        }
      : undefined,
  );

  const firestore = admin.firestore();
  let lastDoc = null;
  const findings = [];
  const summary = createSummary();

  while (true) {
    let query = firestore
      .collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(args.uid ? 1 : args.batchSize);

    if (args.uid) {
      query = firestore
        .collection("users")
        .where(admin.firestore.FieldPath.documentId(), "==", args.uid)
        .limit(1);
    } else if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const hasEnseigne = await hasOwnedEnseigne(firestore, doc.id);
      const finding = buildFinding({
        uid: doc.id,
        data,
        hasEnseigne,
      });

      applySummary(summary, finding);

      if (args.all || finding.findings.length > 0) {
        findings.push(finding);
        console.log(JSON.stringify(finding));
      }
    }

    if (args.uid) {
      break;
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < args.batchSize) {
      break;
    }
  }

  summary.emitted = findings.length;

  const report = {
    projectId: args.projectId || admin.app().options.projectId || "",
    generatedAt: new Date().toISOString(),
    mode: args.all ? "all" : "flagged",
    summary,
    findings,
  };

  if (args.jsonOut) {
    ensureParentDir(args.jsonOut);
    fs.writeFileSync(args.jsonOut, `${JSON.stringify(report, null, 2)}\n`);
  }

  if (args.csvOut) {
    ensureParentDir(args.csvOut);
    fs.writeFileSync(args.csvOut, `${buildCsv(findings)}\n`);
  }

  console.log(`[audit_account_routing][summary] ${JSON.stringify(summary)}`);
  if (args.jsonOut) {
    console.log(`[audit_account_routing] json_report=${args.jsonOut}`);
  }
  if (args.csvOut) {
    console.log(`[audit_account_routing] csv_report=${args.csvOut}`);
  }
  console.log(
    `[audit_account_routing] completed scanned=${summary.scanned} emitted=${summary.emitted} mode=${args.all ? "all" : "flagged"}`,
  );
}

main().catch((error) => {
  console.error("[audit_account_routing] failed", error);
  process.exitCode = 1;
});

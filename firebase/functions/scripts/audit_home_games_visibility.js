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
    jsonOut: getValue("--json-out"),
    csvOut: getValue("--csv-out"),
    serviceAccount: getValue("--service-account"),
    all: flags.has("--all"),
    includeNonAdminOnline: flags.has("--include-non-admin-online"),
  };
}

function trimString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function asIso(value) {
  if (!value) {
    return "";
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  const candidate = new Date(value);
  return Number.isNaN(candidate.getTime()) ? String(value) : candidate.toISOString();
}

function csvEscape(value) {
  const str = value == null ? "" : String(value);
  if (/[",\n;]/.test(str)) {
    return `"${str.replace(/"/g, "\"\"")}"`;
  }
  return str;
}

function isMerchantActiveGame(data, now) {
  const endDate = data.end_date instanceof Date
    ? data.end_date
    : data.end_date && typeof data.end_date.toDate === "function"
      ? data.end_date.toDate()
      : null;
  if (!endDate) {
    return false;
  }
  if (data.hidden_from_merchant_stats === true) {
    return false;
  }
  return endDate.getTime() >= now.getTime();
}

function getPlayerHomeVisibilityReason(data, now) {
  const animationId = trimString(data.animation_id);
  if (animationId) {
    return "animationId-non-vide";
  }

  const endDate = data.end_date instanceof Date
    ? data.end_date
    : data.end_date && typeof data.end_date.toDate === "function"
      ? data.end_date.toDate()
      : null;
  if (!endDate) {
    return "end_date-absente";
  }
  if (endDate.getTime() <= now.getTime()) {
    return "date-fin-depassee";
  }

  const startDate = data.start_date instanceof Date
    ? data.start_date
    : data.start_date && typeof data.start_date.toDate === "function"
      ? data.start_date.toDate()
      : null;
  if (startDate && startDate.getTime() > now.getTime()) {
    return "date-debut-future";
  }

  return "";
}

function getHomeSectionDecision(data, now, section) {
  const reasons = [];
  const hasWinner = data.hasWinner === true;
  if (hasWinner) {
    reasons.push("hasWinner=true");
  }

  if (section === "endingSoon") {
    const endDate = data.end_date instanceof Date
      ? data.end_date
      : data.end_date && typeof data.end_date.toDate === "function"
        ? data.end_date.toDate()
        : null;
    if (!endDate) {
      reasons.push("query:end_date-absente");
    } else if (endDate.getTime() <= now.getTime()) {
      reasons.push("query:end_date<=now");
    }
  }

  const playerReason = getPlayerHomeVisibilityReason(data, now);
  if (playerReason) {
    reasons.push(`player:${playerReason}`);
  }

  return {
    included: reasons.length === 0,
    reasons,
  };
}

function countDistinctGamesWithReason(rows, predicate) {
  return rows.filter(predicate).length;
}

async function loadEnseigneNames(firestore, rows) {
  const refPaths = Array.from(
    new Set(
      rows
        .map((row) => row.enseigneRefPath)
        .filter((value) => typeof value === "string" && value.length > 0),
    ),
  );

  const namesByPath = new Map();
  await Promise.all(
    refPaths.map(async (refPath) => {
      try {
        const snap = await firestore.doc(refPath).get();
        const data = snap.data() || {};
        namesByPath.set(refPath, trimString(data.name));
      } catch (error) {
        namesByPath.set(refPath, "");
      }
    }),
  );

  for (const row of rows) {
    if (!row.enseigneName && row.enseigneRefPath) {
      row.enseigneName = namesByPath.get(row.enseigneRefPath) || "";
    }
  }
}

async function main() {
  const args = parseArgs(process.argv);

  let appOptions;
  if (args.serviceAccount) {
    const serviceAccountPath = path.resolve(args.serviceAccount);
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
    appOptions = {
      credential: admin.credential.cert(serviceAccount),
      projectId: args.projectId || serviceAccount.project_id,
    };
  } else {
    appOptions = args.projectId
      ? {
          projectId: args.projectId,
          credential: admin.credential.applicationDefault(),
        }
      : {
          credential: admin.credential.applicationDefault(),
        };
  }

  admin.initializeApp(appOptions);

  const firestore = admin.firestore();
  const now = new Date();
  const snapshot = await firestore.collection("games").get();
  const rows = snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    const newest = getHomeSectionDecision(data, now, "newGames");
    const endingSoon = getHomeSectionDecision(data, now, "endingSoon");
    const adminOnline = isMerchantActiveGame(data, now);
    const rawIsActive = Object.prototype.hasOwnProperty.call(data, "isActive")
      ? data.isActive
      : "";

    return {
      id: doc.id,
      name: trimString(data.name),
      enseigneName: trimString(data.enseigne_name),
      enseigneRefPath:
        data.enseigne_id && typeof data.enseigne_id.path === "string"
          ? data.enseigne_id.path
          : "",
      isActive: rawIsActive,
      visiblePublic: data.visible_public,
      hasWinner: data.hasWinner === true,
      hasMainPrize: data.hasMainPrize === true,
      animationId: trimString(data.animation_id),
      startDate: asIso(data.start_date),
      endDate: asIso(data.end_date),
      adminOnline,
      inNewGames: newest.included,
      inEndingSoon: endingSoon.included,
      newGamesReasons: newest.reasons,
      endingSoonReasons: endingSoon.reasons,
      cumulativeReasons: Array.from(new Set([...newest.reasons, ...endingSoon.reasons])),
    };
  });

  await loadEnseigneNames(firestore, rows);

  rows.sort((a, b) => {
    if (a.adminOnline !== b.adminOnline) {
      return a.adminOnline ? -1 : 1;
    }
    return a.name.localeCompare(b.name, "fr");
  });

  const scopedRows = args.all || args.includeNonAdminOnline
    ? rows
    : rows.filter((row) => row.adminOnline);

  const summary = {
    projectId: args.projectId || admin.app().options.projectId || "",
    generatedAt: new Date().toISOString(),
    totalGames: rows.length,
    adminOnlineGames: rows.filter((row) => row.adminOnline).length,
    reportedRows: scopedRows.length,
    newGamesVisible: scopedRows.filter((row) => row.inNewGames).length,
    endingSoonVisible: scopedRows.filter((row) => row.inEndingSoon).length,
    excludedByHasWinner: countDistinctGamesWithReason(
      scopedRows,
      (row) =>
        row.newGamesReasons.includes("hasWinner=true") ||
        row.endingSoonReasons.includes("hasWinner=true"),
    ),
    excludedByAnimationId: countDistinctGamesWithReason(
      scopedRows,
      (row) =>
        row.newGamesReasons.includes("player:animationId-non-vide") ||
        row.endingSoonReasons.includes("player:animationId-non-vide"),
    ),
    excludedByDates: countDistinctGamesWithReason(
      scopedRows,
      (row) =>
        row.newGamesReasons.includes("player:date-fin-depassee") ||
        row.newGamesReasons.includes("player:date-debut-future") ||
        row.endingSoonReasons.includes("query:end_date<=now") ||
        row.endingSoonReasons.includes("player:date-debut-future"),
    ),
    excludedByMissingEndDate: countDistinctGamesWithReason(
      scopedRows,
      (row) =>
        row.newGamesReasons.includes("player:end_date-absente") ||
        row.endingSoonReasons.includes("query:end_date-absente"),
    ),
    cumulativeExclusions: scopedRows
      .filter((row) => row.cumulativeReasons.length > 1)
      .map((row) => ({
        id: row.id,
        name: row.name,
        reasons: row.cumulativeReasons,
      })),
    adminOnlineButHiddenForPlayer: scopedRows
      .filter((row) => row.adminOnline && !row.inNewGames && !row.inEndingSoon)
      .map((row) => ({
        id: row.id,
        name: row.name,
        newGamesReasons: row.newGamesReasons,
        endingSoonReasons: row.endingSoonReasons,
      })),
    differencesBetweenAdminAndPlayer: [
      "Admin/commercant actif: end_date >= now et hidden_from_merchant_stats != true.",
      "Accueil joueur nouveautés: hasWinner == false puis exclusion locale animation_id non vide, end_date absente, end_date <= now, start_date future.",
      "Accueil joueur bientôt finis: hasWinner == false, end_date > now puis exclusion locale animation_id non vide et start_date future.",
      "visible_public n'est actuellement pas utilisé par ces requêtes Home joueur.",
      "hasMainPrize n'est actuellement pas utilisé pour filtrer la Home joueur.",
    ],
  };

  console.log("");
  console.log("=== HOME GAMES VISIBILITY AUDIT ===");
  console.log(JSON.stringify(summary, null, 2));
  console.log("");
  console.table(
    scopedRows.map((row) => ({
      id: row.id,
      nom: row.name,
      commerce: row.enseigneName,
      isActive: row.isActive,
      visible_public: row.visiblePublic,
      hasWinner: row.hasWinner,
      hasMainPrize: row.hasMainPrize,
      animationId: row.animationId,
      start_date: row.startDate,
      end_date: row.endDate,
      admin_en_ligne: row.adminOnline ? "oui" : "non",
      nouveautes: row.inNewGames ? "oui" : "non",
      bientot_finis: row.inEndingSoon ? "oui" : "non",
      exclusion_nouveautes: row.newGamesReasons.join(" | "),
      exclusion_bientot_finis: row.endingSoonReasons.join(" | "),
    })),
  );

  if (args.jsonOut) {
    const outputPath = path.resolve(args.jsonOut);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(
      outputPath,
      `${JSON.stringify({ summary, rows: scopedRows }, null, 2)}\n`,
      "utf8",
    );
    console.log(`[audit_home_games_visibility] json written to ${outputPath}`);
  }

  if (args.csvOut) {
    const outputPath = path.resolve(args.csvOut);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    const headers = [
      "id",
      "nom",
      "commerce",
      "isActive",
      "visible_public",
      "hasWinner",
      "hasMainPrize",
      "animationId",
      "start_date",
      "end_date",
      "admin_en_ligne",
      "nouveautes",
      "bientot_finis",
      "exclusion_nouveautes",
      "exclusion_bientot_finis",
    ];
    const lines = [
      headers.join(","),
      ...scopedRows.map((row) =>
        [
          row.id,
          row.name,
          row.enseigneName,
          row.isActive,
          row.visiblePublic,
          row.hasWinner,
          row.hasMainPrize,
          row.animationId,
          row.startDate,
          row.endDate,
          row.adminOnline ? "oui" : "non",
          row.inNewGames ? "oui" : "non",
          row.inEndingSoon ? "oui" : "non",
          row.newGamesReasons.join(" | "),
          row.endingSoonReasons.join(" | "),
        ].map(csvEscape).join(","),
      ),
    ];
    fs.writeFileSync(outputPath, `${lines.join("\n")}\n`, "utf8");
    console.log(`[audit_home_games_visibility] csv written to ${outputPath}`);
  }
}

main().catch((error) => {
  console.error("[audit_home_games_visibility] failed", error);
  process.exitCode = 1;
});

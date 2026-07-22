#!/usr/bin/env node

const API_KEY = "AIzaSyBmHXWsaD3UDvmYOX3aSFGT-rgf_lrBiQY";
const PROJECT_ID = "proxi-play-odzp2e";
const BASE_URL =
  `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function asQueryString(params) {
  const url = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === "") {
      continue;
    }
    url.set(key, String(value));
  }
  return url.toString();
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${response.statusText}: ${text}`);
  }
  return text ? JSON.parse(text) : {};
}

function parseValue(value) {
  if (!value || typeof value !== "object") return null;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("booleanValue" in value) return value.booleanValue;
  if ("timestampValue" in value) return new Date(value.timestampValue);
  if ("nullValue" in value) return null;
  if ("referenceValue" in value) return value.referenceValue;
  if ("mapValue" in value) {
    const fields = value.mapValue.fields || {};
    return Object.fromEntries(
      Object.entries(fields).map(([k, v]) => [k, parseValue(v)]),
    );
  }
  if ("arrayValue" in value) {
    return (value.arrayValue.values || []).map(parseValue);
  }
  return null;
}

function normalizeDoc(document) {
  const fields = document.fields || {};
  const data = Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, parseValue(value)]),
  );
  const id = document.name.split("/").pop();
  return {
    id,
    raw: data,
    name: typeof data.name === "string" && data.name.trim() ? data.name.trim() :
      typeof data.title === "string" ? data.title.trim() : "",
    hasWinner: data.hasWinner === true,
    hasWinnerMissing: !Object.prototype.hasOwnProperty.call(data, "hasWinner"),
    prohibitedForMinors:
      data.prohibited_for_minors === true ? true :
      data.prohibited_for_minors === false ? false : null,
    prohibitedForMinorsMissing:
      !Object.prototype.hasOwnProperty.call(data, "prohibited_for_minors"),
    prizeValue:
      typeof data.prize_value === "number" && Number.isFinite(data.prize_value)
        ? data.prize_value
        : null,
    prizeValueMissing:
      !Object.prototype.hasOwnProperty.call(data, "prize_value") ||
      !(typeof data.prize_value === "number" && Number.isFinite(data.prize_value)),
    animationId:
      typeof data.animation_id === "string" ? data.animation_id.trim() : "",
    startDate: data.start_date instanceof Date ? data.start_date : null,
    endDate: data.end_date instanceof Date ? data.end_date : null,
    visiblePublic:
      data.visible_public === true ? true :
      data.visible_public === false ? false : null,
    visiblePublicMissing:
      !Object.prototype.hasOwnProperty.call(data, "visible_public"),
    createdTime: data.created_time instanceof Date ? data.created_time : null,
    enseigneName:
      typeof data.enseigne_name === "string" ? data.enseigne_name.trim() : "",
  };
}

async function fetchAllGames() {
  const docs = [];
  let pageToken = "";
  while (true) {
    const qs = asQueryString({
      pageSize: 300,
      pageToken,
      key: API_KEY,
    });
    const payload = await fetchJson(`${BASE_URL}/games?${qs}`);
    docs.push(...(payload.documents || []));
    if (!payload.nextPageToken) {
      break;
    }
    pageToken = payload.nextPageToken;
  }
  return docs.map(normalizeDoc);
}

function fieldFilter(field, op, value) {
  const fieldRef = { fieldPath: field };
  if (typeof value === "boolean") {
    return {
      fieldFilter: {
        field: fieldRef,
        op,
        value: { booleanValue: value },
      },
    };
  }
  if (typeof value === "number") {
    return {
      fieldFilter: {
        field: fieldRef,
        op,
        value: Number.isInteger(value)
          ? { integerValue: String(value) }
          : { doubleValue: value },
      },
    };
  }
  if (value instanceof Date) {
    return {
      fieldFilter: {
        field: fieldRef,
        op,
        value: { timestampValue: value.toISOString() },
      },
    };
  }
  throw new Error(`Unsupported filter value for ${field}`);
}

async function runQuery({ filters, orderBy }) {
  const body = {
    structuredQuery: {
      from: [{ collectionId: "games" }],
      where: filters.length === 1
        ? filters[0]
        : {
            compositeFilter: {
              op: "AND",
              filters,
            },
          },
      orderBy,
      limit: 300,
    },
  };
  const result = await fetchJson(
    `${BASE_URL}:runQuery?key=${API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  return result
    .filter((entry) => entry.document)
    .map((entry) => normalizeDoc(entry.document));
}

function isLocallyVisible(doc, now) {
  const reasons = [];
  if (doc.animationId) reasons.push("excluded_locally_animationId");
  if (!doc.endDate) {
    reasons.push("excluded_locally_missingEndDate");
  } else if (!(doc.endDate.getTime() > now.getTime())) {
    reasons.push("excluded_locally_expired");
  }
  if (doc.startDate && doc.startDate.getTime() > now.getTime()) {
    reasons.push("excluded_locally_startDate");
  }
  if (doc.visiblePublic === false) {
    // Current code does not filter on visible_public. Keep diagnostic explicit.
  }
  return reasons;
}

function getFirestoreReasons(doc, section, branch, now) {
  const reasons = [];
  if (doc.hasWinnerMissing) {
    reasons.push("excluded_by_firestore_hasWinner_missing");
  } else if (doc.hasWinner) {
    reasons.push("excluded_by_firestore_hasWinner_true");
  }

  if (branch === "minor_filtered") {
    if (doc.prohibitedForMinorsMissing) {
      reasons.push("excluded_by_firestore_minor_missing");
    } else if (doc.prohibitedForMinors === true) {
      reasons.push("excluded_by_firestore_minor_true");
    }
  }

  if (branch === "prize_value_filtered" && section === "featured") {
    if (doc.prizeValueMissing) {
      reasons.push("excluded_by_firestore_prize_missing");
    } else if (!(doc.prizeValue > 0)) {
      reasons.push("excluded_by_firestore_prize_zero");
    }
  }

  const orderField = section === "featured"
    ? "prize_value"
    : section === "new"
      ? "created_time"
      : "end_date";
  const hasOrderField =
    orderField === "prize_value" ? !doc.prizeValueMissing :
    orderField === "created_time" ? !!doc.createdTime :
    !!doc.endDate;
  if (!hasOrderField) {
    reasons.push(`excluded_by_firestore_${orderField}_missing`);
  }

  if (section === "endingSoon") {
    if (!doc.endDate) {
      reasons.push("excluded_by_firestore_endDate");
    } else if (!(doc.endDate.getTime() > now.getTime())) {
      reasons.push("excluded_by_firestore_endDate");
    }
  }

  return Array.from(new Set(reasons));
}

function evaluateSection(doc, section, branch, now) {
  const firestoreReasons = getFirestoreReasons(doc, section, branch, now);
  const localReasons = firestoreReasons.length === 0 ? isLocallyVisible(doc, now) : [];
  const reasons = [...firestoreReasons, ...localReasons];
  return {
    eligible: reasons.length === 0,
    firestoreReasons,
    localReasons,
    reasons,
  };
}

function summarize(sectionName, branchName, candidateRows, actualFirestoreRows, now) {
  const total = candidateRows.length;
  const actualCount = actualFirestoreRows.length;
  const firestoreExcluded = candidateRows.filter(
    (row) => row[sectionName].firestoreReasons.length > 0,
  );
  const simulatedLocalExcluded = candidateRows.filter(
    (row) =>
      row[sectionName].firestoreReasons.length === 0 &&
      row[sectionName].localReasons.length > 0,
  );
  const simulatedDisplayed = candidateRows.filter(
    (row) => row[sectionName].eligible,
  ).length;

  const actualLocalReasonCounts = {};
  const actuallyDisplayedRows = [];
  const actuallyLocallyExcludedRows = [];
  for (const doc of actualFirestoreRows) {
    const localReasons = isLocallyVisible(doc, now);
    if (localReasons.length === 0) {
      actuallyDisplayedRows.push(doc);
    } else {
      actuallyLocallyExcludedRows.push({
        id: doc.id,
        name: doc.name,
        reasons: localReasons,
      });
      for (const reason of localReasons) {
        actualLocalReasonCounts[reason] = (actualLocalReasonCounts[reason] || 0) + 1;
      }
    }
  }

  const countByReason = {};
  for (const row of candidateRows) {
    for (const reason of row[sectionName].reasons) {
      countByReason[reason] = (countByReason[reason] || 0) + 1;
    }
  }

  return {
    branch: branchName,
    section: sectionName,
    totalCandidates: total,
    firestoreReturned: actualCount,
    firestoreExcluded: firestoreExcluded.length,
    localExcluded: actuallyLocallyExcludedRows.length,
    widgetInput: actuallyDisplayedRows.length,
    rendered: actuallyDisplayedRows.length,
    simulatedLocalExcluded: simulatedLocalExcluded.length,
    simulatedDisplayed,
    reasonCounts: countByReason,
    actualLocalReasonCounts,
    actualReturnedIds: actualFirestoreRows.map((doc) => doc.id),
    actualDisplayedIds: actuallyDisplayedRows.map((doc) => doc.id),
    actualLocalExclusions: actuallyLocallyExcludedRows,
  };
}

function printMath(summary) {
  console.log("");
  console.log(summary.section.toUpperCase());
  console.log(`total candidates = ${summary.totalCandidates}`);
  for (const [reason, count] of Object.entries(summary.reasonCounts).sort()) {
    console.log(`- ${reason} = ${count}`);
  }
  console.log(`= firestore returned = ${summary.firestoreReturned}`);
  for (const [reason, count] of Object.entries(summary.actualLocalReasonCounts).sort()) {
    console.log(`- actual_local_${reason} = ${count}`);
  }
  console.log(`= simulated displayed = ${summary.simulatedDisplayed}`);
  console.log(`= displayed = ${summary.rendered}`);
  console.log(
    `[ACTUAL IDS] section=${summary.section} returned=${summary.actualReturnedIds.join(",")}`,
  );
  console.log(
    `[DISPLAYED IDS] section=${summary.section} displayed=${summary.actualDisplayedIds.join(",")}`,
  );
  for (const exclusion of summary.actualLocalExclusions) {
    console.log(
      `[LOCAL EXCLUDED] section=${summary.section} id=${exclusion.id} name=${exclusion.name} reasons=${exclusion.reasons.join("|")}`,
    );
  }
}

async function main() {
  const now = new Date();
  const allDocs = await fetchAllGames();
  const branches = {
    adult_standard: {
      featured: {
        filters: [fieldFilter("hasWinner", "EQUAL", false)],
        orderBy: [{ field: { fieldPath: "prize_value" }, direction: "DESCENDING" }],
      },
      new: {
        filters: [fieldFilter("hasWinner", "EQUAL", false)],
        orderBy: [{ field: { fieldPath: "created_time" }, direction: "DESCENDING" }],
      },
      endingSoon: {
        filters: [
          fieldFilter("hasWinner", "EQUAL", false),
          fieldFilter("end_date", "GREATER_THAN", now),
        ],
        orderBy: [{ field: { fieldPath: "end_date" }, direction: "ASCENDING" }],
      },
    },
    minor_filtered: {
      featured: {
        filters: [
          fieldFilter("hasWinner", "EQUAL", false),
          fieldFilter("prohibited_for_minors", "EQUAL", false),
        ],
        orderBy: [{ field: { fieldPath: "prize_value" }, direction: "DESCENDING" }],
      },
      new: {
        filters: [
          fieldFilter("hasWinner", "EQUAL", false),
          fieldFilter("prohibited_for_minors", "EQUAL", false),
        ],
        orderBy: [{ field: { fieldPath: "created_time" }, direction: "DESCENDING" }],
      },
      endingSoon: {
        filters: [
          fieldFilter("hasWinner", "EQUAL", false),
          fieldFilter("prohibited_for_minors", "EQUAL", false),
          fieldFilter("end_date", "GREATER_THAN", now),
        ],
        orderBy: [{ field: { fieldPath: "end_date" }, direction: "ASCENDING" }],
      },
    },
    prize_value_filtered: {
      featured: {
        filters: [
          fieldFilter("hasWinner", "EQUAL", false),
          fieldFilter("prize_value", "GREATER_THAN", 0),
        ],
        orderBy: [{ field: { fieldPath: "prize_value" }, direction: "DESCENDING" }],
      },
      new: {
        filters: [fieldFilter("hasWinner", "EQUAL", false)],
        orderBy: [{ field: { fieldPath: "created_time" }, direction: "DESCENDING" }],
      },
      endingSoon: {
        filters: [
          fieldFilter("hasWinner", "EQUAL", false),
          fieldFilter("end_date", "GREATER_THAN", now),
        ],
        orderBy: [{ field: { fieldPath: "end_date" }, direction: "ASCENDING" }],
      },
    },
  };

  console.log(`[WITNESS] totalGamesFetched=${allDocs.length}`);
  console.log(
    `[WITNESS] activeCandidates(end_date>now)=${
      allDocs.filter((doc) => doc.endDate && doc.endDate.getTime() > now.getTime()).length
    }`,
  );

  for (const [branchName, sections] of Object.entries(branches)) {
    console.log("");
    console.log(`=== BRANCH ${branchName} ===`);

    const rows = allDocs.map((doc) => {
      const featured = evaluateSection(doc, "featured", branchName, now);
      const fresh = evaluateSection(doc, "new", branchName, now);
      const endingSoon = evaluateSection(doc, "endingSoon", branchName, now);
      return {
        id: doc.id,
        name: doc.name,
        hasWinner: doc.hasWinner,
        hasWinnerMissing: doc.hasWinnerMissing,
        prohibitedForMinors: doc.prohibitedForMinors,
        prohibitedForMinorsMissing: doc.prohibitedForMinorsMissing,
        prizeValue: doc.prizeValue,
        prizeValueMissing: doc.prizeValueMissing,
        animationId: doc.animationId,
        startDate: doc.startDate ? doc.startDate.toISOString() : "",
        endDate: doc.endDate ? doc.endDate.toISOString() : "",
        visiblePublic: doc.visiblePublic,
        featured,
        new: fresh,
        endingSoon,
      };
    });

    const firestoreFeatured = await runQuery(sections.featured);
    const firestoreNew = await runQuery(sections.new);
    const firestoreEndingSoon = await runQuery(sections.endingSoon);

    console.table(
      rows.map((row) => ({
        id: row.id,
        name: row.name,
        hasWinner: row.hasWinner,
        hasWinnerMissing: row.hasWinnerMissing,
        prohibitedForMinors: row.prohibitedForMinors,
        prohibitedForMinorsMissing: row.prohibitedForMinorsMissing,
        prizeValue: row.prizeValue,
        prizeValueMissing: row.prizeValueMissing,
        animationId: row.animationId,
        startDate: row.startDate,
        endDate: row.endDate,
        visiblePublic: row.visiblePublic,
        featuredEligible: row.featured.eligible,
        featuredReasons: row.featured.reasons.join(" | "),
        newEligible: row.new.eligible,
        newReasons: row.new.reasons.join(" | "),
        endingSoonEligible: row.endingSoon.eligible,
        endingSoonReasons: row.endingSoon.reasons.join(" | "),
      })),
    );

    const featuredSummary = summarize(
      "featured",
      branchName,
      rows,
      firestoreFeatured,
      now,
    );
    const newSummary = summarize("new", branchName, rows, firestoreNew, now);
    const endingSummary = summarize(
      "endingSoon",
      branchName,
      rows,
      firestoreEndingSoon,
      now,
    );

    printMath(featuredSummary);
    printMath(newSummary);
    printMath(endingSummary);

    const tuple = `${featuredSummary.rendered}/${newSummary.rendered}/${endingSummary.rendered}`;
    console.log(`[BRANCH RESULT] ${branchName} => featured/new/endingSoon = ${tuple}`);
    if (tuple === "8/9/10") {
      console.log(`[MATCH OBSERVED] branch=${branchName}`);
    }
  }
}

main().catch((error) => {
  console.error("[audit_home_sections_rest] failed", error);
  process.exitCode = 1;
});

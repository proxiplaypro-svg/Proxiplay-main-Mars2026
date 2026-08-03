"use strict";

const crypto = require("crypto");

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeInteger(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(getTrimmedString(value), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function toMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function expandSecondaryPrizes(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  const expanded = [];
  value.forEach((entry, sourceIndex) => {
    if (!entry || typeof entry !== "object") {
      return;
    }

    const name = getTrimmedString(entry.name);
    const presentation = getTrimmedString(
      entry.presentation || entry.description,
    );
    const count = normalizeInteger(entry.count) || 0;

    if (count <= 0) {
      return;
    }

    for (let occurrenceIndex = 0; occurrenceIndex < count; occurrenceIndex += 1) {
      expanded.push({
        sourceIndex,
        occurrenceIndex,
        name,
        presentation,
      });
    }
  });

  return expanded;
}

function secureRandomUnit() {
  const upperBoundExclusive = 0x100000000;
  const randomInt = crypto.randomInt(upperBoundExclusive);
  return randomInt / upperBoundExclusive;
}

function validateInstantWinnerWindow(startDateMs, endDateMs) {
  if (!Number.isFinite(startDateMs) || !Number.isFinite(endDateMs)) {
    throw new Error("Instant winners require valid start and end dates.");
  }
  if (startDateMs > endDateMs) {
    throw new Error("Instant winners require startDate <= endDate.");
  }
}

function buildOccurrenceKey({
  secondary_prize_index,
  secondary_prize_occurrence_index,
}) {
  return `${secondary_prize_index}:${secondary_prize_occurrence_index}`;
}

function buildInstantWinnerDocId({
  gameId,
  secondary_prize_index,
  secondary_prize_occurrence_index,
}) {
  const normalizedGameId = getTrimmedString(gameId).replace(/[^A-Za-z0-9_-]/g, "_");
  return `instant_${normalizedGameId}_spi_${secondary_prize_index}_occ_${secondary_prize_occurrence_index}`;
}

function generateWinningInstantMillis({
  startDateMs,
  endDateMs,
  randomUnit = secureRandomUnit,
}) {
  validateInstantWinnerWindow(startDateMs, endDateMs);
  const durationMs = endDateMs - startDateMs;
  if (durationMs === 0) {
    return startDateMs;
  }
  const ratio = Math.min(1, Math.max(0, Number(randomUnit())));
  return startDateMs + Math.floor(ratio * (durationMs + 1));
}

function buildInstantWinnerPayloads({
  startDateMs,
  endDateMs,
  secondaryPrizes,
  randomUnit = secureRandomUnit,
}) {
  validateInstantWinnerWindow(startDateMs, endDateMs);
  const expandedSecondaryPrizes = expandSecondaryPrizes(secondaryPrizes);

  return expandedSecondaryPrizes.map((prize) => ({
    dateMs: generateWinningInstantMillis({
      startDateMs,
      endDateMs,
      randomUnit,
    }),
    secondary_prize_index: prize.sourceIndex,
    secondary_prize_occurrence_index: prize.occurrenceIndex,
    secondary_prize_name: prize.name,
    ...(prize.presentation
      ? {secondary_prize_presentation: prize.presentation}
      : {}),
  }));
}

function planInstantWinnerReconciliation({
  gameId,
  startDateMs,
  endDateMs,
  secondaryPrizes,
  existingEntries = [],
  randomUnit = secureRandomUnit,
}) {
  const payloads = buildInstantWinnerPayloads({
    startDateMs,
    endDateMs,
    secondaryPrizes,
    randomUnit,
  });
  const existingByKey = new Map();
  const duplicateExistingByKey = new Map();

  existingEntries.forEach((entry) => {
    if (!entry || typeof entry !== "object") {
      return;
    }
    const key = buildOccurrenceKey(entry);
    if (existingByKey.has(key)) {
      const duplicates = duplicateExistingByKey.get(key) || [];
      duplicates.push(entry);
      duplicateExistingByKey.set(key, duplicates);
      return;
    }
    existingByKey.set(key, entry);
  });

  const missingPayloads = [];
  const preservedEntries = [];
  const desiredKeys = new Set();

  payloads.forEach((payload) => {
    const key = buildOccurrenceKey(payload);
    desiredKeys.add(key);
    const existingEntry = existingByKey.get(key);
    if (existingEntry) {
      preservedEntries.push(existingEntry);
      return;
    }

    missingPayloads.push({
      docId: buildInstantWinnerDocId({
        gameId,
        secondary_prize_index: payload.secondary_prize_index,
        secondary_prize_occurrence_index:
          payload.secondary_prize_occurrence_index,
      }),
      payload,
    });
  });

  const unexpectedExistingEntries = existingEntries.filter((entry) => {
    if (!entry || typeof entry !== "object") {
      return false;
    }
    return !desiredKeys.has(buildOccurrenceKey(entry));
  });

  return {
    desiredCount: payloads.length,
    existingCount: existingEntries.length,
    preservedEntries,
    missingPayloads,
    duplicateExistingKeys: Array.from(duplicateExistingByKey.keys()),
    unexpectedExistingEntries,
  };
}

function pickDueInstantWinner(dueDocs, randomInt = crypto.randomInt) {
  if (!Array.isArray(dueDocs) || dueDocs.length === 0) {
    return {
      selected: null,
      remaining: [],
    };
  }

  const selectedIndex =
    dueDocs.length === 1 ? 0 : randomInt(0, dueDocs.length);

  return {
    selected: dueDocs[selectedIndex],
    remaining: dueDocs.filter((_, index) => index !== selectedIndex),
  };
}

module.exports = {
  buildInstantWinnerDocId,
  buildInstantWinnerPayloads,
  buildOccurrenceKey,
  expandSecondaryPrizes,
  generateWinningInstantMillis,
  planInstantWinnerReconciliation,
  pickDueInstantWinner,
  secureRandomUnit,
  toMillis,
  validateInstantWinnerWindow,
};

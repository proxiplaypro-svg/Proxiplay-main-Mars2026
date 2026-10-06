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

function buildInstantWinnerConfigurationFingerprint({
  startDateMs,
  endDateMs,
  secondaryPrizes,
}) {
  // The index and occurrence number are part of the public identity of an
  // instant winner. Keep the ordered, expanded configuration in the
  // fingerprint so a reorder, a quantity change, or a text/date change is a
  // real reconciliation event rather than an invisible partial update.
  const canonicalConfiguration = JSON.stringify({
    startDateMs,
    endDateMs,
    occurrences: expandSecondaryPrizes(secondaryPrizes).map((prize) => ({
      index: prize.sourceIndex,
      occurrence: prize.occurrenceIndex,
      name: prize.name,
      presentation: prize.presentation,
    })),
  });

  return crypto.createHash("sha256").update(canonicalConfiguration).digest("hex");
}

function isAssignedInstantWinner(entry) {
  return entry?.hasWinner === true || entry?.claimed === true || !!entry?.player_id;
}

function hasSameOptionalPresentation(entry, payload) {
  return getTrimmedString(entry?.secondary_prize_presentation) ===
    getTrimmedString(payload?.secondary_prize_presentation);
}

function planInstantWinnerReconciliation({
  gameId,
  startDateMs,
  endDateMs,
  secondaryPrizes,
  existingEntries = [],
  randomUnit = secureRandomUnit,
  nowMs = null,
}) {
  validateInstantWinnerWindow(startDateMs, endDateMs);
  const effectiveStartDateMs = Number.isFinite(nowMs)
    ? Math.max(startDateMs, nowMs)
    : startDateMs;

  // An instant at exactly "now" is already unusable by the time the player
  // receives the calendar. The callable passes its server clock here.
  if (Number.isFinite(nowMs) && effectiveStartDateMs >= endDateMs) {
    throw new Error("Instant winners require a future scheduling window.");
  }

  const configurationFingerprint = buildInstantWinnerConfigurationFingerprint({
    startDateMs,
    endDateMs,
    secondaryPrizes,
  });
  const payloads = buildInstantWinnerPayloads({
    startDateMs: effectiveStartDateMs,
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
  const replacementPayloads = [];
  const preservedEntries = [];
  const staleTextEntries = [];
  const deleteEntries = [];
  const assignedConflicts = [];
  const desiredKeys = new Set();

  payloads.forEach((payload) => {
    const key = buildOccurrenceKey(payload);
    desiredKeys.add(key);
    const existingEntry = existingByKey.get(key);
    if (existingEntry) {
      if (isAssignedInstantWinner(existingEntry)) {
        // A won/claimed occurrence is historical evidence. Its date and
        // snapshot cannot be rewritten; a reordered prize at the same index
        // would otherwise silently turn that evidence into another prize.
        const conflictsWithCurrentPrize =
          getTrimmedString(existingEntry.secondary_prize_name) !== payload.secondary_prize_name ||
          !hasSameOptionalPresentation(existingEntry, payload);
        if (conflictsWithCurrentPrize) {
          assignedConflicts.push(existingEntry);
        }
        // Preserve it even when it no longer represents the current
        // configuration. Historical attribution wins over configuration;
        // callers receive assignedConflicts for an explicit audit signal.
        preservedEntries.push(existingEntry);
        return;
      }

      const existingDateMs = toMillis(existingEntry.date ?? existingEntry.dateMs);
      const isCurrentConfiguration =
        existingEntry.configuration_fingerprint === configurationFingerprint &&
        Number.isFinite(existingDateMs) &&
        existingDateMs >= effectiveStartDateMs &&
        existingDateMs <= endDateMs &&
        getTrimmedString(existingEntry.secondary_prize_name) === payload.secondary_prize_name &&
        hasSameOptionalPresentation(existingEntry, payload);

      if (isCurrentConfiguration) {
        preservedEntries.push(existingEntry);
        return;
      }

      const nameChanged =
        getTrimmedString(existingEntry.secondary_prize_name) !== payload.secondary_prize_name;
      const presentationChanged = !hasSameOptionalPresentation(existingEntry, payload);
      if (nameChanged || presentationChanged) {
        // Kept for diagnostics and backwards-compatible callers. The callable
        // replaces the full non-assigned occurrence, including its date.
        staleTextEntries.push({
          docId: existingEntry.id,
          patch: {
            secondary_prize_name: payload.secondary_prize_name,
            ...(payload.secondary_prize_presentation
              ? {secondary_prize_presentation: payload.secondary_prize_presentation}
              : {}),
          },
        });
      }
      replacementPayloads.push({
        docId: buildInstantWinnerDocId({gameId, ...payload}),
        previousDocId: existingEntry.id,
        payload,
      });
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

  existingEntries.forEach((entry) => {
    if (!entry || typeof entry !== "object") return;
    const key = buildOccurrenceKey(entry);
    const isPrimaryEntry = existingByKey.get(key) === entry;
    if ((!desiredKeys.has(key) || !isPrimaryEntry) && !isAssignedInstantWinner(entry)) {
      deleteEntries.push(entry);
    }
    if (!desiredKeys.has(key) && isAssignedInstantWinner(entry)) assignedConflicts.push(entry);
  });

  return {
    desiredCount: payloads.length,
    existingCount: existingEntries.length,
    effectiveStartDateMs,
    configurationFingerprint,
    preservedEntries,
    missingPayloads,
    replacementPayloads,
    deleteEntries,
    assignedConflicts,
    staleTextEntries,
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
  buildInstantWinnerConfigurationFingerprint,
  buildInstantWinnerPayloads,
  buildOccurrenceKey,
  expandSecondaryPrizes,
  generateWinningInstantMillis,
  isAssignedInstantWinner,
  planInstantWinnerReconciliation,
  pickDueInstantWinner,
  secureRandomUnit,
  toMillis,
  validateInstantWinnerWindow,
};

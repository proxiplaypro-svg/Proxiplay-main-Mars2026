"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  buildInstantWinnerDocId,
  buildInstantWinnerConfigurationFingerprint,
  buildInstantWinnerPayloads,
  buildOccurrenceKey,
  expandSecondaryPrizes,
  generateWinningInstantMillis,
  planInstantWinnerReconciliation,
  pickDueInstantWinner,
} = require("../lib/instant_winners_core");

function persistedEntriesFromPlan(plan) {
  return [...plan.missingPayloads, ...(plan.replacementPayloads || [])].map(({docId, payload}) => ({
    id: docId,
    dateMs: payload.dateMs,
    hasWinner: false,
    claimed: false,
    configuration_fingerprint: plan.configurationFingerprint,
    secondary_prize_index: payload.secondary_prize_index,
    secondary_prize_occurrence_index: payload.secondary_prize_occurrence_index,
    secondary_prize_name: payload.secondary_prize_name,
    ...(payload.secondary_prize_presentation
      ? {secondary_prize_presentation: payload.secondary_prize_presentation}
      : {}),
  }));
}

test("each secondary prize occurrence receives an instant", () => {
  const payloads = buildInstantWinnerPayloads({
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [
      {name: "Lot A", count: 2},
      {name: "Lot B", count: 3},
    ],
    randomUnit: () => 0.5,
  });

  assert.equal(payloads.length, 5);
});

test("all instants stay within start and end bounds", () => {
  const payloads = buildInstantWinnerPayloads({
    startDateMs: 100,
    endDateMs: 200,
    secondaryPrizes: [{name: "Lot A", count: 4}],
    randomUnit: () => 0.999999,
  });

  payloads.forEach((payload) => {
    assert.ok(payload.dateMs >= 100);
    assert.ok(payload.dateMs <= 200);
  });
});

test("multiple prize occurrences use independent draws", () => {
  const sequence = [0.1, 0.9, 0.2, 0.8];
  let cursor = 0;
  const payloads = buildInstantWinnerPayloads({
    startDateMs: 0,
    endDateMs: 100,
    secondaryPrizes: [{name: "Lot A", count: 4}],
    randomUnit: () => sequence[cursor++],
  });

  assert.deepEqual(
    payloads.map((payload) => payload.dateMs),
    [10, 90, 20, 80],
  );
});

test("prize order does not change the generated instant multiset", () => {
  const sequence = [0.2, 0.4, 0.6, 0.8];
  let cursorA = 0;
  let cursorB = 0;
  const configA = [
    {name: "Lot A", count: 1},
    {name: "Lot B", count: 3},
  ];
  const configB = [
    {name: "Lot B", count: 3},
    {name: "Lot A", count: 1},
  ];

  const payloadsA = buildInstantWinnerPayloads({
    startDateMs: 0,
    endDateMs: 100,
    secondaryPrizes: configA,
    randomUnit: () => sequence[cursorA++],
  });
  const payloadsB = buildInstantWinnerPayloads({
    startDateMs: 0,
    endDateMs: 100,
    secondaryPrizes: configB,
    randomUnit: () => sequence[cursorB++],
  });

  assert.deepEqual(
    payloadsA.map((payload) => payload.dateMs).sort((a, b) => a - b),
    payloadsB.map((payload) => payload.dateMs).sort((a, b) => a - b),
  );
});

test("already won entries are not reselected", () => {
  const dueDocs = [{id: "open-1"}, {id: "open-2"}];
  const selection = pickDueInstantWinner(dueDocs, () => 0);
  const nextSelection = pickDueInstantWinner(selection.remaining, () => 0);

  assert.equal(selection.selected.id, "open-1");
  assert.equal(nextSelection.selected.id, "open-2");
});

test("simultaneous collision keeps one due lot available for next play", () => {
  const dueDocs = [{id: "a"}, {id: "b"}];
  const selection = pickDueInstantWinner(dueDocs, () => 1);

  assert.equal(selection.selected.id, "b");
  assert.deepEqual(selection.remaining.map((doc) => doc.id), ["a"]);
});

test("non-selected due lots remain available when five or ten instants are due", () => {
  const fiveDueDocs = Array.from({length: 5}, (_, index) => ({id: `five-${index}`}));
  const fiveSelection = pickDueInstantWinner(fiveDueDocs, () => 3);
  const tenDueDocs = Array.from({length: 10}, (_, index) => ({id: `ten-${index}`}));
  const tenSelection = pickDueInstantWinner(tenDueDocs, () => 7);

  assert.equal(fiveSelection.selected.id, "five-3");
  assert.equal(fiveSelection.remaining.length, 4);
  assert.deepEqual(
    fiveSelection.remaining.map((doc) => doc.id),
    ["five-0", "five-1", "five-2", "five-4"],
  );

  assert.equal(tenSelection.selected.id, "ten-7");
  assert.equal(tenSelection.remaining.length, 9);
  assert.ok(!tenSelection.remaining.some((doc) => doc.id === "ten-7"));
});

test("very short games still generate a valid instant", () => {
  const dateMs = generateWinningInstantMillis({
    startDateMs: 1000,
    endDateMs: 1000,
    randomUnit: () => 0.42,
  });

  assert.equal(dateMs, 1000);
});

test("due instant winner selection is uniform for two simultaneous due lots", () => {
  const dueDocs = [{id: "a"}, {id: "b"}];
  const counts = {a: 0, b: 0};
  const iterations = 20000;

  for (let index = 0; index < iterations; index += 1) {
    const selection = pickDueInstantWinner(dueDocs);
    counts[selection.selected.id] += 1;
  }

  Object.values(counts).forEach((count) => {
    const delta = Math.abs(count - iterations / 2);
    assert.ok(delta < iterations * 0.03, `count=${count} delta=${delta}`);
  });
});

test("due instant winner selection is uniform for five simultaneous due lots", () => {
  const dueDocs = Array.from({length: 5}, (_, index) => ({id: `doc-${index}`}));
  const counts = Object.fromEntries(dueDocs.map((doc) => [doc.id, 0]));
  const iterations = 50000;

  for (let index = 0; index < iterations; index += 1) {
    const selection = pickDueInstantWinner(dueDocs);
    counts[selection.selected.id] += 1;
  }

  Object.values(counts).forEach((count) => {
    const delta = Math.abs(count - iterations / dueDocs.length);
    assert.ok(delta < iterations * 0.02, `count=${count} delta=${delta}`);
  });
});

test("due instant winner selection is uniform for ten simultaneous due lots", () => {
  const dueDocs = Array.from({length: 10}, (_, index) => ({id: `doc-${index}`}));
  const counts = Object.fromEntries(dueDocs.map((doc) => [doc.id, 0]));
  const iterations = 100000;

  for (let index = 0; index < iterations; index += 1) {
    const selection = pickDueInstantWinner(dueDocs);
    counts[selection.selected.id] += 1;
  }

  Object.values(counts).forEach((count) => {
    const delta = Math.abs(count - iterations / dueDocs.length);
    assert.ok(delta < iterations * 0.01, `count=${count} delta=${delta}`);
  });
});

test("DST boundary is handled in absolute UTC milliseconds", () => {
  const startDateMs = Date.parse("2026-03-29T00:30:00.000Z");
  const endDateMs = Date.parse("2026-03-29T03:30:00.000Z");
  const payloads = buildInstantWinnerPayloads({
    startDateMs,
    endDateMs,
    secondaryPrizes: [{name: "Lot A", count: 3}],
    randomUnit: () => 0.5,
  });

  payloads.forEach((payload) => {
    assert.ok(payload.dateMs >= startDateMs);
    assert.ok(payload.dateMs <= endDateMs);
  });
});

test("secondary prizes are expanded per occurrence", () => {
  const expanded = expandSecondaryPrizes([
    {name: "Lot A", count: 2},
    {name: "Lot B", count: "1"},
  ]);

  assert.deepEqual(
    expanded.map((entry) => `${entry.sourceIndex}:${entry.occurrenceIndex}`),
    ["0:0", "0:1", "1:0"],
  );
});

test("deterministic doc id is stable per game and occurrence", () => {
  const docId = buildInstantWinnerDocId({
    gameId: "game-123",
    secondary_prize_index: 4,
    secondary_prize_occurrence_index: 2,
  });

  assert.equal(docId, "instant_game-123_spi_4_occ_2");
});

test("partial generation preserves existing instants and creates only missing occurrences", () => {
  const configurationFingerprint = buildInstantWinnerConfigurationFingerprint({
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [{name: "Lot A", count: 4}],
  });
  const existingEntries = [
    {
      id: "instant_game-1_spi_0_occ_0",
      secondary_prize_index: 0,
      secondary_prize_occurrence_index: 0,
      dateMs: 111,
      configuration_fingerprint: configurationFingerprint,
      secondary_prize_name: "Lot A",
    },
    {
      id: "instant_game-1_spi_0_occ_1",
      secondary_prize_index: 0,
      secondary_prize_occurrence_index: 1,
      dateMs: 222,
      configuration_fingerprint: configurationFingerprint,
      secondary_prize_name: "Lot A",
    },
  ];

  const plan = planInstantWinnerReconciliation({
    gameId: "game-1",
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [{name: "Lot A", count: 4}],
    existingEntries,
    randomUnit: () => 0.5,
  });

  assert.equal(plan.desiredCount, 4);
  assert.equal(plan.preservedEntries.length, 2);
  assert.deepEqual(
    plan.preservedEntries.map((entry) => entry.dateMs),
    [111, 222],
  );
  assert.deepEqual(
    plan.missingPayloads.map((entry) => entry.docId),
    [
      "instant_game-1_spi_0_occ_2",
      "instant_game-1_spi_0_occ_3",
    ],
  );
});

test("retry after partial generation produces the same missing doc ids without duplicates", () => {
  const existingEntries = [
    {
      id: "instant_game-2_spi_0_occ_0",
      secondary_prize_index: 0,
      secondary_prize_occurrence_index: 0,
      dateMs: 10,
    },
  ];

  const firstPlan = planInstantWinnerReconciliation({
    gameId: "game-2",
    startDateMs: 0,
    endDateMs: 100,
    secondaryPrizes: [{name: "Lot A", count: 3}],
    existingEntries,
    randomUnit: () => 0.25,
  });
  const secondPlan = planInstantWinnerReconciliation({
    gameId: "game-2",
    startDateMs: 0,
    endDateMs: 100,
    secondaryPrizes: [{name: "Lot A", count: 3}],
    existingEntries,
    randomUnit: () => 0.75,
  });

  assert.deepEqual(
    firstPlan.missingPayloads.map((entry) => entry.docId),
    secondPlan.missingPayloads.map((entry) => entry.docId),
  );
  assert.equal(new Set(firstPlan.missingPayloads.map((entry) => entry.docId)).size, 2);
});

test("simultaneous generation attempts converge on the same missing occurrence ids", () => {
  const planA = planInstantWinnerReconciliation({
    gameId: "game-3",
    startDateMs: 0,
    endDateMs: 100,
    secondaryPrizes: [{name: "Lot A", count: 2}, {name: "Lot B", count: 1}],
    existingEntries: [],
    randomUnit: () => 0.5,
  });
  const planB = planInstantWinnerReconciliation({
    gameId: "game-3",
    startDateMs: 0,
    endDateMs: 100,
    secondaryPrizes: [{name: "Lot A", count: 2}, {name: "Lot B", count: 1}],
    existingEntries: [],
    randomUnit: () => 0.9,
  });

  assert.deepEqual(
    planA.missingPayloads.map((entry) => entry.docId).sort(),
    planB.missingPayloads.map((entry) => entry.docId).sort(),
  );
});

test("quantity increase before game start adds only newly missing occurrences", () => {
  const configurationFingerprint = buildInstantWinnerConfigurationFingerprint({
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [{name: "Lot A", count: 3}],
  });
  const existingEntries = [
    {
      id: "instant_game-4_spi_0_occ_0",
      secondary_prize_index: 0,
      secondary_prize_occurrence_index: 0,
      dateMs: 100,
      configuration_fingerprint: configurationFingerprint,
      secondary_prize_name: "Lot A",
    },
  ];

  const plan = planInstantWinnerReconciliation({
    gameId: "game-4",
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [{name: "Lot A", count: 3}],
    existingEntries,
    randomUnit: () => 0.1,
  });

  assert.deepEqual(
    plan.missingPayloads.map((entry) => buildOccurrenceKey(entry.payload)),
    ["0:1", "0:2"],
  );
  assert.equal(plan.preservedEntries[0].dateMs, 100);
});

test("edited prize text refreshes an unwon existing occurrence", () => {
  const existingEntries = [
    {
      id: "instant_game-5_spi_0_occ_0",
      secondary_prize_index: 0,
      secondary_prize_occurrence_index: 0,
      dateMs: 100,
      hasWinner: false,
      secondary_prize_name: "Dessert offert*",
      secondary_prize_presentation: "A utiliser jusqu'au 30 juin 3026",
    },
  ];

  const plan = planInstantWinnerReconciliation({
    gameId: "game-5",
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [
      {
        name: "Dessert offert*",
        count: 1,
        description: "A utiliser jusqu'au 27 Aout 2026",
      },
    ],
    existingEntries,
    randomUnit: () => 0.1,
  });

  assert.equal(plan.missingPayloads.length, 0);
  assert.deepEqual(plan.staleTextEntries, [
    {
      docId: "instant_game-5_spi_0_occ_0",
      patch: {
        secondary_prize_name: "Dessert offert*",
        secondary_prize_presentation: "A utiliser jusqu'au 27 Aout 2026",
      },
    },
  ]);
});

test("an already-won occurrence keeps its original text even if the game prize text changes", () => {
  const existingEntries = [
    {
      id: "instant_game-6_spi_0_occ_0",
      secondary_prize_index: 0,
      secondary_prize_occurrence_index: 0,
      dateMs: 100,
      hasWinner: true,
      player_id: "player-abc",
      secondary_prize_name: "Dessert offert*",
      secondary_prize_presentation: "A utiliser jusqu'au 30 juin 3026",
    },
  ];

  const plan = planInstantWinnerReconciliation({
    gameId: "game-6",
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [
      {
        name: "Dessert offert*",
        count: 1,
        description: "A utiliser jusqu'au 27 Aout 2026",
      },
    ],
    existingEntries,
    randomUnit: () => 0.1,
  });

  assert.equal(plan.staleTextEntries.length, 0);
});

test("unchanged prize text does not produce a stale entry", () => {
  const existingEntries = [
    {
      id: "instant_game-7_spi_0_occ_0",
      secondary_prize_index: 0,
      secondary_prize_occurrence_index: 0,
      dateMs: 100,
      hasWinner: false,
      secondary_prize_name: "Dessert offert*",
      secondary_prize_presentation: "A utiliser jusqu'au 27 Aout 2026",
    },
  ];

  const plan = planInstantWinnerReconciliation({
    gameId: "game-7",
    startDateMs: 0,
    endDateMs: 1000,
    secondaryPrizes: [
      {
        name: "Dessert offert*",
        count: 1,
        description: "A utiliser jusqu'au 27 Aout 2026",
      },
    ],
    existingEntries,
    randomUnit: () => 0.1,
  });

  assert.equal(plan.staleTextEntries.length, 0);
});

test("first generation schedules every occurrence from the current future window", () => {
  const plan = planInstantWinnerReconciliation({
    gameId: "first-generation",
    startDateMs: 100,
    endDateMs: 1000,
    nowMs: 200,
    secondaryPrizes: [{name: "Lot", count: 2}],
    randomUnit: () => 0,
  });
  assert.equal(plan.missingPayloads.length, 2);
  plan.missingPayloads.forEach(({payload}) => assert.equal(payload.dateMs, 200));
});

test("unchanged regeneration is idempotent", () => {
  const initial = planInstantWinnerReconciliation({
    gameId: "idempotent", startDateMs: 100, endDateMs: 1000, nowMs: 100,
    secondaryPrizes: [{name: "Lot", description: "Texte", count: 2}], randomUnit: () => 0.5,
  });
  const retry = planInstantWinnerReconciliation({
    gameId: "idempotent", startDateMs: 100, endDateMs: 1000, nowMs: 100,
    secondaryPrizes: [{name: "Lot", description: "Texte", count: 2}],
    existingEntries: persistedEntriesFromPlan(initial), randomUnit: () => 0,
  });
  assert.equal(retry.missingPayloads.length, 0);
  assert.equal(retry.replacementPayloads.length, 0);
  assert.equal(retry.deleteEntries.length, 0);
  assert.equal(retry.preservedEntries.length, 2);
});

test("changed dates replace unassigned occurrences and discard their former dates", () => {
  const initial = planInstantWinnerReconciliation({
    gameId: "date-change", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "Lot", count: 1}], randomUnit: () => 0.1,
  });
  const regenerated = planInstantWinnerReconciliation({
    gameId: "date-change", startDateMs: 2000, endDateMs: 3000, nowMs: 2100,
    secondaryPrizes: [{name: "Lot", count: 1}],
    existingEntries: persistedEntriesFromPlan(initial), randomUnit: () => 0,
  });
  assert.equal(regenerated.replacementPayloads.length, 1);
  assert.ok(regenerated.replacementPayloads[0].payload.dateMs >= 2100);
  assert.ok(regenerated.replacementPayloads[0].payload.dateMs <= 3000);
  assert.notEqual(regenerated.replacementPayloads[0].payload.dateMs, 100);
});

test("a started game schedules new unassigned occurrences from server now", () => {
  const plan = planInstantWinnerReconciliation({
    gameId: "started", startDateMs: 0, endDateMs: 1000, nowMs: 600,
    secondaryPrizes: [{name: "Lot", count: 1}], randomUnit: () => 0,
  });
  assert.equal(plan.missingPayloads[0].payload.dateMs, 600);
});

test("a game without a future scheduling window fails before mutations", () => {
  assert.throws(() => planInstantWinnerReconciliation({
    gameId: "ended", startDateMs: 0, endDateMs: 1000, nowMs: 1000,
    secondaryPrizes: [{name: "Lot", count: 1}],
  }), /future scheduling window/);
});

test("quantity increase, reduction, removal, and reorder reconcile unassigned occurrences", () => {
  const initial = planInstantWinnerReconciliation({
    gameId: "shape", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "A", count: 2}, {name: "B", count: 1}], randomUnit: () => 0.1,
  });
  const entries = persistedEntriesFromPlan(initial);
  const increased = planInstantWinnerReconciliation({
    gameId: "shape", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "A", count: 3}, {name: "B", count: 1}], existingEntries: entries,
  });
  assert.equal(increased.replacementPayloads.length, 3);
  assert.equal(increased.missingPayloads.length, 1);
  const reduced = planInstantWinnerReconciliation({
    gameId: "shape", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "A", count: 1}], existingEntries: entries,
  });
  assert.equal(reduced.replacementPayloads.length, 1);
  assert.equal(reduced.deleteEntries.length, 2);
  const reordered = planInstantWinnerReconciliation({
    gameId: "shape", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "B", count: 1}, {name: "A", count: 2}], existingEntries: entries,
  });
  assert.equal(reordered.replacementPayloads.length, 2);
  assert.equal(reordered.missingPayloads.length, 1);
  assert.equal(reordered.deleteEntries.length, 1);
});

test("name, presentation, and a cleared presentation replace non-assigned snapshots", () => {
  const initial = planInstantWinnerReconciliation({
    gameId: "snapshot", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "Ancien", description: "Ancienne presentation", count: 1}],
  });
  const withNewText = planInstantWinnerReconciliation({
    gameId: "snapshot", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "Nouveau", description: "Nouvelle presentation", count: 1}],
    existingEntries: persistedEntriesFromPlan(initial),
  });
  assert.equal(withNewText.replacementPayloads[0].payload.secondary_prize_name, "Nouveau");
  assert.equal(withNewText.replacementPayloads[0].payload.secondary_prize_presentation, "Nouvelle presentation");
  const cleared = planInstantWinnerReconciliation({
    gameId: "snapshot", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "Nouveau", description: "", count: 1}],
    existingEntries: persistedEntriesFromPlan(withNewText),
  });
  assert.equal("secondary_prize_presentation" in cleared.replacementPayloads[0].payload, false);
});

test("assigned occurrences remain immutable while non-assigned occurrences reconcile", () => {
  const initial = planInstantWinnerReconciliation({
    gameId: "mixed", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "A", count: 2}], randomUnit: () => 0.1,
  });
  const entries = persistedEntriesFromPlan(initial);
  entries[0] = {...entries[0], hasWinner: true, player_id: "player"};
  const regenerated = planInstantWinnerReconciliation({
    gameId: "mixed", startDateMs: 100, endDateMs: 2000,
    secondaryPrizes: [{name: "A", count: 2}], existingEntries: entries, randomUnit: () => 0.5,
  });
  assert.equal(regenerated.preservedEntries.length, 1);
  assert.equal(regenerated.preservedEntries[0].id, entries[0].id);
  assert.equal(regenerated.replacementPayloads.length, 1);
  assert.ok(regenerated.replacementPayloads[0].payload.dateMs >= 100);
});

test("assigned occurrences that conflict with removal are preserved and reported", () => {
  const initial = planInstantWinnerReconciliation({
    gameId: "assigned-removal", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "A", count: 1}, {name: "B", count: 1}],
  });
  const entries = persistedEntriesFromPlan(initial);
  entries[1] = {...entries[1], claimed: true};
  const plan = planInstantWinnerReconciliation({
    gameId: "assigned-removal", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [{name: "A", count: 1}], existingEntries: entries,
  });
  assert.equal(plan.deleteEntries.length, 0);
  assert.deepEqual(plan.assignedConflicts.map((entry) => entry.id), [entries[1].id]);
});

test("unassigned legacy excess occurrences are deleted", () => {
  const plan = planInstantWinnerReconciliation({
    gameId: "excess", startDateMs: 0, endDateMs: 1000,
    secondaryPrizes: [],
    existingEntries: [{id: "obsolete", secondary_prize_index: 4, secondary_prize_occurrence_index: 0, hasWinner: false}],
  });
  assert.deepEqual(plan.deleteEntries.map((entry) => entry.id), ["obsolete"]);
});

test("player-readable instant_winners access is not allowed in Firestore rules", () => {
  const rulesPath = path.resolve(__dirname, "../../firestore.rules");
  const rules = fs.readFileSync(rulesPath, "utf8");
  const blockMatch = rules.match(
    /match \/games\/\{parent\}\/instant_winners\/\{document\}\s*\{([\s\S]*?)\n\s*\}/m,
  );

  assert.ok(blockMatch);
  const block = blockMatch[1];
  assert.match(block, /allow read: if isAdmin\(\);/);
  assert.doesNotMatch(block, /allow read: if true;/);
});

test("legacy Flutter action no longer generates locally or writes instant_winners directly", () => {
  const actionPath = path.resolve(
    __dirname,
    "../../../lib/custom_code/actions/add_instant_winners_to_game.dart",
  );
  const actionSource = fs.readFileSync(actionPath, "utf8");

  assert.match(actionSource, /httpsCallable\('generateInstantWinnersForGame'\)/);
  assert.doesNotMatch(actionSource, /Random\.secure/);
  assert.doesNotMatch(actionSource, /collection\('instant_winners'\)/);
  assert.doesNotMatch(actionSource, /batch\.set/);
});

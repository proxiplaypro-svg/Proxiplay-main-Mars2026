#!/usr/bin/env node
"use strict";

const {
  pickDueInstantWinner,
} = require("../lib/instant_winners_core");

function parseArgs(argv) {
  const args = {
    iterations: 100000,
    counts: [2, 5, 10],
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--iterations" && index + 1 < argv.length) {
      args.iterations =
        Math.max(1, Number.parseInt(argv[index + 1], 10) || args.iterations);
      index += 1;
    } else if (arg === "--counts" && index + 1 < argv.length) {
      args.counts = String(argv[index + 1] || "")
        .split(",")
        .map((value) => Number.parseInt(value.trim(), 10))
        .filter((value) => Number.isFinite(value) && value > 0);
      index += 1;
    }
  }

  return args;
}

function simulateSelection(count, iterations) {
  const dueDocs = Array.from({length: count}, (_, index) => ({
    id: `doc-${index}`,
  }));
  const counts = Object.fromEntries(dueDocs.map((doc) => [doc.id, 0]));

  for (let index = 0; index < iterations; index += 1) {
    const selection = pickDueInstantWinner(dueDocs);
    counts[selection.selected.id] += 1;
  }

  const expected = iterations / count;
  const rows = dueDocs.map((doc, index) => {
    const observed = counts[doc.id];
    return {
      index,
      id: doc.id,
      observed,
      deviation: observed - expected,
      relativeDeviation: expected === 0 ? 0 : (observed - expected) / expected,
    };
  });

  return {
    dueCount: count,
    iterations,
    expectedPerIndex: expected,
    maxAbsoluteRelativeDeviation: rows.reduce(
      (max, row) => Math.max(max, Math.abs(row.relativeDeviation)),
      0,
    ),
    rows,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const results = args.counts.map((count) =>
    simulateSelection(count, args.iterations),
  );
  console.log(
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        iterations: args.iterations,
        results,
      },
      null,
      2,
    ),
  );
}

main();

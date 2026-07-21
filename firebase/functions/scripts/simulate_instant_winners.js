#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
  buildInstantWinnerPayloads,
} = require("../lib/instant_winners_core");

function parseArgs(argv) {
  const args = {
    games: 100000,
    bins: 20,
    jsonOut: "",
    csvOut: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--games" && i + 1 < argv.length) {
      args.games = Math.max(1, Number.parseInt(argv[i + 1], 10) || args.games);
      i += 1;
    } else if (arg === "--bins" && i + 1 < argv.length) {
      args.bins = Math.max(2, Number.parseInt(argv[i + 1], 10) || args.bins);
      i += 1;
    } else if (arg === "--json-out" && i + 1 < argv.length) {
      args.jsonOut = String(argv[i + 1] || "").trim();
      i += 1;
    } else if (arg === "--csv-out" && i + 1 < argv.length) {
      args.csvOut = String(argv[i + 1] || "").trim();
      i += 1;
    }
  }

  return args;
}

function buildSecondaryPrizesConfig(count) {
  return [{name: "Lot secondaire", count}];
}

function percentile(sortedValues, ratio) {
  if (sortedValues.length === 0) {
    return null;
  }
  const index = Math.min(
    sortedValues.length - 1,
    Math.max(0, Math.floor(ratio * sortedValues.length)),
  );
  return sortedValues[index];
}

function correlation(sumX, sumY, sumXY, sumXX, sumYY, n) {
  if (n <= 1) {
    return null;
  }
  const numerator = n * sumXY - sumX * sumY;
  const denominator = Math.sqrt(
    (n * sumXX - sumX * sumX) * (n * sumYY - sumY * sumY),
  );
  if (!Number.isFinite(denominator) || denominator === 0) {
    return null;
  }
  return numerator / denominator;
}

function runSimulation({games, bins, prizeCount}) {
  const startDateMs = Date.parse("2026-01-01T00:00:00.000Z");
  const endDateMs = Date.parse("2026-01-31T23:59:59.999Z");
  const durationMs = endDateMs - startDateMs;
  const perBinCounts = Array.from({length: bins}, () => 0);
  const perDayCounts = Array.from({length: 31}, () => 0);
  const normalizedOffsets = [];
  let collisionGames = 0;
  let min = Number.POSITIVE_INFINITY;
  let max = Number.NEGATIVE_INFINITY;
  let sum = 0;
  let sumSquares = 0;
  let sumIndex = 0;
  let sumNormalized = 0;
  let sumIndexNormalized = 0;
  let sumIndexSquares = 0;
  let sumNormalizedSquares = 0;
  let totalDraws = 0;

  for (let gameIndex = 0; gameIndex < games; gameIndex += 1) {
    const payloads = buildInstantWinnerPayloads({
      startDateMs,
      endDateMs,
      secondaryPrizes: buildSecondaryPrizesConfig(prizeCount),
    });

    const collisionSet = new Set();
    let hasCollision = false;

    payloads.forEach((payload, index) => {
      if (collisionSet.has(payload.dateMs)) {
        hasCollision = true;
      } else {
        collisionSet.add(payload.dateMs);
      }

      const offset = payload.dateMs - startDateMs;
      const normalized = durationMs === 0 ? 0 : offset / durationMs;
      const binIndex = Math.min(bins - 1, Math.floor(normalized * bins));
      const dayIndex = Math.min(30, Math.floor(offset / (24 * 60 * 60 * 1000)));

      perBinCounts[binIndex] += 1;
      perDayCounts[dayIndex] += 1;
      normalizedOffsets.push(normalized);
      min = Math.min(min, normalized);
      max = Math.max(max, normalized);
      sum += normalized;
      sumSquares += normalized * normalized;
      totalDraws += 1;

      const x = index;
      const y = normalized;
      sumIndex += x;
      sumNormalized += y;
      sumIndexNormalized += x * y;
      sumIndexSquares += x * x;
      sumNormalizedSquares += y * y;
    });

    if (hasCollision) {
      collisionGames += 1;
    }
  }

  normalizedOffsets.sort((a, b) => a - b);
  const mean = totalDraws === 0 ? null : sum / totalDraws;
  const variance =
    totalDraws === 0 ? null : Math.max(0, sumSquares / totalDraws - mean * mean);
  const stddev = variance === null ? null : Math.sqrt(variance);

  return {
    games,
    prizeCount,
    totalDraws,
    bins,
    perBinCounts,
    perDayCounts,
    min,
    max,
    mean,
    median: percentile(normalizedOffsets, 0.5),
    stddev,
    collisionGames,
    collisionRate: games === 0 ? 0 : collisionGames / games,
    indexCorrelation: correlation(
      sumIndex,
      sumNormalized,
      sumIndexNormalized,
      sumIndexSquares,
      sumNormalizedSquares,
      totalDraws,
    ),
  };
}

function writeIfRequested(filePath, content) {
  if (!filePath) {
    return;
  }
  const resolved = path.resolve(process.cwd(), filePath);
  fs.mkdirSync(path.dirname(resolved), {recursive: true});
  fs.writeFileSync(resolved, content);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const configurations = [1, 5, 10];
  const results = configurations.map((prizeCount) =>
    runSimulation({
      games: args.games,
      bins: args.bins,
      prizeCount,
    }),
  );

  const json = JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      configs: results,
    },
    null,
    2,
  );
  const csvLines = [
    "prizeCount,games,totalDraws,mean,median,stddev,min,max,collisionGames,collisionRate,indexCorrelation",
    ...results.map((result) =>
      [
        result.prizeCount,
        result.games,
        result.totalDraws,
        result.mean,
        result.median,
        result.stddev,
        result.min,
        result.max,
        result.collisionGames,
        result.collisionRate,
        result.indexCorrelation,
      ].join(","),
    ),
  ];

  writeIfRequested(args.jsonOut, json);
  writeIfRequested(args.csvOut, `${csvLines.join("\n")}\n`);
  console.log(json);
}

main();

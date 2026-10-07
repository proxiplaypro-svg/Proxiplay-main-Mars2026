"use strict";

const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const functionsDirectory = path.resolve(__dirname, "..");
const stripeEnvironmentKeys = [
  "STRIPE_SECRET_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "STRIPE_PRICE_PROXIMITE",
  "STRIPE_PRICE_SECTEURS_SPECIFIQUES",
  "STRIPE_PRICE_GRANDES_ENSEIGNES",
  "STRIPE_TAX_RATE_TVA_20",
];

test("index loads all endpoints without Stripe configuration", () => {
  const environment = {...process.env};
  stripeEnvironmentKeys.forEach((key) => delete environment[key]);

  const script = `
    const endpoints = require("./index.js");
    const names = [
      "generateInstantWinnersForGame",
      "createMerchantCheckoutSession",
      "createMerchantBillingPortalSession",
      "stripeWebhook",
    ];
    for (const name of names) {
      if (typeof endpoints[name] !== "function") {
        throw new Error("Missing exported endpoint: " + name);
      }
    }
    process.stdout.write("ENDPOINTS_LOADED\\n");
  `;
  const result = spawnSync(process.execPath, ["-e", script], {
    cwd: functionsDirectory,
    env: environment,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /ENDPOINTS_LOADED/);
  assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /Enter a value for STRIPE_/i);
});

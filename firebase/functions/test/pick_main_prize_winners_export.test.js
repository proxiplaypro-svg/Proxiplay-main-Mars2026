// Verifies the ACTUAL function object index.js exports under the name
// "pickMainPrizeWinners" -- not main_prize_draw.js's local const in
// isolation. This is the exact chain production runs:
// index.js -> exports.pickMainPrizeWinners -> main_prize_draw.js's
// pickMainPrizeWinners -> runScheduledDraws.
//
// Context: after deploying commit 50f5bdf (which added
// functions.runWith({timeoutSeconds:300}) in main_prize_draw.js) and
// manually triggering the function, production logs still showed
// "Function execution took 59999 ms, finished with status: 'timeout'"
// -- i.e. still the Gen1 default of ~60s, not 300s. Reading
// main_prize_draw.js and index.js confirmed the source itself is
// correct (single export, no duplicate, no stale build artifact: the
// tsconfig.json build only compiles files under src/**/*.ts into lib/,
// and main_prize_draw.js/index.js are plain .js files outside that
// pipeline entirely). This test proves the exported object itself
// carries timeoutSeconds:300 using the real installed firebase-functions
// package -- so if a future change ever silently drops the runWith()
// wrapper, or an export gets shadowed/duplicated, this test fails before
// any deploy, instead of only being discoverable from a production log
// days later.
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-pick-main-prize-winners-export';
process.env.FUNCTIONS_EMULATOR = 'true';
const test = require('node:test');
const assert = require('node:assert/strict');
require('firebase-functions-test')();
const exported = require('../index').pickMainPrizeWinners;
const fromModule = require('../main_prize_draw').pickMainPrizeWinners;

test('index.js exports the exact same function object main_prize_draw.js defines -- no duplicate, no shadowing', () => {
  assert.equal(exported, fromModule);
});

test('the exported pickMainPrizeWinners carries timeoutSeconds:300, not the Gen1 default of 60', () => {
  assert.equal(exported.__endpoint.timeoutSeconds, 300);
  assert.equal(exported.__trigger.timeout, '300s');
});

test('the exported pickMainPrizeWinners keeps its original schedule and timezone unchanged', () => {
  assert.equal(exported.__endpoint.scheduleTrigger.schedule, '0 0 * * *');
  assert.equal(exported.__endpoint.scheduleTrigger.timeZone, 'Europe/Paris');
  assert.equal(exported.__trigger.schedule.schedule, '0 0 * * *');
  assert.equal(exported.__trigger.schedule.timeZone, 'Europe/Paris');
});

test('the exported pickMainPrizeWinners is still a Gen1 pubsub-scheduled function (platform gcfv1)', () => {
  assert.equal(exported.__endpoint.platform, 'gcfv1');
});

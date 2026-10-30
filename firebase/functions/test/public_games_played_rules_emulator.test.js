const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-public-metric-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc("public_metrics/games_played").set({ gamesPlayed: 136642 });
  });
});

test.after(async () => testEnv?.cleanup());

test("anonymous users can get only the public metric", async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  const metric = await assertSucceeds(db.doc("public_metrics/games_played").get());
  assert.equal(metric.data().gamesPlayed, 136642);
  await assertFails(db.collection("public_metrics").get());
  await assertFails(db.doc("admin_stats/global").get());
});

test("clients cannot write the public metric", async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(db.doc("public_metrics/games_played").update({ gamesPlayed: 1 }));
});

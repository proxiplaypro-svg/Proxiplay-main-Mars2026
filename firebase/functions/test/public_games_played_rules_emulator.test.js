const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

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
    await context.firestore().doc("public_metrics/games_played").set({
      gamesPlayed: 136630,
      validatedAt: new Date("2026-11-02T03:00:00.000Z"),
    });
  });
});

test.after(async () => testEnv?.cleanup());

test("anonymous visitors can get only the public games-played document", async () => {
  const anon = testEnv.unauthenticatedContext().firestore();
  const snapshot = await assertSucceeds(anon.doc("public_metrics/games_played").get());
  assert.equal(snapshot.data().gamesPlayed, 136630);
  await assertFails(anon.collection("public_metrics").get());
  await assertFails(anon.doc("admin_stats/global").get());
});

test("no client can write the public games-played document", async () => {
  const anon = testEnv.unauthenticatedContext().firestore();
  await assertFails(anon.doc("public_metrics/games_played").update({ gamesPlayed: 1 }));
  await assertFails(anon.doc("public_metrics/games_played").delete());
});

#!/usr/bin/env node
const test = require("node:test");
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
    projectId: "demo-proxiplay-public-active-catalog",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc("public_content/active_catalog").set({
      schemaVersion: 1,
      activeGamesCount: 1,
    });
    await context.firestore().doc("admin_stats/global").set({participations_count: 1});
  });
});

test.after(async () => { if (testEnv) await testEnv.cleanup(); });

test("anonymous users can get only the exact public active catalog", async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertSucceeds(db.doc("public_content/active_catalog").get());
  await assertFails(db.collection("public_content").get());
  await assertFails(db.doc("public_content/active_catalog").set({activeGamesCount: 99}));
  await assertFails(db.doc("admin_stats/global").get());
});

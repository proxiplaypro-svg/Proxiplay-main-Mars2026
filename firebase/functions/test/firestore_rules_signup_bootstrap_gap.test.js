// Regression: inscription_informations_page_widget.dart's finalization
// write (currentUserReference!.set(createUsersRecordData(...), merge:true))
// never included `uid`. If the users/{uid} document somehow didn't exist
// yet when the user reached this page (the upstream bootstrap in
// inscription_page_widget.dart used to swallow its own errors via
// catch (_) {}, so a transient failure there went unnoticed), Firestore
// treats this merge .set() as a CREATE, which isAllowedSelfUserCreate()
// refuses without `uid` -- "Property uid is undefined on object" --
// permanently stranding a user with a valid Firebase Auth account but no
// way to ever finish signing up.
//
// Fixed two ways:
// 1. The upstream bootstrap in inscription_page_widget.dart no longer
//    swallows errors locally -- they now reach the existing outer
//    catch/recovery, which is hardened to only proceed once the document
//    is confirmed to exist.
// 2. This finalization write now also includes `uid` defensively, so even
//    if the document is still missing for any other reason, this write
//    succeeds as a valid create instead of crashing.
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;
const uid = "player_uid";

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-signup-bootstrap-gap",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

function finalizationPayload({ withUid }) {
  return {
    ...(withUid ? { uid } : {}),
    phone_number: "0600000000",
    first_name: "Alice",
    last_name: "Martin",
    display_name: "Alice Martin",
    city: "Dunkerque",
    city_insee_code: "59183",
    profile_completed: true,
    profile_completed_at: new Date(),
    profile_schema_version: 3,
  };
}

test("REGRESSION: finalization write without uid on a missing document fails " +
  "(the exact crash a stranded user used to hit)", async () => {
  const player = testEnv.authenticatedContext(uid, {}).firestore();
  await assertFails(
    player.collection("users").doc(uid).set(finalizationPayload({ withUid: false }), { merge: true }),
  );
});

test("fix: finalization write WITH uid succeeds even when the document is still missing", async () => {
  const player = testEnv.authenticatedContext(uid, {}).firestore();
  await assertSucceeds(
    player.collection("users").doc(uid).set(finalizationPayload({ withUid: true }), { merge: true }),
  );
  const doc = await player.collection("users").doc(uid).get();
  assert.equal(doc.data().uid, uid);
  assert.equal(doc.data().profile_completed, true);
});

test("no regression: finalization write WITH uid still succeeds as a normal " +
  "update when the document already exists with the same uid", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc(uid).set({
      uid,
      user_role: "joueur",
      profile_completed: false,
    });
  });
  const player = testEnv.authenticatedContext(uid, {}).firestore();
  await assertSucceeds(
    player.collection("users").doc(uid).set(finalizationPayload({ withUid: true }), { merge: true }),
  );
});

test("no security loosening: a player still cannot smuggle a privileged field " +
  "through this same write even with uid present", async () => {
  const player = testEnv.authenticatedContext(uid, {}).firestore();
  await assertFails(
    player
      .collection("users")
      .doc(uid)
      .set({ ...finalizationPayload({ withUid: true }), account_status: "approved" }, { merge: true }),
  );
});

test("upstream bootstrap write (ensureUserDocumentInitialized shape) creates a " +
  "valid document that the finalization write can then safely update", async () => {
  const player = testEnv.authenticatedContext(uid, {}).firestore();
  // Mirrors ensureUserDocumentInitialized's own patch shape.
  await assertSucceeds(
    player.collection("users").doc(uid).set(
      { uid, user_role: "joueur", created_time: new Date(), email: "a@b.fr" },
      { merge: true },
    ),
  );
  await assertSucceeds(
    player.collection("users").doc(uid).set(finalizationPayload({ withUid: true }), { merge: true }),
  );
});

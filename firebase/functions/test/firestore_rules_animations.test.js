#!/usr/bin/env node

// Verifies animations/{id} is publicly readable, matching games/enseignes --
// the Home "Scans en boutique" carousel shows active animations to every
// player, including guests using "Continuer sans compte" (login_page_widget.dart),
// which sets FFAppState().isGuest = true and navigates straight to Home
// WITHOUT any Firebase sign-in (not even anonymous auth), so request.auth is
// genuinely null for that whole session. The previous rule
// (allow read: if request.auth != null) made every animation-backed home
// section (and animation detail pages) permission-denied for guests, while
// the identical games/enseignes carousels next to it worked fine.
//
// entries/{uid} stays gated to its own owner -- that part was never the bug.
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_animations.test.js"

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
    projectId: "demo-proxiplay-rules-animations-test",
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "../../firestore.rules"),
        "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection("animations").doc("anim1").set({
      name: "Animation test",
      status: "active",
    });
    await db.collection("animations").doc("anim1").collection("entries").doc("player_uid").set({
      threshold_reached: true,
    });
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test("animations : un invite sans session Firebase (isGuest) peut lire une animation", async () => {
  const guest = testEnv.unauthenticatedContext();
  const snap = await assertSucceeds(
    guest.firestore().collection("animations").doc("anim1").get(),
  );
  assert.equal(snap.data().name, "Animation test");
});

test("animations : un joueur connecte peut aussi lire une animation", async () => {
  const player = testEnv.authenticatedContext("player_uid");
  await assertSucceeds(
    player.firestore().collection("animations").doc("anim1").get(),
  );
});

test("animations : ecrire une animation reste reserve a l'admin", async () => {
  const player = testEnv.authenticatedContext("player_uid");
  await assertFails(
    player.firestore().collection("animations").doc("anim1").set(
      {name: "hack"},
      {merge: true},
    ),
  );
});

test("animations/entries : le proprietaire de l'entree peut la lire", async () => {
  const player = testEnv.authenticatedContext("player_uid");
  await assertSucceeds(
    player.firestore().collection("animations").doc("anim1")
      .collection("entries").doc("player_uid").get(),
  );
});

test("animations/entries : un invite sans session ne peut pas lire l'entree d'un autre", async () => {
  const guest = testEnv.unauthenticatedContext();
  await assertFails(
    guest.firestore().collection("animations").doc("anim1")
      .collection("entries").doc("player_uid").get(),
  );
});

test("animations/entries : un autre joueur ne peut pas lire l'entree de player_uid", async () => {
  const stranger = testEnv.authenticatedContext("stranger_uid");
  await assertFails(
    stranger.firestore().collection("animations").doc("anim1")
      .collection("entries").doc("player_uid").get(),
  );
});

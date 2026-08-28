#!/usr/bin/env node

// Verifies the users/{document} rule tightening (Partie E of the plan) does
// what it's supposed to, BEFORE it's deployed: a user can no longer read
// another user's profile, self/admin reads still work, and public reads of
// games/prizes (including the newly denormalized winner fields) are
// unaffected. Also covers isSafeSelfUserUpdate()'s privileged-field guard:
// it must use affectedKeys() (added+removed+changed), not changedKeys()
// (changed-only) -- with changedKeys(), a player could self-write a
// privileged field (remaining_part, account_status, ...) as long as it
// wasn't already present on their doc, since adding a field isn't a
// "change" of an existing value. Run against the local Firestore emulator
// only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_users.test.js"

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
    projectId: "demo-proxiplay-rules-test",
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
    await db.collection("users").doc("alice_uid").set({
      user_role: "joueur",
      email: "alice@example.com",
      first_name: "Alice",
      city: "Paris",
      account_status: "approved",
    });
    await db.collection("users").doc("bob_uid").set({
      user_role: "joueur",
      email: "bob@example.com",
      first_name: "Bob",
    });
    await db.collection("users").doc("admin_uid").set({
      user_role: "admin",
    });
    await db.collection("games").doc("game1").set({
      name: "Jeu test",
      hasWinner: true,
      main_prize_winner: db.doc("users/alice_uid"),
      winnerFirstName: "Alice",
      winner_first_name: "Alice",
      winnerCity: "Paris",
      winner_city: "Paris",
    });
    await db.collection("prizes").doc("prize1").set({
      name: "Lot test",
      winner_id: db.doc("users/alice_uid"),
      winnerFirstName: "Alice",
      winner_first_name: "Alice",
    });
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test("un utilisateur ne peut pas lire le profil d'un autre utilisateur", async () => {
  const bob = testEnv.authenticatedContext("bob_uid");
  await assertFails(
    bob.firestore().collection("users").doc("alice_uid").get(),
  );
});

test("un utilisateur peut lire son propre profil", async () => {
  const alice = testEnv.authenticatedContext("alice_uid");
  await assertSucceeds(
    alice.firestore().collection("users").doc("alice_uid").get(),
  );
});

test("un admin peut lire le profil de n'importe quel utilisateur", async () => {
  const admin = testEnv.authenticatedContext("admin_uid");
  await assertSucceeds(
    admin.firestore().collection("users").doc("bob_uid").get(),
  );
});

test("un utilisateur non authentifie ne peut lire aucun profil", async () => {
  const anon = testEnv.unauthenticatedContext();
  await assertFails(
    anon.firestore().collection("users").doc("alice_uid").get(),
  );
});

test("la lecture publique de games avec champs denormalises reste inchangee", async () => {
  const bob = testEnv.authenticatedContext("bob_uid");
  const snap = await assertSucceeds(
    bob.firestore().collection("games").doc("game1").get(),
  );
  assert.equal(snap.data().winnerFirstName, "Alice");
  assert.equal(snap.data().winnerCity, "Paris");

  const anon = testEnv.unauthenticatedContext();
  await assertSucceeds(anon.firestore().collection("games").doc("game1").get());
});

test("la lecture publique de prizes avec champs denormalises reste inchangee", async () => {
  const anon = testEnv.unauthenticatedContext();
  const snap = await assertSucceeds(
    anon.firestore().collection("prizes").doc("prize1").get(),
  );
  assert.equal(snap.data().winnerFirstName, "Alice");
});

test("un joueur ne peut pas s'attribuer remaining_part quand le champ est absent", async () => {
  // bob_uid n'a pas encore remaining_part (comme un profil fraichement cree,
  // avant que initializeNewPlayerRemainingParts ne l'ait pose) : avec
  // changedKeys() cet ajout passait, avec affectedKeys() il est bloque.
  const bob = testEnv.authenticatedContext("bob_uid");
  await assertFails(
    bob.firestore().collection("users").doc("bob_uid").set(
      {remaining_part: 999},
      {merge: true},
    ),
  );
});

test("un joueur ne peut pas modifier un account_status deja present", async () => {
  const alice = testEnv.authenticatedContext("alice_uid");
  await assertFails(
    alice.firestore().collection("users").doc("alice_uid").set(
      {account_status: "rejected"},
      {merge: true},
    ),
  );
});

test("un joueur ne peut pas s'attribuer allGamesAccessUntil quand le champ est absent", async () => {
  const bob = testEnv.authenticatedContext("bob_uid");
  await assertFails(
    bob.firestore().collection("users").doc("bob_uid").set(
      {allGamesAccessUntil: new Date(Date.now() + 86400000)},
      {merge: true},
    ),
  );
});

test("un joueur peut toujours modifier un champ de profil autorise", async () => {
  const bob = testEnv.authenticatedContext("bob_uid");
  await assertSucceeds(
    bob.firestore().collection("users").doc("bob_uid").set(
      {phone_number: "0600000000"},
      {merge: true},
    ),
  );
});

test("un admin peut toujours modifier un champ privilegie d'un autre utilisateur", async () => {
  const admin = testEnv.authenticatedContext("admin_uid");
  await assertSucceeds(
    admin.firestore().collection("users").doc("bob_uid").set(
      {remaining_part: 5},
      {merge: true},
    ),
  );
});

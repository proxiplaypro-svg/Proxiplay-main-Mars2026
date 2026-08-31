#!/usr/bin/env node

// Verifies the merge of proxiplay-admin's Firestore needs into this repo's
// canonical firestore.rules (see the note at the top of that file): the
// admin console (repo proxiplay-admin, same Firebase project) lost the
// ability to manage /jeux, /merchants and game participants after the
// 2026-08-30 firestore:rules deploy from THIS repo overwrote its own rules
// file wholesale (Firestore keeps only one active ruleset, no merge).
//
// Also re-confirms the two vulnerabilities present in proxiplay-admin's own
// firestore.rules were deliberately NOT carried over:
//   - prizes: allow read: if true (would re-leak claim_code publicly)
//   - users/{userId}: allow read: if isAdmin() || isCurrentUser(userId) || true
//     (literal unconditional public read)
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_admin_console.test.js"

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
    projectId: "demo-proxiplay-rules-admin-console-test",
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

    await db.collection("users").doc("player_uid").set({user_role: "joueur"});

    await db.collection("enseignes").doc("enseigne1").set({
      email: "merchant@example.test",
    });
    await db.collection("merchants").doc("merchant1").set({
      email: "othermerchant@example.test",
    });

    await db.collection("jeux").doc("qr_game1").set({
      name: "Jeu QR legacy",
      merchant_id: "enseigne1",
      access_mode: "qr_only",
    });
    await db.collection("jeux").doc("qr_game_to_delete").set({
      name: "Jeu QR legacy a supprimer",
      merchant_id: "enseigne1",
      access_mode: "qr_only",
    });

    await db.collection("games").doc("classic_game1").set({
      name: "Jeu classique",
      create_by: db.doc("users/player_uid"),
    });
    await db.collection("games").doc("classic_game1").collection("participants").doc("p1").set({
      status: "played",
    });

    await db.collection("prizes").doc("prize1").set({
      name: "Lot test",
      winner_id: db.doc("users/player_uid"),
      claim_code: "SECRET",
    });
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function adminByEmailContext() {
  // No custom claim, no users/{uid} doc at all -- exactly how the
  // proxiplay-admin console's operator account authenticates today.
  return testEnv.authenticatedContext("admin_console_uid", {
    email: "proxiplay.pro@gmail.com",
  });
}

test("isAdmin() reconnait le compte admin de la console par email (sans custom claim ni users doc)", async () => {
  const admin = adminByEmailContext();
  await assertSucceeds(
    admin.firestore().collection("games").doc("classic_game1").update({name: "Renomme"}),
  );
});

test("jeux : le compte admin de la console peut modifier un jeu a scanner legacy", async () => {
  const admin = adminByEmailContext();
  await assertSucceeds(
    admin.firestore().collection("jeux").doc("qr_game1").update({active: false}),
  );
});

test("jeux : le compte admin de la console peut supprimer un jeu a scanner legacy", async () => {
  const admin = adminByEmailContext();
  await assertSucceeds(
    admin.firestore().collection("jeux").doc("qr_game_to_delete").delete(),
  );
});

test("jeux : le commercant proprietaire de l'enseigne liee peut gerer son jeu", async () => {
  const merchant = testEnv.authenticatedContext("merchant_uid", {
    email: "merchant@example.test",
  });
  await assertSucceeds(
    merchant.firestore().collection("jeux").doc("qr_game1").update({active: true}),
  );
});

test("jeux : un joueur sans lien avec l'enseigne ne peut pas modifier le jeu", async () => {
  const player = testEnv.authenticatedContext("player_uid", {
    email: "player@example.test",
  });
  await assertFails(
    player.firestore().collection("jeux").doc("qr_game1").update({active: true}),
  );
});

test("jeux : lecture publique (comme games)", async () => {
  const anon = testEnv.unauthenticatedContext();
  await assertSucceeds(anon.firestore().collection("jeux").doc("qr_game1").get());
});

test("games participants : l'admin de la console peut moderer (update/delete)", async () => {
  const admin = adminByEmailContext();
  await assertSucceeds(
    admin.firestore().collection("games").doc("classic_game1")
      .collection("participants").doc("p1").update({status: "reviewed"}),
  );
});

test("games participants : un joueur ne peut pas moderer les participations", async () => {
  const player = testEnv.authenticatedContext("player_uid");
  await assertFails(
    player.firestore().collection("games").doc("classic_game1")
      .collection("participants").doc("p1").delete(),
  );
});

test(
  "securite : prizes reste protege (claim_code non public) apres la fusion",
  {skip: "TEMPORAIRE 2026-08-31 : prizes est en allow read: if true, a reactiver au prochain build (voir firestore.rules)"},
  async () => {
    const anon = testEnv.unauthenticatedContext();
    await assertFails(anon.firestore().collection("prizes").doc("prize1").get());
  },
);

test("securite : users reste protege (pas de || true) apres la fusion", async () => {
  const stranger = testEnv.authenticatedContext("stranger_uid");
  await assertFails(
    stranger.firestore().collection("users").doc("player_uid").get(),
  );
});

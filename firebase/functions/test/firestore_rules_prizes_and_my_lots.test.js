#!/usr/bin/env node

// Verifies Correction 2 of the jeux audit (my_lots lockdown + claim_code
// protection):
//
// - users/{uid}/my_lots/* used to allow the owning player to write/delete
//   freely (allow write: if request.auth.uid == parent). my_lots is always
//   written server-side, in the same transaction as the matching prizes doc
//   (participate_in_game_transaction.js / pickMainPrizeWinners /
//   drawWinnerForAnimation / referral_game_engine.js / monthly_challenge.js),
//   so a client never needs to write it -- leaving it open let a modified
//   client fabricate an entry pointing at another player's prize.
//
// - prizes/{id} used to be `allow read: if true`, exposing claim_code (and
//   winner_id) to anyone, authenticated or not. The public winners ticker
//   reads a denormalized stats/global doc instead (see
//   global_ticker_service.dart), so prizes never needed to be world-readable;
//   read is now restricted to the winner, the merchant who owns the prize/
//   enseigne, and admins.
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_prizes_and_my_lots.test.js"

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
    projectId: "demo-proxiplay-rules-prizes-test",
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
    await db.collection("users").doc("winner_uid").set({user_role: "joueur"});
    await db.collection("users").doc("stranger_uid").set({user_role: "joueur"});
    await db.collection("users").doc("admin_uid").set({user_role: "admin"});
    await db.collection("users").doc("merchant_owner_uid").set({user_role: "commercant"});
    await db.collection("users").doc("merchant_enseigne_uid").set({user_role: "commercant"});
    await db.collection("users").doc("other_merchant_uid").set({user_role: "commercant"});

    await db.collection("enseignes").doc("enseigne1").set({
      owner: db.doc("users/merchant_enseigne_uid"),
    });

    // Lot classique (owner_id + enseigne_id, comme pickMainPrizeWinners /
    // participate_in_game_transaction.js).
    await db.collection("prizes").doc("classic_prize").set({
      name: "Lot classique",
      winner_id: db.doc("users/winner_uid"),
      owner_id: db.doc("users/merchant_owner_uid"),
      enseigne_id: db.doc("enseignes/enseigne1"),
      claim_code: "SECRET1",
      claimed: false,
    });

    // Lot animation (winner_id seulement, comme drawWinnerForAnimation).
    await db.collection("prizes").doc("animation_prize").set({
      name: "Gros lot animation",
      winner_id: db.doc("users/winner_uid"),
      claim_code: "SECRET2",
      claimed: false,
    });

    await db.collection("users").doc("winner_uid").collection("my_lots").doc("classic_prize").set({
      prize_id: db.doc("prizes/classic_prize"),
    });
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test("prizes : le gagnant peut lire son propre lot (et son claim_code)", async () => {
  const winner = testEnv.authenticatedContext("winner_uid");
  const snap = await assertSucceeds(
    winner.firestore().collection("prizes").doc("classic_prize").get(),
  );
  assert.equal(snap.data().claim_code, "SECRET1");
});

test("prizes : un autre joueur ne peut pas lire le lot d'un gagnant", async () => {
  const stranger = testEnv.authenticatedContext("stranger_uid");
  await assertFails(
    stranger.firestore().collection("prizes").doc("classic_prize").get(),
  );
});

test("prizes : un utilisateur non authentifie ne peut lire aucun lot", async () => {
  const anon = testEnv.unauthenticatedContext();
  await assertFails(anon.firestore().collection("prizes").doc("classic_prize").get());
  await assertFails(anon.firestore().collection("prizes").doc("animation_prize").get());
});

test("prizes : le commercant proprietaire du lot (owner_id) peut le lire", async () => {
  const merchant = testEnv.authenticatedContext("merchant_owner_uid");
  await assertSucceeds(
    merchant.firestore().collection("prizes").doc("classic_prize").get(),
  );
});

test("prizes : le commercant proprietaire de l'enseigne (enseigne_id) peut le lire", async () => {
  const merchant = testEnv.authenticatedContext("merchant_enseigne_uid");
  await assertSucceeds(
    merchant.firestore().collection("prizes").doc("classic_prize").get(),
  );
});

test("prizes : un commercant sans lien avec le lot ne peut pas le lire", async () => {
  const merchant = testEnv.authenticatedContext("other_merchant_uid");
  await assertFails(
    merchant.firestore().collection("prizes").doc("classic_prize").get(),
  );
});

test("prizes : un admin peut lire n'importe quel lot", async () => {
  const admin = testEnv.authenticatedContext("admin_uid");
  await assertSucceeds(
    admin.firestore().collection("prizes").doc("classic_prize").get(),
  );
  await assertSucceeds(
    admin.firestore().collection("prizes").doc("animation_prize").get(),
  );
});

test("prizes : un lot sans owner_id/enseigne_id (animation) reste lisible par son gagnant", async () => {
  const winner = testEnv.authenticatedContext("winner_uid");
  const snap = await assertSucceeds(
    winner.firestore().collection("prizes").doc("animation_prize").get(),
  );
  assert.equal(snap.data().claim_code, "SECRET2");
});

test("my_lots : le proprietaire peut lire ses lots", async () => {
  const winner = testEnv.authenticatedContext("winner_uid");
  await assertSucceeds(
    winner.firestore().collection("users").doc("winner_uid")
      .collection("my_lots").doc("classic_prize").get(),
  );
});

test("my_lots : un autre joueur ne peut pas lire les lots d'un joueur", async () => {
  const stranger = testEnv.authenticatedContext("stranger_uid");
  await assertFails(
    stranger.firestore().collection("users").doc("winner_uid")
      .collection("my_lots").doc("classic_prize").get(),
  );
});

test("my_lots : le proprietaire ne peut plus s'ecrire une entree lui-meme", async () => {
  const winner = testEnv.authenticatedContext("winner_uid");
  await assertFails(
    winner.firestore().collection("users").doc("winner_uid")
      .collection("my_lots").doc("fabricated").set({
        prize_id: winner.firestore().doc("prizes/animation_prize"),
      }),
  );
});

test("my_lots : le proprietaire ne peut pas modifier une entree existante", async () => {
  const winner = testEnv.authenticatedContext("winner_uid");
  await assertFails(
    winner.firestore().collection("users").doc("winner_uid")
      .collection("my_lots").doc("classic_prize").set(
        {prize_id: winner.firestore().doc("prizes/animation_prize")},
        {merge: true},
      ),
  );
});

test("my_lots : le proprietaire ne peut pas supprimer une entree existante", async () => {
  const winner = testEnv.authenticatedContext("winner_uid");
  await assertFails(
    winner.firestore().collection("users").doc("winner_uid")
      .collection("my_lots").doc("classic_prize").delete(),
  );
});

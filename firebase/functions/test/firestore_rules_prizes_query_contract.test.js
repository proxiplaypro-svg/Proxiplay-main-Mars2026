#!/usr/bin/env node

// Compatibility contract for OLD direct prize queries. Explicit owner queries
// still work; raw enseigne queries are denied to preserve owner priority.
// Current mobile listing uses getMerchantPrizes + individual reads: its positive
// and negative end-to-end data path is covered by merchant_prizes.test.js.
// Keep these checks as an explicit migration gate for distributed old clients.

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
    projectId: "demo-proxiplay-prizes-query-contract",
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
    await db.collection("users").doc("merchant_uid").set({user_role: "commercant"});
    await db.collection("enseignes").doc("enseigne1").set({
      owner: db.doc("users/merchant_uid"),
    });
    await db.collection("games").doc("game1").set({name: "Jeu test"});

    await db.collection("prizes").doc("prize_owner").set({
      name: "Lot 1",
      winner_id: db.doc("users/some_winner"),
      owner_id: db.doc("users/merchant_uid"),
      enseigne_id: db.doc("enseignes/enseigne1"),
      game_id: db.doc("games/game1"),
      claim_code: "CODE1",
      claimed: false,
    });
    await db.collection("prizes").doc("prize_enseigne_only").set({
      name: "Lot 2 (animation, pas de owner_id)",
      winner_id: db.doc("users/some_other_winner"),
      enseigne_id: db.doc("enseignes/enseigne1"),
      claim_code: "CODE2",
      claimed: false,
    });
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test("contrat : jeu_detail_commercant_page_widget.dart -- where(game_id) + where(owner_id)", async () => {
  const merchant = testEnv.authenticatedContext("merchant_uid");
  const snap = await assertSucceeds(
    merchant.firestore().collection("prizes")
      .where("game_id", "==", merchant.firestore().doc("games/game1"))
      .where("owner_id", "==", merchant.firestore().doc("users/merchant_uid"))
      .get(),
  );
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].id, "prize_owner");
});

test("contrat : home_commercant_page_widget.dart -- where(owner_id) seul (merchantOwnedPrizes)", async () => {
  const merchant = testEnv.authenticatedContext("merchant_uid");
  const snap = await assertSucceeds(
    merchant.firestore().collection("prizes")
      .where("owner_id", "==", merchant.firestore().doc("users/merchant_uid"))
      .get(),
  );
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].id, "prize_owner");
});

test("contrat : home_commercant_page_widget.dart -- ancienne requete enseigne seule refusee; lecture historique individuelle autorisee", async () => {
  await testEnv.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await db.doc('prizes/conflicting_owner').set({owner_id: db.doc('users/other'), enseigne_id: db.doc('enseignes/enseigne1')});
  });
  const merchant = testEnv.authenticatedContext("merchant_uid");
  await assertFails(
    merchant.firestore().collection("prizes")
      .where("enseigne_id", "==", merchant.firestore().doc("enseignes/enseigne1"))
      .get(),
  );
  await assertSucceeds(merchant.firestore().doc("prizes/prize_enseigne_only").get());
});

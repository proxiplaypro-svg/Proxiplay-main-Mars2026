#!/usr/bin/env node

// End-to-end coverage of the exact read path used by the player screen
// "Mes lots" (LotsJoueurPageWidget) since the 2026-03-15 my_lots migration
// (commit 86f4cec) : list users/{uid}/my_lots, then get() each referenced
// prizes/{prizeId} doc. Exercises the 8 scenarios required by the audit:
// ancien lot instantane (sans lien my_lots), nouveau lot instantane, lot
// principal, lot parrainage, lot defi/animation, lot reclame, lot non
// reclame, plusieurs lots pour le meme joueur -- across BOTH the Firestore
// security rules (read permissions) and the repair path (prize_my_lots_repair.js)
// for the one scenario that starts out invisible.
//
//   firebase emulators:exec --only firestore \
//     "node --test test/lots_joueur_read_path.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-lots-joueur-read-path";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");
const {
  initializeTestEnvironment,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const kProjectId = "demo-proxiplay-lots-joueur-read-path";
// admin.initializeApp() sans argument peut resoudre un autre project id que
// GCLOUD_PROJECT (ex. celui de .firebaserc via GOOGLE_CLOUD_PROJECT, injecte
// par `firebase emulators:exec`) -- il doit correspondre exactement au
// projectId de initializeTestEnvironment() ci-dessous pour que les deux SDK
// (Admin et @firebase/rules-unit-testing) lisent/ecrivent les memes donnees
// sur l'emulateur.
if (!admin.apps.length) admin.initializeApp({projectId: kProjectId});
const adminFirestore = admin.firestore();
const {repairMissingMyLotsLink} = require("../prize_my_lots_repair");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: kProjectId,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "../../firestore.rules"),
        "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

test.after(async () => {
  if (testEnv) await testEnv.cleanup();
});

test.beforeEach(async () => {
  const collections = await adminFirestore.listCollections();
  await Promise.all(collections.map((c) => adminFirestore.recursiveDelete(c)));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection("users").doc("player1").set({user_role: "joueur"});
  });
});

// Reproduit exactement le _loadLotItems() de LotsJoueurPageWidget : liste
// my_lots, puis get() chaque prize reference -- avec le meme skip silencieux
// sur les entrees dont le prize n'existe pas/n'est plus lisible.
async function loadLotItemsAsPlayer(playerContext) {
  const myLotsSnap = await playerContext.firestore()
    .collection("users").doc("player1").collection("my_lots").get();
  const items = [];
  for (const myLotDoc of myLotsSnap.docs) {
    const prizeRef = myLotDoc.data().prize_id;
    if (!prizeRef) continue;
    try {
      // eslint-disable-next-line no-await-in-loop
      const prizeSnap = await prizeRef.get();
      if (!prizeSnap.exists) continue;
      items.push({myLotId: myLotDoc.id, prize: prizeSnap.data()});
    } catch (_error) {
      // Reproduit le try/catch "skip silencieux + log" de _loadLotItems().
      continue;
    }
  }
  return items;
}

async function seedPrize(prizeId, overrides = {}) {
  await adminFirestore.collection("prizes").doc(prizeId).set({
    name: "Lot",
    winner_id: adminFirestore.doc("users/player1"),
    claim_code: "CODE",
    claimed: false,
    ...overrides,
  });
}

async function seedMyLot(prizeId) {
  await adminFirestore.collection("users").doc("player1").collection("my_lots").doc(prizeId).set({
    prize_id: adminFirestore.doc(`prizes/${prizeId}`),
  });
}

test("ancien lot instantane (pre-migration, sans lien my_lots) : invisible tant que non repare, puis visible", async () => {
  await seedPrize("old_instant", {prize_type: "secondaire"});
  // Pas de seedMyLot() ici : reproduit un lot cree avant le 2026-03-15.

  const player = testEnv.authenticatedContext("player1");
  const before = await loadLotItemsAsPlayer(player);
  assert.deepEqual(before, []);

  // La reparation additive (prize_my_lots_repair.js) cree le lien manquant
  // sans toucher au prize existant.
  const outcome = await repairMissingMyLotsLink("old_instant");
  assert.equal(outcome.status, "repaired");

  const after = await loadLotItemsAsPlayer(player);
  assert.equal(after.length, 1);
  assert.equal(after[0].myLotId, "old_instant");
});

test("nouveau lot instantane (avec lien my_lots) : visible immediatement", async () => {
  await seedPrize("new_instant", {prize_type: "secondaire"});
  await seedMyLot("new_instant");

  const player = testEnv.authenticatedContext("player1");
  const items = await loadLotItemsAsPlayer(player);
  assert.equal(items.length, 1);
  assert.equal(items[0].prize.prize_type, "secondaire");
});

test("lot principal (grand tirage) : visible via my_lots", async () => {
  await seedPrize("main_prize", {prize_type: "principal"});
  await seedMyLot("main_prize");

  const player = testEnv.authenticatedContext("player1");
  const items = await loadLotItemsAsPlayer(player);
  assert.deepEqual(items.map((i) => i.myLotId), ["main_prize"]);
});

test("lot parrainage : visible via my_lots", async () => {
  await seedPrize("referral_game_g1", {prize_type: "referral_game"});
  await seedMyLot("referral_game_g1");

  const player = testEnv.authenticatedContext("player1");
  const items = await loadLotItemsAsPlayer(player);
  assert.deepEqual(items.map((i) => i.myLotId), ["referral_game_g1"]);
});

test("lot defi/animation : visible via my_lots", async () => {
  await seedPrize("animation_a1", {prize_type: "animation"});
  await seedMyLot("animation_a1");
  await seedPrize("monthly_challenge_m1", {prize_type: "monthly_challenge"});
  await seedMyLot("monthly_challenge_m1");

  const player = testEnv.authenticatedContext("player1");
  const items = await loadLotItemsAsPlayer(player);
  assert.deepEqual(
    items.map((i) => i.myLotId).sort(),
    ["animation_a1", "monthly_challenge_m1"],
  );
});

test("lot reclame (claimed=true) : visible avec son etat", async () => {
  await seedPrize("claimed_prize", {claimed: true});
  await seedMyLot("claimed_prize");

  const player = testEnv.authenticatedContext("player1");
  const items = await loadLotItemsAsPlayer(player);
  assert.equal(items[0].prize.claimed, true);
});

test("lot non reclame (claimed=false) : visible avec son etat", async () => {
  await seedPrize("unclaimed_prize", {claimed: false});
  await seedMyLot("unclaimed_prize");

  const player = testEnv.authenticatedContext("player1");
  const items = await loadLotItemsAsPlayer(player);
  assert.equal(items[0].prize.claimed, false);
});

test("plusieurs lots pour le meme joueur : tous visibles, aucun doublon", async () => {
  await seedPrize("multi_a", {prize_type: "secondaire"});
  await seedMyLot("multi_a");
  await seedPrize("multi_b", {prize_type: "principal"});
  await seedMyLot("multi_b");
  await seedPrize("multi_c", {prize_type: "animation"});
  await seedMyLot("multi_c");

  const player = testEnv.authenticatedContext("player1");
  const items = await loadLotItemsAsPlayer(player);
  assert.deepEqual(
    items.map((i) => i.myLotId).sort(),
    ["multi_a", "multi_b", "multi_c"],
  );
});

test("my_lots list() est directement autorisee par les regles pour son propre uid", async () => {
  await seedPrize("rules_check_prize", {});
  await seedMyLot("rules_check_prize");

  const player = testEnv.authenticatedContext("player1");
  await assertSucceeds(
    player.firestore().collection("users").doc("player1").collection("my_lots").get(),
  );
});

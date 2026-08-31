#!/usr/bin/env node

// Verifies prize_my_lots_repair.js: the audit (findMissingMyLotsLinks) is
// read-only and finds every prize whose winner_id is a usable
// DocumentReference but has no matching users/{uid}/my_lots/{prizeId} entry,
// across every prize-awarding mechanism (they all write to the same
// "prizes" collection, only prize_type/discriminator fields differ). The
// repair (repairMissingMyLotsLink) only ever CREATES the missing entry, is
// idempotent, never touches "prizes", and never overwrites an existing
// my_lots entry. Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/prize_my_lots_repair.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-my-lots-repair-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();
const firestore = admin.firestore();
const {
  findMissingMyLotsLinks,
  repairMissingMyLotsLink,
} = require("../prize_my_lots_repair");

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(collections.map((collection) => firestore.recursiveDelete(collection)));
}

async function seedUser(uid) {
  await firestore.collection("users").doc(uid).set({user_role: "joueur"});
}

async function seedPrize(prizeId, overrides = {}) {
  await firestore.collection("prizes").doc(prizeId).set({
    name: "Lot test",
    claim_code: "CODE",
    claimed: false,
    ...overrides,
  });
}

async function myLotDoc(uid, prizeId) {
  return firestore.collection("users").doc(uid).collection("my_lots").doc(prizeId).get();
}

test.beforeEach(clearFirestore);

test("audit : detecte un lot instantane historique (avant migration my_lots) sans lien", async () => {
  await seedUser("winner1");
  await seedPrize("old_instant_prize", {
    prize_type: "secondaire",
    winner_id: firestore.doc("users/winner1"),
  });

  const result = await findMissingMyLotsLinks({});
  assert.deepEqual(
    result.missing.map((m) => m.prizeId),
    ["old_instant_prize"],
  );
});

test("audit : un lot instantane recent avec my_lots deja present n'est pas signale", async () => {
  await seedUser("winner1");
  await seedPrize("new_instant_prize", {
    prize_type: "secondaire",
    winner_id: firestore.doc("users/winner1"),
  });
  await firestore.collection("users").doc("winner1").collection("my_lots").doc("new_instant_prize").set({
    prize_id: firestore.doc("prizes/new_instant_prize"),
  });

  const result = await findMissingMyLotsLinks({});
  assert.deepEqual(result.missing, []);
});

test("audit : couvre lot principal, parrainage et defi/animation (memes conditions, prize_type different)", async () => {
  await seedUser("winner1");
  await seedPrize("main_prize", {prize_type: "principal", winner_id: firestore.doc("users/winner1")});
  await seedPrize("referral_game_g1", {prize_type: "referral_game", winner_id: firestore.doc("users/winner1")});
  await seedPrize("animation_a1", {prize_type: "animation", winner_id: firestore.doc("users/winner1")});
  await seedPrize("monthly_challenge_m1", {prize_type: "monthly_challenge", winner_id: firestore.doc("users/winner1")});

  const result = await findMissingMyLotsLinks({});
  assert.deepEqual(
    result.missing.map((m) => m.prizeId).sort(),
    ["animation_a1", "main_prize", "monthly_challenge_m1", "referral_game_g1"].sort(),
  );
});

test("audit : un lot sans gagnant (pas encore attribue) n'est pas signale", async () => {
  await seedPrize("unclaimed_prize", {prize_type: "secondaire"});

  const result = await findMissingMyLotsLinks({});
  assert.deepEqual(result.missing, []);
});

test("audit : un winner_id incompatible (chaine plutot que DocumentReference) est journalise a part, pas dans missing", async () => {
  await seedUser("winner1");
  await seedPrize("bad_format_prize", {prize_type: "secondaire", winner_id: "winner1"});

  const result = await findMissingMyLotsLinks({});
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.skippedNoWinner, [{prizeId: "bad_format_prize", winnerIdType: "string"}]);
});

test("audit : plusieurs lots pour le meme joueur sont tous detectes independamment", async () => {
  await seedUser("winner1");
  await seedPrize("prize_a", {winner_id: firestore.doc("users/winner1")});
  await seedPrize("prize_b", {winner_id: firestore.doc("users/winner1")});
  await firestore.collection("users").doc("winner1").collection("my_lots").doc("prize_a").set({
    prize_id: firestore.doc("prizes/prize_a"),
  });

  const result = await findMissingMyLotsLinks({});
  assert.deepEqual(result.missing.map((m) => m.prizeId), ["prize_b"]);
});

test("reparation : cree l'entree my_lots manquante sans toucher a prizes", async () => {
  await seedUser("winner1");
  await seedPrize("old_prize", {prize_type: "secondaire", winner_id: firestore.doc("users/winner1")});

  const outcome = await repairMissingMyLotsLink("old_prize");
  assert.equal(outcome.status, "repaired");

  const myLotSnap = await myLotDoc("winner1", "old_prize");
  assert.ok(myLotSnap.exists);
  assert.equal(myLotSnap.data().prize_id.path, "prizes/old_prize");

  const prizeSnap = await firestore.collection("prizes").doc("old_prize").get();
  assert.equal(prizeSnap.data().prize_type, "secondaire");
  assert.equal(prizeSnap.data().winner_id.path, "users/winner1");
});

test("reparation : idempotente, ne cree pas de doublon si le lien existe deja", async () => {
  await seedUser("winner1");
  await seedPrize("already_linked_prize", {winner_id: firestore.doc("users/winner1")});
  await firestore.collection("users").doc("winner1").collection("my_lots").doc("already_linked_prize").set({
    prize_id: firestore.doc("prizes/already_linked_prize"),
    custom_marker: "do-not-overwrite",
  });

  const outcome = await repairMissingMyLotsLink("already_linked_prize");
  assert.equal(outcome.status, "already_linked");

  const myLotSnap = await myLotDoc("winner1", "already_linked_prize");
  assert.equal(myLotSnap.data().custom_marker, "do-not-overwrite");
});

test("reparation : deux appels successifs sur le meme prize ne creent qu'une seule entree", async () => {
  await seedUser("winner1");
  await seedPrize("dup_check_prize", {winner_id: firestore.doc("users/winner1")});

  const first = await repairMissingMyLotsLink("dup_check_prize");
  const second = await repairMissingMyLotsLink("dup_check_prize");
  assert.equal(first.status, "repaired");
  assert.equal(second.status, "already_linked");

  const snap = await firestore.collection("users").doc("winner1").collection("my_lots").get();
  assert.equal(snap.size, 1);
});

test("reparation : leve une erreur explicite si le prize n'existe pas", async () => {
  await assert.rejects(
    () => repairMissingMyLotsLink("does_not_exist"),
    /introuvable/,
  );
});

test("reparation : leve une erreur explicite si winner_id n'est pas exploitable", async () => {
  await seedPrize("no_winner_prize", {});
  await assert.rejects(
    () => repairMissingMyLotsLink("no_winner_prize"),
    /winner_id/,
  );
});

test("audit : lot reclame (claimed=true) et non reclame (claimed=false) sont tous deux detectes", async () => {
  await seedUser("winner1");
  await seedPrize("claimed_prize", {winner_id: firestore.doc("users/winner1"), claimed: true});
  await seedPrize("unclaimed_prize", {winner_id: firestore.doc("users/winner1"), claimed: false});

  const result = await findMissingMyLotsLinks({});
  assert.deepEqual(
    result.missing.map((m) => m.prizeId).sort(),
    ["claimed_prize", "unclaimed_prize"],
  );
});

test("audit : pagination via lastId/hasMore permet de parcourir toute la collection", async () => {
  await seedUser("winner1");
  for (let i = 0; i < 5; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await seedPrize(`page_prize_${i}`, {winner_id: firestore.doc("users/winner1")});
  }

  const firstPage = await findMissingMyLotsLinks({pageSize: 2});
  assert.equal(firstPage.scanned, 2);
  assert.equal(firstPage.hasMore, true);

  const secondPage = await findMissingMyLotsLinks({pageSize: 2, startAfterId: firstPage.lastId});
  assert.equal(secondPage.scanned, 2);

  const thirdPage = await findMissingMyLotsLinks({pageSize: 2, startAfterId: secondPage.lastId});
  assert.equal(thirdPage.scanned, 1);
  assert.equal(thirdPage.hasMore, false);

  const allFound = [...firstPage.missing, ...secondPage.missing, ...thirdPage.missing].map((m) => m.prizeId).sort();
  assert.deepEqual(allFound, ["page_prize_0", "page_prize_1", "page_prize_2", "page_prize_3", "page_prize_4"]);
});

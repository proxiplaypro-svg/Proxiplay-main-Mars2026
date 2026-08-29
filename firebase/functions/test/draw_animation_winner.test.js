#!/usr/bin/env node

// Verifies the animation draw engine is transactional and idempotent, and
// that deleted/suspended accounts are excluded from the draw -- the 3 gaps
// found in the pre-fix draw_animation_winner.js (separate, non-transactional
// writes for winner/current, winner_uid+status, prizes, and my_lots; no
// eligibility filtering). Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/draw_animation_winner.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-animation-draw-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();
const firestore = admin.firestore();
const { drawWinnerForAnimation, repairAnimationDraw } = require("../draw_animation_winner");

const NOW = admin.firestore.Timestamp.fromDate(new Date("2026-06-15T12:00:00.000Z"));

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(collections.map((collection) => firestore.recursiveDelete(collection)));
}

async function seedAnimation(id = "anim-1", overrides = {}) {
  await firestore.collection("animations").doc(id).set({
    name: "Animation test",
    prize_description: "Un gros lot",
    status: "active",
    end_date: admin.firestore.Timestamp.fromDate(new Date("2026-06-14T00:00:00.000Z")),
    ...overrides,
  });
}

async function seedUser(uid, overrides = {}) {
  await firestore.collection("users").doc(uid).set({
    first_name: uid,
    email: `${uid}@example.test`,
    user_role: "joueur",
    ...overrides,
  });
}

async function seedEntry(animationId, uid, overrides = {}) {
  await firestore
    .collection("animations")
    .doc(animationId)
    .collection("entries")
    .doc(uid)
    .set({ threshold_reached: true, ...overrides });
}

async function getPrize(animationId = "anim-1") {
  return firestore.collection("prizes").doc(`animation_${animationId}`).get();
}

async function myLotsCount(uid) {
  return (await firestore.collection("users").doc(uid).collection("my_lots").get()).size;
}

test.beforeEach(clearFirestore);

test("tirage : gagnant, prize, my_lots et winner/current ecrits ensemble", async () => {
  await seedAnimation();
  await seedUser("player1");
  await seedEntry("anim-1", "player1");

  const result = await drawWinnerForAnimation("anim-1", { now: NOW });

  assert.equal(result.status, "completed");
  assert.equal(result.winnerUid, "player1");

  const animationSnap = await firestore.collection("animations").doc("anim-1").get();
  assert.equal(animationSnap.data().winner_uid, "player1");
  assert.equal(animationSnap.data().status, "ended");

  const prizeSnap = await getPrize();
  assert.equal(prizeSnap.exists, true);
  assert.equal(prizeSnap.data().winner_id.id, "player1");
  assert.equal(prizeSnap.data().claimed, false);
  assert.ok(prizeSnap.data().claim_code);

  assert.equal(await myLotsCount("player1"), 1);

  const winnerCurrentSnap = await firestore
    .collection("animations")
    .doc("anim-1")
    .collection("winner")
    .doc("current")
    .get();
  assert.equal(winnerCurrentSnap.data().uid, "player1");
});

test("comptes supprimes/suspendus exclus du tirage", async () => {
  await seedAnimation();
  await seedUser("deleted_player", { deleted: true });
  await seedUser("suspended_player", { account_status: "suspended" });
  await seedUser("eligible_player");
  await seedEntry("anim-1", "deleted_player");
  await seedEntry("anim-1", "suspended_player");
  await seedEntry("anim-1", "eligible_player");

  const result = await drawWinnerForAnimation("anim-1", { now: NOW });

  assert.equal(result.status, "completed");
  assert.equal(result.winnerUid, "eligible_player");
  assert.equal(result.eligibleCount, 1);
  assert.equal(result.qualifiedCount, 3);
});

test("aucun candidat eligible -> anime marquee terminee sans lot", async () => {
  await seedAnimation();
  await seedUser("deleted_player", { deleted: true });
  await seedEntry("anim-1", "deleted_player");

  const result = await drawWinnerForAnimation("anim-1", { now: NOW });

  assert.equal(result.status, "no_eligible_entries");

  const animationSnap = await firestore.collection("animations").doc("anim-1").get();
  assert.equal(animationSnap.data().status, "ended");
  assert.equal(animationSnap.data().winner_uid, undefined);

  const prizeSnap = await getPrize();
  assert.equal(prizeSnap.exists, false);
});

test("aucune entree qualifiee -> ne marque rien (retente la nuit suivante)", async () => {
  await seedAnimation();

  const result = await drawWinnerForAnimation("anim-1", { now: NOW });

  assert.equal(result.status, "no_qualified_entries");

  const animationSnap = await firestore.collection("animations").doc("anim-1").get();
  assert.equal(animationSnap.data().status, "active");
});

test("rejouer le tirage sur une animation deja tiree ne cree pas de second prize", async () => {
  await seedAnimation();
  await seedUser("player1");
  await seedEntry("anim-1", "player1");

  await drawWinnerForAnimation("anim-1", { now: NOW });
  const secondResult = await drawWinnerForAnimation("anim-1", { now: NOW });

  assert.equal(secondResult.status, "already_drawn");
  assert.equal(secondResult.winnerUid, "player1");
  assert.equal(await myLotsCount("player1"), 1);
});

test("reparation : winner_uid pose sans prize/my_lots (etat pre-correctif) est complete", async () => {
  await seedAnimation("anim-1", { winner_uid: "player1", drawn_at: NOW });
  await seedUser("player1");

  const result = await repairAnimationDraw("anim-1");

  assert.equal(result.status, "repaired_prize_and_my_lots");

  const prizeSnap = await getPrize();
  assert.equal(prizeSnap.exists, true);
  assert.equal(prizeSnap.data().winner_id.id, "player1");
  assert.equal(await myLotsCount("player1"), 1);
});

test("reparation est idempotente (rejouee, ne duplique rien)", async () => {
  await seedAnimation("anim-1", { winner_uid: "player1", drawn_at: NOW });
  await seedUser("player1");

  await repairAnimationDraw("anim-1");
  const secondResult = await repairAnimationDraw("anim-1");

  assert.equal(secondResult.status, "repaired_my_lots");
  assert.equal(await myLotsCount("player1"), 1);
});

test("reparation : rien a faire si aucun winner_uid", async () => {
  await seedAnimation();

  const result = await repairAnimationDraw("anim-1");

  assert.equal(result.status, "nothing_to_repair");
});

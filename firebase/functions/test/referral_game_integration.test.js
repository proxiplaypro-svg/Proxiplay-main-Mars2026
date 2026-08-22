#!/usr/bin/env node

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-referral-game-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();
const firestore = admin.firestore();
const {addReferralGameTicket, reconcileReferralGameTickets} = require("../lib/share_promo/referral_games");
const {drawReferralGame, repairReferralGameDraw} = require("../referral_game_engine");

const NOW = admin.firestore.Timestamp.fromDate(new Date("2026-06-15T12:00:00.000Z"));
const TICKET_NOW = admin.firestore.Timestamp.fromDate(new Date("2026-06-05T12:00:00.000Z"));

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(collections.map((collection) => firestore.recursiveDelete(collection)));
}

async function seedGame(id = "game-1", overrides = {}) {
  await firestore.collection("referral_games").doc(id).set({
    title: "Tirage parrainage",
    prize_description: "Un lot",
    status: "active",
    start_date: admin.firestore.Timestamp.fromDate(new Date("2026-06-01T00:00:00.000Z")),
    end_date: admin.firestore.Timestamp.fromDate(new Date("2026-06-30T00:00:00.000Z")),
    ticket_count: 0,
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

async function seedReferral(id, inviterUid, overrides = {}) {
  await firestore.collection("referrals").doc(id).set({
    inviterUid,
    status: "accepted",
    acceptedAt: TICKET_NOW,
    ...overrides,
  });
}

async function ticketCount(gameId = "game-1") {
  return (await firestore.collection("referral_games").doc(gameId).collection("entries").get()).size;
}

test.beforeEach(clearFirestore);

test("referral accepte, retry et appels concurrents donnent un ticket deterministe", async () => {
  await seedGame();
  await seedUser("parrain");
  await seedReferral("ref-1", "parrain");
  const results = await Promise.all([
    addReferralGameTicket("game-1", "ref-1", TICKET_NOW),
    addReferralGameTicket("game-1", "ref-1", TICKET_NOW),
    addReferralGameTicket("game-1", "ref-1", TICKET_NOW),
  ]);
  assert.equal(results.filter((result) => result === "created").length, 1);
  assert.equal(await ticketCount(), 1);
  assert.equal((await firestore.doc("referral_games/game-1/entries/ref-1").get()).exists, true);
});

test("plusieurs filleuls donnent plusieurs tickets, les referrals invalides ou hors periode aucun", async () => {
  await seedGame();
  await seedUser("parrain");
  await Promise.all([seedReferral("a", "parrain"), seedReferral("b", "parrain"), seedReferral("c", "parrain", {status: "pending"})]);
  assert.equal(await addReferralGameTicket("game-1", "a", TICKET_NOW), "created");
  assert.equal(await addReferralGameTicket("game-1", "b", TICKET_NOW), "created");
  assert.equal(await addReferralGameTicket("game-1", "c", TICKET_NOW), "ineligible");
  assert.equal(await addReferralGameTicket("game-1", "a", admin.firestore.Timestamp.fromDate(new Date("2026-07-01T00:00:00.000Z"))), "already_exists");
  assert.equal(await ticketCount(), 2);
});

test("parrain supprime, rejected ou suspendu est exclu du ticket", async () => {
  await seedGame();
  for (const [uid, state] of [["deleted", {auto_deleted: true}], ["rejected", {account_status: "rejected"}], ["suspended", {player_status_cached: "suspendu"}]]) {
    await seedUser(uid, state);
    await seedReferral(`ref-${uid}`, uid);
    assert.equal(await addReferralGameTicket("game-1", `ref-${uid}`, TICKET_NOW), "ineligible");
  }
  assert.equal(await ticketCount(), 0);
});

test("tirage cree un seul prize et un seul my_lots, y compris au retry", async () => {
  await seedGame("draw-game", {end_date: admin.firestore.Timestamp.fromDate(new Date("2026-06-10T00:00:00.000Z"))});
  await seedUser("winner");
  await seedReferral("draw-ref", "winner");
  await addReferralGameTicket("draw-game", "draw-ref", TICKET_NOW);
  const first = await drawReferralGame("draw-game", {now: NOW});
  const second = await drawReferralGame("draw-game", {now: NOW});
  assert.equal(first.status, "completed");
  assert.equal(second.status, "already_finalized");
  assert.equal((await firestore.collection("prizes").doc("referral_game_draw-game").get()).exists, true);
  assert.equal((await firestore.collection("users").doc("winner").collection("my_lots").doc("referral_game_draw-game").get()).exists, true);
});

test("jeu sans ticket se termine sans gagnant", async () => {
  await seedGame("empty-game", {end_date: admin.firestore.Timestamp.fromDate(new Date("2026-06-10T00:00:00.000Z"))});
  const result = await drawReferralGame("empty-game", {now: NOW});
  assert.equal(result.status, "no_eligible_entries");
  assert.equal((await firestore.doc("referral_games/empty-game").get()).data().draw_status, "no_eligible_entries");
});

test("reconciliation recree un ticket manquant et reparation restaure my_lots", async () => {
  await seedGame("repair-game", {end_date: admin.firestore.Timestamp.fromDate(new Date("2026-06-10T00:00:00.000Z"))});
  await seedUser("parrain");
  await seedReferral("repair-ref", "parrain");
  const reconciliation = await reconcileReferralGameTickets("repair-game");
  assert.equal(reconciliation.created, 1);
  await drawReferralGame("repair-game", {now: NOW});
  await firestore.doc("users/parrain/my_lots/referral_game_repair-game").delete();
  const repair = await repairReferralGameDraw("repair-game");
  assert.equal(repair.status, "repaired_my_lots");
  assert.equal((await firestore.doc("users/parrain/my_lots/referral_game_repair-game").get()).exists, true);
});

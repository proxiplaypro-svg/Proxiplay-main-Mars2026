#!/usr/bin/env node

// Verifies the managed_by_admin gate added to notifyAnimationWinner()
// (draw_animation_winner.js) for the "gros lot" animation draw: a shop
// managed by Proxiplay must not receive the merchant "winner drawn" push,
// while the winning PLAYER's own email/push and the draw logic itself
// (winner selection, prize, my_lots) stay entirely untouched. See
// firestore.rules / notifyPrizeWon for the equivalent gate on the regular
// per-game prize path -- this file covers the separate animation path found
// during the final review, which shares no code with notifyPrizeWon.
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/draw_animation_winner_managed_by_admin.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
// Projet dedie : voir la meme precaution dans notify_prize_won_idempotence.test.js.
process.env.GCLOUD_PROJECT = "demo-proxiplay-animation-managed-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

const functionsTest = require("firebase-functions-test")();
functionsTest.mockConfig({
  smtp: {
    host: "smtp.test",
    port: "587",
    secure: "false",
    user: "test-user",
    pass: "test-pass",
    from_email: "noreply@proxiplay.fr",
    from_name: "Proxiplay",
  },
});

// createSmtpMailer() (draw_animation_winner.js) calls nodemailer.createTransport()
// itself -- stubbing the shared module is the only way to observe what it
// tries to send without hitting a real SMTP server (same technique as
// notify_prize_won_idempotence.test.js / notify_prize_won_managed_by_admin.test.js).
let sentEmails = [];
nodemailer.createTransport = () => ({
  sendMail: async (mail) => {
    sentEmails.push(mail);
    return {accepted: [mail.to]};
  },
});

if (!admin.apps.length) {
  admin.initializeApp();
}
const firestore = admin.firestore();
const {drawWinnerForAnimation} = require("../draw_animation_winner");

const kPushNotificationsCollection = "ff_push_notifications";
const NOW = admin.firestore.Timestamp.fromDate(new Date("2026-06-15T12:00:00.000Z"));

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(collections.map((col) => firestore.recursiveDelete(col)));
}

test.beforeEach(async () => {
  await clearFirestore();
  sentEmails = [];
});

test.after(async () => {
  await functionsTest.cleanup();
});

// Seede une animation avec un joueur qualifie, et un jeu participant
// (animation_id) rattache a une enseigne dont on controle managed_by_admin.
// managedByAdmin === undefined => champ absent (cas "A. absent", pas
// seulement "false" explicite).
async function seedScenario({managedByAdmin}) {
  const ownerRef = firestore.collection("users").doc("merchant1");
  const enseigneRef = firestore.collection("enseignes").doc("shop1");
  const gameRef = firestore.collection("games").doc("game1");
  const playerRef = firestore.collection("users").doc("player1");

  await ownerRef.set({
    user_role: "commercant",
    email: "merchant@example.com",
    company_name: "Ma boutique",
  });
  await enseigneRef.set({
    name: "Ma boutique",
    owner: ownerRef,
    ...(managedByAdmin === undefined ? {} : {managed_by_admin: managedByAdmin}),
  });
  await gameRef.set({name: "Jeu Test", enseigne_ref: enseigneRef, animation_id: "anim-1"});
  await playerRef.set({first_name: "Alice", email: "alice@example.com", user_role: "joueur"});

  await firestore.collection("animations").doc("anim-1").set({
    name: "Animation test",
    prize_description: "Un gros lot",
    status: "active",
    end_date: admin.firestore.Timestamp.fromDate(new Date("2026-06-14T00:00:00.000Z")),
  });
  await firestore.collection("animations").doc("anim-1").collection("entries")
    .doc("player1").set({threshold_reached: true});

  return {ownerRef, enseigneRef, gameRef, playerRef};
}

async function pushDocsFor(userRef) {
  const snapshot = await firestore.collection(kPushNotificationsCollection)
    .where("user_refs", "==", userRef.path)
    .get();
  return snapshot.docs;
}

test("4. animation, commerce normal (managed_by_admin absent) : push marchand inchange", async () => {
  const {ownerRef} = await seedScenario({managedByAdmin: undefined});

  const result = await drawWinnerForAnimation("anim-1", {now: NOW});
  assert.equal(result.status, "completed");

  const merchantPushes = await pushDocsFor(ownerRef);
  assert.equal(merchantPushes.length, 1, "le push marchand doit toujours partir pour une enseigne non geree");
  assert.match(merchantPushes[0].data().notification_title, /Tirage au sort/);
});

test("5. animation, managed_by_admin=true : aucun push marchand", async () => {
  const {ownerRef} = await seedScenario({managedByAdmin: true});

  const result = await drawWinnerForAnimation("anim-1", {now: NOW});
  assert.equal(result.status, "completed");

  const merchantPushes = await pushDocsFor(ownerRef);
  assert.equal(merchantPushes.length, 0, "aucun push marchand ne doit partir pour une enseigne geree");
});

test("6. notification joueur (animation) : email et push inchanges, meme pour une enseigne geree", async () => {
  const {playerRef} = await seedScenario({managedByAdmin: true});

  const result = await drawWinnerForAnimation("anim-1", {now: NOW});
  assert.equal(result.status, "completed");
  assert.equal(result.winnerUid, "player1");

  const playerEmails = sentEmails.filter((mail) => mail.to === "alice@example.com");
  assert.equal(playerEmails.length, 1, "l'email joueur doit toujours partir");

  const playerPushes = await pushDocsFor(playerRef);
  assert.equal(playerPushes.length, 1, "le push joueur doit toujours partir");
  assert.match(playerPushes[0].data().notification_title, /gros lot/);
});

test("le tirage, le prize et my_lots restent inchanges par le gate managed_by_admin", async () => {
  await seedScenario({managedByAdmin: true});

  const result = await drawWinnerForAnimation("anim-1", {now: NOW});

  assert.equal(result.status, "completed");
  assert.equal(result.winnerUid, "player1");
  assert.ok(result.claimCode);

  const prizeSnap = await firestore.collection("prizes").doc("animation_anim-1").get();
  assert.equal(prizeSnap.exists, true);
  assert.equal(prizeSnap.data().claimed, false);

  const myLotSnap = await firestore.collection("users").doc("player1")
    .collection("my_lots").doc("animation_anim-1").get();
  assert.equal(myLotSnap.exists, true);
});

#!/usr/bin/env node

// notifyPrizeWon for a referral game prize: no shop, so the player email and
// push speak of the referral game and "Mes lots", never "chez votre enseigne".
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/notify_prize_won_referral_game.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
// Dedicated project: same precaution as notify_prize_won_idempotence.test.js.
process.env.GCLOUD_PROJECT = "demo-proxiplay-notify-referral-test";

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

let sentEmails = [];
nodemailer.createTransport = () => ({
  sendMail: async (mail) => {
    sentEmails.push(mail);
    return {accepted: [mail.to]};
  },
});

const myFunctions = require("../index.js");
const wrappedNotifyPrizeWon = functionsTest.wrap(myFunctions.notifyPrizeWon);
const firestore = admin.firestore();

test.beforeEach(async () => {
  const collections = await firestore.listCollections();
  await Promise.all(collections.map((col) => firestore.recursiveDelete(col)));
  sentEmails = [];
});

test.after(async () => {
  await functionsTest.cleanup();
});

async function seedPrize(prizeType) {
  const winnerRef = firestore.collection("users").doc("winner1");
  const prizeRef = firestore.collection("prizes").doc("referral_game_game1");
  await winnerRef.set({first_name: "Alice", city: "Paris", email: "alice@example.com"});
  // Same shape as prizePayload() in referral_game_engine.js.
  await prizeRef.set({
    prize_type: prizeType,
    fulfillment_type: "platform",
    name: "Bon d'achat 50 euros",
    winner_id: winnerRef,
    referral_game_id: "game1",
    claim_code: "ABC123",
    claimed: false,
  });
  await winnerRef.collection("my_lots").doc(prizeRef.id).set({prize_id: prizeRef});
  await wrappedNotifyPrizeWon(await prizeRef.get(), {params: {prizeId: prizeRef.id}});
}

async function playerPush() {
  const pushDoc = await firestore.collection("ff_push_notifications")
    .doc("prize_referral_game_game1_player_push").get();
  assert.equal(pushDoc.exists, true, "the player push is queued");
  return JSON.stringify(pushDoc.data());
}

test("referral game prize: email and push name the referral game and Mes lots", async () => {
  await seedPrize("referral_game");
  const emails = sentEmails.filter((mail) => mail.to === "alice@example.com");
  assert.equal(emails.length, 1);
  const email = JSON.stringify(emails[0]);
  assert.match(email, /au jeu du parrainage ProxiPlay/);
  assert.match(email, /Mes lots/);
  assert.match(email, /ABC123/);
  assert.doesNotMatch(email, /votre enseigne/);
  const push = await playerPush();
  assert.match(push, /Vous avez gagné le jeu du parrainage !/);
  assert.match(push, /Mes lots/);
  assert.doesNotMatch(push, /chez/);
  assert.equal(sentEmails.filter((mail) => mail.to !== "alice@example.com").length, 0, "no merchant email");
});

test("other platform prizes keep their current texts", async () => {
  await seedPrize("animation");
  const email = JSON.stringify(sentEmails.find((mail) => mail.to === "alice@example.com"));
  assert.doesNotMatch(email, /jeu du parrainage/);
  const push = await playerPush();
  assert.match(push, /Vous avez gagné Bon d'achat 50 euros chez/);
});

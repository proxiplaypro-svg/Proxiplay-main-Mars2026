#!/usr/bin/env node

// Verifies notifyPrizeWon only ever sends the merchant "prize won" email
// once for a given prize, even if the Firestore onCreate trigger fires
// more than once for the same document (Cloud Functions v1 only
// guarantees "at least once" delivery, so duplicate invocations are a
// real production scenario, not a hypothetical). Run against the local
// Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/notify_prize_won_idempotence.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
// Dedicated project id: several other test files in this directory share
// "demo-proxiplay-rules-test" and running them together intermittently
// leaks Firestore state across files. Giving this file its own project
// avoids adding a fifth writer to that shared namespace.
process.env.GCLOUD_PROJECT = "demo-proxiplay-notify-prize-test";

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

// notifyPrizeWon calls nodemailer.createTransport() itself (via
// createSmtpMailer), so there's no injection point for a fake mailer --
// stubbing the shared nodemailer module is the only way to observe what
// it actually tries to send without hitting a real SMTP server.
let sentEmails = [];
nodemailer.createTransport = () => ({
  sendMail: async (mail) => {
    sentEmails.push(mail);
    return { accepted: [mail.to] };
  },
});

const myFunctions = require("../index.js");
const wrappedNotifyPrizeWon = functionsTest.wrap(myFunctions.notifyPrizeWon);

const firestore = admin.firestore();

async function clearFirestore() {
  // Plain listDocuments()+delete() only clears root collections; it misses
  // nested subcollections like the prize-notification status doc living
  // under system_jobs/{job}/entries/{prizeId}, which would otherwise leak
  // "already sent" state into the next test. recursiveDelete() clears both.
  const collections = await firestore.listCollections();
  await Promise.all(collections.map((col) => firestore.recursiveDelete(col)));
}

test.before(async () => {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
});

test.beforeEach(async () => {
  await clearFirestore();
  sentEmails = [];
});

test.after(async () => {
  await functionsTest.cleanup();
});

async function seedPrize() {
  const winnerRef = firestore.collection("users").doc("winner1");
  const merchantRef = firestore.collection("users").doc("merchant1");
  const gameRef = firestore.collection("games").doc("game1");
  const prizeRef = firestore.collection("prizes").doc("prize1");

  await winnerRef.set({
    first_name: "Alice",
    last_name: "Dupont",
    city: "Paris",
    email: "alice@example.com",
  });
  await merchantRef.set({
    user_role: "commercant",
    email: "merchant@example.com",
    company_name: "Ma boutique",
  });
  await gameRef.set({ name: "Jeu Test", create_by: merchantRef });
  await prizeRef.set({
    winner_id: winnerRef,
    owner_id: merchantRef,
    game_id: gameRef,
    name: "Lot test",
    claim_code: "CODE123",
  });

  return prizeRef;
}

test("notifyPrizeWon envoie le mail commerçant une seule fois, meme si le trigger se declenche deux fois", async () => {
  const prizeRef = await seedPrize();
  const snapshot = await prizeRef.get();
  const context = { params: { prizeId: prizeRef.id } };

  await wrappedNotifyPrizeWon(snapshot, context);
  await wrappedNotifyPrizeWon(snapshot, context); // simulate a duplicate trigger delivery

  const merchantEmails = sentEmails.filter((mail) => mail.to === "merchant@example.com");
  assert.equal(
    merchantEmails.length,
    1,
    `un seul e-mail marchand doit etre envoye (recu: ${merchantEmails.length})`,
  );
});

test("notifyPrizeWon envoie effectivement le mail commercant au premier declenchement", async () => {
  const prizeRef = await seedPrize();
  const snapshot = await prizeRef.get();
  const context = { params: { prizeId: prizeRef.id } };

  await wrappedNotifyPrizeWon(snapshot, context);

  const merchantEmails = sentEmails.filter((mail) => mail.to === "merchant@example.com");
  assert.equal(
    merchantEmails.length,
    1,
    `le mail commercant doit partir des le premier appel (recu: ${merchantEmails.length})`,
  );
});

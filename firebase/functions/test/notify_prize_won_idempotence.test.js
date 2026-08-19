#!/usr/bin/env node

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-rules-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");
const wrappedNotifyPrizeWon = functionsTest.wrap(myFunctions.notifyPrizeWon);
const wrappedParticipate = functionsTest.wrap(myFunctions.participateInGameTransaction);

const firestore = admin.firestore();

let sendEmailCalls = [];

function createFakeMailer() {
  return {
    transporter: {
      sendMail: async (mail) => {
        sendEmailCalls.push(mail);
        return Promise.resolve({accepted: [mail.to]});
      },
    },
    from: "Proxiplay <noreply@proxiplay.fr>",
    replyTo: "noreply@proxiplay.fr",
  };
}

function wrapSendEmail() {
  const helpersPath = require.resolve("../index.js");
  const original = require.cache[helpersPath].exports;
  return original;
}

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(collections.map(async (col) => {
    const docs = await col.listDocuments();
    await Promise.all(docs.map((doc) => doc.delete()));
  }));
}

test.before(async () => {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  await clearFirestore();
});

test.after(async () => {
  await functionsTest.cleanup();
});

test("notifyPrizeWon envoie une seule fois le mail commerçant", async () => {
  const prizeRef = firestore.collection("prizes").doc("prize1");
  await firestore.collection("users").doc("merchant1").set({ email: "merchant@example.com" });
  await prizeRef.set({
    winner_id: firestore.doc("users/winner1"),
    owner_id: firestore.doc("users/merchant1"),
    name: "Lot test",
    claim_code: "CODE123",
    game_id: firestore.doc("games/game1"),
  });

  sendEmailCalls = [];

  const result = await wrappedNotifyPrizeWon({
    after: {
      data: prizeRef,
    },
  });

  assert.equal(sendEmailCalls.length, 1, "un seul e-mail marchand doit être envoyé");
});

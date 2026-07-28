#!/usr/bin/env node

// Verifies the getPrizeWinnerContactForMerchant callable (Partie D) only
// returns winner PII to the merchant who actually owns the prize (or an
// admin), and never to anyone else. Run against the local Firestore
// emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/get_prize_winner_contact_for_merchant.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-rules-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");
const wrapped = functionsTest.wrap(myFunctions.getPrizeWinnerContactForMerchant);

const firestore = admin.firestore();

test.before(async () => {
  await firestore.collection("users").doc("alice_uid").set({
    user_role: "joueur",
    first_name: "Alice",
    last_name: "Dupont",
    city: "Paris",
    email: "alice@example.com",
    phone_number: "0600000000",
  });
  await firestore.collection("users").doc("merchant_uid").set({
    user_role: "commercant",
  });
  await firestore.collection("users").doc("other_merchant_uid").set({
    user_role: "commercant",
  });
  await firestore.collection("users").doc("admin_uid").set({
    user_role: "admin",
  });
  await firestore.collection("enseignes").doc("ens1").set({
    name: "Ma boutique",
    owner: firestore.doc("users/merchant_uid"),
  });
  await firestore.collection("prizes").doc("prize1").set({
    winner_id: firestore.doc("users/alice_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
    owner_id: firestore.doc("users/merchant_uid"),
  });
});

test.after(async () => {
  await functionsTest.cleanup();
});

test("le commercant proprietaire recoit les coordonnees du gagnant", async () => {
  const result = await wrapped(
    { prizeId: "prize1" },
    { auth: { uid: "merchant_uid" } },
  );
  assert.equal(result.firstName, "Alice");
  assert.equal(result.lastName, "Dupont");
  assert.equal(result.city, "Paris");
  assert.equal(result.email, "alice@example.com");
  assert.equal(result.phoneNumber, "0600000000");
});

test("un admin recoit aussi les coordonnees du gagnant", async () => {
  const result = await wrapped(
    { prizeId: "prize1" },
    { auth: { uid: "admin_uid" } },
  );
  assert.equal(result.firstName, "Alice");
});

test("un autre commercant est refuse", async () => {
  await assert.rejects(
    () => wrapped({ prizeId: "prize1" }, { auth: { uid: "other_merchant_uid" } }),
    (error) => {
      assert.equal(error.code, "permission-denied");
      return true;
    },
  );
});

test("un appel non authentifie est refuse", async () => {
  await assert.rejects(
    () => wrapped({ prizeId: "prize1" }, {}),
    (error) => {
      assert.equal(error.code, "unauthenticated");
      return true;
    },
  );
});

test("un prizeId inexistant est refuse", async () => {
  await assert.rejects(
    () => wrapped({ prizeId: "does_not_exist" }, { auth: { uid: "merchant_uid" } }),
    (error) => {
      assert.equal(error.code, "not-found");
      return true;
    },
  );
});

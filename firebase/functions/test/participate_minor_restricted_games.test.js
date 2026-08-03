#!/usr/bin/env node

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-rules-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");
const wrapped = functionsTest.wrap(myFunctions.participateInGameTransaction);

const firestore = admin.firestore();
const now = admin.firestore.Timestamp.now();
const hourMs = 60 * 60 * 1000;

async function seedGame({
  gameId,
  ownerUid,
  enseigneId,
  prohibitedForMinors = false,
}) {
  await firestore.collection("users").doc(ownerUid).set({
    user_role: "commercant",
  });
  await firestore.collection("enseignes").doc(enseigneId).set({
    name: "Crepe Test",
    owner: firestore.doc(`users/${ownerUid}`),
  });
  await firestore.collection("games").doc(gameId).set({
    name: "Jeu Test",
    create_by: firestore.doc(`users/${ownerUid}`),
    enseigne_id: firestore.doc(`enseignes/${enseigneId}`),
    enseigne_name: "Crepe Test",
    start_date: admin.firestore.Timestamp.fromMillis(now.toMillis() - hourMs),
    end_date: admin.firestore.Timestamp.fromMillis(now.toMillis() + hourMs),
    access_mode: "public",
    prohibited_for_minors: prohibitedForMinors,
    hasMainPrize: true,
    hasWinner: false,
    participations: 5,
  });
}

async function countParticipants(gameId) {
  const snapshot = await firestore
    .collection("games")
    .doc(gameId)
    .collection("participants")
    .get();
  return snapshot.size;
}

test("jeu tout public sans date de naissance : participation autorisee", async () => {
  const uid = "adult_optional_birthday";
  const gameId = "public_game_without_birthday";
  await seedGame({
    gameId,
    ownerUid: "merchant_public",
    enseigneId: "enseigne_public",
    prohibitedForMinors: false,
  });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Alice",
  });

  const result = await wrapped(
    { gameRef: gameId, from_qr: false },
    { auth: { uid } },
  );

  assert.equal(result.alreadyParticipatedToday, false);
  const userSnap = await firestore.collection("users").doc(uid).get();
  assert.equal(userSnap.data().remaining_part, 2);
});

test("jeu interdit sans date de naissance : refus sans consommation", async () => {
  const uid = "restricted_without_birthday";
  const gameId = "restricted_game_without_birthday";
  await seedGame({
    gameId,
    ownerUid: "merchant_restricted_missing_birthday",
    enseigneId: "enseigne_restricted_missing_birthday",
    prohibitedForMinors: true,
  });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Bob",
  });

  await assert.rejects(
    () => wrapped({ gameRef: gameId, from_qr: false }, { auth: { uid } }),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.match(error.message, /date de naissance/i);
      return true;
    },
  );

  const userSnap = await firestore.collection("users").doc(uid).get();
  assert.equal(userSnap.data().remaining_part, 3);
  assert.equal(await countParticipants(gameId), 0);
});

test("jeu interdit avec joueur majeur : participation autorisee", async () => {
  const uid = "restricted_adult";
  const gameId = "restricted_game_adult";
  await seedGame({
    gameId,
    ownerUid: "merchant_restricted_adult",
    enseigneId: "enseigne_restricted_adult",
    prohibitedForMinors: true,
  });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Chloe",
    birthday: admin.firestore.Timestamp.fromDate(new Date("1990-05-10T00:00:00Z")),
  });

  const result = await wrapped(
    { gameRef: gameId, from_qr: false },
    { auth: { uid } },
  );

  assert.equal(result.alreadyParticipatedToday, false);
  const userSnap = await firestore.collection("users").doc(uid).get();
  assert.equal(userSnap.data().remaining_part, 2);
});

test("jeu interdit avec joueur mineur : refus sans consommation", async () => {
  const uid = "restricted_minor";
  const gameId = "restricted_game_minor";
  await seedGame({
    gameId,
    ownerUid: "merchant_restricted_minor",
    enseigneId: "enseigne_restricted_minor",
    prohibitedForMinors: true,
  });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "David",
    birthday: admin.firestore.Timestamp.fromDate(new Date("2010-09-01T00:00:00Z")),
  });

  await assert.rejects(
    () => wrapped({ gameRef: gameId, from_qr: false }, { auth: { uid } }),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.match(error.message, /majeures/i);
      return true;
    },
  );

  const userSnap = await firestore.collection("users").doc(uid).get();
  assert.equal(userSnap.data().remaining_part, 3);
  assert.equal(await countParticipants(gameId), 0);
});

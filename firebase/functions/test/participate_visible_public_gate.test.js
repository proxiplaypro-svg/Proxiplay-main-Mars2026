#!/usr/bin/env node

// Regression: a game still in draft (visible_public:false, set by the
// client at creation and flipped to true only by the server once the
// instant winners calendar is confirmed complete) was never checked by
// participateInGameTransaction -- a client that already knew the game ID
// (QR/deep link race, or a brief listing in the Home carousel before the
// draft filter -- see home_games_logic.dart's isGameDraftHiddenFromPlayer)
// could play it directly. `visible_public === false` is the only value
// that blocks: a legacy game that never had this field (undefined) stays
// playable, same "absent = public" convention as the admin console.
//
//   firebase emulators:exec --only firestore \
//     "node --test test/participate_visible_public_gate.test.js"

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

async function seedGame({ gameId, ownerUid, enseigneId, visiblePublic }) {
  await firestore.collection("users").doc(ownerUid).set({ user_role: "commercant" });
  await firestore.collection("enseignes").doc(enseigneId).set({
    name: "Crepe Test",
    owner: firestore.doc(`users/${ownerUid}`),
  });
  const data = {
    name: "Jeu Test",
    create_by: firestore.doc(`users/${ownerUid}`),
    enseigne_id: firestore.doc(`enseignes/${enseigneId}`),
    enseigne_name: "Crepe Test",
    start_date: admin.firestore.Timestamp.fromMillis(now.toMillis() - hourMs),
    end_date: admin.firestore.Timestamp.fromMillis(now.toMillis() + hourMs),
    access_mode: "public",
    prohibited_for_minors: false,
    hasMainPrize: true,
    hasWinner: false,
    participations: 0,
  };
  if (visiblePublic !== undefined) {
    data.visible_public = visiblePublic;
  }
  await firestore.collection("games").doc(gameId).set(data);
}

async function countParticipants(gameId) {
  const snapshot = await firestore.collection("games").doc(gameId).collection("participants").get();
  return snapshot.size;
}

test("REGRESSION: a draft game (visible_public:false) cannot be played even by direct game ID", async () => {
  const uid = "player_draft_attempt";
  const gameId = "draft_game";
  await seedGame({
    gameId,
    ownerUid: "merchant_draft",
    enseigneId: "enseigne_draft",
    visiblePublic: false,
  });
  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Carla",
  });

  await assert.rejects(
    () => wrapped({ gameRef: gameId, from_qr: false }, { auth: { uid } }),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      return true;
    },
  );

  const userSnap = await firestore.collection("users").doc(uid).get();
  assert.equal(userSnap.data().remaining_part, 3, "no part should be consumed on a refused draft game");
  assert.equal(await countParticipants(gameId), 0);
});

test("no regression: a published game (visible_public:true) is playable", async () => {
  const uid = "player_published";
  const gameId = "published_game";
  await seedGame({
    gameId,
    ownerUid: "merchant_published",
    enseigneId: "enseigne_published",
    visiblePublic: true,
  });
  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Dan",
  });

  const result = await wrapped({ gameRef: gameId, from_qr: false }, { auth: { uid } });
  assert.equal(result.alreadyParticipatedToday, false);
});

test("no regression: a legacy game without the visible_public field is still playable", async () => {
  const uid = "player_legacy";
  const gameId = "legacy_game_no_field";
  await seedGame({
    gameId,
    ownerUid: "merchant_legacy",
    enseigneId: "enseigne_legacy",
    visiblePublic: undefined,
  });
  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Eve",
  });

  const result = await wrapped({ gameRef: gameId, from_qr: false }, { auth: { uid } });
  assert.equal(result.alreadyParticipatedToday, false);
});

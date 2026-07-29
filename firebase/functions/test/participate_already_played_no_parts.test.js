#!/usr/bin/env node

// Verifies the fix for a real, reported bug: a player who already played a
// game today (remaining_part already spent on that exact play) retries —
// via the "Rejouer"/deja-joue button, now unlocked in
// jeu_detail_joueur_page_widget.dart — and must get their cached result
// back (message/isWin/prize_id), NOT "Vous n'avez plus de parties
// disponibles.". Before this fix, the remaining_part<=0 check ran BEFORE
// the alreadyParticipatedToday check and always won for a player with 0
// parts left, making the cached-result replay (see
// resolveCachedLastResult) unreachable for the single most common case:
// someone who just spent their last part on this very game.
//
// Run against the local Firestore emulator only:
//   firebase emulators:exec --only firestore \
//     "node --test test/participate_already_played_no_parts.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-rules-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");
const wrapped = functionsTest.wrap(myFunctions.participateInGameTransaction);

const firestore = admin.firestore();

function getParisDayKey(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = parts.find((p) => p.type === "year")?.value || "";
  const month = parts.find((p) => p.type === "month")?.value || "";
  const day = parts.find((p) => p.type === "day")?.value || "";
  return `${year}${month}${day}`;
}

const dayKey = getParisDayKey(new Date());
const now = admin.firestore.Timestamp.now();
const hourMs = 60 * 60 * 1000;

async function seedGame({ gameId, ownerUid, enseigneId }) {
  await firestore.collection("users").doc(ownerUid).set({
    user_role: "commercant",
  });
  await firestore.collection("enseignes").doc(enseigneId).set({
    name: "Crepe Test",
    owner: firestore.doc(`users/${ownerUid}`),
  });
  await firestore.collection("games").doc(gameId).set({
    name: "un menu Midi semaine",
    create_by: firestore.doc(`users/${ownerUid}`),
    enseigne_id: firestore.doc(`enseignes/${enseigneId}`),
    enseigne_name: "Crepe Test",
    start_date: admin.firestore.Timestamp.fromMillis(now.toMillis() - hourMs),
    end_date: admin.firestore.Timestamp.fromMillis(now.toMillis() + hourMs),
    access_mode: "public",
    hasMainPrize: true,
    hasWinner: false,
    participations: 5,
  });
}

test("joueur a 0 partie qui a deja joue ce jeu aujourd'hui recoit son resultat en cache, pas l'erreur plus de parties", async () => {
  const uid = "player_already_played";
  const gameId = "game_already_played";
  await seedGame({
    gameId,
    ownerUid: "merchant_already_played",
    enseigneId: "enseigne_already_played",
  });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 0,
    first_name: "Alice",
  });

  const participantDocId = `${dayKey}_${uid}`;
  await firestore
    .collection("games")
    .doc(gameId)
    .collection("participants")
    .doc(participantDocId)
    .set({ user_id: firestore.doc(`users/${uid}`), participation_date: now });

  await firestore
    .collection("games")
    .doc(gameId)
    .collection("participants_details")
    .doc(uid)
    .set({
      last_play: now,
      game_bonus: 0,
      user_id: firestore.doc(`users/${uid}`),
      last_result: {
        message: "Retente ta chance demain !",
        messageBonus: "",
        isWin: false,
        prize_id: null,
        recorded_at: now,
      },
    });

  const result = await wrapped(
    { gameRef: gameId, from_qr: false },
    { auth: { uid } },
  );

  assert.equal(result.alreadyParticipatedToday, true);
  assert.equal(result.message, "Retente ta chance demain !");
  assert.equal(result.isWin, false);
});

test("joueur a 0 partie qui n'a PAS joue ce jeu aujourd'hui recoit bien l'erreur plus de parties (non-regression)", async () => {
  const uid = "player_no_parts_fresh";
  const gameId = "game_no_parts_fresh";
  await seedGame({
    gameId,
    ownerUid: "merchant_no_parts_fresh",
    enseigneId: "enseigne_no_parts_fresh",
  });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 0,
    first_name: "Bob",
  });

  await assert.rejects(
    () => wrapped({ gameRef: gameId, from_qr: false }, { auth: { uid } }),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.match(error.message, /plus de parties/);
      return true;
    },
  );
});

test("joueur avec des parties restantes qui joue un jeu jamais tente aujourd'hui participe normalement", async () => {
  const uid = "player_fresh_with_parts";
  const gameId = "game_fresh_with_parts";
  await seedGame({
    gameId,
    ownerUid: "merchant_fresh_with_parts",
    enseigneId: "enseigne_fresh_with_parts",
  });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Chloe",
  });

  const result = await wrapped(
    { gameRef: gameId, from_qr: false },
    { auth: { uid } },
  );

  assert.equal(result.alreadyParticipatedToday, false);

  const userSnap = await firestore.collection("users").doc(uid).get();
  assert.equal(userSnap.data().remaining_part, 2);
});

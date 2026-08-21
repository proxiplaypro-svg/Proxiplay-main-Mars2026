#!/usr/bin/env node

// Integration coverage for the one path that was never exercised end-to-end:
// participateInGameTransaction (the hot-path hit by every single game play)
// combined with an ACTIVE monthly attendance challenge. The tracking hook
// (trackMonthlyChallengeParticipation) previously broke this exact
// transaction once already (see the "reads before writes" fix in
// monthly_challenge.js's git history) -- monthly_challenge.test.js only
// calls trackMonthlyChallengeParticipation directly, never through the real
// participateInGameTransaction transaction, so a future regression in how
// the two are wired together would go undetected without this file.
//
// Run against the local Firestore emulator only:
//   firebase emulators:exec --only firestore \
//     "node --test test/participate_with_monthly_challenge.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-monthly-challenge-participation-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");
const wrapped = functionsTest.wrap(myFunctions.participateInGameTransaction);
const { getParisMonthKey, getParisDayKey } = require("../monthly_challenge.js");

const firestore = admin.firestore();

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(
    collections.map((collection) => firestore.recursiveDelete(collection)),
  );
}

async function seedGame({ gameId, ownerUid, enseigneId }) {
  const now = admin.firestore.Timestamp.now();
  const hourMs = 60 * 60 * 1000;
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

async function seedActiveChallenge({ targetDays = 1 } = {}) {
  const monthKey = getParisMonthKey();
  // Far enough in the future to stay a plausible draw date; this test never
  // runs the draw, so validateMonthlyChallengeConfig's exact bound doesn't
  // matter here.
  const drawDate = admin.firestore.Timestamp.fromMillis(
    Date.now() + 60 * 24 * 60 * 60 * 1000,
  );
  await firestore.doc("app_config/monthly_challenge").set({
    enabled: true,
    month: monthKey,
    title: "Defi Proxiplay",
    description: "Joue au moins un jour ce mois-ci pour participer au tirage.",
    target_days: targetDays,
    prize_title: "Un resto pour 2",
    prize_description: "Bon cadeau restaurant",
    prize_value: 120,
    image_url: "",
    draw_date: drawDate,
  });
  return monthKey;
}

async function getUserChallengeState(uid, monthKey) {
  const snap = await firestore
    .collection("users")
    .doc(uid)
    .collection("monthly_challenges")
    .doc(monthKey)
    .get();
  return snap.exists ? snap.data() || {} : null;
}

async function getDrawEntry(monthKey, uid) {
  const snap = await firestore
    .collection("monthly_challenge_entries")
    .doc(`${monthKey}_${uid}`)
    .get();
  return snap.exists ? snap.data() || {} : null;
}

test.beforeEach(async () => {
  await clearFirestore();
});

test("jouer pendant un defi actif (target_days=1) qualifie immediatement et cree l'entree de tirage", async () => {
  const uid = "player_monthly_challenge_qualify";
  const gameId = "game_monthly_challenge_qualify";
  await seedGame({
    gameId,
    ownerUid: "merchant_mc_qualify",
    enseigneId: "enseigne_mc_qualify",
  });
  const monthKey = await seedActiveChallenge({ targetDays: 1 });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Dana",
  });

  const result = await wrapped(
    { gameRef: gameId, from_qr: false },
    { auth: { uid } },
  );

  // La partie elle-meme n'est pas affectee par le suivi d'assiduite.
  assert.equal(result.alreadyParticipatedToday, false);

  const todayKey = getParisDayKey();
  const state = await getUserChallengeState(uid, monthKey);
  assert.ok(state, "l'etat mensuel du joueur doit avoir ete cree");
  assert.equal(state.active_days_count, 1);
  assert.deepEqual(state.active_dates, [todayKey]);
  assert.equal(state.qualified, true);
  assert.equal(state.draw_entry_created, true);

  const entry = await getDrawEntry(monthKey, uid);
  assert.ok(entry, "une entree de tirage doit avoir ete creee");
  assert.equal(entry.status, "qualified");
  assert.equal(entry.uid, uid);
});

test("deux parties le meme jour (jeux differents) ne comptent que pour un seul jour actif", async () => {
  const uid = "player_monthly_challenge_two_games";
  const gameIdA = "game_mc_two_games_a";
  const gameIdB = "game_mc_two_games_b";
  await seedGame({
    gameId: gameIdA,
    ownerUid: "merchant_mc_two_a",
    enseigneId: "enseigne_mc_two_a",
  });
  await seedGame({
    gameId: gameIdB,
    ownerUid: "merchant_mc_two_b",
    enseigneId: "enseigne_mc_two_b",
  });
  // target_days=2 pour verifier l'absence de double-comptage sans que la
  // premiere partie ne qualifie deja tout court.
  const monthKey = await seedActiveChallenge({ targetDays: 2 });

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Eli",
  });

  await wrapped({ gameRef: gameIdA, from_qr: false }, { auth: { uid } });
  await wrapped({ gameRef: gameIdB, from_qr: false }, { auth: { uid } });

  const state = await getUserChallengeState(uid, monthKey);
  assert.ok(state);
  assert.equal(state.active_days_count, 1);
  assert.equal(state.qualified, false);
});

test("defi desactive : la partie fonctionne normalement, aucun suivi d'assiduite cree", async () => {
  const uid = "player_monthly_challenge_disabled";
  const gameId = "game_mc_disabled";
  await seedGame({
    gameId,
    ownerUid: "merchant_mc_disabled",
    enseigneId: "enseigne_mc_disabled",
  });
  const monthKey = await seedActiveChallenge({ targetDays: 1 });
  await firestore.doc("app_config/monthly_challenge").set(
    { enabled: false },
    { merge: true },
  );

  await firestore.collection("users").doc(uid).set({
    user_role: "joueur",
    remaining_part: 3,
    first_name: "Farah",
  });

  const result = await wrapped(
    { gameRef: gameId, from_qr: false },
    { auth: { uid } },
  );

  assert.equal(result.alreadyParticipatedToday, false);
  const state = await getUserChallengeState(uid, monthKey);
  assert.equal(state, null);
});

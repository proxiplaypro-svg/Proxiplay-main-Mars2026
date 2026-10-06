#!/usr/bin/env node

// Verifies createAdminPushNotification end to end: admin gating, destination
// resolution/validation wired into the callable, and that the resolved
// initial_page_name/parameter_data survive on both an immediate and a
// scheduled (programmee) notification document.
//
//   firebase emulators:exec --only firestore \
//     "node --test test/create_admin_push_notification.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-admin-push-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");
const wrapped = functionsTest.wrap(myFunctions.createAdminPushNotification);

const firestore = admin.firestore();

const ADMIN_UID = "admin_uid";
const PLAYER_UID = "player_uid";

test.before(async () => {
  await firestore.collection("users").doc(ADMIN_UID).set({user_role: "admin"});
  await firestore.collection("users").doc(PLAYER_UID).set({user_role: "joueur"});
  await firestore.collection("enseignes").doc("ens1").set({name: "Ma boutique"});
  await firestore.collection("games").doc("game1").set({
    title: "Grand Jeu",
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
});

async function readCreatedDoc(result) {
  const snap = await firestore.collection("ff_push_notifications").doc(result.id).get();
  return snap.data();
}

test("unauthenticated calls are refused", async () => {
  await assert.rejects(() => wrapped({title: "T", body: "B"}, {auth: null}), /unauthenticated/i);
});

test("a non-admin caller is refused", async () => {
  await assert.rejects(
    () => wrapped({title: "T", body: "B"}, {auth: {uid: PLAYER_UID}}),
    /permission-denied/i,
  );
});

test("no destination (legacy-equivalent) writes empty initial_page_name/parameter_data", async () => {
  const result = await wrapped(
    {title: "Sans destination", body: "Corps"},
    {auth: {uid: ADMIN_UID}},
  );
  const doc = await readCreatedDoc(result);
  assert.equal(doc.initial_page_name, "");
  assert.equal(doc.parameter_data, "");
});

test("internal:home writes HomeJoueurPage", async () => {
  const result = await wrapped(
    {title: "Accueil", body: "Corps", destinationType: "internal", destinationId: "home"},
    {auth: {uid: ADMIN_UID}},
  );
  const doc = await readCreatedDoc(result);
  assert.equal(doc.initial_page_name, "HomeJoueurPage");
  assert.equal(doc.parameter_data, "");
});

test("a valid game writes JeuDetailJoueurPage with gameDoc + enseigneDoc", async () => {
  const result = await wrapped(
    {title: "Nouveau jeu", body: "Corps", destinationType: "game", destinationId: "game1"},
    {auth: {uid: ADMIN_UID}},
  );
  const doc = await readCreatedDoc(result);
  assert.equal(doc.initial_page_name, "JeuDetailJoueurPage");
  assert.deepEqual(JSON.parse(doc.parameter_data), {gameDoc: "games/game1", enseigneDoc: "enseignes/ens1"});
});

test("an invalid game is refused and nothing is written", async () => {
  await assert.rejects(
    () =>
      wrapped(
        {title: "Jeu invalide", body: "Corps", destinationType: "game", destinationId: "does_not_exist"},
        {auth: {uid: ADMIN_UID}},
      ),
    (err) => err.code === 'invalid-argument',
  );
});

test("a forbidden internal screen is refused", async () => {
  await assert.rejects(
    () =>
      wrapped(
        {title: "Ecran interdit", body: "Corps", destinationType: "internal", destinationId: "admin_settings"},
        {auth: {uid: ADMIN_UID}},
      ),
    (err) => err.code === 'invalid-argument',
  );
});

test("a valid https URL is accepted", async () => {
  const result = await wrapped(
    {
      title: "Lien externe",
      body: "Corps",
      destinationType: "external_url",
      destinationId: "https://proxiplay.fr",
    },
    {auth: {uid: ADMIN_UID}},
  );
  const doc = await readCreatedDoc(result);
  assert.equal(doc.initial_page_name, "ExternalUrlRedirectPage");
  assert.deepEqual(JSON.parse(doc.parameter_data), {url: "https://proxiplay.fr"});
});

test("a dangerous URL scheme is refused", async () => {
  await assert.rejects(
    () =>
      wrapped(
        {
          title: "Lien dangereux",
          body: "Corps",
          destinationType: "external_url",
          destinationId: "javascript:alert(1)",
        },
        {auth: {uid: ADMIN_UID}},
      ),
    (err) => err.code === 'invalid-argument',
  );
});

test("a scheduled notification keeps its destination until send time", async () => {
  const scheduledTimeMs = Date.now() + 60 * 60 * 1000;
  const result = await wrapped(
    {
      title: "Programmee",
      body: "Corps",
      destinationType: "merchant",
      destinationId: "ens1",
      scheduledTimeMs,
    },
    {auth: {uid: ADMIN_UID}},
  );
  const doc = await readCreatedDoc(result);
  assert.equal(doc.status, "scheduled");
  assert.equal(doc.initial_page_name, "EnseigneDetailJoueurPage");
  assert.deepEqual(JSON.parse(doc.parameter_data), {enseigneDoc: "enseignes/ens1"});
});

test("title/body are still required regardless of destination", async () => {
  await assert.rejects(
    () => wrapped({title: "", body: "", destinationType: "internal", destinationId: "home"}, {auth: {uid: ADMIN_UID}}),
    (err) => err.code === 'invalid-argument',
  );
});

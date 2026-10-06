#!/usr/bin/env node

// Verifies resolveNotificationDestination(): the single validation point a
// notification's destination_type/destination_id must pass through before
// ever being written to ff_push_notifications (manual or automatic).
//
//   firebase emulators:exec --only firestore \
//     "node --test test/notification_destination.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-notif-destination-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const {
  resolveNotificationDestination,
  buildGameDestinationFromRefs,
  buildInternalDestination,
  isHttpsUrl,
} = require("../notification_destination");

const firestore = admin.firestore();

test.before(async () => {
  await firestore.collection("enseignes").doc("ens1").set({name: "Ma boutique"});
  await firestore.collection("games").doc("game1").set({
    title: "Grand Jeu",
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  await firestore.collection("games").doc("game_no_enseigne").set({title: "Jeu orphelin"});
});

test("none: no destination -> empty initialPageName/parameterData", async () => {
  const result = await resolveNotificationDestination({destinationType: undefined, destinationId: undefined});
  assert.deepEqual(result, {initialPageName: "", parameterData: ""});
});

test("none: explicit destinationType none behaves identically", async () => {
  const result = await resolveNotificationDestination({destinationType: "none", destinationId: "anything"});
  assert.deepEqual(result, {initialPageName: "", parameterData: ""});
});

test("internal: home resolves to HomeJoueurPage with no parameters", async () => {
  const result = await resolveNotificationDestination({destinationType: "internal", destinationId: "home"});
  assert.deepEqual(result, {initialPageName: "HomeJoueurPage", parameterData: ""});
});

test("internal: whitelisted screen resolves correctly", async () => {
  const result = await resolveNotificationDestination({destinationType: "internal", destinationId: "gagnants"});
  assert.deepEqual(result, {initialPageName: "LotsJoueurPage", parameterData: ""});
});

test("internal: a screen outside the whitelist is refused", async () => {
  await assert.rejects(
    () => resolveNotificationDestination({destinationType: "internal", destinationId: "ParametresAdminPage"}),
    (err) => err.code === 'invalid-argument',
  );
});

test("game: a valid, existing game resolves gameDoc + enseigneDoc", async () => {
  const result = await resolveNotificationDestination({destinationType: "game", destinationId: "game1"});
  assert.equal(result.initialPageName, "JeuDetailJoueurPage");
  assert.deepEqual(JSON.parse(result.parameterData), {
    gameDoc: "games/game1",
    enseigneDoc: "enseignes/ens1",
  });
});

test("game: a game without an enseigne_id still resolves (gameDoc only)", async () => {
  const result = await resolveNotificationDestination({destinationType: "game", destinationId: "game_no_enseigne"});
  assert.deepEqual(JSON.parse(result.parameterData), {gameDoc: "games/game_no_enseigne"});
});

test("game: a non-existent game is refused", async () => {
  await assert.rejects(
    () => resolveNotificationDestination({destinationType: "game", destinationId: "does_not_exist"}),
    (err) => err.code === 'invalid-argument',
  );
});

test("game: a missing destination_id is refused", async () => {
  await assert.rejects(
    () => resolveNotificationDestination({destinationType: "game", destinationId: ""}),
    (err) => err.code === 'invalid-argument',
  );
});

test("merchant: a valid enseigne resolves EnseigneDetailJoueurPage", async () => {
  const result = await resolveNotificationDestination({destinationType: "merchant", destinationId: "ens1"});
  assert.equal(result.initialPageName, "EnseigneDetailJoueurPage");
  assert.deepEqual(JSON.parse(result.parameterData), {enseigneDoc: "enseignes/ens1"});
});

test("merchant: a non-existent enseigne is refused", async () => {
  await assert.rejects(
    () => resolveNotificationDestination({destinationType: "merchant", destinationId: "does_not_exist"}),
    (err) => err.code === 'invalid-argument',
  );
});

test("external_url: a valid https URL is accepted", async () => {
  const result = await resolveNotificationDestination({
    destinationType: "external_url",
    destinationId: "https://proxiplay.fr/offres",
  });
  assert.equal(result.initialPageName, "ExternalUrlRedirectPage");
  assert.deepEqual(JSON.parse(result.parameterData), {url: "https://proxiplay.fr/offres"});
});

test("external_url: http:// is refused (https only)", async () => {
  await assert.rejects(
    () => resolveNotificationDestination({destinationType: "external_url", destinationId: "http://proxiplay.fr"}),
    (err) => err.code === 'invalid-argument',
  );
});

test("external_url: a javascript: URI is refused", async () => {
  await assert.rejects(
    () =>
      resolveNotificationDestination({
        destinationType: "external_url",
        destinationId: "javascript:alert(1)",
      }),
    (err) => err.code === 'invalid-argument',
  );
});

test("external_url: a malformed string is refused, not thrown as a parse crash", async () => {
  await assert.rejects(
    () => resolveNotificationDestination({destinationType: "external_url", destinationId: "not a url"}),
    (err) => err.code === 'invalid-argument',
  );
});

test("unknown destination_type is refused", async () => {
  await assert.rejects(
    () => resolveNotificationDestination({destinationType: "prize", destinationId: "x"}),
    (err) => err.code === 'invalid-argument',
  );
});

test("isHttpsUrl: direct unit coverage of the URL guard", () => {
  assert.equal(isHttpsUrl("https://proxiplay.fr"), true);
  assert.equal(isHttpsUrl("http://proxiplay.fr"), false);
  assert.equal(isHttpsUrl("javascript:alert(1)"), false);
  assert.equal(isHttpsUrl(""), false);
  assert.equal(isHttpsUrl(undefined), false);
});

test("buildGameDestinationFromRefs: used by automatic producers that already hold the refs", () => {
  const result = buildGameDestinationFromRefs({
    gameRef: firestore.doc("games/game1"),
    enseigneRef: firestore.doc("enseignes/ens1"),
  });
  assert.equal(result.initialPageName, "JeuDetailJoueurPage");
  assert.deepEqual(JSON.parse(result.parameterData), {
    gameDoc: "games/game1",
    enseigneDoc: "enseignes/ens1",
  });
});

test("buildGameDestinationFromRefs: tolerates a missing enseigne ref", () => {
  const result = buildGameDestinationFromRefs({gameRef: firestore.doc("games/game1"), enseigneRef: null});
  assert.deepEqual(JSON.parse(result.parameterData), {gameDoc: "games/game1"});
});

test("buildInternalDestination: direct unit coverage for automatic producers", () => {
  assert.deepEqual(buildInternalDestination("gagnants"), {
    initialPageName: "LotsJoueurPage",
    parameterData: "",
  });
  assert.throws(() => buildInternalDestination("not_a_real_screen"));
});

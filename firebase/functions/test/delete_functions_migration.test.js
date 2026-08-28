#!/usr/bin/env node

// Verifies deleteEnseigneAndGames and deleteCommercantAccount, migrated from
// the retired firebase/custom_cloud_functions codebase into firebase/functions,
// are still exported under exactly the same names and keep their behavior
// (auth checks, cascade deletes). deleteCommercantAccount also deletes the
// Firebase Auth user, so this needs the Auth emulator too. Run against the
// local emulators only:
//
//   firebase emulators:exec --only firestore,auth \
//     "node --test test/delete_functions_migration.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "demo-proxiplay-rules-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");

test("deleteEnseigneAndGames et deleteCommercantAccount sont exportees sous exactement les memes noms", () => {
  assert.equal(typeof myFunctions.deleteEnseigneAndGames, "function");
  assert.equal(typeof myFunctions.deleteCommercantAccount, "function");
});

const wrappedDeleteEnseigne = functionsTest.wrap(myFunctions.deleteEnseigneAndGames);
const wrappedDeleteCommercant = functionsTest.wrap(myFunctions.deleteCommercantAccount);
const firestore = admin.firestore();

test.after(async () => {
  await functionsTest.cleanup();
});

test.describe("deleteEnseigneAndGames", () => {
  test.before(async () => {
    await firestore.collection("users").doc("owner_uid").set({user_role: "commercant"});
    await firestore.collection("users").doc("other_uid").set({user_role: "commercant"});
    await firestore.collection("users").doc("admin_uid").set({user_role: "admin"});
    await firestore.collection("enseignes").doc("ens_owned").set({
      name: "Boutique du proprietaire",
      owner: firestore.doc("users/owner_uid"),
    });
    await firestore.collection("games").doc("game_owned_1").set({
      name: "Jeu 1",
      enseigne_id: firestore.doc("enseignes/ens_owned"),
    });
    await firestore.collection("games").doc("game_owned_2").set({
      name: "Jeu 2",
      enseigne_id: firestore.doc("enseignes/ens_owned"),
    });
    await firestore.collection("enseignes").doc("ens_for_permission_check").set({
      name: "Boutique protegee",
      owner: firestore.doc("users/owner_uid"),
    });
  });

  test("refuse un appel non authentifie", async () => {
    await assert.rejects(
      () => wrappedDeleteEnseigne({enseignePath: "enseignes/ens_owned"}, {}),
      (error) => {
        assert.equal(error.code, "unauthenticated");
        return true;
      },
    );
  });

  test("refuse sans enseignePath", async () => {
    await assert.rejects(
      () => wrappedDeleteEnseigne({}, {auth: {uid: "owner_uid"}}),
      (error) => {
        assert.equal(error.code, "invalid-argument");
        return true;
      },
    );
  });

  test("refuse un utilisateur qui n'est ni proprietaire ni admin", async () => {
    await assert.rejects(
      () =>
        wrappedDeleteEnseigne(
          {enseignePath: "enseignes/ens_for_permission_check"},
          {auth: {uid: "other_uid"}},
        ),
      (error) => {
        assert.equal(error.code, "permission-denied");
        return true;
      },
    );
  });

  test("le proprietaire supprime l'enseigne et tous ses jeux", async () => {
    const result = await wrappedDeleteEnseigne(
      {enseignePath: "enseignes/ens_owned"},
      {auth: {uid: "owner_uid"}},
    );
    assert.match(result.message, /supprim/i);

    const enseigneSnap = await firestore.collection("enseignes").doc("ens_owned").get();
    assert.equal(enseigneSnap.exists, false);

    const gamesSnap = await firestore
      .collection("games")
      .where("enseigne_id", "==", firestore.doc("enseignes/ens_owned"))
      .get();
    assert.equal(gamesSnap.size, 0);
  });
});

test.describe("deleteCommercantAccount", () => {
  test.before(async () => {
    await firestore.collection("users").doc("admin_for_delete_uid").set({user_role: "admin"});
    await firestore.collection("users").doc("non_admin_caller_uid").set({user_role: "commercant"});
    await firestore.collection("users").doc("commercant_to_delete_uid").set({
      user_role: "commercant",
      email: "commercant@example.com",
    });
    await firestore.collection("enseignes").doc("ens_to_cascade").set({
      name: "Boutique a supprimer",
      owner: firestore.doc("users/commercant_to_delete_uid"),
    });
    await admin.auth().createUser({
      uid: "commercant_to_delete_uid",
      email: "commercant@example.com",
    });
  });

  test("refuse un appel non authentifie", async () => {
    await assert.rejects(
      () => wrappedDeleteCommercant({commercantUid: "commercant_to_delete_uid"}, {}),
      (error) => {
        assert.equal(error.code, "unauthenticated");
        return true;
      },
    );
  });

  test("refuse un appelant non admin", async () => {
    await assert.rejects(
      () =>
        wrappedDeleteCommercant(
          {commercantUid: "commercant_to_delete_uid"},
          {auth: {uid: "non_admin_caller_uid"}},
        ),
      (error) => {
        assert.equal(error.code, "permission-denied");
        return true;
      },
    );
  });

  test("un admin supprime le compte commercant et son enseigne", async () => {
    const result = await wrappedDeleteCommercant(
      {commercantUid: "commercant_to_delete_uid"},
      {auth: {uid: "admin_for_delete_uid"}},
    );
    assert.equal(result.success, true);

    const userSnap = await firestore.collection("users").doc("commercant_to_delete_uid").get();
    assert.equal(userSnap.exists, false);

    const enseigneSnap = await firestore.collection("enseignes").doc("ens_to_cascade").get();
    assert.equal(enseigneSnap.exists, false);

    await assert.rejects(() => admin.auth().getUser("commercant_to_delete_uid"));
  });
});

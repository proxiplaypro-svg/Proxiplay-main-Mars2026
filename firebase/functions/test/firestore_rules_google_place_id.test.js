#!/usr/bin/env node

// Verifies the write/read surface of the "google_place_id" field on
// enseignes documents (association manuelle a une fiche Google).
//
// Historique : le champ a d'abord ete admin-only (isSafeMerchantEnseigneUpdate()
// ne l'incluait pas). Ce chantier ouvre isSafeMerchantEnseigneUpdate() pour
// que le proprietaire legitime d'une enseigne puisse lui-meme ajouter,
// remplacer ou supprimer le google_place_id -- mais UNIQUEMENT sur sa
// propre enseigne, sans elargir aucun autre droit. Ces tests couvrent :
// lecture publique (champ present/absent), admin (toujours full access),
// commercant proprietaire (ajout/remplacement/suppression), commercant sur
// une AUTRE enseigne (refuse), tiers (refuse), creation d'une enseigne avec
// google_place_id des la creation (deja permis par la regle create, non
// affectee par ce chantier).
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_google_place_id.test.js"

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-rules-google-place-id-test",
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "../../firestore.rules"),
        "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await db.collection("users").doc("merchant_uid").set({
      user_role: "commercant",
      account_status: "approved",
    });

    await db.collection("enseignes").doc("enseigne_without_field").set({
      owner: db.doc("users/merchant_uid"),
      name: "Sans association Google",
    });

    await db.collection("enseignes").doc("enseigne_with_field").set({
      owner: db.doc("users/merchant_uid"),
      name: "La Civette Jean Bart",
      google_place_id: "ChIJExistingPlaceId",
    });

    await db.collection("enseignes").doc("other_merchant_enseigne").set({
      owner: db.doc("users/other_merchant_uid"),
      name: "Une autre enseigne",
    });
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function adminContext() {
  return testEnv.authenticatedContext("admin_uid", {admin: true});
}

function ownerContext() {
  return testEnv.authenticatedContext("merchant_uid", {
    email: "merchant@example.test",
  });
}

function strangerContext() {
  return testEnv.authenticatedContext("stranger_uid", {
    email: "stranger@example.test",
  });
}

function fieldValueDelete() {
  require("firebase/compat/firestore");
  return require("firebase/compat/app").default.firestore.FieldValue.delete();
}

test("lecture publique inchangee pour une enseigne sans google_place_id", async () => {
  const anon = testEnv.unauthenticatedContext();
  const snap = await assertSucceeds(
    anon.firestore().collection("enseignes").doc("enseigne_without_field").get(),
  );
  assert.equal(snap.data().google_place_id, undefined);
});

test("lecture publique inchangee pour une enseigne avec google_place_id", async () => {
  const anon = testEnv.unauthenticatedContext();
  const snap = await assertSucceeds(
    anon.firestore().collection("enseignes").doc("enseigne_with_field").get(),
  );
  assert.equal(snap.data().google_place_id, "ChIJExistingPlaceId");
});

test("admin peut associer un google_place_id sur une enseigne qui n'en a pas", async () => {
  const admin = adminContext();
  await assertSucceeds(
    admin.firestore().collection("enseignes").doc("enseigne_without_field")
      .update({google_place_id: "ChIJNewlyAssociated"}),
  );
});

test("admin peut retirer une association google_place_id existante", async () => {
  const admin = adminContext();
  await assertSucceeds(
    admin.firestore().collection("enseignes").doc("enseigne_with_field")
      .update({google_place_id: fieldValueDelete()}),
  );
});

test("le commercant proprietaire peut associer un google_place_id sur sa propre enseigne", async () => {
  const owner = ownerContext();
  await assertSucceeds(
    owner.firestore().collection("enseignes").doc("enseigne_without_field")
      .update({google_place_id: "ChIJAddedByOwner"}),
  );
});

test("le commercant proprietaire peut remplacer une association google_place_id existante", async () => {
  const owner = ownerContext();
  await assertSucceeds(
    owner.firestore().collection("enseignes").doc("enseigne_with_field")
      .update({google_place_id: "ChIJReplacedByOwner"}),
  );
});

test("le commercant proprietaire peut dissocier (supprimer) son google_place_id", async () => {
  const owner = ownerContext();
  await assertSucceeds(
    owner.firestore().collection("enseignes").doc("enseigne_with_field")
      .update({google_place_id: fieldValueDelete()}),
  );
});

test("le commercant proprietaire peut modifier google_place_id en meme temps qu'un autre champ autorise", async () => {
  const owner = ownerContext();
  await assertSucceeds(
    owner.firestore().collection("enseignes").doc("enseigne_without_field")
      .update({name: "Nouveau nom", google_place_id: "ChIJWithNameChange"}),
  );
});

test("le commercant proprietaire garde ses droits normaux sur les champs deja autorises (non-regression)", async () => {
  const owner = ownerContext();
  await assertSucceeds(
    owner.firestore().collection("enseignes").doc("enseigne_without_field")
      .update({name: "Nom mis a jour"}),
  );
});

test("le commercant proprietaire ne peut toujours pas modifier un champ hors whitelist", async () => {
  const owner = ownerContext();
  await assertFails(
    owner.firestore().collection("enseignes").doc("enseigne_without_field")
      .update({owner: owner.firestore().doc("users/someone_else_uid")}),
  );
});

test("un commercant ne peut pas modifier le google_place_id d'une enseigne qui n'est pas la sienne", async () => {
  const owner = ownerContext();
  await assertFails(
    owner.firestore().collection("enseignes").doc("other_merchant_enseigne")
      .update({google_place_id: "ChIJAttemptedOnOthers"}),
  );
});

test("un utilisateur sans lien avec l'enseigne ne peut pas modifier google_place_id", async () => {
  const stranger = strangerContext();
  await assertFails(
    stranger.firestore().collection("enseignes").doc("enseigne_without_field")
      .update({google_place_id: "ChIJAttemptedByStranger"}),
  );
});

test("un commercant approuve peut creer une enseigne avec un google_place_id des la creation", async () => {
  const owner = testEnv.authenticatedContext("brand_new_merchant_uid", {
    email: "new-merchant@example.test",
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection("users").doc("brand_new_merchant_uid").set({
      user_role: "commercant",
      account_status: "approved",
    });
  });
  await assertSucceeds(
    owner.firestore().collection("enseignes").doc("brand_new_enseigne").set({
      owner: owner.firestore().doc("users/brand_new_merchant_uid"),
      name: "Nouvelle enseigne",
      google_place_id: "ChIJCreatedWithAssociation",
    }),
  );
});

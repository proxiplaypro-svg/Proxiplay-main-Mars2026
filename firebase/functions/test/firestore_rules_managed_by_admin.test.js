#!/usr/bin/env node

// Verifies le gate managed_by_admin ajoute a firestore.rules (voir la note
// au sommet de ce fichier) : une enseigne/merchant marquee geree par
// Proxiplay n'est plus modifiable par le commercant proprietaire (fiche,
// jeux games/jeux, ni le flag lui-meme), tandis que l'admin console garde
// la main et que le comportement normal (champ absent ou false) reste
// inchange -- y compris la creation autonome mobile, non touchee par ce
// correctif.
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_managed_by_admin.test.js"

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
    projectId: "demo-proxiplay-rules-managed-by-admin-test",
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "../../firestore.rules"),
        "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Compte marchand "approuve", condition requise par isApprovedMerchant()
    // pour creer/gerer une enseigne et ses jeux -- y compris depuis le
    // parcours mobile autonome.
    await db.collection("users").doc("owner_uid").set({
      user_role: "commercant",
      account_status: "approved",
    });
    await db.collection("users").doc("other_owner_uid").set({
      user_role: "commercant",
      account_status: "approved",
    });

    // Enseigne normale (managed_by_admin absent : cas historique).
    await db.collection("enseignes").doc("shop-normal").set({
      name: "Boutique normale",
      owner: db.doc("users/owner_uid"),
    });

    // Enseigne geree par Proxiplay.
    await db.collection("enseignes").doc("shop-managed").set({
      name: "Boutique geree",
      owner: db.doc("users/owner_uid"),
      managed_by_admin: true,
    });

    // Merchant legacy normal et gere.
    await db.collection("merchants").doc("merch-normal").set({
      name: "Merchant normal",
      owner_id: db.doc("users/owner_uid"),
    });
    await db.collection("merchants").doc("merch-managed").set({
      name: "Merchant gere",
      owner_id: db.doc("users/owner_uid"),
      managed_by_admin: true,
    });

    // Jeux (collection moderne) rattaches par enseigne_id.
    await db.collection("games").doc("game-normal").set({
      name: "Jeu normal",
      create_by: db.doc("users/owner_uid"),
      enseigne_id: db.doc("enseignes/shop-normal"),
      owner_id: db.doc("users/owner_uid"),
    });
    await db.collection("games").doc("game-managed").set({
      name: "Jeu geree",
      create_by: db.doc("users/owner_uid"),
      enseigne_id: db.doc("enseignes/shop-managed"),
      owner_id: db.doc("users/owner_uid"),
    });

    // Jeux legacy a scanner (collection /jeux), rattaches par merchantId
    // uniquement (pas de owner_uid sur le jeu lui-meme) : on veut exercer la
    // resolution via enseignes/merchants, pas le court-circuit
    // ownsTrustedMerchant(resource.data) reserve aux jeux qui portent leur
    // propre identite (hors perimetre de ce gate, cf. commentaire dans
    // firestore.rules).
    await db.collection("jeux").doc("qr-normal").set({
      name: "QR normal",
      merchantId: "shop-normal",
    });
    await db.collection("jeux").doc("qr-managed").set({
      name: "QR gere",
      merchantId: "shop-managed",
    });
    await db.collection("jeux").doc("qr-merchant-managed").set({
      name: "QR gere (via merchants)",
      merchantId: "merch-managed",
    });
  });
});

function ownerContext(uid = "owner_uid") {
  return testEnv.authenticatedContext(uid, {email: `${uid}@example.test`});
}

function strangerContext() {
  return testEnv.authenticatedContext("stranger_uid", {email: "stranger@example.test"});
}

function adminByEmailContext() {
  // Meme mecanisme que le reste de la suite (firestore_rules_admin_console) :
  // aucun custom claim, aucun document users/{uid} -- exactement comment le
  // compte operateur de la console proxiplay-admin s'authentifie aujourd'hui.
  return testEnv.authenticatedContext("admin_console_uid", {
    email: "proxiplay.pro@gmail.com",
  });
}

// --- 1/2 : commercant normal, comportement inchange ---

test("1. commercant normal peut continuer a gerer sa fiche enseigne", async () => {
  const db = ownerContext().firestore();
  await assertSucceeds(
    db.collection("enseignes").doc("shop-normal").update({description: "maj"}),
  );
});

test("2. commercant normal peut continuer a gerer ses jeux (games et jeux legacy)", async () => {
  const db = ownerContext().firestore();
  // updated_time, pas hidden_from_merchant_stats : isSafeMerchantGameUpdate()
  // (preexistante, non touchee) ne permet cette transition que si le jeu a
  // deja une end_date passee, hors sujet ici -- on ne veut prouver que
  // l'acces normal, pas cette regle metier separee.
  await assertSucceeds(
    db.collection("games").doc("game-normal").update({updated_time: new Date()}),
  );
  await assertSucceeds(
    db.collection("jeux").doc("qr-normal").update({active: false}),
  );
});

// --- 3/4/5 : managed_by_admin=true bloque le commercant ---

test("3. managed_by_admin=true bloque la modification de la fiche par le commercant", async () => {
  const db = ownerContext().firestore();
  await assertFails(
    db.collection("enseignes").doc("shop-managed").update({description: "je gere quand meme"}),
  );
  await assertFails(
    db.collection("enseignes").doc("shop-managed").delete(),
  );
});

test("3bis. le commercant ne peut pas repasser managed_by_admin a false", async () => {
  const db = ownerContext().firestore();
  await assertFails(
    db.collection("enseignes").doc("shop-managed").update({managed_by_admin: false}),
  );
});

test("4. managed_by_admin=true bloque la gestion des games par le commercant", async () => {
  const db = ownerContext().firestore();
  await assertFails(
    db.collection("games").doc("game-managed").update({updated_time: new Date()}),
  );
  await assertFails(
    db.collection("games").doc("game-managed").delete(),
  );
});

test("5. managed_by_admin=true bloque la gestion des jeux legacy par le commercant (via enseignes et via merchants)", async () => {
  const db = ownerContext().firestore();
  await assertFails(db.collection("jeux").doc("qr-managed").update({active: false}));
  await assertFails(db.collection("jeux").doc("qr-merchant-managed").update({active: false}));
});

// --- 6/7 : l'admin reel garde la main ---

test("6. l'admin reel (par email, sans custom claim) peut toujours gerer la fiche geree", async () => {
  const db = adminByEmailContext().firestore();
  await assertSucceeds(
    db.collection("enseignes").doc("shop-managed").update({description: "maj admin"}),
  );
  await assertSucceeds(
    db.collection("enseignes").doc("shop-managed").update({managed_by_admin: false}),
  );
});

test("7. l'admin reel peut toujours gerer games et jeux d'une enseigne geree", async () => {
  const db = adminByEmailContext().firestore();
  await assertSucceeds(
    db.collection("games").doc("game-managed").update({name: "renomme par admin"}),
  );
  await assertSucceeds(
    db.collection("jeux").doc("qr-managed").delete(),
  );
});

// --- 8 : compatibilite historique ---

test("8. enseigne sans champ managed_by_admin : comportement normal (deja couvert par 1/2, confirme explicitement)", async () => {
  const db = ownerContext().firestore();
  // enseignes autorise la lecture publique (allow read: if true) : pas besoin
  // de withSecurityRulesDisabled pour verifier la forme du document seede.
  const snapshot = await db.collection("enseignes").doc("shop-normal").get();
  assert.equal("managed_by_admin" in snapshot.data(), false);
  await assertSucceeds(
    db.collection("enseignes").doc("shop-normal").update({city: "Lyon"}),
  );
});

// --- 9 : merchants legacy couvert egalement ---

test("9. merchants legacy : managed_by_admin=true bloque le commercant, comportement normal sinon", async () => {
  const db = ownerContext().firestore();
  await assertSucceeds(
    db.collection("merchants").doc("merch-normal").update({description: "maj"}),
  );
  await assertFails(
    db.collection("merchants").doc("merch-managed").update({description: "je gere quand meme"}),
  );
});

// --- 10 : creation mobile autonome non regressee ---

test("10. creation mobile autonome d'une enseigne par un commercant approuve : inchangee", async () => {
  const db = ownerContext().firestore();
  await assertSucceeds(
    db.collection("enseignes").doc("shop-new-mobile").set({
      name: "Nouvelle boutique (mobile)",
      owner: db.doc("users/owner_uid"),
    }),
  );
});

test("10bis. creation mobile autonome d'un jeu (games) par le commercant proprietaire : inchangee", async () => {
  const db = ownerContext().firestore();
  await assertSucceeds(
    db.collection("games").doc("game-new-mobile").set({
      name: "Nouveau jeu (mobile)",
      create_by: db.doc("users/owner_uid"),
      enseigne_id: db.doc("enseignes/shop-normal"),
    }),
  );
});

// --- Verifications croisees : un tiers ne peut jamais agir a la place du proprietaire ---

test("un utilisateur quelconque ne peut modifier ni une enseigne normale ni une geree", async () => {
  const db = strangerContext().firestore();
  await assertFails(db.collection("enseignes").doc("shop-normal").update({description: "hijack"}));
  await assertFails(db.collection("enseignes").doc("shop-managed").update({description: "hijack"}));
});

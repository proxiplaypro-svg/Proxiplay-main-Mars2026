#!/usr/bin/env node

// "Contrat de requetes" pour la collection prizes : contrairement aux autres
// tests de regles, qui verifient des permissions en abstrait ("qui a le
// droit de lire quoi"), ce fichier reproduit les VRAIES requetes en liste
// (.where(...).get()) que l'app Flutter envoie aujourd'hui, ecran par
// ecran. C'est precisement l'angle mort qui a laisse passer 3 regressions
// silencieuses le 29/08/2026 (commit 48cd073, prizes en lecture restreinte) :
// les tests de regles existants ne testaient que des get() sur un document
// precis, jamais les requetes list() reellement utilisees -- or Firestore
// traite les deux tres differemment (une requete list() est rejetee en
// bloc si un seul de ses where() ne correspond a aucune branche de la regle,
// meme si le document concerne serait individuellement lisible).
//
// Chaque test ci-dessous correspond a UN site d'appel reel dans lib/ :
//   - jeu_detail_commercant_page_widget.dart : where(game_id) + where(owner_id)
//   - home_commercant_page_widget.dart : where(owner_id) seul (merchantOwnedPrizes)
//   - home_commercant_page_widget.dart : where(enseigne_id) seul (par enseigne, dans Future.wait)
// Si un site d'appel change de forme de requete, ou si un nouveau site
// d'appel est ajoute ailleurs dans l'app, ce fichier doit etre mis a jour en
// meme temps (grep `queryPrizesRecord` dans lib/ pour verifier la liste est
// complete).
//
// NOTE 2026-08-31 : firestore.rules a temporairement `allow read: if true`
// sur prizes (voir le commentaire TEMPORAIRE dans ce fichier) -- ces trois
// requetes reussissent donc trivialement en ce moment. Ce n'est pas un
// probleme : elles continueront a reussir exactement pareil une fois la
// regle stricte reactivee (elles sont concues pour), donc ce fichier reste
// la protection utile pour CE moment-la, sans rien avoir a changer ici.
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/firestore_rules_prizes_query_contract.test.js"

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-prizes-query-contract",
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
    await db.collection("users").doc("merchant_uid").set({user_role: "commercant"});
    await db.collection("enseignes").doc("enseigne1").set({
      owner: db.doc("users/merchant_uid"),
    });
    await db.collection("games").doc("game1").set({name: "Jeu test"});

    await db.collection("prizes").doc("prize_owner").set({
      name: "Lot 1",
      winner_id: db.doc("users/some_winner"),
      owner_id: db.doc("users/merchant_uid"),
      enseigne_id: db.doc("enseignes/enseigne1"),
      game_id: db.doc("games/game1"),
      claim_code: "CODE1",
      claimed: false,
    });
    await db.collection("prizes").doc("prize_enseigne_only").set({
      name: "Lot 2 (animation, pas de owner_id)",
      winner_id: db.doc("users/some_other_winner"),
      enseigne_id: db.doc("enseignes/enseigne1"),
      claim_code: "CODE2",
      claimed: false,
    });
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test("contrat : jeu_detail_commercant_page_widget.dart -- where(game_id) + where(owner_id)", async () => {
  const merchant = testEnv.authenticatedContext("merchant_uid");
  const snap = await assertSucceeds(
    merchant.firestore().collection("prizes")
      .where("game_id", "==", merchant.firestore().doc("games/game1"))
      .where("owner_id", "==", merchant.firestore().doc("users/merchant_uid"))
      .get(),
  );
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].id, "prize_owner");
});

test("contrat : home_commercant_page_widget.dart -- where(owner_id) seul (merchantOwnedPrizes)", async () => {
  const merchant = testEnv.authenticatedContext("merchant_uid");
  const snap = await assertSucceeds(
    merchant.firestore().collection("prizes")
      .where("owner_id", "==", merchant.firestore().doc("users/merchant_uid"))
      .get(),
  );
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].id, "prize_owner");
});

test("contrat : home_commercant_page_widget.dart -- where(enseigne_id) seul (par enseigne)", async () => {
  const merchant = testEnv.authenticatedContext("merchant_uid");
  const snap = await assertSucceeds(
    merchant.firestore().collection("prizes")
      .where("enseigne_id", "==", merchant.firestore().doc("enseignes/enseigne1"))
      .get(),
  );
  const ids = snap.docs.map((doc) => doc.id).sort();
  assert.deepEqual(ids, ["prize_enseigne_only", "prize_owner"]);
});

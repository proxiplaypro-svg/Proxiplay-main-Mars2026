// FAILLE 1 (audit global) : la regle games/{document} empechait deja
// correctement un commercant de modifier un jeu finalise
// (isSafeMerchantGameUpdate() restreint l'update a hidden_from_merchant_stats
// et updated_time), mais ne verifiait PAS isGameFinalized() sur `delete` --
// un commercant proprietaire pouvait donc supprimer directement le document
// games/{id} d'un jeu deja clos (gagnant designe ou etat terminal sans
// gagnant), effacant la preuve d'un tirage reellement effectue. Corrige en
// reutilisant isGameFinalized(), la MEME definition canonique deja utilisee
// pour la regle update (ligne juste au-dessus) -- jamais une deuxieme
// definition de "jeu finalise".
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;
const adminUid = "admin_uid";
const merchantUid = "merchant_uid";
const otherMerchantUid = "other_merchant_uid";
const playerUid = "player_uid";
const enseigneId = "shop";
const otherEnseigneId = "other_shop";
const adminManagedEnseigneId = "admin_shop";

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-game-deletion-finalized",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("users").doc(merchantUid).set({
      uid: merchantUid, user_role: "commercant", account_status: "approved",
    });
    await db.collection("users").doc(otherMerchantUid).set({
      uid: otherMerchantUid, user_role: "commercant", account_status: "approved",
    });
    await db.collection("users").doc(playerUid).set({
      uid: playerUid, user_role: "joueur",
    });
    await db.collection("enseignes").doc(enseigneId).set({
      name: "Boutique", owner: db.doc(`users/${merchantUid}`),
    });
    await db.collection("enseignes").doc(otherEnseigneId).set({
      name: "Autre boutique", owner: db.doc(`users/${otherMerchantUid}`),
    });
    await db.collection("enseignes").doc(adminManagedEnseigneId).set({
      name: "Boutique geree admin", managed_by_admin: true,
    });
  });
});

function baseGameFields(ctx, enseigne = enseigneId, owner = merchantUid) {
  return {
    owner_id: ctx.doc(`users/${owner}`),
    enseigne_id: ctx.doc(`enseignes/${enseigne}`),
    create_by: ctx.doc(`users/${owner}`),
    name: "Jeu",
  };
}

async function seedGame(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("games").doc(id).set(data);
  });
}

function merchantDb() {
  return testEnv.authenticatedContext(merchantUid).firestore();
}

// ---------------------------------------------------------------------
// Etats non finalises : suppression legitime toujours autorisee.
// ---------------------------------------------------------------------
test("1. jeu actif appartenant au marchand : suppression autorisee", async () => {
  const db = merchantDb();
  await seedGame("active_game", {
    ...baseGameFields(db),
    status: "actif", end_date: new Date("2099-01-01T00:00:00Z"),
    hasWinner: false, main_prize_winner: null, draw_status: null, drawn_at: null,
  });
  await assertSucceeds(db.collection("games").doc("active_game").delete());
});

test("2. jeu termine normalement (end_date passee) mais sans resultat de tirage : suppression autorisee", async () => {
  const db = merchantDb();
  await seedGame("ended_no_draw", {
    ...baseGameFields(db),
    status: "termine", end_date: new Date("2020-01-01T00:00:00Z"),
    hasWinner: false, main_prize_winner: null, draw_status: null, drawn_at: null,
  });
  await assertSucceeds(db.collection("games").doc("ended_no_draw").delete());
});

// ---------------------------------------------------------------------
// Etats finalises : suppression refusee pour le marchand.
// ---------------------------------------------------------------------
test("3. jeu avec hasWinner:true : suppression refusee pour le marchand", async () => {
  const db = merchantDb();
  await seedGame("has_winner", {
    ...baseGameFields(db), hasWinner: true,
  });
  await assertFails(db.collection("games").doc("has_winner").delete());
});

test("4. jeu avec draw_status:'completed' : suppression refusee", async () => {
  const db = merchantDb();
  await seedGame("draw_completed", {
    ...baseGameFields(db), draw_status: "completed",
  });
  await assertFails(db.collection("games").doc("draw_completed").delete());
});

test("5. jeu avec main_prize_winner : suppression refusee", async () => {
  const db = merchantDb();
  await seedGame("has_main_prize_winner", {
    ...baseGameFields(db), main_prize_winner: db.doc(`users/${playerUid}`),
  });
  await assertFails(db.collection("games").doc("has_main_prize_winner").delete());
});

test("6a. jeu terminal sans gagnant (no_eligible_entries) : suppression refusee", async () => {
  const db = merchantDb();
  await seedGame("no_eligible", {
    ...baseGameFields(db), draw_status: "no_eligible_entries",
  });
  await assertFails(db.collection("games").doc("no_eligible").delete());
});

test("6b. jeu terminal sans gagnant (no_main_prize) : suppression refusee", async () => {
  const db = merchantDb();
  await seedGame("no_main_prize", {
    ...baseGameFields(db), draw_status: "no_main_prize",
  });
  await assertFails(db.collection("games").doc("no_main_prize").delete());
});

test("drawn_at seul (sans autre marqueur) suffit deja a finaliser : suppression refusee", async () => {
  const db = merchantDb();
  await seedGame("drawn_at_only", {
    ...baseGameFields(db), drawn_at: new Date("2026-01-01T00:00:00Z"),
  });
  await assertFails(db.collection("games").doc("drawn_at_only").delete());
});

// ---------------------------------------------------------------------
// Autres acteurs.
// ---------------------------------------------------------------------
test("7. jeu administre par la plateforme (managed_by_admin) : jamais supprimable par un marchand, finalise ou non", async () => {
  const db = merchantDb();
  await seedGame("admin_managed_active", {
    owner_id: db.doc(`users/${merchantUid}`),
    enseigne_id: db.doc(`enseignes/${adminManagedEnseigneId}`),
    create_by: db.doc(`users/${merchantUid}`),
    hasWinner: false,
  });
  await seedGame("admin_managed_finalized", {
    owner_id: db.doc(`users/${merchantUid}`),
    enseigne_id: db.doc(`enseignes/${adminManagedEnseigneId}`),
    create_by: db.doc(`users/${merchantUid}`),
    hasWinner: true,
  });
  await assertFails(db.collection("games").doc("admin_managed_active").delete());
  await assertFails(db.collection("games").doc("admin_managed_finalized").delete());
});

test("8. autre marchand : suppression refusee, jeu actif ou finalise", async () => {
  const other = testEnv.authenticatedContext(otherMerchantUid).firestore();
  await seedGame("active_for_owner", baseGameFields(other, enseigneId, merchantUid));
  await seedGame("finalized_for_owner", {
    owner_id: other.doc(`users/${merchantUid}`),
    enseigne_id: other.doc(`enseignes/${enseigneId}`),
    create_by: other.doc(`users/${merchantUid}`),
    hasWinner: true,
  });
  await assertFails(other.collection("games").doc("active_for_owner").delete());
  await assertFails(other.collection("games").doc("finalized_for_owner").delete());
});

test("9. utilisateur joueur : suppression refusee, jeu actif ou finalise", async () => {
  const player = testEnv.authenticatedContext(playerUid).firestore();
  await seedGame("active_for_player_test", baseGameFields(player, enseigneId, merchantUid));
  await seedGame("finalized_for_player_test", {
    owner_id: player.doc(`users/${merchantUid}`),
    enseigne_id: player.doc(`enseignes/${enseigneId}`),
    create_by: player.doc(`users/${merchantUid}`),
    hasWinner: true,
  });
  await assertFails(player.collection("games").doc("active_for_player_test").delete());
  await assertFails(player.collection("games").doc("finalized_for_player_test").delete());
});

test("Admin : suppression toujours autorisee, meme sur un jeu finalise (comportement de confiance inchange)", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await seedGame("admin_can_delete_finalized", {
    owner_id: admin.doc(`users/${merchantUid}`),
    enseigne_id: admin.doc(`enseignes/${enseigneId}`),
    create_by: admin.doc(`users/${merchantUid}`),
    hasWinner: true,
  });
  await assertSucceeds(admin.collection("games").doc("admin_can_delete_finalized").delete());
});

// ---------------------------------------------------------------------
// Contournements.
// ---------------------------------------------------------------------
test("contournement : changer le statut avant suppression est deja refuse par isSafeMerchantGameUpdate", async () => {
  const db = merchantDb();
  await seedGame("try_unfinalize", {
    ...baseGameFields(db), hasWinner: true, draw_status: "completed",
  });
  // isSafeMerchantGameUpdate() n'autorise que hidden_from_merchant_stats/
  // updated_time : toute tentative de reecrire hasWinner/draw_status doit
  // deja echouer, independamment de ce correctif.
  await assertFails(
    db.collection("games").doc("try_unfinalize").update({ hasWinner: false, draw_status: null }),
  );
  await assertFails(db.collection("games").doc("try_unfinalize").delete());
});

test("contournement : supprimer/recreer sous le meme id reste bloque (le document existe toujours, c'est un update)", async () => {
  const db = merchantDb();
  await seedGame("same_id_recreate", {
    ...baseGameFields(db), hasWinner: true,
  });
  await assertFails(db.collection("games").doc("same_id_recreate").delete());
  // Le document existe toujours : un set() cote client est evalue comme un
  // update, deja borne par isSafeMerchantGameUpdate() (hasOnly restreint).
  await assertFails(
    db.collection("games").doc("same_id_recreate").set({ name: "Nouvelle edition", hasWinner: false }),
  );
});

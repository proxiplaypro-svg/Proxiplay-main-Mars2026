// Regression: the games/{document} update rule granted admin an
// unconditional `allow update: if isAdmin()` with no restriction at all.
// The Admin console's "Modifier" screen (proxiplay-admin:
// app/admin/games/page.tsx -> GameEditModal -> updateGame(), a direct
// client-SDK write with no server intermediary) could therefore push a
// finished/drawn game's end_date into the future and flip it back to
// active/visible on the SAME document -- exactly what happened to the
// real "Memphis" game in production: created 24/04/2026, drawn
// 30/09/2026 (draw_status:no_main_prize), then republished with
// end_date 03/11/2026 while its old instant_winners/participants from
// the first edition were left untouched.
//
// Fixed by isGameFinalized()/isSafeFinalizedGameUpdate() in
// firestore.rules: once a game carries any real finalization marker
// (hasWinner, main_prize_winner, draw_status, drawn_at -- the exact
// fields main_prize_draw.js writes together as a draw result), admin can
// still correct harmless fields (name, description, photo...) but can no
// longer change end_date, status, visible_public, or the finalization
// markers themselves. Organizing a new edition still goes through
// Dupliquer (a brand-new document, unaffected create-side), never
// through editing this one.
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
const enseigneId = "shop";

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-game-finalization-guard",
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
      uid: merchantUid,
      user_role: "commercant",
      account_status: "approved",
    });
    await db.collection("enseignes").doc(enseigneId).set({
      name: "Boutique",
      owner: db.doc(`users/${merchantUid}`),
    });
  });
});

function baseGameFields(merchant) {
  return {
    owner_id: merchant.doc(`users/${merchantUid}`),
    enseigne_id: merchant.doc(`enseignes/${enseigneId}`),
    create_by: merchant.doc(`users/${merchantUid}`),
    name: "Jeu",
  };
}

async function seedGame(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("games").doc(id).set(data);
  });
}

test("1. jeu jamais cloture : modification normale (y compris end_date/status) toujours autorisee pour l'admin", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await seedGame("active_game", {
    ...baseGameFields(admin),
    status: "actif",
    visible_public: true,
    end_date: new Date("2026-06-01T00:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: null,
    drawn_at: null,
  });

  await assertSucceeds(
    admin.collection("games").doc("active_game").update({
      end_date: new Date("2026-12-31T00:00:00Z"),
      status: "actif",
      visible_public: true,
    }),
  );
});

test("2. jeu cloture : correction non reactivante (name/description) autorisee", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  const endDate = new Date("2026-09-30T00:00:00Z");
  const drawnAt = new Date("2026-09-30T20:00:00Z");
  await seedGame("memphis_like", {
    ...baseGameFields(admin),
    status: "ended",
    visible_public: false,
    end_date: endDate,
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: drawnAt,
  });

  await assertSucceeds(
    admin.collection("games").doc("memphis_like").update({
      name: "Jeu (titre corrige)",
      description: "Description corrigee",
    }),
  );
});

test("3. jeu cloture + nouvelle end_date future : refuse", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  const endDate = new Date("2026-09-30T00:00:00Z");
  const drawnAt = new Date("2026-09-30T20:00:00Z");
  await seedGame("memphis_relaunch_attempt", {
    ...baseGameFields(admin),
    status: "ended",
    visible_public: false,
    end_date: endDate,
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: drawnAt,
  });

  await assertFails(
    admin.collection("games").doc("memphis_relaunch_attempt").update({
      end_date: new Date("2026-11-03T00:00:00Z"),
    }),
  );
});

test("4. jeu cloture + tentative de retour actif/public : refuse", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  const endDate = new Date("2026-09-30T00:00:00Z");
  const drawnAt = new Date("2026-09-30T20:00:00Z");
  await seedGame("memphis_status_flip", {
    ...baseGameFields(admin),
    status: "ended",
    visible_public: false,
    end_date: endDate,
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: drawnAt,
  });

  await assertFails(
    admin.collection("games").doc("memphis_status_flip").update({ status: "actif" }),
  );
  await assertFails(
    admin.collection("games").doc("memphis_status_flip").update({ visible_public: true }),
  );
});

test("4b. jeu cloture avec un vrai gagnant : meme refus (hasWinner/main_prize_winner couverts, pas seulement draw_status)", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await seedGame("won_game", {
    ...baseGameFields(admin),
    status: "ended",
    visible_public: false,
    end_date: new Date("2026-09-30T00:00:00Z"),
    hasWinner: true,
    main_prize_winner: admin.doc(`users/${merchantUid}`),
    draw_status: "completed",
    drawn_at: new Date("2026-09-30T20:00:00Z"),
  });

  await assertFails(
    admin.collection("games").doc("won_game").update({
      end_date: new Date("2026-12-01T00:00:00Z"),
    }),
  );
  await assertFails(
    admin.collection("games").doc("won_game").update({ hasWinner: false }),
  );
});

test("5. Dupliquer un jeu cloture : toujours autorise, nouveau gameId, non affecte par le garde", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await seedGame("source_finished_game", {
    ...baseGameFields(admin),
    status: "ended",
    visible_public: false,
    end_date: new Date("2026-09-30T00:00:00Z"),
    hasWinner: false,
    main_prize_winner: null,
    draw_status: "no_main_prize",
    drawn_at: new Date("2026-09-30T20:00:00Z"),
  });

  // Dupliquer passe toujours par `create` (nouveau document), jamais par
  // `update` sur le document source -- le garde ci-dessus ne s'applique
  // qu'a `update` et ne doit donc jamais bloquer une vraie nouvelle
  // edition.
  const newGameRef = admin.collection("games").doc();
  assert.notEqual(newGameRef.id, "source_finished_game");
  await assertSucceeds(
    newGameRef.set({
      ...baseGameFields(admin),
      status: "brouillon",
      visible_public: false,
      end_date: new Date("2027-01-01T00:00:00Z"),
      hasWinner: false,
      main_prize_winner: null,
    }),
  );
});

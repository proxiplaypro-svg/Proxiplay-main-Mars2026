// Full production cycle: jeu actif -> fin du jeu -> finalisation -> etat
// final, with the EXACT write shape main_prize_draw.js uses in production
// (a single atomic update bundling status+draw_status+drawn_at, and
// status+draw_status+drawn_at+hasWinner+main_prize_winner for the winner
// case). Confirms isGameFinalized()/isSafeFinalizedGameUpdate() never
// blocks this transition, because the guard only restricts updates where
// the game is ALREADY finalized (resource.data, the BEFORE state) -- the
// finalizing write itself goes from non-finalized to finalized, so it is
// never caught by the guard regardless of which SDK performs it.
//
// Requested as a follow-up to the rules review: confirm the real closure
// sequence still works after isSafeFinalizedGameUpdate() was added.
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
const playerUid = "player_uid";
const enseigneId = "shop";

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-game-closure-cycle",
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
    await db.collection("users").doc(playerUid).set({ uid: playerUid });
    await db.collection("enseignes").doc(enseigneId).set({
      name: "Boutique",
      owner: db.doc(`users/${merchantUid}`),
    });
  });
});

function baseFields(ctxFirestore) {
  return {
    owner_id: ctxFirestore.doc(`users/${merchantUid}`),
    enseigne_id: ctxFirestore.doc(`enseignes/${enseigneId}`),
    create_by: ctxFirestore.doc(`users/${merchantUid}`),
    name: "Jeu du cycle complet",
  };
}

// The write performed as admin here deliberately goes through the
// authenticated CLIENT path (not withSecurityRulesDisabled): production
// always does this via main_prize_draw.js's Admin SDK, which bypasses
// rules entirely and would never be blocked either way -- but running it
// through the rules-bound admin path is a STRICTER check: it proves the
// guard would not interfere even if this write were ever subject to it.
test("cycle 1: jeu actif -> fin -> aucun lot principal (no_main_prize), ecriture atomique", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("games").doc("cycle_no_main_prize").set({
      ...baseFields(ctx.firestore()),
      status: "actif",
      visible_public: true,
      end_date: new Date("2026-09-30T20:00:00Z"),
      hasMainPrize: false,
      hasWinner: false,
      main_prize_winner: null,
      draw_status: null,
      drawn_at: null,
    });
  });

  // Exact shape of main_prize_draw.js line 25:
  // tx.update(gameRef, {status:'ended', draw_status:'no_main_prize', drawn_at:now})
  await assertSucceeds(
    admin.collection("games").doc("cycle_no_main_prize").update({
      status: "ended",
      draw_status: "no_main_prize",
      drawn_at: new Date("2026-09-30T20:05:00Z"),
    }),
  );

  // Once finalized, the SAME document can no longer be pushed back to an
  // active/visible state -- this is the behavior being protected.
  await assertFails(
    admin.collection("games").doc("cycle_no_main_prize").update({
      end_date: new Date("2026-11-03T00:00:00Z"),
      status: "actif",
      visible_public: true,
    }),
  );
});

test("cycle 2: jeu actif -> fin -> aucun participant eligible (no_eligible_entries), ecriture atomique", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("games").doc("cycle_no_eligible").set({
      ...baseFields(ctx.firestore()),
      status: "actif",
      visible_public: true,
      end_date: new Date("2026-09-30T20:00:00Z"),
      hasMainPrize: true,
      prize_value: 50,
      hasWinner: false,
      main_prize_winner: null,
      draw_status: null,
      drawn_at: null,
    });
  });

  // Exact shape of main_prize_draw.js line 39.
  await assertSucceeds(
    admin.collection("games").doc("cycle_no_eligible").update({
      status: "ended",
      draw_status: "no_eligible_entries",
      drawn_at: new Date("2026-09-30T20:05:00Z"),
    }),
  );

  await assertFails(
    admin.collection("games").doc("cycle_no_eligible").update({ status: "actif" }),
  );
});

test("cycle 3: jeu actif -> fin -> tirage avec gagnant (completed), ecriture atomique des 5 champs ensemble", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("games").doc("cycle_completed").set({
      ...baseFields(ctx.firestore()),
      status: "actif",
      visible_public: true,
      end_date: new Date("2026-09-30T20:00:00Z"),
      hasMainPrize: true,
      prize_value: 50,
      hasWinner: false,
      main_prize_winner: null,
      draw_status: null,
      drawn_at: null,
    });
  });

  // Exact shape of main_prize_draw.js line 65: hasWinner, main_prize_winner,
  // status, draw_status and drawn_at all written together in one update.
  await assertSucceeds(
    admin.collection("games").doc("cycle_completed").update({
      hasWinner: true,
      main_prize_winner: admin.doc(`users/${playerUid}`),
      status: "ended",
      draw_status: "completed",
      drawn_at: new Date("2026-09-30T20:05:00Z"),
    }),
  );

  // The result is now immutable on these fields, including an attempt to
  // "correct" the winner or un-flag hasWinner.
  await assertFails(
    admin.collection("games").doc("cycle_completed").update({ hasWinner: false }),
  );
  await assertFails(
    admin.collection("games").doc("cycle_completed").update({
      end_date: new Date("2026-11-03T00:00:00Z"),
      visible_public: true,
    }),
  );

  // But harmless historical corrections remain possible.
  await assertSucceeds(
    admin.collection("games").doc("cycle_completed").update({ name: "Jeu du cycle complet (corrige)" }),
  );
});

test("cycle 4: une 2e ecriture separee qui ne toucherait QUE visible_public apres coup serait refusee -- " +
  "confirme que seule l'ecriture atomique (la seule utilisee en production) fonctionne", async () => {
  const admin = testEnv.authenticatedContext(adminUid, { admin: true }).firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("games").doc("cycle_two_step").set({
      ...baseFields(ctx.firestore()),
      status: "actif",
      visible_public: true,
      end_date: new Date("2026-09-30T20:00:00Z"),
      hasMainPrize: false,
      hasWinner: false,
      main_prize_winner: null,
      draw_status: null,
      drawn_at: null,
    });
  });

  await assertSucceeds(
    admin.collection("games").doc("cycle_two_step").update({
      status: "ended",
      draw_status: "no_main_prize",
      drawn_at: new Date("2026-09-30T20:05:00Z"),
    }),
  );

  // No production code path does this second, separate write -- it is
  // intentionally refused by design, not a scenario main_prize_draw.js
  // (or any other backend writer, all Admin SDK and all atomic) ever
  // produces. See the writer audit in the review response.
  await assertFails(
    admin.collection("games").doc("cycle_two_step").update({ visible_public: false }),
  );
});

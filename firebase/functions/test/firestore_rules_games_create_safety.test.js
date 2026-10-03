// Regression: the `games` create rule checked ownership (create_by, ownsGame,
// isApprovedMerchant) but never restricted the VALUES of server-controlled
// fields at creation time -- a merchant could create a game that is already
// visible_public:true, already has a winner (hasWinner/main_prize_winner),
// or already carries a fabricated participations count. isSafeMerchantGameUpdate()
// already protects these fields from a later update, but create was wide open.
// Fixed by isSafeMerchantGameCreate() in firestore.rules.
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
const uid = "merchant_uid";
const enseigneId = "shop";

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-games-create-safety",
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
    await db.collection("users").doc(uid).set({ uid, user_role: "commercant", account_status: "approved" });
    await db.collection("enseignes").doc(enseigneId).set({ name: "Boutique", owner: db.doc(`users/${uid}`) });
  });
});

function baseGame(merchant) {
  return {
    owner_id: merchant.doc(`users/${uid}`),
    enseigne_id: merchant.doc(`enseignes/${enseigneId}`),
    create_by: merchant.doc(`users/${uid}`),
    name: "Jeu",
    end_date: new Date(Date.now() + 86400000),
  };
}

test("merchant cannot self-publish a game at creation (visible_public:true)", async () => {
  const merchant = testEnv.authenticatedContext(uid, {}).firestore();
  await assertFails(
    merchant.collection("games").doc().set({ ...baseGame(merchant), visible_public: true }),
  );
});

test("merchant cannot fabricate a winner at creation (hasWinner/main_prize_winner)", async () => {
  const merchant = testEnv.authenticatedContext(uid, {}).firestore();
  await assertFails(
    merchant.collection("games").doc().set({
      ...baseGame(merchant),
      hasWinner: true,
      main_prize_winner: merchant.doc(`users/${uid}`),
    }),
  );
});

test("merchant cannot inject a participations count at creation", async () => {
  const merchant = testEnv.authenticatedContext(uid, {}).firestore();
  await assertFails(
    merchant.collection("games").doc().set({ ...baseGame(merchant), participations: 999999 }),
  );
});

test("no regression: the real merchant form's exact draft payload still succeeds", async () => {
  // Mirrors add_game_commercant_page_widget.dart's gameFieldsData shape.
  const merchant = testEnv.authenticatedContext(uid, {}).firestore();
  await assertSucceeds(
    merchant.collection("games").doc().set({
      ...baseGame(merchant),
      visible_public: false,
      hasWinner: false,
      main_prize_winner: null,
      participations: 0,
      has_main_prize: true,
      prize_value: 20,
    }),
  );
});

test("no regression: omitting the server-controlled fields entirely still succeeds (defaults are safe)", async () => {
  const merchant = testEnv.authenticatedContext(uid, {}).firestore();
  await assertSucceeds(merchant.collection("games").doc().set(baseGame(merchant)));
});

test("no regression: admin retains full freedom to create any game shape", async () => {
  const admin = testEnv.authenticatedContext("admin_uid", { admin: true }).firestore();
  await assertSucceeds(
    admin.collection("games").doc().set({
      ...baseGame(admin),
      create_by: admin.doc("users/admin_uid"),
      visible_public: true,
      hasWinner: true,
    }),
  );
});

// FAILLE 2 (audit global) : ownsMerchantPrize() (firestore.rules) prouve
// seulement que le marchand EST le proprietaire du document prizes (via
// owner_id, ou a defaut via l'enseigne), jamais que ce lot le concerne
// reellement. gamePrizeOwnership() (merchant_ownership.js, utilise par
// main_prize_draw.js ET participate_in_game_transaction.js) pose owner_id
// des que l'enseigne a un proprietaire, QUEL QUE SOIT le fulfillment_type --
// y compris sur un lot fulfillment_type:'platform' (un marchand peut
// configurer ce mode sur son propre jeu sans que cela le prive d'etre
// proprietaire de l'enseigne). Resultat avant correction : un marchand
// hebergeant le jeu pouvait get() le document prizes COMPLET d'un lot
// partner/platform, claim_code inclus, alors que seule la plateforme (ou le
// partenaire) gere reellement la remise de ce lot.
//
// Correction : get()/list() exigent desormais isMerchantPrize(resource.data)
// (fulfillment_type == 'merchant', deja le contrat utilise par
// isPrizeClaimValidationUpdate() pour l'ecriture) EN PLUS de
// ownsMerchantPrize(). Le gagnant (isOwnerRef(winner_id)) et l'admin restent
// inchanges. ownsPrize() (merchant_ownership.js, utilise par
// getMerchantPrizes/merchantPrizesPage) recoit le meme garde-fou pour que le
// callable ne propose plus au client des ids qu'il ne pourra de toute facon
// plus lire (Future.wait sur des .get() individuels, voir
// merchant_prizes_service.dart : un seul permission-denied ferait echouer
// toute la page).
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-prize-fulfillment-confidentiality";
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
if (!admin.apps.length) admin.initializeApp();
const { merchantPrizesPage } = require("../merchant_prizes");

let testEnv;
const adminUid = "admin_uid";
const merchantUid = "merchant_uid";
const otherMerchantUid = "other_merchant_uid";
const winnerUid = "winner_uid";
const playerUid = "third_party_player_uid";
const enseigneId = "shop";

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-proxiplay-prize-fulfillment-confidentiality",
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
    await db.collection("users").doc(merchantUid).set({ uid: merchantUid, user_role: "commercant" });
    await db.collection("users").doc(otherMerchantUid).set({ uid: otherMerchantUid, user_role: "commercant" });
    await db.collection("users").doc(winnerUid).set({ uid: winnerUid, user_role: "joueur" });
    await db.collection("users").doc(playerUid).set({ uid: playerUid, user_role: "joueur" });
    await db.collection("enseignes").doc(enseigneId).set({
      owner: db.doc(`users/${merchantUid}`), owner_id: db.doc(`users/${merchantUid}`),
    });
  });
});

async function seedPrize(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("prizes").doc(id).set({
      winner_id: ctx.firestore().doc(`users/${winnerUid}`),
      enseigne_id: ctx.firestore().doc(`enseignes/${enseigneId}`),
      claim_code: "SECRET-CODE-1234",
      claimed: false,
      ...data,
    });
  });
}

function merchantDb() { return testEnv.authenticatedContext(merchantUid).firestore(); }
function otherMerchantDb() { return testEnv.authenticatedContext(otherMerchantUid).firestore(); }
function winnerDb() { return testEnv.authenticatedContext(winnerUid).firestore(); }
function playerDb() { return testEnv.authenticatedContext(playerUid).firestore(); }
function adminDb() { return testEnv.authenticatedContext(adminUid, { admin: true }).firestore(); }

// ---------------------------------------------------------------------
// Le coeur de la faille : owner_id == marchand sur un lot NON "merchant".
// ---------------------------------------------------------------------
test("fulfillment_type='platform' avec owner_id==marchand : get() refuse au marchand (ALLOW gagnant/admin preserve)", async () => {
  const db = merchantDb();
  await seedPrize("platform_prize", {
    owner_id: db.doc(`users/${merchantUid}`), fulfillment_type: "platform",
  });
  // DENY : le marchand ne doit jamais lire le claim_code d'un lot platform.
  await assertFails(db.collection("prizes").doc("platform_prize").get());
  // ALLOW : le gagnant garde son acces legitime.
  await assertSucceeds(winnerDb().collection("prizes").doc("platform_prize").get());
  // ALLOW : l'admin garde son acces de confiance.
  await assertSucceeds(adminDb().collection("prizes").doc("platform_prize").get());
});

test("fulfillment_type='partner' avec owner_id==marchand (cas defensif) : get() refuse au marchand", async () => {
  const db = merchantDb();
  await seedPrize("partner_prize", {
    owner_id: db.doc(`users/${merchantUid}`), fulfillment_type: "partner",
  });
  await assertFails(db.collection("prizes").doc("partner_prize").get());
  await assertSucceeds(winnerDb().collection("prizes").doc("partner_prize").get());
  await assertSucceeds(adminDb().collection("prizes").doc("partner_prize").get());
});

// ---------------------------------------------------------------------
// Workflow legitime preserve : fulfillment_type='merchant' (explicite ou
// par defaut, compatibilite avec les documents historiques).
// ---------------------------------------------------------------------
test("fulfillment_type='merchant' explicite : get() reste autorise pour le marchand proprietaire", async () => {
  const db = merchantDb();
  await seedPrize("merchant_prize_explicit", {
    owner_id: db.doc(`users/${merchantUid}`), fulfillment_type: "merchant",
  });
  await assertSucceeds(db.collection("prizes").doc("merchant_prize_explicit").get());
});

test("fulfillment_type absent (document historique) : get() reste autorise pour le marchand proprietaire (defaut 'merchant')", async () => {
  const db = merchantDb();
  await seedPrize("merchant_prize_legacy", {
    owner_id: db.doc(`users/${merchantUid}`),
  });
  await assertSucceeds(db.collection("prizes").doc("merchant_prize_legacy").get());
});

// ---------------------------------------------------------------------
// Acteurs.
// ---------------------------------------------------------------------
test("autre marchand : toujours refuse, quel que soit le fulfillment_type", async () => {
  await seedPrize("for_other_merchant_1", { owner_id: testEnv.authenticatedContext(merchantUid).firestore().doc(`users/${merchantUid}`), fulfillment_type: "merchant" });
  await seedPrize("for_other_merchant_2", { owner_id: testEnv.authenticatedContext(merchantUid).firestore().doc(`users/${merchantUid}`), fulfillment_type: "platform" });
  const other = otherMerchantDb();
  await assertFails(other.collection("prizes").doc("for_other_merchant_1").get());
  await assertFails(other.collection("prizes").doc("for_other_merchant_2").get());
});

test("joueur tiers (ni gagnant ni marchand) : toujours refuse, quel que soit le fulfillment_type", async () => {
  const ref = testEnv.authenticatedContext(merchantUid).firestore().doc(`users/${merchantUid}`);
  await seedPrize("for_third_party_1", { owner_id: ref, fulfillment_type: "merchant" });
  await seedPrize("for_third_party_2", { owner_id: ref, fulfillment_type: "platform" });
  const player = playerDb();
  await assertFails(player.collection("prizes").doc("for_third_party_1").get());
  await assertFails(player.collection("prizes").doc("for_third_party_2").get());
});

test("Admin : get() toujours autorise, quel que soit le fulfillment_type (comportement de confiance inchange)", async () => {
  const ref = testEnv.authenticatedContext(merchantUid).firestore().doc(`users/${merchantUid}`);
  await seedPrize("for_admin_1", { owner_id: ref, fulfillment_type: "merchant" });
  await seedPrize("for_admin_2", { owner_id: ref, fulfillment_type: "platform" });
  await seedPrize("for_admin_3", { owner_id: ref, fulfillment_type: "partner" });
  const admin = adminDb();
  await assertSucceeds(admin.collection("prizes").doc("for_admin_1").get());
  await assertSucceeds(admin.collection("prizes").doc("for_admin_2").get());
  await assertSucceeds(admin.collection("prizes").doc("for_admin_3").get());
});

test("gagnant : get() toujours autorise, quel que soit le fulfillment_type", async () => {
  const ref = testEnv.authenticatedContext(merchantUid).firestore().doc(`users/${merchantUid}`);
  await seedPrize("winner_access_merchant", { owner_id: ref, fulfillment_type: "merchant" });
  await seedPrize("winner_access_platform", { owner_id: ref, fulfillment_type: "platform" });
  await seedPrize("winner_access_partner", { owner_id: ref, fulfillment_type: "partner" });
  const winner = winnerDb();
  await assertSucceeds(winner.collection("prizes").doc("winner_access_merchant").get());
  await assertSucceeds(winner.collection("prizes").doc("winner_access_platform").get());
  await assertSucceeds(winner.collection("prizes").doc("winner_access_partner").get());
});

// ---------------------------------------------------------------------
// list() : limite architecturale CONSTATEE (pas corrigee par ce garde-fou
// seul) -- a signaler, pas a cacher.
//
// Contrairement a get() (verifie document par document, correctement
// refuse ci-dessus), Firestore evalue une regle list() en fonction de ce
// que les filtres where() de la REQUETE elle-meme permettent de PROUVER,
// pas en reverifiant chaque document retourne un par un. Verifie
// empiriquement sur cet emulateur :
//  - where('owner_id','==',marchand) SEUL : la requete reussit et renvoie
//    quand meme un lot fulfillment_type:'platform' (isMerchantPrize()
//    n'est pas constatable depuis les filtres de cette requete : Firestore
//    ne le verifie donc pas a l'execution).
//  - where('owner_id','==',marchand).where('fulfillment_type','==','merchant')
//    (le filtre encode explicitement la condition) : la meme requete
//    exclut alors correctement le lot platform.
// Le chemin reellement emprunte par l'app actuelle (getMerchantPrizes +
// get() individuel, voir merchant_prizes_service.dart) ne passe PAS par
// une requete where(owner_id) brute et reste donc protege par le
// correctif get()/ownsPrize() ci-dessus. Mais firestore_rules_prizes_
// query_contract.test.js documente explicitement que cette requete brute
// est gardee en compatibilite pour d'anciennes versions client encore en
// circulation -- pour CES clients-la, ce garde-fou list() seul NE SUFFIT
// PAS a empecher la fuite tant que leur requete ne filtre pas elle-meme
// sur fulfillment_type. Signale en risque residuel plutot que presente a
// tort comme ferme.
test("LIMITE CONSTATEE : where(owner_id) seul renvoie encore un lot platform (list() non filtrant sur un champ hors requete)", async () => {
  const db = merchantDb();
  await seedPrize("list_platform_only", { owner_id: db.doc(`users/${merchantUid}`), fulfillment_type: "platform" });
  const snap = await assertSucceeds(
    db.collection("prizes").where("owner_id", "==", db.doc(`users/${merchantUid}`)).get(),
  );
  assert.deepEqual(snap.docs.map((d) => d.id), ["list_platform_only"]);
});

test("where(owner_id) + where(fulfillment_type=='merchant') explicite : le lot platform est correctement exclu", async () => {
  const db = merchantDb();
  await seedPrize("list_platform_excluded", { owner_id: db.doc(`users/${merchantUid}`), fulfillment_type: "platform" });
  const snap = await assertSucceeds(
    db.collection("prizes")
      .where("owner_id", "==", db.doc(`users/${merchantUid}`))
      .where("fulfillment_type", "==", "merchant")
      .get(),
  );
  assert.equal(snap.size, 0);
});

// ---------------------------------------------------------------------
// Contournement : getMerchantPrizes/merchantPrizesPage ne doit plus
// proposer au client un id qu'il ne pourra de toute facon plus lire.
// ---------------------------------------------------------------------
test("contournement : getMerchantPrizes n'inclut plus les lots platform/partner du marchand", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc("games/g1").set({ owner_id: db.doc(`users/${merchantUid}`) });
  });
  const ref = testEnv.authenticatedContext(merchantUid).firestore().doc(`users/${merchantUid}`);
  await seedPrize("page_merchant", { owner_id: ref, fulfillment_type: "merchant", game_id: testEnv.authenticatedContext(merchantUid).firestore().doc("games/g1") });
  await seedPrize("page_platform", { owner_id: ref, fulfillment_type: "platform", game_id: testEnv.authenticatedContext(merchantUid).firestore().doc("games/g1") });

  const page = await merchantPrizesPage(merchantUid, {});
  assert.deepEqual(page.ids.sort(), ["page_merchant"]);

  // Chaque id renvoye doit reellement rester lisible par le client (pas de
  // permission-denied qui ferait echouer tout le Future.wait cote Dart).
  for (const id of page.ids) {
    await assertSucceeds(testEnv.authenticatedContext(merchantUid).firestore().doc(`prizes/${id}`).get());
  }
});

// ---------------------------------------------------------------------
// Meme secret ailleurs ? public_prize_winners / my_lots / instant_winners.
// ---------------------------------------------------------------------
test("public_prize_winners ne contient jamais claim_code (lecture publique)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc("public_prize_winners/platform_prize").set({
      winnerFirstName: "Al", winnerCity: "Paris", name: "Lot", win_date: new Date(),
    });
  });
  const snap = await assertSucceeds(
    testEnv.unauthenticatedContext().firestore().doc("public_prize_winners/platform_prize").get(),
  );
  assert.equal("claim_code" in (snap.data() || {}), false);
});

test("instant_winners reste reserve a l'admin, meme pour le marchand proprietaire du jeu", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc("games/g2").set({ owner_id: ctx.firestore().doc(`users/${merchantUid}`) });
    await ctx.firestore().doc("games/g2/instant_winners/iw1").set({ claim_code: "SECRET" });
  });
  await assertFails(merchantDb().doc("games/g2/instant_winners/iw1").get());
  await assertSucceeds(adminDb().doc("games/g2/instant_winners/iw1").get());
});

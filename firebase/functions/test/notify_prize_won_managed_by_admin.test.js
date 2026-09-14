#!/usr/bin/env node

// Verifies notifyPrizeWon respects managed_by_admin sur l'enseigne du jeu :
// aucun email ni push marchand "nouveau gagnant" pour une enseigne geree par
// Proxiplay, sans toucher aux notifications joueur ni aux ecritures
// prize/my_lots/claim_code/stats (que notifyPrizeWon ne modifie de toute
// facon jamais -- verifie explicitement ci-dessous).
//
// Run against the local Firestore emulator only:
//
//   firebase emulators:exec --only firestore \
//     "node --test test/notify_prize_won_managed_by_admin.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
// Projet dedie : voir la meme precaution dans notify_prize_won_idempotence.test.js.
process.env.GCLOUD_PROJECT = "demo-proxiplay-notify-managed-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

const functionsTest = require("firebase-functions-test")();
functionsTest.mockConfig({
  smtp: {
    host: "smtp.test",
    port: "587",
    secure: "false",
    user: "test-user",
    pass: "test-pass",
    from_email: "noreply@proxiplay.fr",
    from_name: "Proxiplay",
  },
});

let sentEmails = [];
nodemailer.createTransport = () => ({
  sendMail: async (mail) => {
    sentEmails.push(mail);
    return {accepted: [mail.to]};
  },
});

const myFunctions = require("../index.js");
const wrappedNotifyPrizeWon = functionsTest.wrap(myFunctions.notifyPrizeWon);

const firestore = admin.firestore();
const kPushNotificationsCollection = "ff_push_notifications";

async function clearFirestore() {
  const collections = await firestore.listCollections();
  await Promise.all(collections.map((col) => firestore.recursiveDelete(col)));
}

test.before(async () => {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
});

test.beforeEach(async () => {
  await clearFirestore();
  sentEmails = [];
});

test.after(async () => {
  await functionsTest.cleanup();
});

async function seedPrize({managedByAdmin}) {
  const winnerRef = firestore.collection("users").doc("winner1");
  const merchantRef = firestore.collection("users").doc("merchant1");
  const enseigneRef = firestore.collection("enseignes").doc("shop1");
  const gameRef = firestore.collection("games").doc("game1");
  const prizeRef = firestore.collection("prizes").doc("prize1");

  await winnerRef.set({
    first_name: "Alice",
    last_name: "Dupont",
    city: "Paris",
    email: "alice@example.com",
  });
  await merchantRef.set({
    user_role: "commercant",
    email: "merchant@example.com",
    company_name: "Ma boutique",
  });
  await enseigneRef.set({
    name: "Ma boutique",
    owner: merchantRef,
    managed_by_admin: managedByAdmin,
  });
  await gameRef.set({name: "Jeu Test", create_by: merchantRef, enseigne_id: enseigneRef});
  const prizeData = {
    winner_id: winnerRef,
    owner_id: merchantRef,
    enseigne_id: enseigneRef,
    game_id: gameRef,
    name: "Lot test",
    claim_code: "CODE123",
    claimed: false,
    prize_type: "principal",
    fulfillment_type: "merchant",
  };
  await prizeRef.set(prizeData);
  // Requis par inspectPrizeAssignmentConsistency() pour que l'email joueur
  // parte (garde-fou d'integrite preexistant, sans rapport avec managed_by_admin).
  await winnerRef.collection("my_lots").doc(prizeRef.id).set({prize_id: prizeRef});

  return {prizeRef, prizeData};
}

async function invoke(prizeRef) {
  const snapshot = await prizeRef.get();
  const context = {params: {prizeId: prizeRef.id}};
  await wrappedNotifyPrizeWon(snapshot, context);
}

function statusRef(prizeId) {
  // Meme resolution que getPrizeNotificationStatusRef() dans index.js.
  return firestore.collection("_system_jobs").doc("prize_notifications")
    .collection("entries").doc(prizeId);
}

// --- 11 : managed_by_admin=true => aucun email marchand ---

test("11. managed_by_admin=true : aucun email marchand envoye", async () => {
  const {prizeRef} = await seedPrize({managedByAdmin: true});
  await invoke(prizeRef);

  const merchantEmails = sentEmails.filter((mail) => mail.to === "merchant@example.com");
  assert.equal(merchantEmails.length, 0, "aucun email marchand ne doit partir pour une enseigne geree");

  const status = (await statusRef("prize1").get()).data() || {};
  assert.equal(status.merchant_email_skipped, true);
  assert.equal(status.merchant_email_skip_reason, "managed_by_admin");
});

// --- 12 : managed_by_admin=true => aucun push marchand ---

test("12. managed_by_admin=true : aucun push marchand mis en file", async () => {
  const {prizeRef} = await seedPrize({managedByAdmin: true});
  await invoke(prizeRef);

  const pushDoc = await firestore.collection(kPushNotificationsCollection)
    .doc("prize_prize1_merchant_push").get();
  assert.equal(pushDoc.exists, false, "aucune notification push marchand ne doit etre mise en file");

  const status = (await statusRef("prize1").get()).data() || {};
  assert.equal(status.merchant_push_skipped, true);
  assert.equal(status.merchant_push_skip_reason, "managed_by_admin");
});

// --- 13/14 : notifications joueur inchangees ---

test("13. managed_by_admin=true : l'email joueur part normalement", async () => {
  const {prizeRef} = await seedPrize({managedByAdmin: true});
  await invoke(prizeRef);

  const playerEmails = sentEmails.filter((mail) => mail.to === "alice@example.com");
  assert.equal(playerEmails.length, 1, "l'email joueur doit toujours partir, meme enseigne geree");
});

test("14. managed_by_admin=true : le push joueur est toujours mis en file", async () => {
  const {prizeRef} = await seedPrize({managedByAdmin: true});
  await invoke(prizeRef);

  const pushDoc = await firestore.collection(kPushNotificationsCollection)
    .doc("prize_prize1_player_push").get();
  assert.equal(pushDoc.exists, true, "le push joueur doit toujours etre mis en file");
});

// --- 15 : enseigne normale, comportement marchand actuel conserve ---

test("15. enseigne normale (managed_by_admin absent) : email et push marchand inchanges", async () => {
  const {prizeRef} = await seedPrize({managedByAdmin: false});
  await invoke(prizeRef);

  const merchantEmails = sentEmails.filter((mail) => mail.to === "merchant@example.com");
  assert.equal(merchantEmails.length, 1, "l'email marchand doit partir normalement");

  const pushDoc = await firestore.collection(kPushNotificationsCollection)
    .doc("prize_prize1_merchant_push").get();
  assert.equal(pushDoc.exists, true, "le push marchand doit etre mis en file normalement");

  const status = (await statusRef("prize1").get()).data() || {};
  assert.equal(status.merchant_email_skipped || false, false);
  assert.equal(status.merchant_push_skipped || false, false);
});

// --- 16 : prize / my_lots / claim_code / stats non regresses ---

test("16. la fiche prize (claim_code, claimed, status) et my_lots ne sont jamais modifies par notifyPrizeWon, geree ou non", async () => {
  for (const managedByAdmin of [true, false]) {
    const {prizeRef, prizeData} = await seedPrize({managedByAdmin});
    const myLotRef = firestore.collection("users").doc("winner1")
      .collection("my_lots").doc(prizeRef.id);
    const myLotBefore = (await myLotRef.get()).data();

    await invoke(prizeRef);

    const after = (await prizeRef.get()).data();
    assert.equal(after.claim_code, prizeData.claim_code);
    assert.equal(after.claimed, prizeData.claimed);
    assert.equal(after.name, prizeData.name);
    assert.equal(after.fulfillment_type, prizeData.fulfillment_type);
    assert.deepEqual((await myLotRef.get()).data(), myLotBefore);

    await clearFirestore();
  }
});

// --- 17-19 : transition managed_by_admin (interrupteur reversible) --------
// Le skip est decide une fois pour toutes a la creation du prize (jamais
// re-evalue apres coup) : un skip deja enregistre ne doit jamais etre
// rejoue retroactivement, mais un NOUVEAU prize cree apres un changement
// d'etat doit refleter l'etat courant de l'enseigne.

test("17. transition true -> false : le skip deja enregistre n'est jamais rejoue, meme sur un retry apres desactivation", async () => {
  const {prizeRef} = await seedPrize({managedByAdmin: true});
  await invoke(prizeRef);

  let status = (await statusRef("prize1").get()).data() || {};
  assert.equal(status.merchant_email_skipped, true);
  assert.equal(status.merchant_push_skipped, true);
  assert.equal(sentEmails.filter((m) => m.to === "merchant@example.com").length, 0);

  // L'admin repasse la fiche en mode normal, sans autre intervention.
  await firestore.collection("enseignes").doc("shop1").update({managed_by_admin: false});

  // Cloud Functions v1 ne garantit qu'une livraison "au moins une fois" :
  // un retry du meme evenement onCreate est un scenario reel (meme
  // hypothese que notify_prize_won_idempotence.test.js), pas une
  // hypothese de laboratoire.
  sentEmails = [];
  await invoke(prizeRef);

  assert.equal(
    sentEmails.filter((m) => m.to === "merchant@example.com").length,
    0,
    "un skip managed_by_admin deja enregistre ne doit jamais etre rejoue retroactivement",
  );
  const pushDoc = await firestore.collection(kPushNotificationsCollection)
    .doc("prize_prize1_merchant_push").get();
  assert.equal(pushDoc.exists, false);

  status = (await statusRef("prize1").get()).data() || {};
  assert.equal(status.merchant_email_skipped, true);
  assert.equal(status.merchant_push_skipped, true);
});

test("18. transition true -> false : les FUTURS lots (crees apres la desactivation) notifient de nouveau le marchand normalement", async () => {
  const {prizeRef: firstPrize} = await seedPrize({managedByAdmin: true});
  await invoke(firstPrize);
  assert.equal(sentEmails.filter((m) => m.to === "merchant@example.com").length, 0);

  // Sans creation de compte, sans migration : un seul champ change.
  await firestore.collection("enseignes").doc("shop1").update({managed_by_admin: false});
  sentEmails = [];

  const secondPrizeRef = firestore.collection("prizes").doc("prize2");
  await secondPrizeRef.set({
    winner_id: firestore.collection("users").doc("winner1"),
    owner_id: firestore.collection("users").doc("merchant1"),
    enseigne_id: firestore.collection("enseignes").doc("shop1"),
    game_id: firestore.collection("games").doc("game1"),
    name: "Lot test 2",
    claim_code: "CODE456",
    claimed: false,
    prize_type: "principal",
    fulfillment_type: "merchant",
  });
  await firestore.collection("users").doc("winner1")
    .collection("my_lots").doc(secondPrizeRef.id).set({prize_id: secondPrizeRef});

  await invoke(secondPrizeRef);

  assert.equal(
    sentEmails.filter((m) => m.to === "merchant@example.com").length,
    1,
    "le marchand doit etre notifie normalement pour un lot cree apres le retour a managed_by_admin=false",
  );
  const pushDoc = await firestore.collection(kPushNotificationsCollection)
    .doc("prize_prize2_merchant_push").get();
  assert.equal(pushDoc.exists, true);

  const status = (await statusRef("prize2").get()).data() || {};
  assert.equal(status.merchant_email_skipped || false, false);
  assert.equal(status.merchant_push_skipped || false, false);
});

test("19. transition false -> true : un lot cree apres activation reste bloque, sans effet retroactif sur un lot deja notifie avant", async () => {
  const {prizeRef: firstPrize} = await seedPrize({managedByAdmin: false});
  await invoke(firstPrize);
  assert.equal(sentEmails.filter((m) => m.to === "merchant@example.com").length, 1);

  await firestore.collection("enseignes").doc("shop1").update({managed_by_admin: true});
  sentEmails = [];

  const secondPrizeRef = firestore.collection("prizes").doc("prize2");
  await secondPrizeRef.set({
    winner_id: firestore.collection("users").doc("winner1"),
    owner_id: firestore.collection("users").doc("merchant1"),
    enseigne_id: firestore.collection("enseignes").doc("shop1"),
    game_id: firestore.collection("games").doc("game1"),
    name: "Lot test 2",
    claim_code: "CODE789",
    claimed: false,
    prize_type: "principal",
    fulfillment_type: "merchant",
  });
  await firestore.collection("users").doc("winner1")
    .collection("my_lots").doc(secondPrizeRef.id).set({prize_id: secondPrizeRef});

  await invoke(secondPrizeRef);

  assert.equal(sentEmails.filter((m) => m.to === "merchant@example.com").length, 0);
  const status = (await statusRef("prize2").get()).data() || {};
  assert.equal(status.merchant_email_skipped, true);
  assert.equal(status.merchant_push_skip_reason, "managed_by_admin");

  // Le premier lot (notifie avant l'activation) ne doit pas etre affecte
  // retroactivement par le changement d'etat survenu apres son traitement.
  const firstStatus = (await statusRef("prize1").get()).data() || {};
  assert.equal(firstStatus.merchant_email_skipped || false, false);
});

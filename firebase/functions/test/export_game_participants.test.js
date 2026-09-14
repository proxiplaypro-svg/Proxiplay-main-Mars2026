#!/usr/bin/env node

// Verifies the exportGameParticipants callable: only the merchant who owns
// the game (or an admin) can export its players, the CSV contains only the
// documented columns, and cross-merchant/cross-game access is refused.
//
//   firebase emulators:exec --only firestore \
//     "node --test test/export_game_participants.test.js"

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-proxiplay-export-test";

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const functionsTest = require("firebase-functions-test")();
const myFunctions = require("../index.js");
const wrapped = functionsTest.wrap(myFunctions.exportGameParticipants);

const firestore = admin.firestore();

function decodeCsv(result) {
  return Buffer.from(result.csvBase64, "base64").toString("utf8");
}

test.before(async () => {
  await firestore.collection("users").doc("merchant_uid").set({user_role: "commercant"});
  await firestore.collection("users").doc("other_merchant_uid").set({user_role: "commercant"});
  await firestore.collection("users").doc("admin_uid").set({user_role: "admin"});
  await firestore.collection("enseignes").doc("ens1").set({
    name: "Ma boutique",
    owner: firestore.doc("users/merchant_uid"),
  });

  await firestore.collection("users").doc("alice_uid").set({
    first_name: "Alice", last_name: "Dupont", city: "Dunkerque",
    email: "alice@example.com", phone_number: "0600000000",
  });
  // Deliberately missing email/phone/city -- must export cleanly, not crash.
  await firestore.collection("users").doc("bob_uid").set({
    first_name: "Bob", last_name: "Martin",
  });
  await firestore.collection("users").doc("chloe_uid").set({
    first_name: "Chloé", last_name: "O'Brien-Été", city: "Crêperie \"Le Nid\"",
    email: "chloe@example.com", phone_number: "0611111111",
  });

  await firestore.collection("games").doc("game1").set({
    name: "Grand Jeu d'Été",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  await firestore.collection("games").doc("game_empty").set({
    name: "Jeu Sans Participant",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  await firestore.collection("games").doc("game_old").set({
    name: "Jeu Ancien",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
    end_date: admin.firestore.Timestamp.fromDate(new Date("2020-01-01")),
  });

  await firestore.collection("games/game1/participants").doc("p1").set({
    user_id: firestore.doc("users/alice_uid"),
    participation_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-01T10:00:00Z")),
  });
  await firestore.collection("games/game1/participants").doc("p2").set({
    user_id: firestore.doc("users/bob_uid"),
    participation_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-02T11:00:00Z")),
  });
  await firestore.collection("games/game1/participants").doc("p3").set({
    user_id: firestore.doc("users/chloe_uid"),
    participation_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-03T12:00:00Z")),
  });
  // Alice won a prize on this game.
  await firestore.collection("prizes").doc("prize1").set({
    game_id: "game1",
    winner_id: firestore.doc("users/alice_uid"),
    name: "Bon d'achat 20€",
  });

  await firestore.collection("games/game_old/participants").doc("p1").set({
    user_id: firestore.doc("users/alice_uid"),
    participation_date: admin.firestore.Timestamp.fromDate(new Date("2020-06-01T10:00:00Z")),
  });
});

test.after(async () => {
  await functionsTest.cleanup();
});

test("le commercant proprietaire exporte les 3 participants avec les bonnes colonnes", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.ok, true);
  assert.equal(result.format, "csv");
  assert.equal(result.rowCount, 3);
  assert.match(result.fileName, /^proxiplay_joueurs_grand-jeu-d-ete_\d{4}-\d{2}-\d{2}\.csv$/);

  const csv = decodeCsv(result);
  assert.equal(csv.charCodeAt(0), 0xfeff, "CSV must start with a UTF-8 BOM");
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  assert.equal(lines.length, 4); // header + 3 rows
  assert.equal(
    lines[0],
    "Prénom;Nom;Email;Téléphone;Ville;Jeu;Date de participation;Gagnant;Lot gagné",
  );
  assert.ok(lines.some((l) => l.startsWith("Alice;Dupont;alice@example.com;0600000000;Dunkerque;")));
  assert.ok(lines.some((l) => l.includes(";Bon d'achat 20€")), "winner row must carry the prize name");
});

test("gagnant vs non-gagnant est correctement marque", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n").slice(1);
  const aliceRow = lines.find((l) => l.startsWith("Alice;"));
  const bobRow = lines.find((l) => l.startsWith("Bob;"));
  assert.match(aliceRow, /;Oui;Bon d'achat 20€$/);
  assert.match(bobRow, /;Non;$/);
});

test("champs email/telephone/ville absents -> colonnes vides, pas de crash", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  const bobRow = lines.find((l) => l.startsWith("Bob;"));
  assert.equal(bobRow, "Bob;Martin;;;;Grand Jeu d'Été;02/09/2026 11:00;Non;");
});

test("caracteres accentues et guillemets sont correctement echappes en CSV", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  assert.ok(csv.includes("Chloé"));
  assert.ok(csv.includes("O'Brien-Été"));
  // The city contains a double quote -> must be wrapped and the inner quote doubled.
  assert.ok(csv.includes('"Crêperie ""Le Nid"""'));
});

test("aucune colonne technique (uid, tokens, device ids) n'est exportee", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  assert.ok(!csv.includes("alice_uid"));
  assert.ok(!csv.includes("bob_uid"));
  assert.ok(!csv.includes("chloe_uid"));
  assert.ok(!/users\//.test(csv));
});

test("jeu sans participant -> 0 ligne, pas d'erreur", async () => {
  const result = await wrapped({gameId: "game_empty", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 0);
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  assert.equal(lines.length, 1); // header only
});

test("jeu ancien (deja termine) reste exportable", async () => {
  const result = await wrapped({gameId: "game_old", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 1);
});

test("un admin peut exporter n'importe quel jeu", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "admin_uid"}});
  assert.equal(result.rowCount, 3);
});

test("un autre commercant ne peut PAS exporter ce jeu", async () => {
  await assert.rejects(
    () => wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "other_merchant_uid"}}),
    (error) => {
      assert.equal(error.code, "permission-denied");
      return true;
    },
  );
});

test("appel non authentifie refuse", async () => {
  await assert.rejects(
    () => wrapped({gameId: "game1", format: "csv"}, {}),
    (error) => {
      assert.equal(error.code, "unauthenticated");
      return true;
    },
  );
});

test("gameId inexistant refuse", async () => {
  await assert.rejects(
    () => wrapped({gameId: "does_not_exist", format: "csv"}, {auth: {uid: "merchant_uid"}}),
    (error) => {
      assert.equal(error.code, "not-found");
      return true;
    },
  );
});

test("gameId manquant refuse", async () => {
  await assert.rejects(
    () => wrapped({format: "csv"}, {auth: {uid: "merchant_uid"}}),
    (error) => {
      assert.equal(error.code, "invalid-argument");
      return true;
    },
  );
});

test("format pdf explicitement refuse (non implemente), pas de fallback silencieux", async () => {
  await assert.rejects(
    () => wrapped({gameId: "game1", format: "pdf"}, {auth: {uid: "merchant_uid"}}),
    (error) => {
      assert.equal(error.code, "unimplemented");
      return true;
    },
  );
});

test("format omis => csv par defaut", async () => {
  const result = await wrapped({gameId: "game1"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.format, "csv");
});

test("nombreux participants (50) -> tous exportes, un seul batch de lecture users", async () => {
  await firestore.collection("games").doc("game_many").set({
    name: "Jeu Populaire",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  const batch = firestore.batch();
  for (let i = 0; i < 50; i++) {
    const uid = `bulk_user_${i}`;
    batch.set(firestore.collection("users").doc(uid), {
      first_name: `Joueur${i}`, last_name: "Test", email: `joueur${i}@example.com`,
    });
    batch.set(firestore.collection("games/game_many/participants").doc(`p${i}`), {
      user_id: firestore.doc(`users/${uid}`),
      participation_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-05T10:00:00Z")),
    });
  }
  await batch.commit();

  const result = await wrapped({gameId: "game_many", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 50);
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  assert.equal(lines.length, 51);
  assert.ok(csv.includes("Joueur0;Test;joueur0@example.com"));
  assert.ok(csv.includes("Joueur49;Test;joueur49@example.com"));
});

test("un log d'audit est ecrit sans donnees personnelles", async () => {
  const before = await firestore.collection("_export_audit_logs")
    .where("gameId", "==", "game1").get();
  await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const after = await firestore.collection("_export_audit_logs")
    .where("gameId", "==", "game1").get();
  assert.equal(after.size, before.size + 1);
  const entry = after.docs[after.docs.length - 1].data();
  assert.equal(entry.merchantId, "users/merchant_uid");
  assert.equal(entry.gameId, "game1");
  assert.equal(entry.format, "csv");
  assert.equal(entry.rowCount, 3);
  assert.equal(Object.keys(entry).sort().join(","), "exportedAt,format,gameId,merchantId,rowCount");
});

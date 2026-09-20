#!/usr/bin/env node

// Verifies the exportGameParticipants callable: exports WINNERS only (one
// row per prize actually awarded on the game, sourced from "prizes" -- the
// same canonical source getMerchantPrizes/merchant_prizes.js already uses,
// see report point 9), never a losing participation. Only the merchant who
// owns the game (or an admin) can export it, and cross-merchant/cross-game
// access is refused.
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
  // Deliberately missing email/phone/city/claim_code/win_date on her prize --
  // must export cleanly, not crash.
  await firestore.collection("users").doc("bob_uid").set({
    first_name: "Bob", last_name: "Martin",
  });
  await firestore.collection("users").doc("chloe_uid").set({
    first_name: "Chloé", last_name: "O'Brien-Été", city: "Crêperie \"Le Nid\"",
    email: "chloe@example.com", phone_number: "0611111111",
  });

  // game_id on prizes is ALWAYS a DocumentReference in production (every
  // prize-awarding engine writes db.collection('games').doc(id) -- see
  // report point 1/2) -- these fixtures use firestore.doc(...), matching
  // reality, not a bare string.
  const game1Ref = firestore.collection("games").doc("game1");
  await game1Ref.set({
    name: "Grand Jeu d'Été",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  const gameNoWinnerRef = firestore.collection("games").doc("game_no_winner");
  await gameNoWinnerRef.set({
    name: "Jeu Sans Gagnant",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  const gameOldRef = firestore.collection("games").doc("game_old");
  await gameOldRef.set({
    name: "Jeu Ancien",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
    end_date: admin.firestore.Timestamp.fromDate(new Date("2020-01-01")),
  });
  const gameHiddenRef = firestore.collection("games").doc("game_hidden");
  await gameHiddenRef.set({
    name: "Jeu Retiré",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
    hidden_from_merchant_stats: true,
  });
  // Ancien format : pas d'owner_id explicite sur le jeu, resolu via
  // l'enseigne (shopOwnerRef), comme le fait deja getMerchantPrizes.
  const gameLegacyRef = firestore.collection("games").doc("game_legacy");
  await gameLegacyRef.set({
    name: "Jeu Historique",
    enseigne_id: firestore.doc("enseignes/ens1"),
  });

  // game1 : un lot secondaire (Alice) et un lot principal (Bob) attribues ;
  // un prize sans winner_id (pas encore attribue) -- ne doit PAS apparaitre.
  await firestore.collection("prizes").doc("prize_secondaire").set({
    game_id: game1Ref,
    winner_id: firestore.doc("users/alice_uid"),
    name: "Bon d'achat 20€",
    prize_type: "secondaire",
    claim_code: "ABC123",
    claimed: false,
    win_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-01T10:00:00Z")),
  });
  await firestore.collection("prizes").doc("prize_principal").set({
    game_id: game1Ref,
    winner_id: firestore.doc("users/bob_uid"),
    name: "Weekend au spa",
    prize_type: "principal",
    claimed: true,
    // claim_code / win_date volontairement absents.
  });
  await firestore.collection("prizes").doc("prize_unassigned").set({
    game_id: game1Ref,
    name: "Lot pas encore gagne",
    // Pas de winner_id : ce lot ne doit generer aucune ligne.
  });
  // Chloé a gagne deux lots sur ce meme jeu -- deux lignes distinctes, pas
  // fusionnees.
  await firestore.collection("prizes").doc("prize_chloe_1").set({
    game_id: game1Ref,
    winner_id: firestore.doc("users/chloe_uid"),
    name: "Crêpe offerte",
    claim_code: "CREPE1",
    win_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-02T09:00:00Z")),
  });
  await firestore.collection("prizes").doc("prize_chloe_2").set({
    game_id: game1Ref,
    winner_id: firestore.doc("users/chloe_uid"),
    name: "Café offert",
    claim_code: "CAFE1",
    win_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-03T09:00:00Z")),
  });

  await firestore.collection("prizes").doc("prize_old").set({
    game_id: gameOldRef,
    winner_id: firestore.doc("users/alice_uid"),
    name: "Lot ancien jeu",
    claim_code: "OLD1",
  });

  await firestore.collection("prizes").doc("prize_hidden_game").set({
    game_id: gameHiddenRef,
    winner_id: firestore.doc("users/alice_uid"),
    name: "Lot du jeu retire",
    claim_code: "HID1",
  });

  await firestore.collection("prizes").doc("prize_legacy_game").set({
    game_id: gameLegacyRef,
    winner_id: firestore.doc("users/alice_uid"),
    name: "Lot jeu historique",
    claim_code: "LEG1",
  });

  // Un prize d'un AUTRE jeu, meme proprietaire : ne doit jamais fuiter dans
  // l'export de game1.
  const otherGameRef = firestore.collection("games").doc("game_other");
  await otherGameRef.set({
    name: "Autre jeu",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  await firestore.collection("prizes").doc("prize_other_game").set({
    game_id: otherGameRef,
    winner_id: firestore.doc("users/alice_uid"),
    name: "Lot d'un autre jeu",
    claim_code: "OTHER1",
  });
});

test.after(async () => {
  await functionsTest.cleanup();
});

test("le commercant proprietaire exporte les gagnants avec les bonnes colonnes", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.ok, true);
  assert.equal(result.format, "csv");
  assert.equal(result.rowCount, 4); // Alice, Bob, Chloé x2 -- prize_unassigned exclu
  assert.match(result.fileName, /^proxiplay_gagnants_grand-jeu-d-ete_\d{4}-\d{2}-\d{2}\.csv$/);

  const csv = decodeCsv(result);
  assert.equal(csv.charCodeAt(0), 0xfeff, "CSV must start with a UTF-8 BOM");
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  assert.equal(lines.length, 5); // header + 4 rows
  assert.equal(
    lines[0],
    "Prénom;Nom;Email;Téléphone;Ville;Date du gain;Lot gagné;Code gagnant;Statut",
  );
});

test("lot secondaire gagne apparait avec son code et le statut 'A retirer'", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  const aliceRow = lines.find((l) => l.startsWith("Alice;"));
  assert.equal(
    aliceRow,
    "Alice;Dupont;alice@example.com;0600000000;Dunkerque;01/09/2026 10:00;Bon d'achat 20€;ABC123;À retirer",
  );
});

test("lot principal gagne et deja retire (claimed) apparait avec le bon statut", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  const bobRow = lines.find((l) => l.startsWith("Bob;"));
  // email/telephone/ville/date_du_gain/code_gagnant absents -> colonnes vides.
  assert.equal(bobRow, "Bob;Martin;;;;;Weekend au spa;;Retiré");
});

test("gain non retire dont l'echeance est depassee apparait avec le statut 'Expiré'", async () => {
  const gameExpiredRef = firestore.collection("games").doc("game_expired_prize");
  await gameExpiredRef.set({
    name: "Jeu Echeance Depassee",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  await firestore.collection("prizes").doc("prize_expired").set({
    game_id: gameExpiredRef,
    winner_id: firestore.doc("users/alice_uid"),
    name: "Lot expire",
    claim_code: "EXP1",
    claimed: false,
    usage_deadline: admin.firestore.Timestamp.fromDate(new Date("2020-01-01")),
  });

  const result = await wrapped({gameId: "game_expired_prize", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 1);
  const csv = decodeCsv(result);
  assert.ok(csv.includes("Lot expire;EXP1;Expiré"));
});

test("plusieurs gains du meme joueur -> une ligne par lot, jamais fusionnees", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  const chloeRows = lines.filter((l) => l.startsWith("Chloé;") || l.startsWith('"Chloé";'));
  assert.equal(chloeRows.length, 2);
  assert.ok(csv.includes("Crêpe offerte;CREPE1"));
  assert.ok(csv.includes("Café offert;CAFE1"));
});

test("un lot pas encore attribue (sans winner_id) ne genere aucune ligne", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  assert.ok(!csv.includes("Lot pas encore gagne"));
});

test("Lot gagne n'est jamais vide meme sur un ancien prize sans name ni description", async () => {
  const gameLabelRef = firestore.collection("games").doc("game_label_fallback");
  await gameLabelRef.set({
    name: "Jeu Fallback",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });
  await firestore.collection("prizes").doc("prize_no_name_principal").set({
    game_id: gameLabelRef,
    winner_id: firestore.doc("users/alice_uid"),
    prize_type: "principal",
    // Ni name, ni description : document historique minimal.
  });
  await firestore.collection("prizes").doc("prize_no_name_secondaire").set({
    game_id: gameLabelRef,
    winner_id: firestore.doc("users/bob_uid"),
    prize_type: "secondaire",
  });
  await firestore.collection("prizes").doc("prize_no_name_no_type").set({
    game_id: gameLabelRef,
    winner_id: firestore.doc("users/chloe_uid"),
    // Ni name, ni description, ni prize_type : le pire cas possible.
  });

  const result = await wrapped({gameId: "game_label_fallback", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 3);
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n").slice(1);
  // Colonnes : prenom(0),nom(1),email(2),telephone(3),ville(4),date_du_gain(5),lot_gagne(6),...
  for (const line of lines) {
    const cell = line.split(";")[6];
    assert.ok(cell && cell.trim().length > 0, `Lot gagné ne doit jamais etre vide (ligne: ${line})`);
  }
  assert.ok(csv.includes("Lot principal"));
  assert.ok(csv.includes("Lot secondaire"));
  assert.ok(csv.includes("Lot gagné")); // dernier repli, prize sans aucune info
});

// Scenario obligatoire : 10 participants, dont seulement 2 ont reellement
// gagne un lot -- les 8 autres (perdants) ne doivent apparaitre NULLE PART
// dans le CSV, puisque participants n'est plus consulte du tout pour
// construire les lignes (seul prizes l'est).
test("10 participants / 2 gagnants / 8 perdants -> CSV = exactement 2 lignes, aucun perdant", async () => {
  const gameRegressionRef = firestore.collection("games").doc("game_10p_2w");
  await gameRegressionRef.set({
    name: "Jeu Regression 10 participants",
    owner_id: firestore.doc("users/merchant_uid"),
    enseigne_id: firestore.doc("enseignes/ens1"),
  });

  const batch = firestore.batch();
  const loserNames = [];
  for (let i = 0; i < 10; i++) {
    const uid = `regression_player_${i}`;
    const firstName = `Joueur${i}`;
    batch.set(firestore.collection("users").doc(uid), {
      first_name: firstName, last_name: "Regression",
      email: `${uid}@example.com`,
    });
    // Les 10 joueurs participent (meme si "participants" n'est plus lu par
    // l'export, on le seede quand meme pour prouver qu'il est bien ignore).
    batch.set(gameRegressionRef.collection("participants").doc(`p${i}`), {
      user_id: firestore.doc(`users/${uid}`),
      participation_date: admin.firestore.Timestamp.fromDate(new Date("2026-09-10T10:00:00Z")),
    });
    if (i >= 2) loserNames.push(firstName); // seuls i=0 et i=1 gagnent
  }
  await batch.commit();

  // Seuls 2 des 10 participants ont reellement gagne un lot.
  await firestore.collection("prizes").doc("prize_regression_winner_0").set({
    game_id: gameRegressionRef,
    winner_id: firestore.doc("users/regression_player_0"),
    name: "Lot gagnant 0",
    claim_code: "REG0",
  });
  await firestore.collection("prizes").doc("prize_regression_winner_1").set({
    game_id: gameRegressionRef,
    winner_id: firestore.doc("users/regression_player_1"),
    name: "Lot gagnant 1",
    claim_code: "REG1",
  });

  const result = await wrapped({gameId: "game_10p_2w", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 2, "seuls les 2 gagnants doivent produire une ligne");

  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  assert.equal(lines.length, 3, "header + exactement 2 lignes de donnees");
  assert.equal(
    lines[0],
    "Prénom;Nom;Email;Téléphone;Ville;Date du gain;Lot gagné;Code gagnant;Statut",
  );

  // Aucun des 8 perdants n'apparait, sous aucune forme.
  for (const loserName of loserNames) {
    assert.ok(!csv.includes(loserName), `${loserName} (perdant) ne doit apparaitre nulle part`);
  }

  // Lot gagné n'est vide sur aucune des 2 lignes de donnees.
  for (const line of lines.slice(1)) {
    const cells = line.split(";");
    const lotGagne = cells[6]; // prenom,nom,email,telephone,ville,date_du_gain,lot_gagne
    assert.ok(lotGagne && lotGagne.trim().length > 0, `Lot gagné vide sur: ${line}`);
  }
  assert.ok(csv.includes("Joueur0;Regression"));
  assert.ok(csv.includes("Joueur1;Regression"));
  assert.ok(csv.includes("Lot gagnant 0;REG0"));
  assert.ok(csv.includes("Lot gagnant 1;REG1"));
});

test("les gagnants d'un AUTRE jeu ne fuitent pas dans cet export", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  assert.ok(!csv.includes("Lot d'un autre jeu"));
  assert.equal(result.rowCount, 4);
});

test("caracteres accentues et guillemets sont correctement echappes en CSV", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "merchant_uid"}});
  const csv = decodeCsv(result);
  assert.ok(csv.includes("Chloé"));
  assert.ok(csv.includes("O'Brien-Été") || csv.includes('"O\'Brien-Été"'));
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

test("jeu sans gagnant -> 0 ligne, pas une erreur technique", async () => {
  const result = await wrapped({gameId: "game_no_winner", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.ok, true);
  assert.equal(result.rowCount, 0);
  const csv = decodeCsv(result);
  const lines = csv.replace(/^﻿/, "").trim().split("\r\n");
  assert.equal(lines.length, 1); // header only
});

test("jeu ancien (deja termine) reste exportable", async () => {
  const result = await wrapped({gameId: "game_old", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 1);
  const csv = decodeCsv(result);
  assert.ok(csv.includes("Lot ancien jeu;OLD1"));
});

test("jeu retire (hidden_from_merchant_stats) mais statistiques conservees -> export toujours disponible", async () => {
  const result = await wrapped({gameId: "game_hidden", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 1);
  const csv = decodeCsv(result);
  assert.ok(csv.includes("Lot du jeu retire;HID1"));
});

test("jeu historique sans owner_id explicite -> propriete resolue via l'enseigne", async () => {
  const result = await wrapped({gameId: "game_legacy", format: "csv"}, {auth: {uid: "merchant_uid"}});
  assert.equal(result.rowCount, 1);
  const csv = decodeCsv(result);
  assert.ok(csv.includes("Lot jeu historique;LEG1"));
});

test("un admin peut exporter n'importe quel jeu", async () => {
  const result = await wrapped({gameId: "game1", format: "csv"}, {auth: {uid: "admin_uid"}});
  assert.equal(result.rowCount, 4);
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

test("gameId inexistant -> vraie erreur 'Jeu introuvable' (not-found)", async () => {
  await assert.rejects(
    () => wrapped({gameId: "does_not_exist", format: "csv"}, {auth: {uid: "merchant_uid"}}),
    (error) => {
      assert.equal(error.code, "not-found");
      return true;
    },
  );
});

// Reproduit le bug rapporte : la fiche jeu affichee connait forcement le
// jeu (elle l'affiche) ; son gameId canonique, transmis tel quel a l'export,
// doit retrouver EXACTEMENT ce jeu -- jamais "Jeu introuvable" pour un jeu
// qui existe reellement et dont l'ID est passe sans modification.
test("fiche jeu valide -> gameId canonique transmis -> le backend retrouve exactement ce jeu", async () => {
  const gameRef = firestore.collection("games").doc("game1");
  const gameSnap = await gameRef.get();
  assert.ok(gameSnap.exists, "fixture sanity check");
  const canonicalGameId = gameRef.id; // ce que Flutter envoie : game.reference.id

  const result = await wrapped(
    {gameId: canonicalGameId, format: "csv"},
    {auth: {uid: "merchant_uid"}},
  );
  assert.equal(result.ok, true, "le jeu existant doit etre trouve, jamais not-found");
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

test("nombreux gagnants (50) -> tous exportes, un seul batch de lecture users", async () => {
  const gameManyRef = firestore.collection("games").doc("game_many");
  await gameManyRef.set({
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
    batch.set(firestore.collection("prizes").doc(`bulk_prize_${i}`), {
      game_id: gameManyRef,
      winner_id: firestore.doc(`users/${uid}`),
      name: `Lot ${i}`,
      claim_code: `CODE${i}`,
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
  assert.equal(entry.rowCount, 4);
  assert.equal(Object.keys(entry).sort().join(","), "exportedAt,format,gameId,merchantId,rowCount");
});

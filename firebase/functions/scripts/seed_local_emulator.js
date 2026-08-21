#!/usr/bin/env node
"use strict";

if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8080") {
  throw new Error("Refusing to seed: FIRESTORE_EMULATOR_HOST must be 127.0.0.1:8080.");
}
if (process.env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:9099") {
  throw new Error("Refusing to seed: FIREBASE_AUTH_EMULATOR_HOST must be 127.0.0.1:9099.");
}
if (!process.argv.includes("--confirm")) {
  throw new Error("Refusing to seed without --confirm.");
}

const admin = require("firebase-admin");
const projectId = "proxi-play-odzp2e";
admin.initializeApp({projectId});

const db = admin.firestore();
const auth = admin.auth();
const playerUid = "local-player";
const merchantUid = "local-merchant";
const storeId = "local-enseigne";
const gameId = "local-active-game";

async function ensureUser(uid, email, password) {
  try {
    await auth.updateUser(uid, {email, password, displayName: email.split("@")[0]});
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    await auth.createUser({uid, email, password, displayName: email.split("@")[0]});
  }
}

async function main() {
  await ensureUser(playerUid, "player@proxiplay.local", "LocalPass123!");
  await ensureUser(merchantUid, "merchant@proxiplay.local", "LocalPass123!");

  const now = Date.now();
  const playerRef = db.collection("users").doc(playerUid);
  const merchantRef = db.collection("users").doc(merchantUid);
  const storeRef = db.collection("enseignes").doc(storeId);

  await merchantRef.set({
    email: "merchant@proxiplay.local",
    first_name: "Marchand",
    user_role: "commercant",
  }, {merge: true});
  await playerRef.set({
    email: "player@proxiplay.local",
    first_name: "Joueur local",
    user_role: "joueur",
    remaining_part: 5,
  }, {merge: true});
  await storeRef.set({name: "Commerce local", owner: merchantRef}, {merge: true});
  await db.collection("games").doc(gameId).set({
    name: "Jeu local actif",
    create_by: merchantRef,
    enseigne_id: storeRef,
    enseigne_name: "Commerce local",
    start_date: admin.firestore.Timestamp.fromMillis(now - 60 * 60 * 1000),
    end_date: admin.firestore.Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
    access_mode: "public",
    prohibited_for_minors: false,
    hasMainPrize: false,
    hasWinner: false,
    participations: 10,
  }, {merge: true});

  console.log("Local emulator seed complete.");
  console.log("Player: player@proxiplay.local / LocalPass123!");
  console.log(`Game: games/${gameId}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

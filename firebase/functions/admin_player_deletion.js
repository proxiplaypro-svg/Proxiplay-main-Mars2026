"use strict";

// Suppression d'un compte joueur par l'Admin (1.1.4).
//
// Avant : le bouton « Supprimer ce joueur » de la console effacait
// seulement users/{uid} depuis le navigateur ; le compte Firebase Auth
// restait actif et l'app recreait la fiche a la connexion suivante (avec une
// nouvelle date de naissance), sans aucune trace de l'action.
//
// Ici : confirmation explicite, motif obligatoire, compte Auth supprime en
// premier (plus aucune reconnexion possible), puis effacement des donnees
// par cleanupDeletedUserData, le meme que pour une suppression par le joueur
// (onUserDeleted s'execute aussi ; les deux sont idempotents). Chaque demande
// est journalisee dans admin_account_deletions (identifiant technique du
// compte, administrateur, motif, resultat ; aucune donnee de profil).
//
// Les commercants ont leur propre suppression (deleteCommercantAccount) ;
// un compte administrateur n'est jamais supprime ici.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {isTrustedAdmin} = require("./admin_identity");
const {cleanupDeletedUserData} = require("./deleted_user_cleanup");

const kConfirmationWord = "SUPPRIMER";
const kReasonMinLength = 5;
const kReasonMaxLength = 200;

function roleOf(userData) {
  return userData?.user_role || userData?.userRole || "";
}

async function getAuthUserOrNull(uid) {
  try {
    return await admin.auth().getUser(uid);
  } catch (error) {
    if (error?.code === "auth/user-not-found") return null;
    throw error;
  }
}

async function adminDeletePlayerAccountHandler(data, context = {}) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const db = admin.firestore();
  const callerSnap = await db.collection("users").doc(context.auth.uid).get();
  if (!isTrustedAdmin(context.auth, callerSnap.data() || {})) {
    throw new functions.https.HttpsError("permission-denied", "Reserve a l'administration.");
  }

  const userId = typeof data?.userId === "string" ? data.userId.trim() : "";
  const reason = typeof data?.reason === "string" ? data.reason.trim().replace(/\s+/g, " ") : "";
  if (!userId || userId.includes("/") || userId.length > 128) {
    throw new functions.https.HttpsError("invalid-argument", "Joueur invalide.");
  }
  if (data?.confirmation !== kConfirmationWord) {
    throw new functions.https.HttpsError("invalid-argument",
      `Confirmation explicite requise (saisir ${kConfirmationWord}).`);
  }
  if (reason.length < kReasonMinLength || reason.length > kReasonMaxLength) {
    throw new functions.https.HttpsError("invalid-argument",
      `Le motif est obligatoire (${kReasonMinLength} a ${kReasonMaxLength} caracteres).`);
  }
  if (userId === context.auth.uid) {
    throw new functions.https.HttpsError("failed-precondition",
      "Un administrateur ne supprime pas son propre compte ici.");
  }

  const [profileSnap, authUser] = await Promise.all([
    db.collection("users").doc(userId).get(),
    getAuthUserOrNull(userId),
  ]);
  if (!profileSnap.exists && !authUser) {
    throw new functions.https.HttpsError("not-found", "Compte introuvable.");
  }
  const role = roleOf(profileSnap.data());
  if (role === "admin" || authUser?.customClaims?.admin === true ||
      isTrustedAdmin({token: {email: authUser?.email}}, {})) {
    throw new functions.https.HttpsError("failed-precondition",
      "Un compte administrateur ne peut pas etre supprime ici.");
  }
  if (role === "commercant") {
    throw new functions.https.HttpsError("failed-precondition",
      "Compte commercant : utiliser la suppression dediee aux commercants.");
  }

  const logRef = db.collection("admin_account_deletions").doc();
  await logRef.create({
    deleted_uid: userId,
    deleted_by: context.auth.uid,
    reason,
    requested_at: admin.firestore.FieldValue.serverTimestamp(),
    auth_account_found: !!authUser,
    profile_found: profileSnap.exists,
    status: "pending",
  });

  try {
    if (authUser) await admin.auth().deleteUser(userId);
  } catch (error) {
    await logRef.update({status: "failed", failed_step: "auth"});
    console.error("[adminDeletePlayerAccount] auth deletion failed", error);
    throw new functions.https.HttpsError("internal", "La suppression du compte a echoue.");
  }

  let cleanup;
  try {
    cleanup = await cleanupDeletedUserData(db, userId);
  } catch (error) {
    // Le compte Auth est supprime : onUserDeleted refera l'effacement.
    await logRef.update({status: "auth_deleted_cleanup_pending", failed_step: "cleanup"});
    console.error("[adminDeletePlayerAccount] cleanup failed", error);
    throw new functions.https.HttpsError("internal",
      "Compte supprime ; l'effacement des donnees sera termine automatiquement.");
  }

  await logRef.update({
    status: "completed",
    completed_at: admin.firestore.FieldValue.serverTimestamp(),
    consent_events_retained: cleanup.consentEventsRetained,
  });
  return {
    deletionId: logRef.id,
    authDeleted: !!authUser,
    profileDeleted: profileSnap.exists,
    consentEventsRetained: cleanup.consentEventsRetained,
  };
}

exports.adminDeletePlayerAccount = functions
  .region("us-central1")
  .https.onCall(adminDeletePlayerAccountHandler);

exports._test = {adminDeletePlayerAccountHandler, kConfirmationWord};

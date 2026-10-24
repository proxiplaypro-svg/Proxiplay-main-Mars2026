// Profil users/{uid} d'un compte cree par le serveur lors d'une inscription
// avec code (parrainage joueur : createReferralEmailAccount, role "joueur" ;
// parrainage commercant : createMerchantAccountWithReferral, role
// "commercant"). Le serveur est la source de verite : le profil existe avec
// son role des la creation du compte, quoi que fasse l'app ensuite. Les
// declencheurs existants posent alors les 3 parties d'un joueur
// (initializeNewPlayerRemainingParts / ...OnRoleAssignment) ou le statut d'un
// commercant (initializeNewMerchantAccountStatus / ...OnRoleAssignment).
//
// Securite : a n'appeler que pour le compte de l'operation d'inscription (uid
// derive de l'operation par le serveur, adresse du compte Auth verifiee par
// l'appelant). Un profil existant ne recoit qu'un role ABSENT ; un role
// present et different n'est jamais modifie (refus "profile_conflict"), donc
// aucune elevation ni changement de role.
const functions = require("firebase-functions");
const admin = require("firebase-admin");

const kServerProfileRoles = ["joueur", "commercant"];

const roleOf = (data) => {
  for (const key of ["user_role", "userRole"]) {
    const value = typeof data?.[key] === "string" ? data[key].trim() : "";
    if (value) return value;
  }
  return "";
};

async function ensureServerCreatedProfile(db, {uid, email, role}) {
  if (!kServerProfileRoles.includes(role) || typeof uid !== "string" || !uid) {
    throw new Error("invalid server profile request");
  }
  const ref = db.doc(`users/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.create(ref, {uid, email, user_role: role, created_time: admin.firestore.FieldValue.serverTimestamp()});
      return "created";
    }
    const data = snap.data() || {};
    const existing = roleOf(data);
    if (existing === role) return "unchanged";
    if (existing) {
      throw new functions.https.HttpsError("failed-precondition", "Account profile conflict.",
        {reason: "profile_conflict", accountCreated: true});
    }
    // Document cree par l'app sans role (connexion avant le serveur) : seul
    // le role manquant est ajoute, et les identifiants s'ils manquent.
    const patch = {user_role: role};
    if (typeof data.uid !== "string" || !data.uid.trim()) patch.uid = uid;
    if ((typeof data.email !== "string" || !data.email.trim()) && email) patch.email = email;
    tx.update(ref, patch);
    return "role_added";
  });
}

module.exports = {ensureServerCreatedProfile};

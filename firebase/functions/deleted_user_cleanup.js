"use strict";

// Effacement des donnees Firestore d'un compte supprime (1.1.4).
//
// Appele par onUserDeleted (suppression Firebase Auth : par le joueur, ou
// par l'Admin via adminDeletePlayerAccount) et directement par
// adminDeletePlayerAccount quand le compte Auth n'existe deja plus.
//
// Inventaire et justification : docs/account-deletion-data-1.1.4.md.
//  - Supprime : document users/{uid} et sous-collections sans valeur de
//    preuve (preferences, jetons d'appareil, notifications, etat de
//    partage, journal des corrections de date de naissance).
//  - Conserve, en attente de decision : my_lots (miroir des lots, relu par
//    les controles d'integrite des lots), monthly_challenges (participation
//    au defi du mois en cours).
//  - Conserve comme preuve : marketing_consent_events, horodates
//    account_deleted_at pour une purge future comptee a partir de la fin de
//    la relation (duree a valider juridiquement, aucune purge ici).
//  - Comportement historique inchange pour les enseignes et jeux possedes.

const admin = require("firebase-admin");

const kPurgedUserSubcollections = Object.freeze([
  "birthday_corrections",
  "fcm_tokens",
  "notifications",
  "favorite_games",
  "favorite_enseignes",
  "my_enseignes",
  "private",
]);

const kRetainedUserSubcollections = Object.freeze([
  "marketing_consent_events",
  "my_lots",
  "monthly_challenges",
]);

const kBatchSize = 400;

async function deleteCollectionDocs(collectionRef) {
  let deleted = 0;
  for (;;) {
    const snapshot = await collectionRef.limit(kBatchSize).get();
    if (snapshot.empty) return deleted;
    const batch = collectionRef.firestore.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += snapshot.size;
    if (snapshot.size < kBatchSize) return deleted;
  }
}

async function markConsentEventsForRetention(userRef) {
  const events = await userRef.collection("marketing_consent_events").get();
  if (events.empty) return 0;
  const deletedAt = admin.firestore.FieldValue.serverTimestamp();
  for (let index = 0; index < events.docs.length; index += kBatchSize) {
    const batch = userRef.firestore.batch();
    events.docs.slice(index, index + kBatchSize).forEach((doc) => {
      batch.update(doc.ref, {account_deleted_at: deletedAt});
    });
    await batch.commit();
  }
  return events.size;
}

async function cleanupDeletedUserData(firestore, uid) {
  const userRef = firestore.doc("users/" + uid);
  // Both fields and all legacy encodings are supported. Filter with the
  // canonical normalizer so a contradictory shop is never deleted as owned.
  const ownerValues = [userRef, userRef.path, `/${userRef.path}`, uid];
  const snapshots = await Promise.all(["owner", "owner_id"].flatMap((field) =>
    ownerValues.map((value) => firestore.collection("enseignes").where(field, "==", value).get())));
  const {shopOwnerPath, userPath} = require("./merchant_ownership");
  const ownedShops = [...new Map(snapshots.flatMap((s) => s.docs).map((d) => [d.id, d])).values()]
    .filter((doc) => shopOwnerPath(doc.data()) === userRef.path && doc.data().managed_by_admin !== true);
  await require("./deleted_shop_games_cleanup").deleteGamesForDeletedShops(
    firestore, ownedShops.map((doc) => doc.ref));
  for (const doc of ownedShops) {
    for (const collection of ["enseigne_game", "horaires", "images"]) {
      const children = await doc.ref.collection(collection).get();
      for (const child of children.docs) await child.ref.delete();
    }
  }

  const purged = {};
  for (const name of kPurgedUserSubcollections) {
    purged[name] = await deleteCollectionDocs(userRef.collection(name));
  }
  const consentEventsRetained = await markConsentEventsForRetention(userRef);
  await userRef.delete();

  for (const doc of ownedShops) {
    console.log(`Deleting document ${doc.id} from collection enseignes`);
    await doc.ref.delete();
  }
  const games = await firestore.collection("games").where("create_by", "==", userRef).get();
  for (const doc of games.docs) {
    // create_by is provenance, never ownership. Preserve all games attached
    // to an enseigne, including those created on behalf of it by an admin.
    if (!doc.data().enseigne_id && !doc.data().enseigne_ref &&
        userPath(doc.data().owner_id) === userRef.path) {
      await doc.ref.delete();
    }
  }
  return {purged, consentEventsRetained, ownedShopsDeleted: ownedShops.length};
}

module.exports = {
  cleanupDeletedUserData,
  kPurgedUserSubcollections,
  kRetainedUserSubcollections,
};

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Cette fonction auxiliaire permet de supprimer un lot de documents d'une collection
async function deleteCollection(collectionRef) {
  const batch = admin.firestore().batch();
  const query = collectionRef.limit(500);
  const snapshot = await query.get();

  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });

  await batch.commit();

  if (snapshot.size === 500) {
    await deleteCollection(collectionRef);
  }
}

// Fonction auxiliaire pour supprimer un fichier de Firebase Storage
async function deleteFileFromStorage(filePath) {
  if (!filePath || filePath.length === 0) {
    return;
  }
  const bucket = admin.storage().bucket();
  try {
    await bucket.file(filePath).delete();
    console.log(`Fichier ${filePath} supprimé du stockage.`);
  } catch (error) {
    console.warn(
      `Impossible de supprimer le fichier ${filePath}: ${error.message}`,
    );
  }
}

exports.deleteCommercantAccount = functions.https.onCall(
  async (data, context) => {
    // 1. Vérification de l'authentification et du rôle d'administrateur
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "La fonction doit être appelée avec une authentification.",
      );
    }

    const callingUserUid = context.auth.uid;
    const callingUserDoc = await admin
      .firestore()
      .collection("users")
      .doc(callingUserUid)
      .get();

    if (!callingUserDoc.exists || callingUserDoc.data().user_role !== "admin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Seuls les utilisateurs administrateurs peuvent supprimer des comptes.",
      );
    }

    // 2. Obtenir l'UID du commerçant à supprimer
    const commercantUid = data.commercantUid;
    if (!commercantUid) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        'Le paramètre "commercantUid" est requis.',
      );
    }

    try {
      // --- Étape 3 : Suppression en cascade de toutes les données ---

      // 3.1. Suppression des sous-collections de l'utilisateur et de leurs images
      const userDocRef = admin
        .firestore()
        .collection("users")
        .doc(commercantUid);
      const userDocPath = userDocRef.path;

      // Sous-collection 'identity_documents' et ses images
      const identityDocsSnapshot = await userDocRef
        .collection("identity_documents")
        .get();
      for (const doc of identityDocsSnapshot.docs) {
        const data = doc.data();
        await deleteFileFromStorage(data.id_photo_commercant_url);
        await deleteFileFromStorage(data.id_front_card_url);
        await deleteFileFromStorage(data.id_back_card_url);
        await doc.ref.delete();
      }

      // Autres sous-collections
      await deleteCollection(userDocRef.collection("fcm_tokens"));
      await deleteCollection(userDocRef.collection("notifications"));
      await deleteCollection(userDocRef.collection("my_lots"));

      // 3.2. Suppression du document 'users' principal
      await userDocRef.delete();

      // 3.3. Suppression des enseignes de la collection de niveau supérieur et de leurs sous-collections
      const enseignesRef = admin.firestore().collection("enseignes");
      const [enseignesByRefSnapshot, enseignesByStringSnapshot] =
        await Promise.all([
          enseignesRef.where("owner", "==", userDocRef).get(),
          // Backward compatibility: certains anciens documents peuvent stocker un string.
          enseignesRef.where("owner", "==", userDocPath).get(),
        ]);
      const enseignesMap = new Map();
      enseignesByRefSnapshot.docs.forEach((doc) => enseignesMap.set(doc.id, doc));
      enseignesByStringSnapshot.docs.forEach((doc) =>
        enseignesMap.set(doc.id, doc),
      );
      const enseignesDocs = [...enseignesMap.values()];

      for (const doc of enseignesDocs) {
        const enseigneDocRef = doc.ref;

        // Suppression de la sous-collection 'images' et des fichiers
        const imagesSnapshot = await enseigneDocRef.collection("images").get();
        for (const imageDoc of imagesSnapshot.docs) {
          const imageData = imageDoc.data();
          await deleteFileFromStorage(imageData.url);
          await imageDoc.ref.delete();
        }

        // Suppression des autres sous-collections de l'enseigne
        await deleteCollection(enseigneDocRef.collection("enseigne_game"));
        await deleteCollection(enseigneDocRef.collection("horaires"));

        // Suppression du document 'enseigne' principal
        await enseigneDocRef.delete();
      }

      // 3.4. Suppression de la collection 'accountDeletionRequests'
      const deletionRequestsRef = admin
        .firestore()
        .collection("accountDeletionRequests");
      const [deletionRequestsByRefSnapshot, deletionRequestsByStringSnapshot] =
        await Promise.all([
          deletionRequestsRef.where("merchant_id", "==", userDocRef).get(),
          // Backward compatibility: certains anciens documents peuvent stocker un string.
          deletionRequestsRef.where("merchant_id", "==", commercantUid).get(),
        ]);
      const deletionRequestsMap = new Map();
      deletionRequestsByRefSnapshot.docs.forEach((doc) =>
        deletionRequestsMap.set(doc.id, doc),
      );
      deletionRequestsByStringSnapshot.docs.forEach((doc) =>
        deletionRequestsMap.set(doc.id, doc),
      );
      const deletionRequestsDocs = [...deletionRequestsMap.values()];
      for (const doc of deletionRequestsDocs) {
        await doc.ref.delete();
      }

      // 4. Supprimer l'utilisateur de Firebase Authentication
      await admin.auth().deleteUser(commercantUid);

      return {
        success: true,
        message: `Compte commerçant ${commercantUid} et toutes les données associées ont été supprimées.`,
      };
    } catch (error) {
      console.error(
        "Erreur lors de la suppression du compte commerçant :",
        error,
      );
      throw new functions.https.HttpsError(
        "internal",
        "Impossible de supprimer le compte commerçant.",
        error.message,
      );
    }
  },
);

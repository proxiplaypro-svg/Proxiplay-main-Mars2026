const functions = require("firebase-functions");
const admin = require("firebase-admin");

exports.deleteEnseigneAndGames = functions.https.onCall(
  async (data, context) => {
    // Vérifier que le client est authentifié ou possède le droit nécessaire (optionnel)

    // Récupérer le chemin complet de l'enseigne envoyé par le client
    const enseignePath = data.enseignePath;
    if (!enseignePath) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Le chemin de l'enseigne est requis.",
      );
    }

    const enseigneRef = admin.firestore().doc(enseignePath);

    // Vérifier que l’enseigne existe
    const enseigneDoc = await enseigneRef.get();
    if (!enseigneDoc.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "L'enseigne n'existe pas.",
      );
    }

    // Récupérer les documents dans "games" dont le champ "enseigne_id" correspond à l'enseigne
    const gamesQuerySnapshot = await admin
      .firestore()
      .collection("games")
      .where("enseigne_id", "==", enseigneRef)
      .get();

    const gameDocs = gamesQuerySnapshot.docs;

    // Fonction utilitaire : découper un tableau en sous-tableaux de taille chunkSize
    function chunkArray(arr, chunkSize = 500) {
      const chunks = [];
      for (let i = 0; i < arr.length; i += chunkSize) {
        chunks.push(arr.slice(i, i + chunkSize));
      }
      return chunks;
    }

    // Diviser le tableau en groupes de 500 opérations maximum
    const chunks = chunkArray(gameDocs, 500);

    // Traitement de chaque batch
    for (const chunk of chunks) {
      const batch = admin.firestore().batch();
      chunk.forEach((doc) => {
        batch.delete(doc.ref);
      });
      await batch.commit();
    }

    // Supprimer l’enseigne une fois que tous les jeux ont été supprimés
    await enseigneRef.delete();

    return {
      message:
        "L'enseigne et tous ses jeux associés ont été supprimés avec succès.",
    };
  },
);

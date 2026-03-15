const functions = require("firebase-functions");
const admin = require("firebase-admin");

exports.deleteEnseigneAndGames = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Vous devez etre connecte pour supprimer une enseigne.",
      );
    }

    const enseignePath = data.enseignePath;
    if (!enseignePath) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Le chemin de l'enseigne est requis.",
      );
    }

    const db = admin.firestore();
    const enseigneRef = db.doc(enseignePath);
    const enseigneDoc = await enseigneRef.get();

    if (!enseigneDoc.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "L'enseigne n'existe pas.",
      );
    }

    const callerUid = context.auth.uid;
    const callerRef = db.collection("users").doc(callerUid);
    const callerDoc = await callerRef.get();
    const callerData = callerDoc.exists ? callerDoc.data() : {};
    const isAdmin = callerData?.user_role === "admin";

    const enseigneData = enseigneDoc.data() || {};
    const ownerRef = enseigneData.owner;
    const isOwner =
      ownerRef &&
      typeof ownerRef.path === "string" &&
      ownerRef.path === callerRef.path;

    if (!isAdmin && !isOwner) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Vous n'avez pas les droits pour supprimer cette enseigne.",
      );
    }

    const gamesQuerySnapshot = await db
      .collection("games")
      .where("enseigne_id", "==", enseigneRef)
      .get();

    const gameDocs = gamesQuerySnapshot.docs;

    function chunkArray(arr, chunkSize = 500) {
      const chunks = [];
      for (let i = 0; i < arr.length; i += chunkSize) {
        chunks.push(arr.slice(i, i + chunkSize));
      }
      return chunks;
    }

    const chunks = chunkArray(gameDocs, 500);

    for (const chunk of chunks) {
      const batch = db.batch();
      chunk.forEach((doc) => {
        batch.delete(doc.ref);
      });
      await batch.commit();
    }

    await enseigneRef.delete();

    return {
      message:
        "L'enseigne et tous ses jeux associes ont ete supprimes avec succes.",
    };
  },
);

const functions = require("firebase-functions");
const admin = require("firebase-admin");

exports.unlockCommercantAccount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "La fonction doit etre appelee avec une authentification.",
    );
  }

  const callerUid = context.auth.uid;
  const callerDoc = await admin.firestore().collection("users").doc(callerUid).get();

  if (!callerDoc.exists || callerDoc.data().user_role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Seuls les administrateurs peuvent debloquer un commercant.",
    );
  }

  const commercantUid =
    typeof data?.commercantUid === "string" ? data.commercantUid.trim() : "";

  if (!commercantUid) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      'Le parametre "commercantUid" est requis.',
    );
  }

  const userRef = admin.firestore().collection("users").doc(commercantUid);
  const userSnap = await userRef.get();

  if (!userSnap.exists) {
    throw new functions.https.HttpsError(
      "not-found",
      "Aucun document Firestore users/{uid} trouve pour ce commercant.",
    );
  }

  const userData = userSnap.data() || {};
  const targetRole =
    typeof userData.user_role === "string" ? userData.user_role.trim() : "";

  if (targetRole && targetRole !== "commercant") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Le compte cible ne peut pas etre debloque car user_role="${targetRole}" et non "commercant".`,
    );
  }

  let authUser;
  try {
    authUser = await admin.auth().getUser(commercantUid);
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      throw new functions.https.HttpsError(
        "not-found",
        "Aucun utilisateur Firebase Auth trouve pour cet UID.",
      );
    }

    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Impossible de lire le compte Firebase Auth cible.",
    );
  }

  try {
    await admin.auth().updateUser(commercantUid, {
      emailVerified: true,
      disabled: false,
    });

    await userRef.set(
      {
        account_status: "approved",
        user_role: "commercant",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      ok: true,
      commercantUid,
      auth: {
        emailVerifiedBefore: authUser.emailVerified === true,
        disabledBefore: authUser.disabled === true,
        emailVerifiedAfter: true,
        disabledAfter: false,
      },
      firestore: {
        account_status: "approved",
        user_role: "commercant",
      },
    };
  } catch (error) {
    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Impossible de debloquer le commercant.",
    );
  }
});

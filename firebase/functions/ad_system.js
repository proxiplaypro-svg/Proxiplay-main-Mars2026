// Systeme publicitaire ProxiPlay (vendu en direct, pas AdMob). La config
// de chaque emplacement (ads/open, ads/home_banner) est lue directement
// par le client (regles: read:true) -- aucune Callable necessaire pour
// ca. Seuls les compteurs impressions/clics passent ici, pour ne jamais
// laisser un client ecrire une valeur arbitraire sur ces champs (les
// regles Firestore interdisent toute ecriture directe sur /ads/*, y
// compris pour un utilisateur connecte).
//
// Non authentifie par conception : la pub est montree aussi aux invites,
// qui doivent pouvoir generer une impression/un clic.

const functions = require("firebase-functions");
const admin = require("firebase-admin");

const kFunctionsRegion = "us-central1";
const kAdsCollection = "ads";
const kValidPlacements = new Set(["open", "home_banner"]);
const kValidEventTypes = new Set(["impression", "click"]);

async function recordAdEventHandler(data) {
  const placement = typeof data?.placement === "string" ? data.placement.trim() : "";
  const type = typeof data?.type === "string" ? data.type.trim() : "";
  if (!kValidPlacements.has(placement)) {
    throw new functions.https.HttpsError("invalid-argument", "placement invalide.");
  }
  if (!kValidEventTypes.has(type)) {
    throw new functions.https.HttpsError("invalid-argument", "type invalide.");
  }

  const field = type === "impression" ? "impressions" : "clicks";
  await admin.firestore().doc(`${kAdsCollection}/${placement}`).set({
    [field]: admin.firestore.FieldValue.increment(1),
  }, {merge: true});

  return {status: "recorded"};
}

exports.recordAdEvent = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 10, memory: "128MB"})
  .https.onCall(recordAdEventHandler);

exports.recordAdEventHandler = recordAdEventHandler;

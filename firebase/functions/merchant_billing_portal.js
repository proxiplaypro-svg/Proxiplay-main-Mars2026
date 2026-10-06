// Session Stripe Customer Portal (espace commercant, proxiplay.fr) :
// permet au commercant de consulter son abonnement, gerer son moyen de
// paiement, telecharger ses factures Stripe et annuler le renouvellement.
// Session toujours creee cote serveur, apres verification de la
// propriete de l'enseigne -- jamais un stripeCustomerId transmis par le
// client.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {shopOwnerPath} = require("./merchant_ownership");
const stripeClientModule = require("./stripe_client");

const kFunctionsRegion = "us-central1";
const kMerchantSubscriptionsCollection = "merchant_subscriptions";

async function createMerchantBillingPortalSessionHandler(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const enseigneId = typeof data?.enseigneId === "string" ? data.enseigneId.trim() : "";
  const returnUrl = typeof data?.returnUrl === "string" ? data.returnUrl : "";
  if (!enseigneId || !returnUrl) {
    throw new functions.https.HttpsError("invalid-argument", "enseigneId et returnUrl sont requis.");
  }

  const db = admin.firestore();
  const uid = context.auth.uid;

  const enseigneSnap = await db.collection("enseignes").doc(enseigneId).get();
  if (!enseigneSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Enseigne introuvable.");
  }
  if (shopOwnerPath(enseigneSnap.data()) !== `users/${uid}`) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Vous n'etes pas proprietaire de cette enseigne.",
    );
  }

  const subscriptionSnap = await db.collection(kMerchantSubscriptionsCollection).doc(enseigneId).get();
  const stripeCustomerId = subscriptionSnap.exists ? subscriptionSnap.data().stripe_customer_id : null;
  if (!stripeCustomerId) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Aucun abonnement Stripe pour cette enseigne.",
    );
  }

  const stripe = stripeClientModule.getStripeClient();
  const portalSession = await stripe.billingPortal.sessions.create({
    customer: stripeCustomerId,
    return_url: returnUrl,
  });

  return {portalUrl: portalSession.url};
}

exports.createMerchantBillingPortalSession = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
  .https.onCall(createMerchantBillingPortalSessionHandler);

exports.createMerchantBillingPortalSessionHandler = createMerchantBillingPortalSessionHandler;

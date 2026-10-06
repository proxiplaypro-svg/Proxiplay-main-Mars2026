// Session Stripe Customer Portal (espace commercant, proxiplay.fr) :
// permet au commercant de consulter son abonnement (qui couvre toutes ses
// enseignes), gerer son moyen de paiement, telecharger ses factures Stripe
// et annuler le renouvellement. Session toujours creee cote serveur, pour
// le compte de l'appelant authentifie lui-meme -- jamais un
// stripeCustomerId transmis par le client, jamais pour le compte d'un
// autre commercant.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const stripeClientModule = require("./stripe_client");

const kFunctionsRegion = "us-central1";
const kMerchantSubscriptionsCollection = "merchant_subscriptions";

async function createMerchantBillingPortalSessionHandler(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const returnUrl = typeof data?.returnUrl === "string" ? data.returnUrl : "";
  if (!returnUrl) {
    throw new functions.https.HttpsError("invalid-argument", "returnUrl est requis.");
  }

  const db = admin.firestore();
  const uid = context.auth.uid;

  const subscriptionSnap = await db.collection(kMerchantSubscriptionsCollection).doc(uid).get();
  const stripeCustomerId = subscriptionSnap.exists ? subscriptionSnap.data().stripe_customer_id : null;
  if (!stripeCustomerId) {
    throw new functions.https.HttpsError("failed-precondition", "Aucun abonnement Stripe pour ce compte.");
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

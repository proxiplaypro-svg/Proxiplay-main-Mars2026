// Instanciation paresseuse du SDK Stripe : la valeur du secret
// STRIPE_SECRET_KEY n'est lisible qu'au moment de l'execution d'une
// Cloud Function (jamais au chargement du module), donc jamais construite
// au niveau module. Un seul client reutilise par invocation "chaude".
//
// Une cle LIVE est refusee tant que STRIPE_LIVE_MODE_ENABLED !== "true" :
// aucun paiement reel ne peut partir d'un environnement de test mal
// configure.

const Stripe = require("stripe");
const {stripeSecretKey, stripeLiveModeEnabled} = require("./stripe_secrets");

const kStripeApiVersion = "2024-06-20";

let cachedClient = null;
let cachedKey = null;

function isLiveKey(key) {
  return /^(sk|rk)_live_/.test(key);
}

function assertKeyAllowed(key) {
  const {https} = require("firebase-functions");
  if (!key) {
    throw new https.HttpsError("failed-precondition", "STRIPE_SECRET_KEY n'est pas configure.");
  }
  if (isLiveKey(key) && stripeLiveModeEnabled.value() !== "true") {
    throw new https.HttpsError(
      "failed-precondition",
      "Cle Stripe LIVE refusee : STRIPE_LIVE_MODE_ENABLED n'est pas active.",
    );
  }
}

function getStripeClient() {
  const key = stripeSecretKey.value();
  assertKeyAllowed(key);
  if (!cachedClient || cachedKey !== key) {
    cachedClient = new Stripe(key, {apiVersion: kStripeApiVersion});
    cachedKey = key;
  }
  return cachedClient;
}

module.exports = {getStripeClient, assertKeyAllowed, isLiveKey, kStripeApiVersion};

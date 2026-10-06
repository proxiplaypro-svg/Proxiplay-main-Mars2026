// Instanciation paresseuse du SDK Stripe : la valeur du secret
// STRIPE_SECRET_KEY n'est lisible qu'au moment de l'execution d'une
// Cloud Function (jamais au chargement du module), donc jamais construite
// au niveau module. Un seul client reutilise par invocation "chaude".

const Stripe = require("stripe");
const {stripeSecretKey} = require("./stripe_secrets");

let cachedClient = null;
let cachedKey = null;

function getStripeClient() {
  const key = stripeSecretKey.value();
  if (!key) {
    const {https} = require("firebase-functions");
    throw new https.HttpsError(
      "failed-precondition",
      "STRIPE_SECRET_KEY n'est pas configure.",
    );
  }
  if (!cachedClient || cachedKey !== key) {
    cachedClient = new Stripe(key, {apiVersion: "2024-06-20"});
    cachedKey = key;
  }
  return cachedClient;
}

module.exports = {getStripeClient};

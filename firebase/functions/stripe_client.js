// Instanciation paresseuse du SDK Stripe : la valeur du secret
// STRIPE_SECRET_KEY n'est lisible qu'au moment de l'execution d'une
// Cloud Function (jamais au chargement du module), donc jamais construite
// au niveau module. Un seul client reutilise par invocation "chaude".
//
// Mode de la cle impose par le projet (stripe_mode.js) :
//   - production : cle LIVE uniquement, et seulement si
//     STRIPE_LIVE_MODE_ENABLED === "true" ; une cle TEST est refusee (aucun
//     paiement fictif ne peut ouvrir de droits reels) ;
//   - projet demo- (emulateurs) : cle TEST uniquement ; une cle LIVE est
//     refusee (aucun paiement reel depuis un poste de developpement).
// Toute autre valeur (vide, placeholder) est refusee : paiements fermes.

const Stripe = require("stripe");
const {stripeSecretKey, stripeLiveModeEnabled} = require("./stripe_secrets");
const {isStripeSandbox, keyMode} = require("./stripe_mode");

const kStripeApiVersion = "2024-06-20";

let cachedClient = null;
let cachedKey = null;

function isLiveKey(key) {
  return keyMode(key) === "live";
}

function assertKeyAllowed(key) {
  const {https} = require("firebase-functions");
  const refuse = (message) => {
    throw new https.HttpsError("failed-precondition", message, {reason: "payments_closed"});
  };
  const mode = keyMode(key);
  if (!key) refuse("STRIPE_SECRET_KEY n'est pas configure.");
  if (!mode) refuse("STRIPE_SECRET_KEY n'est pas une cle Stripe : paiements fermes.");
  if (isStripeSandbox()) {
    if (mode !== "test") refuse("Cle Stripe LIVE refusee sur un projet d'emulation (demo-).");
    return;
  }
  if (mode !== "live") refuse("Cle Stripe TEST refusee sur le projet de production.");
  if (stripeLiveModeEnabled.value() !== "true") {
    refuse("Cle Stripe LIVE refusee : STRIPE_LIVE_MODE_ENABLED n'est pas active.");
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

module.exports = {getStripeClient, assertKeyAllowed, isLiveKey, keyMode, kStripeApiVersion};

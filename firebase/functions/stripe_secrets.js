// Secrets Stripe du chantier paiement commercant (proxiplay.fr). Suit la
// meme convention que GOOGLE_PLACES_API_KEY (google_places_secret.js) :
// une seule declaration defineSecret() ici, importee partout ailleurs.
// Jamais de valeur en dur, jamais de cle LIVE dans un test.
//
//   firebase functions:secrets:set STRIPE_SECRET_KEY
//   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET

const {defineSecret, defineString} = require("firebase-functions/params");

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

// Les ID de prix Stripe ne sont pas des secrets (ils apparaissent dans les
// URLs Stripe Dashboard et ne donnent aucun droit), mais n'existent pas
// avant que Pascal cree les produits/prix reels dans Stripe -- params non
// secrets pour pouvoir les configurer sans redeploiement de code.
const stripePriceProximite = defineString("STRIPE_PRICE_PROXIMITE");
const stripePriceSecteursSpecifiques = defineString("STRIPE_PRICE_SECTEURS_SPECIFIQUES");
const stripePriceGrandesEnseignes = defineString("STRIPE_PRICE_GRANDES_ENSEIGNES");
const stripeTaxRateId = defineString("STRIPE_TAX_RATE_TVA_20");

module.exports = {
  stripeSecretKey,
  stripeWebhookSecret,
  stripePriceProximite,
  stripePriceSecteursSpecifiques,
  stripePriceGrandesEnseignes,
  stripeTaxRateId,
};

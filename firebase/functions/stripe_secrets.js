// Configuration Stripe du chantier paiement commercant (proxiplay.fr).
//
// IMPORTANT : ce module est importe par index.js pendant la decouverte de
// TOUTES les Functions. defineSecret() enregistre un parametre obligatoire
// globalement, ce qui faisait demander STRIPE_SECRET_KEY meme lors du
// deploiement d'une Function non-Stripe. Les secrets restent rattaches aux
// seuls endpoints Stripe par leurs runWith({secrets: [...]}) respectifs ;
// ces accesseurs paresseux ne lisent donc jamais une valeur Stripe tant que
// ces endpoints ne sont pas executes.
//
// Jamais de valeur en dur, jamais de cle LIVE dans un test.
//
//   firebase functions:secrets:set STRIPE_SECRET_KEY
//   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET

function environmentParameter(name) {
  return Object.freeze({
    value() {
      return process.env[name] || "";
    },
  });
}

const stripeSecretKey = environmentParameter("STRIPE_SECRET_KEY");
const stripeWebhookSecret = environmentParameter("STRIPE_WEBHOOK_SECRET");

// Les ID de prix Stripe ne sont pas des secrets. Ils sont lus au moment de
// l'execution de l'endpoint Stripe, comme les deux secrets ci-dessus, afin
// qu'une configuration Stripe absente ne bloque jamais la decouverte des
// Functions non-Stripe.
const stripePriceProximite = environmentParameter("STRIPE_PRICE_PROXIMITE");
const stripePriceSecteursSpecifiques = environmentParameter("STRIPE_PRICE_SECTEURS_SPECIFIQUES");
const stripePriceGrandesEnseignes = environmentParameter("STRIPE_PRICE_GRANDES_ENSEIGNES");
const stripeTaxRateId = environmentParameter("STRIPE_TAX_RATE_TVA_20");

module.exports = {
  stripeSecretKey,
  stripeWebhookSecret,
  stripePriceProximite,
  stripePriceSecteursSpecifiques,
  stripePriceGrandesEnseignes,
  stripeTaxRateId,
};

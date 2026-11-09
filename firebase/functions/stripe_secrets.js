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
      return String(process.env[name] || "").trim();
    },
  });
}

const stripeSecretKey = environmentParameter("STRIPE_SECRET_KEY");
const stripeWebhookSecret = environmentParameter("STRIPE_WEBHOOK_SECRET");

// Les ID de prix Stripe ne sont pas des secrets. Ils sont lus au moment de
// l'execution de l'endpoint Stripe, comme les deux secrets ci-dessus, afin
// qu'une configuration Stripe absente ne bloque jamais la decouverte des
// Functions non-Stripe.
const stripePriceAutonome = environmentParameter("STRIPE_PRICE_AUTONOME");
const stripePriceAccompagnee = environmentParameter("STRIPE_PRICE_ACCOMPAGNEE");

// Regime fiscal : jamais presume. STRIPE_TAX_MODE doit etre pose
// explicitement apres validation comptable, sinon aucun Checkout n'est cree.
//   tax_rate  -> STRIPE_TAX_RATE_ID (txr_...) applique a la ligne
//   automatic -> Stripe Tax (a activer dans le Dashboard)
//   none      -> aucune taxe ajoutee (ex. franchise en base), choix assume
const stripeTaxMode = environmentParameter("STRIPE_TAX_MODE");
const stripeTaxRateId = environmentParameter("STRIPE_TAX_RATE_ID");

// Garde-fou : une cle sk_live_/rk_live_ est refusee tant que ce drapeau
// n'est pas explicitement "true" (bascule LIVE decidee par Pascal).
const stripeLiveModeEnabled = environmentParameter("STRIPE_LIVE_MODE_ENABLED");

// Origines autorisees pour success_url / cancel_url / return_url (liste
// separee par des virgules). A defaut, les domaines ProxiPlay connus.
const merchantBillingAllowedOrigins = environmentParameter("MERCHANT_BILLING_ALLOWED_ORIGINS");

module.exports = {
  stripeSecretKey,
  stripeWebhookSecret,
  stripePriceAutonome,
  stripePriceAccompagnee,
  stripeTaxMode,
  stripeTaxRateId,
  stripeLiveModeEnabled,
  merchantBillingAllowedOrigins,
};

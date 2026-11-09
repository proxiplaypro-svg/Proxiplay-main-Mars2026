// Source unique des offres commercant (chantier paiement Stripe). Les
// montants HT de reference sont definis UNE SEULE FOIS ici et exposes au
// site/admin via la Callable listMerchantOffers -- jamais recopies en dur
// dans le site ou l'app. Les ID de prix Stripe correspondants sont des
// parametres non secrets (stripe_secrets.js), fournis par Pascal apres
// creation reelle des produits/prix dans le Dashboard Stripe (doc associee).
//
// TVA : aucun regime n'est presume. La configuration fiscale (STRIPE_TAX_MODE)
// doit etre posee explicitement apres validation ; sans elle, aucun Checkout
// n'est cree. Le montant HT est la seule valeur de reference metier ici.

const {
  stripePriceAutonome,
  stripePriceAccompagnee,
  stripeTaxMode,
  stripeTaxRateId,
} = require("./stripe_secrets");

const kOffers = Object.freeze({
  autonome: Object.freeze({
    id: "autonome",
    label: "Autonome",
    amountHtCents: 36500,
    stripePriceParam: stripePriceAutonome,
  }),
  accompagnee: Object.freeze({
    id: "accompagnee",
    label: "Accompagnée",
    amountHtCents: 100000,
    stripePriceParam: stripePriceAccompagnee,
  }),
});

// Libelles d'affichage d'identifiants d'offre deja rencontres (catalogue
// precedent jamais ouvert a la vente, tarif negocie). Non souscriptibles.
const kOfferLabels = Object.freeze({
  autonome: "Autonome",
  accompagnee: "Accompagnée",
  custom: "Tarif négocié",
  proximite: "Proximité (ancien catalogue)",
  secteurs_specifiques: "Secteurs spécifiques (ancien catalogue)",
  grandes_enseignes: "Grandes enseignes (ancien catalogue)",
});

function httpsError(code, message) {
  const {https} = require("firebase-functions");
  return new https.HttpsError(code, message);
}

function getOfferOrThrow(offerId) {
  const offer = typeof offerId === "string" && Object.prototype.hasOwnProperty.call(kOffers, offerId) ?
    kOffers[offerId] : undefined;
  if (!offer) throw httpsError("invalid-argument", "Offre inconnue.");
  return offer;
}

function getStripePriceIdOrThrow(offer) {
  const priceId = offer.stripePriceParam.value();
  if (!priceId) {
    throw httpsError("failed-precondition", `Aucun ID de prix Stripe configure pour l'offre ${offer.id}.`);
  }
  return priceId;
}

/**
 * Verifie que le prix Stripe configure correspond bien a l'offre (montant
 * HT, EUR, annuel, actif) : un ID de prix mal colle ne doit jamais facturer
 * un autre montant ou une autre periodicite que celle annoncee.
 */
function assertStripePriceMatchesOffer(price, offer) {
  const ok = price && price.active === true &&
    price.currency === "eur" &&
    price.unit_amount === offer.amountHtCents &&
    price.type === "recurring" &&
    price.recurring?.interval === "year" &&
    (price.recurring?.interval_count || 1) === 1;
  if (!ok) {
    throw httpsError(
      "failed-precondition",
      `Le prix Stripe configure pour l'offre ${offer.id} ne correspond pas au catalogue (montant, devise ou periodicite).`,
    );
  }
}

/**
 * Configuration fiscale explicitement validee, ou refus. Renvoie les
 * parametres a fusionner dans la session Checkout et la ligne d'article.
 */
function getTaxConfigOrThrow() {
  const mode = stripeTaxMode.value();
  if (mode === "tax_rate") {
    const taxRateId = stripeTaxRateId.value();
    if (!/^txr_/.test(taxRateId)) {
      throw httpsError("failed-precondition", "STRIPE_TAX_RATE_ID (txr_...) requis pour STRIPE_TAX_MODE=tax_rate.");
    }
    return {mode, lineItemExtra: {tax_rates: [taxRateId]}, sessionExtra: {}};
  }
  if (mode === "automatic") {
    return {mode, lineItemExtra: {}, sessionExtra: {automatic_tax: {enabled: true}}};
  }
  if (mode === "none") {
    return {mode, lineItemExtra: {}, sessionExtra: {}};
  }
  throw httpsError(
    "failed-precondition",
    "Configuration fiscale non validee (STRIPE_TAX_MODE) : paiement indisponible.",
  );
}

function publicOfferCatalog() {
  return Object.values(kOffers).map(({id, label, amountHtCents}) => ({
    id, label, amountHtCents, currency: "eur", interval: "year",
  }));
}

function offerLabel(offerId) {
  return (typeof offerId === "string" && kOfferLabels[offerId]) || null;
}

module.exports = {
  kOffers,
  kOfferLabels,
  getOfferOrThrow,
  getStripePriceIdOrThrow,
  assertStripePriceMatchesOffer,
  getTaxConfigOrThrow,
  publicOfferCatalog,
  offerLabel,
};

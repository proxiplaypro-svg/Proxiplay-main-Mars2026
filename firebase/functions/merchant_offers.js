// Source unique des offres commercant (chantier paiement Stripe). Les
// montants et le taux de TVA sont definis UNE SEULE FOIS ici et exposes au
// site/admin via la Callable listMerchantOffers -- jamais recopies en dur
// dans le site ou l'app. Les ID de prix Stripe correspondants sont des
// parametres non secrets (stripe_secrets.js), fournis par Pascal apres
// creation reelle des produits/prix dans le Dashboard Stripe (doc associee).
//
// TVA : ProxiPlay (SASU) facture ses commercants TTC avec TVA a 20% sur un
// prix de base HT (decision explicite -- voir docs/stripe-merchant-billing.md).
// `amountHtCents` est la valeur de reference metier ; `amountTtcCents` est
// deduit ici pour ne jamais etre recalcule/incoherent ailleurs.

const {
  stripePriceProximite,
  stripePriceSecteursSpecifiques,
  stripePriceGrandesEnseignes,
} = require("./stripe_secrets");

const kVatRate = 0.20;

function withTtc(offer) {
  return {
    ...offer,
    vatRate: kVatRate,
    amountTtcCents: Math.round(offer.amountHtCents * (1 + kVatRate)),
  };
}

// "Grandes enseignes" est un tarif "a partir de" dans la grille historique
// (enseignes multi-sites, devis specifique au-dela). Le Checkout en V1 ne
// gere que le prix plancher en autoservice ; un besoin de devis superieur
// reste hors perimetre Stripe Checkout et doit rester traite hors-ligne
// (voir rapport final, section ACTIONS MANUELLES).
const kOffers = Object.freeze({
  proximite: withTtc({
    id: "proximite",
    label: "Proximité",
    amountHtCents: 36500,
    stripePriceParam: stripePriceProximite,
  }),
  secteurs_specifiques: withTtc({
    id: "secteurs_specifiques",
    label: "Secteurs spécifiques",
    amountHtCents: 109500,
    stripePriceParam: stripePriceSecteursSpecifiques,
  }),
  grandes_enseignes: withTtc({
    id: "grandes_enseignes",
    label: "Grandes enseignes (à partir de)",
    amountHtCents: 182500,
    stripePriceParam: stripePriceGrandesEnseignes,
  }),
});

function getOfferOrThrow(offerId) {
  const offer = typeof offerId === "string" ? kOffers[offerId] : undefined;
  if (!offer) {
    const {https} = require("firebase-functions");
    throw new https.HttpsError("invalid-argument", "Offre inconnue.");
  }
  return offer;
}

function getStripePriceIdOrThrow(offer) {
  const priceId = offer.stripePriceParam.value();
  if (!priceId) {
    const {https} = require("firebase-functions");
    throw new https.HttpsError(
      "failed-precondition",
      `Aucun ID de prix Stripe configure pour l'offre ${offer.id}.`,
    );
  }
  return priceId;
}

function publicOfferCatalog() {
  return Object.values(kOffers).map(({id, label, amountHtCents, amountTtcCents, vatRate}) => ({
    id, label, amountHtCents, amountTtcCents, vatRate,
  }));
}

module.exports = {
  kVatRate,
  kOffers,
  getOfferOrThrow,
  getStripePriceIdOrThrow,
  publicOfferCatalog,
};

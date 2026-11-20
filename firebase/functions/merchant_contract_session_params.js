// Phase 1, tranche 2a, lot 1.7 : parametres Stripe de la session Checkout et
// de l'apercu de premiere facture, sans dependance (module pur). Partages
// entre merchant_contract_checkout.js et le script d'essai en mode TEST, pour
// que l'essai envoie exactement les parametres du code.

const kSessionMaxMs = 24 * 60 * 60 * 1000;
const kSessionMinMs = 30 * 60 * 1000; // minimum impose par Stripe a la reception
// Marge contre le temps de transit : l'echeance est calculee juste avant
// l'appel, mais Stripe la compare a SA propre horloge a la reception.
const kSessionMarginMs = 60 * 1000;

/**
 * Echeance de la session (secondes) : au plus 24 h, au moins 30 min + marge,
 * sinon la fin du lien (decision 4 : depassement de 31 min au plus).
 * nowMs doit etre lu juste avant checkout.sessions.create.
 */
function sessionExpiresAtSeconds(nowMs, linkExpiresMs) {
  const ms = Math.min(nowMs + kSessionMaxMs, Math.max(linkExpiresMs, nowMs + kSessionMinMs + kSessionMarginMs));
  return Math.floor(ms / 1000);
}

/** Parametres de checkout.sessions.create pour un contrat. */
function buildSessionParams({customerId, contractId, enseigneId, ownerUid, offerId, priceId, tax, couponId,
  expiresAtSeconds, successUrl, cancelUrl}) {
  const metadata = {contractId, enseigneId, merchantUserId: ownerUid, offerId};
  return {
    mode: "subscription",
    customer: customerId,
    client_reference_id: contractId,
    line_items: [{price: priceId, quantity: 1, ...tax.lineItemExtra}],
    payment_method_types: ["card"],
    ...(couponId ? {discounts: [{coupon: couponId}]} : {allow_promotion_codes: false}),
    ...tax.sessionExtra,
    tax_id_collection: {enabled: true},
    customer_update: {name: "auto", address: "auto"},
    metadata,
    subscription_data: {metadata},
    expires_at: expiresAtSeconds,
    success_url: successUrl,
    cancel_url: cancelUrl,
    locale: "fr",
  };
}

/** Parametres de invoices.retrieveUpcoming (API 2024-06-20) : apercu sans rien creer. */
function buildUpcomingParams({customerId, priceId, tax, couponId}) {
  return {
    customer: customerId,
    subscription_items: [{price: priceId, quantity: 1, ...(tax.lineItemExtra.tax_rates ? {tax_rates: tax.lineItemExtra.tax_rates} : {})}],
    ...(couponId ? {discounts: [{coupon: couponId}]} : {}),
    ...(tax.mode === "automatic" ? {automatic_tax: {enabled: true}} : {}),
  };
}

/** Parametres de coupons.create (duration "once", montant de l'instantane). */
function buildCouponParams({code, offerId, discountCents}) {
  return {
    amount_off: discountCents, currency: "eur", duration: "once",
    name: `${code} (première année)`, metadata: {promo_code: code, offer_id: offerId},
  };
}

module.exports = {
  kSessionMaxMs,
  kSessionMinMs,
  kSessionMarginMs,
  sessionExpiresAtSeconds,
  buildSessionParams,
  buildUpcomingParams,
  buildCouponParams,
};

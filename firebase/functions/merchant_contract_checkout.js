// Phase 1, tranche 2a, lot 1.7 : session Stripe Checkout creee au clic, depuis
// la page de paiement ProxiPlay (lien d'invitation du lot 1.6). Une session
// par enseigne (client Stripe propre a l'enseigne), carte seulement.
//
// Garde-fous :
//   - jamais de lien de paiement Stripe ni de prix libre : la ligne est le
//     prix existant du catalogue (STRIPE_PRICE_*), verifie a chaque paiement :
//     montant, devise, annuel, actif, tax_behavior "exclusive" (hors taxes),
//     mode TEST/LIVE attendu ;
//   - TVA : STRIPE_TAX_MODE. "tax_rate" (decide pour la production : 20 %
//     hors taxes, commercants etablis en France) verifie le taux existant
//     (actif, 20 %, non inclus, meme mode) ; "none" est refuse en LIVE ;
//   - remise de premiere annee : coupon "duration: once" cree par le serveur
//     depuis le miroir promo_codes, montant = l'instantane du contrat ;
//   - avant l'envoi : apercu Stripe de la premiere facture
//     (invoices.retrieveUpcoming, API 2024-06-20) compare a l'instantane du
//     contrat ; tout ecart refuse la session et alerte l'administration ;
//   - aucun droit n'est ouvert ici : seul le webhook (lot 1.8) active.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {getOfferOrThrow, getStripePriceIdOrThrow, assertStripePriceMatchesOffer, getTaxConfigOrThrow} = require("./merchant_offers");
const {assertMerchantCaller, assertAllowedReturnUrl, assertPaymentsOpen} = require("./merchant_billing_access");
const {expectedLivemode} = require("./stripe_mode");
const stripeClientModule = require("./stripe_client");
const {stripeTaxRateId} = require("./stripe_secrets");
const {
  kFunctionsRegion,
  kContractsCollection,
  kPromoCodesCollection,
  httpsError,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const {loadToken} = require("./merchant_contract_payment");
const mail = require("./merchant_contract_mail");
const sessionParams = require("./merchant_contract_session_params");

const kEnseigneSubscriptionsCollection = "enseigne_subscriptions";
const kCheckoutLockMs = 60 * 1000;

function refuse(reason, message) {
  return httpsError("failed-precondition", message, {reason});
}

function mode() {
  return expectedLivemode() ? "live" : "test";
}

function assertMode(object, what) {
  if (!object || object.livemode !== expectedLivemode()) {
    throw refuse("stripe_mode_mismatch", `${what} Stripe d'un autre mode (TEST/LIVE) : paiement refusé.`);
  }
  return object;
}

/** Prix existant du catalogue, verifie a chaque paiement (decision 1). */
async function verifiedCatalogPrice(stripe, offerId) {
  const offer = getOfferOrThrow(offerId);
  const price = assertMode(await stripe.prices.retrieve(getStripePriceIdOrThrow(offer)), "Prix");
  assertStripePriceMatchesOffer(price, offer);
  if (price.tax_behavior !== "exclusive") {
    throw refuse("price_tax_behavior", `Le prix Stripe de l'offre ${offer.id} n'est pas configuré « hors taxes » (exclusive).`);
  }
  return price;
}

/** Mode de TVA explicite ; "none" interdit en LIVE ; taux verifie (decision 2). */
async function verifiedTaxConfig(stripe) {
  const tax = getTaxConfigOrThrow();
  if (tax.mode === "none" && expectedLivemode()) {
    throw refuse("tax_none_forbidden_live", "STRIPE_TAX_MODE=none est interdit en LIVE : un assujetti facture la TVA.");
  }
  if (tax.mode === "tax_rate") {
    const rate = assertMode(await stripe.taxRates.retrieve(stripeTaxRateId.value()), "Taux de TVA");
    if (rate.active !== true || rate.inclusive !== false || Number(rate.percentage) !== 20) {
      throw refuse("tax_rate_mismatch", "Le taux de TVA Stripe configuré n'est pas 20 % hors taxes, actif.");
    }
  }
  return tax;
}

/** Un client Stripe par enseigne, cree par le serveur, reutilise ensuite. */
async function ensureEnseigneCustomer(db, stripe, contract, contractId) {
  const ref = db.collection(kEnseigneSubscriptionsCollection).doc(contract.enseigne_id);
  const snap = await ref.get();
  const current = snap.exists ? snap.data() : {};
  if (current.stripe_customer_id && current.stripe_livemode === expectedLivemode()) {
    if (current.owner_uid !== contract.owner_uid) {
      throw refuse("enseigne_owner_changed", "L'enseigne a changé de titulaire : contactez ProxiPlay.");
    }
    return current.stripe_customer_id;
  }
  const customer = assertMode(await stripe.customers.create({
    email: contract.owner_email,
    name: contract.enseigne_name || undefined,
    metadata: {enseigneId: contract.enseigne_id, merchantUserId: contract.owner_uid, contractId},
  }, {idempotencyKey: `customer-enseigne-${contract.enseigne_id}-${mode()}`}), "Client");
  await ref.set({
    enseigne_id: contract.enseigne_id,
    owner_uid: contract.owner_uid,
    contract_id: contractId,
    stripe_customer_id: customer.id,
    stripe_livemode: customer.livemode,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return customer.id;
}

/**
 * Coupon de premiere annee (duration "once") cree par le serveur depuis le
 * miroir promo_codes ; montant = remise de l'instantane du contrat. Sens
 * unique : rien n'est cree ni modifie a la main dans Stripe.
 */
async function ensureCoupon(db, stripe, contract) {
  const discount = contract.offer?.discount_ht_cents || 0;
  if (!contract.promo?.code || discount <= 0) return null;
  const code = contract.promo.code;
  const offerId = contract.offer.id;
  const key = `${offerId}_${discount}`;
  const ref = db.collection(kPromoCodesCollection).doc(code);
  const known = (await ref.get()).data()?.stripe_coupons?.[mode()]?.[key] || null;
  if (known) {
    const coupon = assertMode(await stripe.coupons.retrieve(known), "Coupon");
    if (coupon.valid === true && coupon.amount_off === discount && coupon.currency === "eur" && coupon.duration === "once") {
      return coupon.id;
    }
  }
  const coupon = assertMode(await stripe.coupons.create(sessionParams.buildCouponParams({code, offerId, discountCents: discount}), {idempotencyKey: `coupon-${mode()}-${code}-${key}`}), "Coupon");
  await ref.set({stripe_coupons: {[mode()]: {[key]: coupon.id}}}, {merge: true});
  return coupon.id;
}

/**
 * Apercu Stripe de la premiere facture (sans rien creer) compare a
 * l'instantane du contrat : HT apres remise et TTC.
 */
async function assertFirstYearMatches(db, stripe, {customerId, priceId, tax, couponId, contract, contractId}) {
  const upcoming = await stripe.invoices.retrieveUpcoming(sessionParams.buildUpcomingParams({customerId, priceId, tax, couponId}));
  const expectedTtc = contract.offer.first_year_ttc_cents;
  const expectedHt = contract.offer.first_year_ht_cents;
  const ht = typeof upcoming.total_excluding_tax === "number" ? upcoming.total_excluding_tax : null;
  if (upcoming.total !== expectedTtc || (ht !== null && ht !== expectedHt) || upcoming.currency !== "eur") {
    await mail.raiseAdminAlert(db, {kind: "montant_stripe_ecart", contractId,
      detail: `Aperçu Stripe ${upcoming.total} TTC / ${ht} HT, contrat ${expectedTtc} TTC / ${expectedHt} HT : session refusée.`});
    throw refuse("amount_mismatch", "Le montant calculé par Stripe ne correspond pas à votre souscription : aucun paiement n'est demandé, ProxiPlay est prévenu.");
  }
}

async function acquireLock(db, contractId, nowMs) {
  const ref = internalRef(db, contractId);
  return db.runTransaction(async (tx) => {
    // Relu dans la transaction : la cloture du lot 1.9 (meme verrou) ne peut
    // pas passer entre la lecture du jeton et la creation de la session.
    const contract = (await tx.get(db.collection(kContractsCollection).doc(contractId))).data();
    if (contract?.state !== "payment_invited") {
      throw refuse("not_payment_invited", "Cette souscription n'attend plus de paiement.");
    }
    const snap = await tx.get(ref);
    const lockAt = millisOf(snap.data()?.checkout?.lock_at);
    if (lockAt && nowMs - lockAt < kCheckoutLockMs) {
      throw httpsError("aborted", "Une page de paiement est déjà en préparation : réessayez dans un instant.", {reason: "checkout_in_progress"});
    }
    tx.set(ref, {checkout: {lock_at: admin.firestore.Timestamp.fromMillis(nowMs)}}, {merge: true});
    return snap.data()?.checkout || {};
  });
}

async function releaseLock(db, contractId) {
  await internalRef(db, contractId).set({checkout: {lock_at: admin.firestore.FieldValue.delete()}}, {merge: true});
}

async function createContractCheckoutSessionHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  // Contrat deja invite : payable meme si les nouvelles ventes sont en pause.
  assertPaymentsOpen();
  const successUrl = assertAllowedReturnUrl(data?.successUrl, "successUrl");
  const cancelUrl = assertAllowedReturnUrl(data?.cancelUrl, "cancelUrl");
  const nowMs = Date.now();
  const {tokenRef, tokenData, contractId, contract, expiresMs} = await loadToken(db, data?.token, context.auth.uid, nowMs);
  if (!contract.enseigne_id) throw refuse("enseigne_missing", "Aucune enseigne rattachée à cette souscription.");

  const previous = await acquireLock(db, contractId, nowMs);
  try {
    const stripe = stripeClientModule.getStripeClient();
    // Double clic, retour arriere : la session encore ouverte est reutilisee.
    if (previous.session_id) {
      const existing = await stripe.checkout.sessions.retrieve(previous.session_id);
      if (existing?.status === "open" && existing.metadata?.contractId === contractId && existing.url) {
        await tokenRef.update({last_session_id: existing.id});
        return {checkoutUrl: existing.url, reused: true};
      }
    }
    const price = await verifiedCatalogPrice(stripe, contract.offer.id);
    const tax = await verifiedTaxConfig(stripe);
    const customerId = await ensureEnseigneCustomer(db, stripe, contract, contractId);
    const couponId = await ensureCoupon(db, stripe, contract);
    await assertFirstYearMatches(db, stripe, {customerId, priceId: price.id, tax, couponId, contract, contractId});

    // Echeance de la session : au plus 24 h, au moins 30 min + 1 min de marge
    // (minimum Stripe, compte a la reception), sinon la fin du lien
    // (decision 4). Heure relue juste avant l'appel : les appels Stripe
    // precedents prennent plusieurs secondes.
    const sessionExpiresAt = sessionParams.sessionExpiresAtSeconds(Date.now(), expiresMs);
    const sessionExpiresMs = sessionExpiresAt * 1000;
    const generation = (previous.generation || 0) + 1;
    const session = assertMode(await stripe.checkout.sessions.create(sessionParams.buildSessionParams({
      customerId, contractId, enseigneId: contract.enseigne_id, ownerUid: contract.owner_uid, offerId: contract.offer.id,
      priceId: price.id, tax, couponId, expiresAtSeconds: sessionExpiresAt, successUrl, cancelUrl,
    }), {idempotencyKey: `checkout-contract-${contractId}-${generation}`}), "Session");

    await internalRef(db, contractId).set({checkout: {
      session_id: session.id,
      generation,
      created_at: admin.firestore.Timestamp.fromMillis(nowMs),
      expires_at: admin.firestore.Timestamp.fromMillis(sessionExpiresMs),
      stripe_customer_id: customerId,
      coupon_id: couponId,
    }}, {merge: true});
    await tokenRef.update({
      last_session_id: session.id,
      ...(tokenData.first_used_at ? {} : {first_used_at: admin.firestore.Timestamp.fromMillis(nowMs)}),
    });
    await eventRef(db, contractId).set({type: "checkout_session_created", at: admin.firestore.FieldValue.serverTimestamp(),
      actor: "merchant", generation, session_expires_at: admin.firestore.Timestamp.fromMillis(sessionExpiresMs)});
    return {checkoutUrl: session.url, reused: false};
  } finally {
    await releaseLock(db, contractId);
  }
}

/** Expire la session Checkout encore ouverte d'un contrat (retractation, signalement, cloture). */
async function expireOpenSessions(db, contractId) {
  const internal = (await internalRef(db, contractId).get()).data() || {};
  const sessionId = internal.checkout?.session_id;
  if (!sessionId) return 0;
  const stripe = stripeClientModule.getStripeClient();
  const session = await stripe.checkout.sessions.retrieve(sessionId);
  if (session?.status !== "open") return 0;
  await stripe.checkout.sessions.expire(sessionId);
  await eventRef(db, contractId).set({type: "checkout_session_expired", at: admin.firestore.FieldValue.serverTimestamp(), session_id: sessionId});
  return 1;
}

module.exports = {
  kEnseigneSubscriptionsCollection,
  verifiedCatalogPrice,
  verifiedTaxConfig,
  ensureEnseigneCustomer,
  ensureCoupon,
  assertFirstYearMatches,
  expireOpenSessions,
  createContractCheckoutSessionHandler,
  createContractCheckoutSession: functions
    .region(kFunctionsRegion)
    .runWith({timeoutSeconds: 60, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
    .https.onCall(createContractCheckoutSessionHandler),
  kContractsCollection,
};

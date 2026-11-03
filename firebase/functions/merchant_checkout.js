// Creation serveur d'une session Stripe Checkout pour l'abonnement annuel
// d'un commercant (chantier paiement commercant, proxiplay.fr). Un seul
// abonnement par compte commercant, qui couvre toutes ses enseignes -- pas
// un abonnement par enseigne. Le client (site web) ne transmet jamais de
// prix/montant : uniquement des identifiants. Le serveur resout seul le
// prix Stripe autorise (catalogue, ou tarif negocie fixe par l'Admin pour
// les commercants multi-enseignes) et attache les metadata necessaires a
// la reconciliation webhook.
//
// Anti double abonnement, dans cet ordre :
//   1. miroir Firestore : un abonnement ouvert connu bloque ;
//   2. verrou court (checkout_lock) : deux clics simultanes ne creent
//      jamais deux sessions ;
//   3. Stripe lui-meme : tout abonnement ouvert du Customer bloque, meme si
//      le webhook n'est pas encore arrive ;
//   4. une session Checkout encore ouverte pour la meme offre est reutilisee,
//      une session ouverte pour une autre offre est expiree avant d'en creer
//      une nouvelle.
// Aucun droit n'est ouvert ici : seul le webhook (statut lu chez Stripe) le
// fait.

const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {
  getOfferOrThrow,
  getStripePriceIdOrThrow,
  assertStripePriceMatchesOffer,
  getTaxConfigOrThrow,
} = require("./merchant_offers");
const {kRewardAmountCents} = require("./merchant_referral_engine");
const {
  assertMerchantCaller,
  assertAllowedReturnUrl,
  assertPaymentsOpen,
  isValidatedMerchant,
  kOpenSubscriptionStatuses,
} = require("./merchant_billing_access");
const {expectedLivemode, isForeignModeMirror, foreignModeResetFields} = require("./stripe_mode");
// Reference au module (pas destructure) : permet aux tests de remplacer
// stripeClientModule.getStripeClient par un mock apres le chargement de ce
// fichier, sans avoir a mocker require() lui-meme.
const stripeClientModule = require("./stripe_client");

const kFunctionsRegion = "us-central1";
const kMerchantSubscriptionsCollection = "merchant_subscriptions";
const kMerchantCustomOffersCollection = "merchant_custom_offers";
const kMerchantReferralCodesCollection = "merchant_referral_codes";
const kMerchantReferralsCollection = "merchant_referrals";
const kCheckoutLockMs = 60 * 1000;
const kCheckoutSessionLifetimeSeconds = 60 * 60; // minimum Stripe : 30 min

/**
 * Normalise et valide un code de parrainage commercant optionnel. Renvoie
 * `null` si absent (pas une erreur : la saisie du code est facultative).
 * Leve si le code est fourni mais invalide/inexistant -- jamais un
 * ratachement silencieux.
 */
async function resolveReferralCode(db, rawCode) {
  if (rawCode === undefined || rawCode === null || rawCode === "") {
    return null;
  }
  if (typeof rawCode !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Code de parrainage invalide.");
  }
  const code = rawCode.trim().toUpperCase();
  const codeSnap = await db.collection(kMerchantReferralCodesCollection).doc(code).get();
  if (!codeSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Ce code de parrainage n'existe pas.");
  }
  // inviter_user_id est stocke comme DocumentReference (generateMerchantReferralCode) :
  // on travaille uniquement avec son chemin ('users/{uid}') a partir d'ici.
  return {code, inviterUserPath: codeSnap.data().inviter_user_id.path};
}

/**
 * Resout le prix a facturer pour ce commercant. Priorite au tarif negocie
 * (fixe UNIQUEMENT par l'Admin, jamais par le client) s'il en existe un --
 * pertinent pour un commercant multi-enseignes dont le tarif de catalogue
 * standard ne correspond pas. A defaut, retombe sur une offre de catalogue
 * standard (offerId fourni par le client, mais le prix lui-meme vient du
 * serveur).
 */
async function resolvePriceSelection(db, uid, offerId) {
  const customOfferSnap = await db.collection(kMerchantCustomOffersCollection).doc(uid).get();
  if (customOfferSnap.exists) {
    const customOffer = customOfferSnap.data();
    if (!Number.isInteger(customOffer.amount_ht_cents) || customOffer.amount_ht_cents <= 0) {
      throw new functions.https.HttpsError("failed-precondition", "Tarif negocie invalide.");
    }
    return {
      offerIdForMetadata: "custom",
      priceKey: `custom:${customOffer.amount_ht_cents}`,
      catalogOffer: null,
      stripePriceId: null,
      lineItem: {
        price_data: {
          currency: "eur",
          unit_amount: customOffer.amount_ht_cents,
          recurring: {interval: "year"},
          product_data: {name: customOffer.label || "Abonnement ProxiPlay (tarif negocie)"},
          tax_behavior: "exclusive",
        },
        quantity: 1,
      },
    };
  }
  if (!offerId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "offerId est requis (aucun tarif negocie pour ce compte).",
    );
  }
  const offer = getOfferOrThrow(offerId);
  const stripePriceId = getStripePriceIdOrThrow(offer);
  return {
    offerIdForMetadata: offer.id,
    priceKey: stripePriceId,
    catalogOffer: offer,
    stripePriceId,
    lineItem: {price: stripePriceId, quantity: 1},
  };
}

function hasOpenSubscription(subscriptionDoc) {
  const status = subscriptionDoc?.subscription_status;
  if (!kOpenSubscriptionStatuses.includes(status)) return false;
  // Ancien comportement : "incomplete" etait pose des la creation du
  // Checkout, sans abonnement Stripe reel. Il ne bloque que s'il est adosse
  // a un abonnement Stripe.
  return status !== "incomplete" || Boolean(subscriptionDoc.stripe_subscription_id);
}

async function acquireCheckoutLock(db, subscriptionRef, uid, token) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(subscriptionRef);
    const raw = snap.exists ? snap.data() : {};
    // Miroir de l'autre mode (ex. abonnement TEST en production) : ni son
    // statut ni son Customer ne comptent ; il sera remplace a l'ecriture.
    const foreign = isForeignModeMirror(raw);
    const current = foreign ? {checkout_lock: raw.checkout_lock, foreign_mode: true} : raw;
    if (hasOpenSubscription(current)) {
      throw new functions.https.HttpsError("already-exists", "Vous avez deja un abonnement en cours.");
    }
    const lockExpiresAt = current.checkout_lock?.expires_at?.toMillis?.() || 0;
    if (lockExpiresAt > Date.now()) {
      throw new functions.https.HttpsError(
        "aborted",
        "Une souscription est deja en cours de preparation. Reessayez dans un instant.",
      );
    }
    tx.set(subscriptionRef, {
      merchant_user_id: db.doc(`users/${uid}`),
      checkout_lock: {token, expires_at: admin.firestore.Timestamp.fromMillis(Date.now() + kCheckoutLockMs)},
      ...(snap.exists ? {} : {created_at: admin.firestore.FieldValue.serverTimestamp()}),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return current;
  });
}

async function releaseCheckoutLock(db, subscriptionRef, token) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(subscriptionRef);
    if (snap.exists && snap.data().checkout_lock?.token === token) {
      tx.update(subscriptionRef, {checkout_lock: admin.firestore.FieldValue.delete()});
    }
  });
}

async function linkReferral(db, uid, referral) {
  const referralRef = db.collection(kMerchantReferralsCollection).doc(uid);
  if (!referral) return null;
  await db.runTransaction(async (tx) => {
    const referralSnap = await tx.get(referralRef);
    const configSnap = await tx.get(db.doc("app_config/merchant_referral"));
    if (!referralSnap.exists) {
      if (configSnap.data()?.enabled === false) {
        throw new functions.https.HttpsError("failed-precondition", "Le programme de parrainage est temporairement indisponible.");
      }
      // Lien parrain <-> commercant immuable : cree ici, jamais ecrase par
      // un Checkout ulterieur.
      tx.create(referralRef, {
        merchant_user_id: db.doc(`users/${uid}`),
        inviter_user_id: db.doc(referral.inviterUserPath),
        code: referral.code,
        status: "linked",
        reward_amount_cents: kRewardAmountCents,
        linked_at: admin.firestore.FieldValue.serverTimestamp(),
        first_payment_confirmed_at: null,
        eligible_at: null,
        subscription_amount_ht_cents: null,
        stripe_subscription_id: null,
        admin_decision: null,
        rejected_reason: null,
        cancelled_reason: null,
        paid_at: null,
        paid_reference: null,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else if (referralSnap.data().inviter_user_id?.path !== referral.inviterUserPath) {
      // Un commercant deja parraine ne peut pas etre re-parraine.
      throw new functions.https.HttpsError("already-exists", "Ce compte commercant est deja parraine.");
    }
  });
  return referralRef;
}

/**
 * Customer Stripe unique par compte commercant : celui du miroir, sinon
 * celui retrouve par metadata (miroir perdu), sinon cree avec une cle
 * d'idempotence (un retry apres coupure ne cree jamais un second Customer).
 */
async function resolveStripeCustomerId(stripe, uid, email, existingCustomerId) {
  if (existingCustomerId) {
    // Un miroir ancien peut porter un Customer cree avec une cle de l'autre
    // mode (inconnu de la cle actuelle) : verifie chez Stripe avant reemploi.
    try {
      const customer = await stripe.customers.retrieve(existingCustomerId);
      if (customer && !customer.deleted && customer.livemode === expectedLivemode()) return existingCustomerId;
    } catch (err) {
      if (err?.code !== "resource_missing") throw err;
    }
  }
  try {
    const found = await stripe.customers.search({query: `metadata['merchantUserId']:'${uid}'`, limit: 1});
    if (found?.data?.[0]?.id) return found.data[0].id;
  } catch (err) {
    // Recherche indisponible ou indexation en retard : la cle d'idempotence
    // reste la protection.
    console.warn("[MERCHANT_CHECKOUT] recherche Customer indisponible", err?.type || err?.code || "");
  }
  const emailHash = crypto.createHash("sha256").update(String(email || "")).digest("hex").slice(0, 16);
  const customer = await stripe.customers.create(
    {metadata: {merchantUserId: uid}, ...(email ? {email} : {})},
    {idempotencyKey: `merchant-customer-${uid}-${emailHash}`},
  );
  return customer.id;
}

async function assertNoOpenStripeSubscription(stripe, customerId) {
  const subscriptions = await stripe.subscriptions.list({customer: customerId, status: "all", limit: 20});
  const open = (subscriptions?.data || []).find((sub) => kOpenSubscriptionStatuses.includes(sub.status));
  if (open) {
    throw new functions.https.HttpsError(
      "already-exists",
      "Un abonnement existe deja pour ce compte. Utilisez « Gerer mon abonnement ».",
    );
  }
}

async function retrieveSessionOrNull(stripe, sessionId) {
  if (!sessionId) return null;
  try {
    return await stripe.checkout.sessions.retrieve(sessionId);
  } catch (_) {
    return null;
  }
}

async function createMerchantCheckoutSessionHandler(data, context) {
  const db = admin.firestore();
  const user = await assertMerchantCaller(db, context);
  const uid = context.auth.uid;
  // Un compte en attente de validation consulte son espace et les offres,
  // mais ne peut pas payer tant que l'equipe ne l'a pas valide.
  if (!isValidatedMerchant(user)) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Votre compte commercant est en cours de validation : la souscription sera possible des sa validation.",
      {reason: "pending_validation"},
    );
  }
  // Paiements fermes (defaut) : refus avant toute ecriture et tout appel Stripe.
  assertPaymentsOpen();
  const successUrl = assertAllowedReturnUrl(data?.successUrl, "successUrl");
  const cancelUrl = assertAllowedReturnUrl(data?.cancelUrl, "cancelUrl");
  const offerId = typeof data?.offerId === "string" ? data.offerId.trim() : "";

  // Le serveur seul decide du prix/produit : jamais de montant transmis par
  // le client, meme indirectement.
  const selection = await resolvePriceSelection(db, uid, offerId);
  const tax = getTaxConfigOrThrow();

  const referral = await resolveReferralCode(db, data?.referralCode);
  if (referral && referral.inviterUserPath === `users/${uid}`) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Vous ne pouvez pas utiliser votre propre code de parrainage.",
    );
  }

  const subscriptionRef = db.collection(kMerchantSubscriptionsCollection).doc(uid);
  const lockToken = crypto.randomUUID();
  const existing = await acquireCheckoutLock(db, subscriptionRef, uid, lockToken);

  try {
    const referralRef = await linkReferral(db, uid, referral);
    const stripe = stripeClientModule.getStripeClient();

    if (selection.catalogOffer) {
      const price = await stripe.prices.retrieve(selection.stripePriceId);
      assertStripePriceMatchesOffer(price, selection.catalogOffer);
    }

    const email = context.auth.token?.email || user.email || "";
    const stripeCustomerId = await resolveStripeCustomerId(stripe, uid, email, existing.stripe_customer_id || null);
    await assertNoOpenStripeSubscription(stripe, stripeCustomerId);

    const previousSession = await retrieveSessionOrNull(stripe, existing.stripe_checkout_session_id);
    if (previousSession?.status === "open") {
      const sameSelection = previousSession.metadata?.offerId === selection.offerIdForMetadata &&
        previousSession.metadata?.priceKey === selection.priceKey;
      if (sameSelection && previousSession.url) {
        await subscriptionRef.set({
          stripe_customer_id: stripeCustomerId,
          checkout_lock: admin.firestore.FieldValue.delete(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return {checkoutUrl: previousSession.url, reused: true};
      }
      await stripe.checkout.sessions.expire(previousSession.id);
    }

    const metadata = {
      merchantUserId: uid,
      offerId: selection.offerIdForMetadata,
      priceKey: selection.priceKey,
      referralCode: referral?.code || "",
    };
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: stripeCustomerId,
      client_reference_id: uid,
      line_items: [{...selection.lineItem, ...tax.lineItemExtra}],
      ...tax.sessionExtra,
      customer_update: {address: "auto", name: "auto"},
      billing_address_collection: "required",
      tax_id_collection: {enabled: true},
      locale: "fr",
      success_url: successUrl,
      cancel_url: cancelUrl,
      expires_at: Math.floor(Date.now() / 1000) + kCheckoutSessionLifetimeSeconds,
      subscription_data: {metadata},
      metadata,
    }, {idempotencyKey: `merchant-checkout-${uid}-${lockToken}`});

    await subscriptionRef.set({
      ...(existing.foreign_mode ? foreignModeResetFields(admin.firestore.FieldValue) : {}),
      stripe_customer_id: stripeCustomerId,
      // Mode de la cle serveur qui a cree le Customer (stripe_mode.js).
      stripe_mode: expectedLivemode() ? "live" : "test",
      stripe_checkout_session_id: session.id,
      pending_offer_id: selection.offerIdForMetadata,
      checkout_status: "open",
      checkout_expires_at: admin.firestore.Timestamp.fromMillis(
        (session.expires_at || Math.floor(Date.now() / 1000) + kCheckoutSessionLifetimeSeconds) * 1000,
      ),
      tax_mode: tax.mode,
      ...(referralRef ? {referral_id: referralRef} : {}),
      checkout_lock: admin.firestore.FieldValue.delete(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {checkoutUrl: session.url, reused: false};
  } catch (err) {
    await releaseCheckoutLock(db, subscriptionRef, lockToken).catch(() => {});
    if (err instanceof functions.https.HttpsError) throw err;
    console.error("[MERCHANT_CHECKOUT] echec", {uid, type: err?.type, code: err?.code});
    throw new functions.https.HttpsError("internal", "Paiement momentanement indisponible.");
  }
}

exports.createMerchantCheckoutSession = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
  .https.onCall(createMerchantCheckoutSessionHandler);

// Expose pour les tests (mock du client Stripe sans passer par onCall).
exports.createMerchantCheckoutSessionHandler = createMerchantCheckoutSessionHandler;
exports.hasOpenSubscription = hasOpenSubscription;

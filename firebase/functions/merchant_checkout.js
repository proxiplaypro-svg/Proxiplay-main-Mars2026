// Creation serveur d'une session Stripe Checkout pour l'abonnement annuel
// d'une enseigne (chantier paiement commercant, proxiplay.fr). Le client
// (site web) ne transmet jamais de prix/montant : uniquement des
// identifiants. Le serveur resout seul le prix Stripe autorise et attache
// les metadata necessaires a la reconciliation webhook.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {shopOwnerPath} = require("./merchant_ownership");
const {getOfferOrThrow, getStripePriceIdOrThrow} = require("./merchant_offers");
// Reference au module (pas destructure) : permet aux tests de remplacer
// stripeClientModule.getStripeClient par un mock apres le chargement de ce
// fichier, sans avoir a mocker require() lui-meme.
const stripeClientModule = require("./stripe_client");
const {stripeTaxRateId} = require("./stripe_secrets");

const kFunctionsRegion = "us-central1";
const kMerchantSubscriptionsCollection = "merchant_subscriptions";
const kMerchantReferralCodesCollection = "merchant_referral_codes";
const kMerchantReferralsCollection = "merchant_referrals";

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

async function createMerchantCheckoutSessionHandler(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const enseigneId = typeof data?.enseigneId === "string" ? data.enseigneId.trim() : "";
  const offerId = typeof data?.offerId === "string" ? data.offerId.trim() : "";
  const successUrl = typeof data?.successUrl === "string" ? data.successUrl : "";
  const cancelUrl = typeof data?.cancelUrl === "string" ? data.cancelUrl : "";
  if (!enseigneId || !offerId || !successUrl || !cancelUrl) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "enseigneId, offerId, successUrl et cancelUrl sont requis.",
    );
  }

  const db = admin.firestore();
  const uid = context.auth.uid;

  const enseigneRef = db.collection("enseignes").doc(enseigneId);
  const enseigneSnap = await enseigneRef.get();
  if (!enseigneSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Enseigne introuvable.");
  }
  const ownerPath = shopOwnerPath(enseigneSnap.data());
  if (ownerPath !== `users/${uid}`) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Vous n'etes pas proprietaire de cette enseigne.",
    );
  }

  // Le serveur seul decide du prix/produit : jamais de montant transmis par
  // le client, meme indirectement.
  const offer = getOfferOrThrow(offerId);
  const stripePriceId = getStripePriceIdOrThrow(offer);

  const referral = await resolveReferralCode(db, data?.referralCode);
  if (referral && referral.inviterUserPath === `users/${uid}`) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Vous ne pouvez pas utiliser votre propre code de parrainage.",
    );
  }

  // Abonnement existant actif/en cours : jamais un deuxieme Checkout pour la
  // meme enseigne (pas de double abonnement, pas de double prime).
  const subscriptionRef = db.collection(kMerchantSubscriptionsCollection).doc(enseigneId);
  const existingSubscriptionSnap = await subscriptionRef.get();
  const existingStatus = existingSubscriptionSnap.exists ?
    existingSubscriptionSnap.data().subscription_status : null;
  if (existingStatus && ["active", "trialing", "past_due"].includes(existingStatus)) {
    throw new functions.https.HttpsError(
      "already-exists",
      "Cette enseigne a deja un abonnement en cours.",
    );
  }

  // Lien parrain <-> commercant immuable : cree ici (create() echoue si le
  // document existe deja), jamais ecrase par un Checkout ulterieur.
  const referralRef = db.collection(kMerchantReferralsCollection).doc(enseigneId);
  if (referral) {
    const referralSnap = await referralRef.get();
    if (!referralSnap.exists) {
      await referralRef.create({
        enseigne_id: enseigneRef,
        merchant_user_id: db.doc(`users/${uid}`),
        inviter_user_id: db.doc(referral.inviterUserPath),
        code: referral.code,
        status: "linked",
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
      // Une enseigne deja parrainee (meme par un autre parrain) ne peut pas
      // etre re-parrainee : le lien est immuable une fois cree.
      throw new functions.https.HttpsError(
        "already-exists",
        "Cette enseigne est deja parrainee.",
      );
    }
  }

  const stripe = stripeClientModule.getStripeClient();

  let subscriptionDoc = existingSubscriptionSnap.exists ? existingSubscriptionSnap.data() : null;
  let stripeCustomerId = subscriptionDoc?.stripe_customer_id || null;
  if (!stripeCustomerId) {
    const customer = await stripe.customers.create({
      metadata: {enseigneId, merchantUserId: uid},
      name: enseigneSnap.data().name || undefined,
    });
    stripeCustomerId = customer.id;
  }

  const taxRate = stripeTaxRateId.value();
  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    customer: stripeCustomerId,
    line_items: [{
      price: stripePriceId,
      quantity: 1,
      ...(taxRate ? {tax_rates: [taxRate]} : {}),
    }],
    success_url: successUrl,
    cancel_url: cancelUrl,
    client_reference_id: enseigneId,
    subscription_data: {
      metadata: {
        enseigneId,
        merchantUserId: uid,
        offerId: offer.id,
        referralCode: referral?.code || "",
      },
    },
    metadata: {
      enseigneId,
      merchantUserId: uid,
      offerId: offer.id,
      referralCode: referral?.code || "",
    },
  });

  await subscriptionRef.set({
    enseigne_id: enseigneRef,
    merchant_user_id: db.doc(`users/${uid}`),
    offer_id: offer.id,
    stripe_customer_id: stripeCustomerId,
    stripe_checkout_session_id: session.id,
    subscription_status: "incomplete",
    referral_id: referral ? referralRef : null,
    created_at: existingSubscriptionSnap.exists ?
      existingSubscriptionSnap.data().created_at : admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {checkoutUrl: session.url};
}

exports.createMerchantCheckoutSession = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
  .https.onCall(createMerchantCheckoutSessionHandler);

// Expose pour les tests (mock du client Stripe sans passer par onCall).
exports.createMerchantCheckoutSessionHandler = createMerchantCheckoutSessionHandler;

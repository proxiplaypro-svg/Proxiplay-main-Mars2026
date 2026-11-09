// Vue "espace commercant" du site proxiplay.fr : le site n'a pas de comptes
// propres, il utilise les comptes Firebase Auth de l'app. Cette Callable
// verifie cote serveur que le compte connecte correspond bien a un profil
// commercant Firebase (users/{uid}, role commercant, compte non exclu), liste
// ses enseignes et renvoie l'etat de son abonnement (miroir ecrit par le
// webhook). Aucune donnee Stripe sensible, aucun appel Stripe ici.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {
  assertMerchantCaller,
  isManualAccessActive,
  isValidatedMerchant,
  paymentsOpen,
  stripeEntitlement,
} = require("./merchant_billing_access");
const {getPublicationAccess} = require("./merchant_publication_access");
const {publicOfferCatalog, offerLabel} = require("./merchant_offers");
const {isForeignModeMirror} = require("./stripe_mode");

const kFunctionsRegion = "us-central1";

const millis = (value) => (value?.toMillis ? value.toMillis() : null);

async function enseignesOf(db, uid) {
  const ownerRef = db.doc(`users/${uid}`);
  const [byOwner, byOwnerId] = await Promise.all([
    db.collection("enseignes").where("owner", "==", ownerRef).get(),
    db.collection("enseignes").where("owner_id", "==", ownerRef).get(),
  ]);
  const byId = new Map();
  [...byOwner.docs, ...byOwnerId.docs].forEach((doc) => byId.set(doc.id, {id: doc.id, name: doc.data().name || ""}));
  return [...byId.values()];
}

async function getMerchantBillingAccountHandler(data, context) {
  const db = admin.firestore();
  const user = await assertMerchantCaller(db, context);
  const uid = context.auth.uid;

  const [subscriptionSnap, customOfferSnap, enseignes] = await Promise.all([
    db.collection("merchant_subscriptions").doc(uid).get(),
    db.collection("merchant_custom_offers").doc(uid).get(),
    enseignesOf(db, uid),
  ]);
  const mirror = subscriptionSnap.exists ? subscriptionSnap.data() : {};
  // Abonnement de l'autre mode (ex. TEST en production) : presente comme
  // absent ; seuls les droits poses par l'Admin restent.
  const sub = isForeignModeMirror(mirror) ?
    {manual_access: mirror.manual_access, legacy_access: mirror.legacy_access} : mirror;
  const customOffer = customOfferSnap.exists ? customOfferSnap.data() : null;
  const status = sub.subscription_status || null;
  const entitlement = sub.stripe_entitlement || stripeEntitlement(status);
  const manualActive = isManualAccessActive(sub.manual_access);
  const offerId = sub.offer_id || null;
  const validated = isValidatedMerchant(user);
  const publication = await getPublicationAccess(db, uid);

  return {
    account: {
      uid,
      email: context.auth.token?.email || user.email || null,
      displayName: user.display_name || user.displayName || null,
      accountStatus: user.account_status || null,
      enseignes,
    },
    subscription: {
      status,
      entitlement,
      offerId,
      offerLabel: offerId === "custom" ? customOffer?.label || offerLabel("custom") : offerLabel(offerId),
      pendingOfferId: sub.pending_offer_id || null,
      checkoutStatus: sub.checkout_status || null,
      currentPeriodEnd: millis(sub.current_period_end),
      cancelAtPeriodEnd: sub.cancel_at_period_end === true,
      cancelAt: millis(sub.cancel_at),
      lastPaymentFailedAt: millis(sub.last_payment_failed_at),
      nextPaymentAttemptAt: millis(sub.next_payment_attempt_at),
      hasStripeCustomer: Boolean(sub.stripe_customer_id),
      testMode: sub.stripe_livemode === false ? true : null,
    },
    manualAccess: manualActive ? {active: true, until: millis(sub.manual_access.until)} : {active: false, until: null},
    // Droit de publier/relancer des jeux (meme calcul que firestore.rules).
    publication: {
      status: publication.status,
      canPublish: publication.canPublish,
      enforced: publication.enforced,
      allowed: publication.allowed,
      graceUntil: publication.status === "grace" ? publication.until : null,
      suspendedSince: publication.status === "suspended" ? publication.since || null : null,
    },
    hasPaidAccess: publication.canPublish,
    regularizeUrl: ["grace", "suspended"].includes(publication.status) ? sub.unpaid_invoice_url || null : null,
    validationPending: !validated,
    canCheckout: validated && paymentsOpen(),
    customOffer: customOffer ? {amountHtCents: customOffer.amount_ht_cents, label: customOffer.label || null} : null,
    offers: publicOfferCatalog(),
    paymentsEnabled: paymentsOpen(),
  };
}

exports.getMerchantBillingAccount = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 15, memory: "256MB"})
  .https.onCall(getMerchantBillingAccountHandler);

exports.getMerchantBillingAccountHandler = getMerchantBillingAccountHandler;

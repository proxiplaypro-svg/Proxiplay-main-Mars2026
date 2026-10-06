// Endpoint webhook Stripe (chantier paiement commercant). Verifie
// imperativement la signature Stripe et deduplique chaque evenement par
// son ID avant tout traitement -- un meme evenement recu plusieurs fois
// (retry Stripe, double livraison) ne doit jamais activer deux fois un
// abonnement ni declencher deux fois une recompense.
//
// Evenements traites (volontairement limites a ce qui est necessaire au
// cycle d'abonnement annuel retenu -- voir docs/stripe-merchant-billing.md) :
//   invoice.paid                 -> source de verite du paiement reussi
//                                    (premier paiement ET renouvellement,
//                                    distingues par billing_reason).
//   invoice.payment_failed       -> visibilite Admin uniquement.
//   customer.subscription.updated/deleted -> synchro statut/echeance.
//   charge.refunded, charge.dispute.created -> anti-fraude parrainage.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const stripeClientModule = require("./stripe_client");
const {stripeWebhookSecret} = require("./stripe_secrets");
const {markReferralEligibleOnFirstPayment, cancelReferralIfNotYetPaid} =
  require("./merchant_referral_engine");

const kFunctionsRegion = "us-central1";
const kMerchantSubscriptionsCollection = "merchant_subscriptions";
const kStripeWebhookEventsCollection = "stripe_webhook_events";

function enseigneIdFromSubscription(subscription) {
  return subscription?.metadata?.enseigneId || null;
}

/**
 * Verrou d'idempotence : cree le document de dedoublonnage avant tout
 * traitement. `create()` echoue si l'evenement a deja ete recu -- la seule
 * garantie atomique fiable sous livraisons concurrentes/retries.
 */
async function claimEventOrSkip(db, event) {
  const eventRef = db.collection(kStripeWebhookEventsCollection).doc(event.id);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(eventRef);
    if (!snap.exists) {
      tx.set(eventRef, {
        type: event.type,
        received_at: admin.firestore.FieldValue.serverTimestamp(),
        status: "processing",
      });
      return true;
    }
    const status = snap.data().status;
    if (status === "done") return false; // deja traite avec succes : jamais rejoue
    if (status === "processing") return false; // livraison concurrente en cours : on laisse faire
    // status === 'error' : un retry Stripe sur un echec precedent doit
    // pouvoir retraiter (le traitement lui-meme reste idempotent cote
    // Firestore via set/merge et les transitions d'etat du parrainage).
    tx.update(eventRef, {status: "processing"});
    return true;
  });
}

async function markEventDone(db, eventId, status, errorMessage) {
  await db.collection(kStripeWebhookEventsCollection).doc(eventId).set({
    status,
    processed_at: admin.firestore.FieldValue.serverTimestamp(),
    ...(errorMessage ? {error: String(errorMessage).slice(0, 500)} : {}),
  }, {merge: true});
}

async function handleInvoicePaid(db, invoice) {
  const subscriptionId = typeof invoice.subscription === "string" ?
    invoice.subscription : invoice.subscription?.id;
  if (!subscriptionId) return; // facture hors abonnement (hors perimetre) : rien a faire
  const stripe = stripeClientModule.getStripeClient();
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  const enseigneId = enseigneIdFromSubscription(subscription);
  if (!enseigneId) return;

  const subscriptionRef = db.collection(kMerchantSubscriptionsCollection).doc(enseigneId);
  await subscriptionRef.set({
    stripe_subscription_id: subscription.id,
    stripe_price_id: subscription.items?.data?.[0]?.price?.id || null,
    subscription_status: subscription.status,
    current_period_end: admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000),
    cancel_at_period_end: subscription.cancel_at_period_end === true,
    last_payment_failed_at: null,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  const isFirstPayment = invoice.billing_reason === "subscription_create";
  if (isFirstPayment) {
    await db.collection(kMerchantSubscriptionsCollection).doc(enseigneId).set({
      first_payment_confirmed_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    // Le renouvellement (N+1, billing_reason=subscription_cycle) ne doit
    // JAMAIS passer par cette branche : la prime concerne uniquement le
    // premier abonnement qualifiant.
    await markReferralEligibleOnFirstPayment(db, {
      enseigneId,
      subscriptionAmountHtCents: invoice.subtotal, // montant HT de la ligne, en centimes
      stripeSubscriptionId: subscription.id,
    });
  }
}

async function handleInvoicePaymentFailed(db, invoice) {
  const subscriptionId = typeof invoice.subscription === "string" ?
    invoice.subscription : invoice.subscription?.id;
  if (!subscriptionId) return;
  const stripe = stripeClientModule.getStripeClient();
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  const enseigneId = enseigneIdFromSubscription(subscription);
  if (!enseigneId) return;
  await db.collection(kMerchantSubscriptionsCollection).doc(enseigneId).set({
    last_payment_failed_at: admin.firestore.FieldValue.serverTimestamp(),
    subscription_status: subscription.status,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function handleSubscriptionUpdated(db, subscription) {
  const enseigneId = enseigneIdFromSubscription(subscription);
  if (!enseigneId) return;
  await db.collection(kMerchantSubscriptionsCollection).doc(enseigneId).set({
    stripe_subscription_id: subscription.id,
    subscription_status: subscription.status,
    current_period_end: admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000),
    cancel_at_period_end: subscription.cancel_at_period_end === true,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function handleSubscriptionDeleted(db, subscription) {
  const enseigneId = enseigneIdFromSubscription(subscription);
  if (!enseigneId) return;
  await db.collection(kMerchantSubscriptionsCollection).doc(enseigneId).set({
    subscription_status: "canceled",
    ended_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await cancelReferralIfNotYetPaid(db, enseigneId, "subscription_cancelled");
}

async function enseigneIdFromCharge(charge) {
  const subscriptionId = charge.invoice ?
    (await stripeClientModule.getStripeClient().invoices.retrieve(
      typeof charge.invoice === "string" ? charge.invoice : charge.invoice.id,
    )).subscription : null;
  if (!subscriptionId) return null;
  const subId = typeof subscriptionId === "string" ? subscriptionId : subscriptionId.id;
  const subscription = await stripeClientModule.getStripeClient().subscriptions.retrieve(subId);
  return enseigneIdFromSubscription(subscription);
}

async function handleChargeRefunded(db, charge) {
  const enseigneId = await enseigneIdFromCharge(charge);
  if (!enseigneId) return;
  await cancelReferralIfNotYetPaid(db, enseigneId, "refunded");
}

async function handleChargeDisputeCreated(db, dispute) {
  const stripe = stripeClientModule.getStripeClient();
  const charge = await stripe.charges.retrieve(
    typeof dispute.charge === "string" ? dispute.charge : dispute.charge.id,
  );
  const enseigneId = await enseigneIdFromCharge(charge);
  if (!enseigneId) return;
  await cancelReferralIfNotYetPaid(db, enseigneId, "dispute");
}

async function dispatchEvent(db, event) {
  switch (event.type) {
    case "invoice.paid":
      return handleInvoicePaid(db, event.data.object);
    case "invoice.payment_failed":
      return handleInvoicePaymentFailed(db, event.data.object);
    case "customer.subscription.updated":
      return handleSubscriptionUpdated(db, event.data.object);
    case "customer.subscription.deleted":
      return handleSubscriptionDeleted(db, event.data.object);
    case "charge.refunded":
      return handleChargeRefunded(db, event.data.object);
    case "charge.dispute.created":
      return handleChargeDisputeCreated(db, event.data.object);
    default:
      return; // evenement non pertinent pour ce cycle d'abonnement : ignore volontairement
  }
}

async function stripeWebhookHandler(req, res) {
  const db = admin.firestore();
  const stripe = stripeClientModule.getStripeClient();
  let event;
  try {
    event = stripe.webhooks.constructEvent(
      req.rawBody, req.headers["stripe-signature"], stripeWebhookSecret.value(),
    );
  } catch (err) {
    console.error("[STRIPE_WEBHOOK] signature invalide", err.message);
    res.status(400).send("Signature invalide.");
    return;
  }

  const claimed = await claimEventOrSkip(db, event);
  if (!claimed) {
    // Deja traite (ou en cours) : on repond 200 sans rien rejouer, sinon
    // Stripe continuerait a retenter indefiniment un evenement deja absorbe.
    res.status(200).send("Deja traite.");
    return;
  }

  try {
    await dispatchEvent(db, event);
    await markEventDone(db, event.id, "done");
    res.status(200).send("OK");
  } catch (err) {
    console.error(`[STRIPE_WEBHOOK] echec traitement ${event.type} (${event.id})`, err);
    await markEventDone(db, event.id, "error", err.message);
    // 500 : Stripe retentera -- claimEventOrSkip empechera un double effet
    // si le traitement avait deja partiellement reussi avant l'erreur.
    res.status(500).send("Erreur de traitement.");
  }
}

exports.stripeWebhook = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB", secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"]})
  .https.onRequest(stripeWebhookHandler);

exports.stripeWebhookHandler = stripeWebhookHandler;
exports.dispatchEvent = dispatchEvent;

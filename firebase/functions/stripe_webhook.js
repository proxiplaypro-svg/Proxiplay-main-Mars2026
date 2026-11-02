// Endpoint webhook Stripe (chantier paiement commercant). Verifie
// imperativement la signature Stripe et deduplique chaque evenement par
// son ID avant tout traitement -- un meme evenement recu plusieurs fois
// (retry Stripe, double livraison) ne doit jamais activer deux fois un
// abonnement ni declencher deux fois une recompense.
//
// Ordre d'arrivee : Stripe ne garantit pas l'ordre des evenements. Le
// payload d'un evenement n'est donc jamais recopie tel quel : l'abonnement
// est TOUJOURS relu chez Stripe (etat courant) avant d'etre reflete dans
// merchant_subscriptions. Un evenement ancien recu en retard ecrit donc
// l'etat actuel, jamais un etat perime. Les champs propres a un evenement
// (dernier paiement reussi / echoue) sont gardes par event.created.
//
// Association au commercant : metadata de l'abonnement (posee au Checkout
// par le serveur), a defaut metadata du Customer, recoupees avec le miroir
// Firestore (stripe_customer_id). Toute contradiction est ignoree et tracee,
// jamais appliquee a un compte au hasard.
//
// Evenements traites (voir docs/stripe-merchant-billing.md) :
//   checkout.session.completed / expired
//   customer.subscription.created / updated / deleted / paused / resumed
//   invoice.paid             -> premier paiement ET renouvellement
//   invoice.payment_failed   -> echec (relances Stripe)
//   charge.refunded, charge.dispute.created -> anti-fraude parrainage.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const stripeClientModule = require("./stripe_client");
const {stripeWebhookSecret} = require("./stripe_secrets");
const {markReferralEligibleOnFirstPayment, cancelReferralIfNotYetPaid} =
  require("./merchant_referral_engine");
const {kOpenSubscriptionStatuses, stripeEntitlement} = require("./merchant_billing_access");
const {kGraceStatuses, graceUntilMs, computePublicationAccess} = require("./merchant_publication_access");

const kFunctionsRegion = "us-central1";
const kMerchantSubscriptionsCollection = "merchant_subscriptions";
const kStripeWebhookEventsCollection = "stripe_webhook_events";
// Au-dela, un traitement "processing" est considere comme interrompu
// (timeout, crash) et peut etre repris par un retry Stripe.
const kProcessingLeaseMs = 5 * 60 * 1000;

const isOpenStatus = (status) => kOpenSubscriptionStatuses.includes(status);
const idOf = (value) => (typeof value === "string" ? value : value?.id || null);
const tsFromSeconds = (seconds) =>
  (typeof seconds === "number" && seconds > 0 ? admin.firestore.Timestamp.fromMillis(seconds * 1000) : null);

/**
 * Verrou d'idempotence. Renvoie :
 *   "claimed" -> a traiter maintenant ;
 *   "done"    -> deja traite avec succes, jamais rejoue ;
 *   "busy"    -> une autre livraison le traite (bail en cours).
 * Un bail expire (exécution interrompue) ou un echec precedent est repris.
 */
async function claimEventOrSkip(db, event) {
  const eventRef = db.collection(kStripeWebhookEventsCollection).doc(event.id);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(eventRef);
    const nowMs = Date.now();
    const lease = admin.firestore.Timestamp.fromMillis(nowMs + kProcessingLeaseMs);
    if (!snap.exists) {
      tx.set(eventRef, {
        type: event.type,
        event_created: event.created || null,
        livemode: event.livemode === true,
        received_at: admin.firestore.FieldValue.serverTimestamp(),
        status: "processing",
        lease_expires_at: lease,
        attempts: 1,
      });
      return "claimed";
    }
    const current = snap.data();
    if (current.status === "done") return "done";
    if (current.status === "processing" && (current.lease_expires_at?.toMillis?.() || 0) > nowMs) {
      return "busy";
    }
    tx.update(eventRef, {
      status: "processing",
      lease_expires_at: lease,
      attempts: admin.firestore.FieldValue.increment(1),
    });
    return "claimed";
  });
}

async function markEvent(db, eventId, status, details = {}) {
  await db.collection(kStripeWebhookEventsCollection).doc(eventId).set({
    status,
    processed_at: admin.firestore.FieldValue.serverTimestamp(),
    lease_expires_at: admin.firestore.FieldValue.delete(),
    ...(details.outcome ? {outcome: details.outcome} : {}),
    ...(details.merchantUserId ? {merchant_user_id: details.merchantUserId} : {}),
    ...(details.error ? {error: String(details.error).slice(0, 300)} : {}),
  }, {merge: true});
}

/**
 * Retrouve le commercant d'un abonnement Stripe. Renvoie {merchantUserId}
 * ou {outcome} si l'association est impossible ou contradictoire.
 */
async function resolveMerchantForSubscription(db, stripe, subscription) {
  const customerId = idOf(subscription.customer);
  let fromStripe = subscription.metadata?.merchantUserId || null;
  if (!fromStripe && customerId) {
    const customer = await stripe.customers.retrieve(customerId);
    fromStripe = customer && !customer.deleted ? customer.metadata?.merchantUserId || null : null;
  }
  let fromMirror = null;
  if (customerId) {
    const byCustomer = await db.collection(kMerchantSubscriptionsCollection)
      .where("stripe_customer_id", "==", customerId).limit(2).get();
    if (byCustomer.size > 1) return {outcome: "ignored_customer_shared"};
    fromMirror = byCustomer.docs[0]?.id || null;
  }
  if (fromStripe && fromMirror && fromStripe !== fromMirror) {
    return {outcome: "ignored_merchant_conflict"};
  }
  const merchantUserId = fromStripe || fromMirror;
  if (!merchantUserId) return {outcome: "ignored_unknown_merchant"};
  return {merchantUserId, customerId};
}

/**
 * Delai de grace d'un renouvellement impaye : il demarre a l'echeance
 * impayee (debut de la periode non reglee) et n'est jamais repousse ; il
 * disparait des que Stripe confirme la regularisation (statut actif).
 */
function graceFields(subscription, current, periodStartSeconds) {
  if (kGraceStatuses.includes(subscription.status)) {
    const sameSubscription = current.stripe_subscription_id === subscription.id;
    const existingMs = sameSubscription ? current.grace_until?.toMillis?.() ?? null : null;
    const dueMs = typeof periodStartSeconds === "number" ? periodStartSeconds * 1000 : Date.now();
    const untilMs = graceUntilMs(existingMs, dueMs);
    return {
      grace_until: admin.firestore.Timestamp.fromMillis(untilMs),
      grace_started_at: sameSubscription && current.grace_started_at ?
        current.grace_started_at : admin.firestore.Timestamp.fromMillis(dueMs),
    };
  }
  return {grace_until: null, grace_started_at: null};
}

function mirrorFields(db, merchantUserId, subscription, current, fetchedAtMs, eventId) {
  const item = subscription.items?.data?.[0];
  const periodStart = subscription.current_period_start ?? item?.current_period_start;
  const periodEnd = subscription.current_period_end ?? item?.current_period_end;
  const publication = computePublicationAccess({
    ...current, ...graceFields(subscription, current, periodStart), subscription_status: subscription.status,
  });
  return {
    ...graceFields(subscription, current, periodStart),
    // Statut explicite au moment de la synchronisation (le calcul fait foi a
    // chaque lecture : la grace expire avec le temps, sans evenement Stripe).
    publication_access_status: publication.status,
    merchant_user_id: db.doc(`users/${merchantUserId}`),
    stripe_customer_id: idOf(subscription.customer),
    stripe_subscription_id: subscription.id,
    stripe_price_id: item?.price?.id || null,
    offer_id: subscription.metadata?.offerId || current.offer_id || null,
    subscription_status: subscription.status,
    stripe_entitlement: stripeEntitlement(subscription.status),
    current_period_start: tsFromSeconds(periodStart),
    current_period_end: tsFromSeconds(periodEnd),
    cancel_at_period_end: subscription.cancel_at_period_end === true,
    cancel_at: tsFromSeconds(subscription.cancel_at),
    canceled_at: tsFromSeconds(subscription.canceled_at),
    ended_at: tsFromSeconds(subscription.ended_at),
    stripe_livemode: subscription.livemode === true,
    stripe_fetched_at_ms: fetchedAtMs,
    stripe_synced_at: admin.firestore.FieldValue.serverTimestamp(),
    last_stripe_event_id: eventId,
    ...(current.checkout_status === "open" && isOpenStatus(subscription.status) ?
      {checkout_status: "completed"} : {}),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Relit l'abonnement chez Stripe et le reflete dans le miroir du
 * commercant. N'ecrit jamais manual_access ni les champs de parrainage.
 * Renvoie {outcome, merchantUserId, tracked, subscription}.
 */
async function syncSubscriptionFromStripe(db, subscriptionId, eventId) {
  const stripe = stripeClientModule.getStripeClient();
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  const fetchedAtMs = Date.now();
  if (!subscription?.id) return {outcome: "ignored_subscription_not_found", tracked: false};

  const resolved = await resolveMerchantForSubscription(db, stripe, subscription);
  if (!resolved.merchantUserId) {
    console.warn("[STRIPE_WEBHOOK] association impossible", {subscriptionId, outcome: resolved.outcome});
    return {outcome: resolved.outcome, tracked: false};
  }
  const {merchantUserId, customerId} = resolved;
  const ref = db.collection(kMerchantSubscriptionsCollection).doc(merchantUserId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? snap.data() : {};
    if (current.stripe_customer_id && customerId && current.stripe_customer_id !== customerId) {
      console.warn("[STRIPE_WEBHOOK] Customer different du miroir", {merchantUserId, subscriptionId});
      return {outcome: "ignored_customer_mismatch", merchantUserId, tracked: false};
    }

    const trackedId = current.stripe_subscription_id || null;
    if (trackedId && trackedId !== subscription.id) {
      const trackedOpen = isOpenStatus(current.subscription_status);
      const incomingOpen = isOpenStatus(subscription.status);
      if (trackedOpen || !incomingOpen) {
        const duplicate = trackedOpen && incomingOpen;
        tx.set(ref, {
          other_subscriptions: {[subscription.id]: {
            status: subscription.status,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          }},
          ...(duplicate ? {duplicate_subscription_alert: true} : {}),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        if (duplicate) {
          console.warn("[STRIPE_WEBHOOK] second abonnement ouvert detecte", {merchantUserId, subscriptionId});
        }
        return {
          outcome: duplicate ? "duplicate_subscription" : "ignored_untracked_subscription",
          merchantUserId,
          tracked: false,
        };
      }
      // L'abonnement suivi est termine et un nouvel abonnement ouvert
      // arrive : il devient l'abonnement suivi.
    }

    if (trackedId === subscription.id && (current.stripe_fetched_at_ms || 0) > fetchedAtMs) {
      return {outcome: "ignored_stale", merchantUserId, tracked: true, subscription};
    }

    tx.set(ref, {
      ...mirrorFields(db, merchantUserId, subscription, current, fetchedAtMs, eventId),
      ...(snap.exists ? {} : {created_at: admin.firestore.FieldValue.serverTimestamp()}),
    }, {merge: true});
    return {outcome: "synced", merchantUserId, tracked: true, subscription};
  });
}

/**
 * Champs propres a un evenement de paiement : appliques seulement si
 * l'evenement n'est pas plus ancien que le dernier deja applique.
 */
async function applyPaymentEvent(db, merchantUserId, eventCreated, fields) {
  const ref = db.collection(kMerchantSubscriptionsCollection).doc(merchantUserId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const last = snap.exists ? snap.data().last_payment_event_created || 0 : 0;
    if ((eventCreated || 0) < last) return false;
    tx.set(ref, {
      ...fields,
      last_payment_event_created: eventCreated || 0,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return true;
  });
}

function invoiceSubscriptionId(invoice) {
  return idOf(invoice.subscription) || idOf(invoice.parent?.subscription_details?.subscription);
}

async function handleInvoicePaid(db, event) {
  const invoice = event.data.object;
  const subscriptionId = invoiceSubscriptionId(invoice);
  if (!subscriptionId) return {outcome: "ignored_no_subscription"};
  const sync = await syncSubscriptionFromStripe(db, subscriptionId, event.id);
  if (!sync.tracked) return sync;
  const {merchantUserId} = sync;

  const paidAtSeconds = invoice.status_transitions?.paid_at || event.created;
  await applyPaymentEvent(db, merchantUserId, event.created, {
    last_payment_succeeded_at: tsFromSeconds(paidAtSeconds),
    last_invoice_id: invoice.id || null,
    last_payment_failed_at: null,
    unpaid_invoice_url: null,
    payment_attempt_count: 0,
    next_payment_attempt_at: null,
    ...(invoice.billing_reason === "subscription_cycle" ?
      {last_renewal_paid_at: tsFromSeconds(paidAtSeconds)} : {}),
  });

  // Le renouvellement (N+1, billing_reason=subscription_cycle) ne doit
  // JAMAIS passer par cette branche : la prime concerne uniquement le
  // premier abonnement qualifiant.
  if (invoice.billing_reason === "subscription_create") {
    const ref = db.collection(kMerchantSubscriptionsCollection).doc(merchantUserId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.data()?.first_payment_confirmed_at) {
        tx.set(ref, {first_payment_confirmed_at: tsFromSeconds(paidAtSeconds)}, {merge: true});
      }
    });
    await markReferralEligibleOnFirstPayment(db, {
      merchantUserId,
      subscriptionAmountHtCents: invoice.subtotal, // montant HT de la ligne, en centimes
      stripeSubscriptionId: subscriptionId,
    });
  }
  return {outcome: invoice.billing_reason === "subscription_cycle" ? "renewal_paid" : "payment_confirmed", merchantUserId};
}

async function handleInvoicePaymentFailed(db, event) {
  const invoice = event.data.object;
  const subscriptionId = invoiceSubscriptionId(invoice);
  if (!subscriptionId) return {outcome: "ignored_no_subscription"};
  const sync = await syncSubscriptionFromStripe(db, subscriptionId, event.id);
  if (!sync.tracked) return sync;
  // Aucune donnee bancaire : uniquement date, compteur de tentatives et
  // prochaine relance Stripe.
  await applyPaymentEvent(db, sync.merchantUserId, event.created, {
    last_payment_failed_at: tsFromSeconds(event.created),
    last_failed_invoice_id: invoice.id || null,
    // Page Stripe hebergee de la facture impayee : permet au commercant de
    // regulariser (lisible uniquement par lui-meme et l'Admin).
    unpaid_invoice_url: invoice.hosted_invoice_url || null,
    payment_attempt_count: typeof invoice.attempt_count === "number" ? invoice.attempt_count : null,
    next_payment_attempt_at: tsFromSeconds(invoice.next_payment_attempt),
  });
  return {outcome: "payment_failed", merchantUserId: sync.merchantUserId};
}

async function handleSubscriptionEvent(db, event) {
  const subscription = event.data.object;
  const sync = await syncSubscriptionFromStripe(db, subscription.id, event.id);
  if (sync.tracked && event.type === "customer.subscription.deleted" &&
      sync.subscription?.status === "canceled") {
    await cancelReferralIfNotYetPaid(db, sync.merchantUserId, "subscription_cancelled");
  }
  return sync;
}

async function handleCheckoutSessionCompleted(db, event) {
  const session = event.data.object;
  if (session.mode !== "subscription") return {outcome: "ignored_not_subscription"};
  const subscriptionId = idOf(session.subscription);
  if (!subscriptionId) return {outcome: "ignored_no_subscription"};
  const sync = await syncSubscriptionFromStripe(db, subscriptionId, event.id);
  const expected = session.client_reference_id || session.metadata?.merchantUserId || null;
  if (sync.merchantUserId && expected && sync.merchantUserId !== expected) {
    console.warn("[STRIPE_WEBHOOK] session et abonnement rattaches a deux comptes", {sessionId: session.id});
  }
  return sync;
}

async function handleCheckoutSessionExpired(db, event) {
  const session = event.data.object;
  const merchantUserId = session.client_reference_id || session.metadata?.merchantUserId;
  if (!merchantUserId) return {outcome: "ignored_unknown_merchant"};
  const ref = db.collection(kMerchantSubscriptionsCollection).doc(merchantUserId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.data().stripe_checkout_session_id === session.id &&
        snap.data().checkout_status === "open") {
      tx.update(ref, {checkout_status: "expired", updated_at: admin.firestore.FieldValue.serverTimestamp()});
    }
  });
  return {outcome: "checkout_expired", merchantUserId};
}

async function merchantUserIdFromCharge(db, charge) {
  const invoiceId = idOf(charge.invoice);
  if (!invoiceId) return null;
  const stripe = stripeClientModule.getStripeClient();
  const invoice = await stripe.invoices.retrieve(invoiceId);
  const subscriptionId = invoiceSubscriptionId(invoice || {});
  if (!subscriptionId) return null;
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  const resolved = await resolveMerchantForSubscription(db, stripe, subscription);
  return resolved.merchantUserId || null;
}

async function handleChargeRefunded(db, event) {
  const merchantUserId = await merchantUserIdFromCharge(db, event.data.object);
  if (!merchantUserId) return {outcome: "ignored_unknown_merchant"};
  await cancelReferralIfNotYetPaid(db, merchantUserId, "refunded");
  return {outcome: "refund_recorded", merchantUserId};
}

async function handleChargeDisputeCreated(db, event) {
  const dispute = event.data.object;
  const charge = await stripeClientModule.getStripeClient().charges.retrieve(idOf(dispute.charge));
  const merchantUserId = await merchantUserIdFromCharge(db, charge);
  if (!merchantUserId) return {outcome: "ignored_unknown_merchant"};
  await cancelReferralIfNotYetPaid(db, merchantUserId, "dispute");
  return {outcome: "dispute_recorded", merchantUserId};
}

async function dispatchEvent(db, event) {
  switch (event.type) {
    case "checkout.session.completed":
      return handleCheckoutSessionCompleted(db, event);
    case "checkout.session.expired":
      return handleCheckoutSessionExpired(db, event);
    case "customer.subscription.created":
    case "customer.subscription.updated":
    case "customer.subscription.deleted":
    case "customer.subscription.paused":
    case "customer.subscription.resumed":
      return handleSubscriptionEvent(db, event);
    case "invoice.paid":
      return handleInvoicePaid(db, event);
    case "invoice.payment_failed":
      return handleInvoicePaymentFailed(db, event);
    case "charge.refunded":
      return handleChargeRefunded(db, event);
    case "charge.dispute.created":
      return handleChargeDisputeCreated(db, event);
    default:
      return {outcome: "ignored_event_type"}; // non pertinent pour ce cycle d'abonnement
  }
}

async function stripeWebhookHandler(req, res) {
  if (req.method && req.method !== "POST") {
    res.status(405).send("Methode non autorisee.");
    return;
  }
  const secret = stripeWebhookSecret.value();
  if (!secret) {
    console.error("[STRIPE_WEBHOOK] STRIPE_WEBHOOK_SECRET absent");
    res.status(500).send("Configuration incomplete.");
    return;
  }
  const db = admin.firestore();
  let event;
  try {
    const stripe = stripeClientModule.getStripeClient();
    event = stripe.webhooks.constructEvent(req.rawBody, req.headers["stripe-signature"], secret);
  } catch (err) {
    console.error("[STRIPE_WEBHOOK] signature invalide ou configuration refusee", err.message);
    res.status(400).send("Signature invalide.");
    return;
  }

  const claim = await claimEventOrSkip(db, event);
  if (claim === "done") {
    // Deja traite : 200 sans rien rejouer, sinon Stripe retenterait
    // indefiniment un evenement deja absorbe.
    res.status(200).send("Deja traite.");
    return;
  }
  if (claim === "busy") {
    // Une autre livraison le traite : non-2xx pour que Stripe retente plus
    // tard, au cas ou ce traitement concurrent echouerait.
    res.status(409).send("Traitement en cours.");
    return;
  }

  try {
    const result = await dispatchEvent(db, event);
    await markEvent(db, event.id, "done", result || {});
    res.status(200).send("OK");
  } catch (err) {
    console.error(`[STRIPE_WEBHOOK] echec traitement ${event.type} (${event.id})`, err.message);
    await markEvent(db, event.id, "error", {error: err.message});
    // 500 : Stripe retentera ; le traitement relit l'etat Stripe et reste
    // idempotent (set/merge, transitions de parrainage gardees).
    res.status(500).send("Erreur de traitement.");
  }
}

exports.stripeWebhook = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB", secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"]})
  .https.onRequest(stripeWebhookHandler);

exports.stripeWebhookHandler = stripeWebhookHandler;
exports.dispatchEvent = dispatchEvent;
exports.claimEventOrSkip = claimEventOrSkip;

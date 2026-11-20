// Phase 1, tranche 2a, lot 1.8 : traitement par le webhook Stripe des
// abonnements souscrits par contrat (metadata.contractId), un par enseigne.
//
// Le webhook existant (stripe_webhook.js) relit l'abonnement chez Stripe
// (version d'API epinglee 2024-06-20 ; l'endpoint emet en
// 2026-10-28.endive) et, s'il porte metadata.contractId, delegue ici : le
// miroir V1 par compte (merchant_subscriptions) n'est jamais ecrit pour un
// contrat. Toute decision repose sur des objets relus par l'API, jamais sur
// le contenu du payload (seuls les identifiants en sont lus).
//
// - Paiement initial (checkout.session.completed ou invoice.paid de
//   creation) : contrat payment_invited -> active (art. 8.2), une seule fois.
//   Contrat clos, retracte, refuse, en delai de retractation, inconnu, ou
//   second abonnement : remboursement integral (avoir si l'option est
//   activee), annulation immediate, jamais de reactivation (art. 8.1).
// - Miroir enseigne_subscriptions/{enseigneId} : statut, periode,
//   desactivation, delai de grace de 15 jours (art. 11).
// - Echec de prelevement d'un renouvellement : notification immediate au
//   commercant (art. 11), une fois par facture. Relances J+5 et J+10 : lot 1.9.

const admin = require("firebase-admin");
const stripeClientModule = require("./stripe_client");
const {expectedLivemode} = require("./stripe_mode");
const {kGraceStatuses, graceUntilMs} = require("./merchant_publication_access");
const {
  kContractsCollection,
  kStates,
  assertTransition,
  readContractsConfig,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

const kEnseigneSubscriptionsCollection = "enseigne_subscriptions";
const kUnmatchedEventsCollection = "stripe_unmatched_events";

// Politique de remboursement automatique (decision du 2026-11-20) : un
// paiement initial n'est rembourse et annule que si le contrat EXISTE et est
// dans l'un de ces etats (actif : seulement avec un autre abonnement que
// celui suivi). Contrat inconnu, enseigne differente, submitted, confirmed
// ou tout autre etat : aucune action sur l'argent, trace et alerte admin.
const kAutoRefundStates = Object.freeze([
  kStates.CLOSED_UNPAID, kStates.WITHDRAWN, kStates.REFUSED, kStates.ENDED, kStates.WITHDRAWAL_PENDING, kStates.ACTIVE,
]);

function idOf(value) {
  return typeof value === "string" ? value : value?.id || null;
}

function tsFromSeconds(seconds) {
  return typeof seconds === "number" ? admin.firestore.Timestamp.fromMillis(seconds * 1000) : null;
}

function periodOf(subscription) {
  const item = subscription.items?.data?.[0];
  return {
    start: subscription.current_period_start ?? item?.current_period_start ?? null,
    end: subscription.current_period_end ?? item?.current_period_end ?? null,
  };
}

/**
 * Rembourse integralement les factures payees d'un abonnement et l'annule
 * immediatement, sans prorata. Avoir (credit note) si l'option est activee
 * dans app_config/merchant_contracts (credit_notes_enabled, decision du
 * comptable). Idempotent (cles par facture et par abonnement).
 */
/**
 * Rembourse une facture payee, integralement ou en partie (amountCents),
 * par avoir si l'option est activee (credit_notes_enabled), sinon par
 * remboursement du paiement. Cle d'idempotence fournie par l'appelant.
 */
async function refundInvoice(stripe, {invoice, amountCents = null, contractId, reason, creditNotes, keySuffix = ""}) {
  const amount = amountCents === null ? invoice.amount_paid : amountCents;
  if (!Number.isInteger(amount) || amount <= 0 || amount > invoice.amount_paid) {
    throw new Error(`montant de remboursement invalide (${amount} pour ${invoice.amount_paid})`);
  }
  const full = amount === invoice.amount_paid;
  if (creditNotes) {
    const note = await stripe.creditNotes.create({
      invoice: invoice.id,
      amount,
      refund_amount: amount,
      reason: "order_change",
      memo: `${full ? "Remboursement intégral" : "Remboursement partiel"} (${reason})`,
      metadata: {contractId, reason},
    }, {idempotencyKey: `credit-note-${invoice.id}${keySuffix}`});
    return {invoice_id: invoice.id, credit_note_id: note.id, refund_id: idOf(note.refund), amount};
  }
  const refund = await stripe.refunds.create({
    payment_intent: idOf(invoice.payment_intent),
    ...(full ? {} : {amount}),
    reason: "requested_by_customer",
    metadata: {contractId, reason, invoiceId: invoice.id},
  }, {idempotencyKey: `refund-${invoice.id}${keySuffix}`});
  return {invoice_id: invoice.id, refund_id: refund.id, amount};
}

/**
 * Art. 9, facture de renouvellement non payee : le statut est TOUJOURS relu
 * chez Stripe avant d'agir, jamais deduit d'un code d'erreur (vide quand la
 * facture est payee, essai du 2026-11-20). Brouillon : auto_advance=false puis
 * finalisation sans prelevement ; ouverte : annulation (void). Renvoie le
 * statut final relu : "void", "paid" (prelevement passe entre-temps : a
 * rembourser par l'appelant), "uncollectible", ou un autre statut si
 * l'annulation n'a pas abouti (l'appelant n'annule alors rien).
 */
async function settleRenewalInvoice(stripe, invoiceId) {
  const steps = [];
  let invoice = await stripe.invoices.retrieve(invoiceId);
  if (invoice?.status === "draft") {
    await stripe.invoices.update(invoiceId, {auto_advance: false}, {idempotencyKey: `no-advance-${invoiceId}`});
    steps.push("auto_advance_false");
    await stripe.invoices.finalizeInvoice(invoiceId, {auto_advance: false}, {idempotencyKey: `finalize-${invoiceId}`});
    steps.push("finalized");
    invoice = await stripe.invoices.retrieve(invoiceId);
  }
  if (invoice?.status === "open") {
    try {
      await stripe.invoices.voidInvoice(invoiceId, {}, {idempotencyKey: `void-${invoiceId}`});
      steps.push("voided");
    } catch (error) {
      steps.push("void_refused");
    }
    invoice = await stripe.invoices.retrieve(invoiceId);
  }
  return {status: invoice?.status || null, invoice, steps};
}

async function refundAndCancel(db, stripe, {contractId, subscriptionId, reason}) {
  const config = await readContractsConfig(db);
  const invoices = (await stripe.invoices.list({subscription: subscriptionId, limit: 20})).data || [];
  const records = [];
  for (const invoice of invoices.filter((inv) => inv.status === "paid" && (inv.amount_paid || 0) > 0)) {
    records.push(await refundInvoice(stripe, {invoice, contractId, reason, creditNotes: config.creditNotesEnabled}));
  }
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  if (subscription && !["canceled", "incomplete_expired"].includes(subscription.status)) {
    await stripe.subscriptions.cancel(subscriptionId, {prorate: false, invoice_now: false},
      {idempotencyKey: `cancel-${subscriptionId}`});
  }
  if (contractId) {
    await internalRef(db, contractId).set({refunds: admin.firestore.FieldValue.arrayUnion(...records.map((r) => ({
      ...r, reason, subscription_id: subscriptionId, at: admin.firestore.Timestamp.now(),
    })))}, {merge: true}).catch(() => null);
  }
  return records;
}

function graceFor(subscription, current, observedAtMs) {
  if (!kGraceStatuses.includes(subscription.status)) return {grace_until: null, grace_started_at: null};
  const same = current.stripe_subscription_id === subscription.id;
  const existing = same ? millisOf(current.grace_until) : null;
  const periodStartMs = periodOf(subscription).start ? periodOf(subscription).start * 1000 : observedAtMs;
  const dueMs = Math.max(periodStartMs, observedAtMs);
  return {
    grace_until: admin.firestore.Timestamp.fromMillis(graceUntilMs(existing, dueMs)),
    grace_started_at: same && current.grace_started_at ? current.grace_started_at : admin.firestore.Timestamp.fromMillis(dueMs),
  };
}

/**
 * Miroir de l'abonnement suivi par le contrat. Un abonnement non suivi
 * (paiement tardif rembourse, doublon) n'est que note a part.
 */
async function syncContractSubscription(db, subscription, eventId) {
  const contractId = subscription.metadata?.contractId;
  const contractSnap = await db.collection(kContractsCollection).doc(contractId).get();
  // Non rattachable : trace et alerte ecrites par le webhook (une fois par evenement).
  if (!contractSnap.exists) return {outcome: "contract_unknown", contractId, subscriptionId: subscription.id};
  const contract = contractSnap.data();
  const tracked = (await internalRef(db, contractId).get()).data()?.billing?.stripe_subscription_id === subscription.id;
  const enseigneId = contract.enseigne_id || subscription.metadata?.enseigneId;
  if (!enseigneId || (subscription.metadata?.enseigneId && subscription.metadata.enseigneId !== contract.enseigne_id)) {
    return {outcome: "ignored_enseigne_mismatch", reason: `abonnement sur ${subscription.metadata?.enseigneId}, contrat sur ${contract.enseigne_id}`,
      contractId, subscriptionId: subscription.id};
  }
  const ref = db.collection(kEnseigneSubscriptionsCollection).doc(enseigneId);
  const fetchedAtMs = Date.now();
  let previousStatus = null;
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? snap.data() : {};
    previousStatus = current.stripe_subscription_id === subscription.id ? current.status || null : null;
    if (!tracked) {
      tx.set(ref, {other_subscriptions: {[subscription.id]: {status: subscription.status,
        updated_at: admin.firestore.FieldValue.serverTimestamp()}}}, {merge: true});
      return "untracked_noted";
    }
    if (current.stripe_subscription_id === subscription.id && (current.stripe_fetched_at_ms || 0) > fetchedAtMs) return "ignored_stale";
    const period = periodOf(subscription);
    tx.set(ref, {
      enseigne_id: enseigneId,
      owner_uid: contract.owner_uid,
      contract_id: contractId,
      stripe_customer_id: idOf(subscription.customer),
      stripe_subscription_id: subscription.id,
      status: subscription.status,
      current_period_start: tsFromSeconds(period.start),
      current_period_end: tsFromSeconds(period.end),
      cancel_at_period_end: subscription.cancel_at_period_end === true,
      cancel_at: tsFromSeconds(subscription.cancel_at),
      canceled_at: tsFromSeconds(subscription.canceled_at),
      ended_at: tsFromSeconds(subscription.ended_at),
      ...graceFor(subscription, current, fetchedAtMs),
      // Regularisation : la suspension notifiee en fin de grace (lot 1.9) est levee.
      ...(kGraceStatuses.includes(subscription.status) ? {} : {suspended_at: null}),
      stripe_livemode: subscription.livemode === true,
      stripe_fetched_at_ms: fetchedAtMs,
      last_stripe_event_id: eventId,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return "synced";
  });
  // Passage a "unpaid" (action finale de Stripe apres ses relances) : le
  // contrat reste actif et aucun acces n'est coupe ; decision manuelle de
  // l'admin (art. 11 : mise en demeure, suspension, resiliation). Une alerte
  // par passage (statut precedent du miroir, lu dans la transaction).
  if (outcome === "synced" && subscription.status === "unpaid" && previousStatus !== "unpaid") {
    await mail.raiseAdminAlert(db, {kind: "abonnement_impaye", contractId,
      detail: `Abonnement Stripe ${subscription.id} passé à « unpaid » (relances Stripe terminées). Le contrat reste actif, ` +
        "aucun accès n'est coupé automatiquement : décision manuelle (art. 11 : mise en demeure, suspension, résiliation)."});
  }
  // Abonnement suivi termine : le contrat actif se termine (motif precise par
  // le lot 1.12 quand la fin vient d'une action ProxiPlay).
  if (outcome === "synced" && subscription.status === "canceled") {
    await db.runTransaction(async (tx) => {
      const c = (await tx.get(contractSnap.ref)).data();
      if (c.state !== kStates.ACTIVE) return;
      const internal = (await tx.get(internalRef(db, contractId))).data() || {};
      assertTransition(c.state, kStates.ENDED);
      tx.update(contractSnap.ref, {state: kStates.ENDED, state_version: (c.state_version || 1) + 1,
        ended_at: tsFromSeconds(subscription.ended_at || subscription.canceled_at) || admin.firestore.Timestamp.now(),
        end_reason: internal.pending_end_reason || "stripe_canceled", updated_at: admin.firestore.FieldValue.serverTimestamp()});
      tx.set(eventRef(db, contractId), {type: "ended", at: admin.firestore.FieldValue.serverTimestamp(),
        subscription_id: subscription.id, event_id: eventId});
    });
  }
  return {outcome: `contract_${outcome}`, contractId};
}

/**
 * Paiement initial d'un abonnement de contrat. Active le contrat attendu, une
 * seule fois ; sinon rembourse integralement et annule (art. 8.1).
 */
async function onInitialPayment(db, stripe, subscription, eventId) {
  const contractId = subscription.metadata?.contractId;
  const contractRef = db.collection(kContractsCollection).doc(contractId);
  const decision = await db.runTransaction(async (tx) => {
    const snap = await tx.get(contractRef);
    if (!snap.exists) return {kind: "unmatched", reason: "contrat_inconnu"};
    const contract = snap.data();
    const internal = (await tx.get(internalRef(db, contractId))).data() || {};
    if (internal.billing?.stripe_subscription_id === subscription.id) return {kind: "already", contract};
    const unmatched = (reason) => {
      // Une entree par evenement (rejeu idempotent).
      tx.set(internalRef(db, contractId), {unmatched_payments: {[eventId]: {
        subscription_id: subscription.id, state_at_payment: contract.state, reason, at: admin.firestore.Timestamp.now(),
      }}}, {merge: true});
      return {kind: "unmatched", reason, contract};
    };
    if (contract.enseigne_id !== subscription.metadata?.enseigneId) return unmatched("enseigne_differente");
    if (contract.state === kStates.PAYMENT_INVITED) {
      assertTransition(contract.state, kStates.ACTIVE);
      const now = admin.firestore.Timestamp.now();
      const open = await tx.get(db.collection("payment_tokens").where("contract_id", "==", contractId).where("revoked_at", "==", null));
      tx.update(contractRef, {state: kStates.ACTIVE, state_version: (contract.state_version || 1) + 1,
        activated_at: now, updated_at: admin.firestore.FieldValue.serverTimestamp()});
      tx.set(internalRef(db, contractId), {billing: {
        stripe_subscription_id: subscription.id,
        stripe_customer_id: idOf(subscription.customer),
        initial_invoice_id: idOf(subscription.latest_invoice),
        activated_by_event: eventId,
      }}, {merge: true});
      open.docs.forEach((doc) => tx.update(doc.ref, {revoked_at: now, used_for_payment: true}));
      tx.set(eventRef(db, contractId), {type: "activated", at: now, subscription_id: subscription.id, event_id: eventId});
      return {kind: "activated", contract: {...contract, activated_at: now}};
    }
    if (!kAutoRefundStates.includes(contract.state)) return unmatched(`etat_${contract.state}`);
    // Paiement non attendu sur un contrat clos, retracte, refuse, termine, en
    // delai de retractation, ou actif avec un autre abonnement : jamais de
    // reactivation, remboursement integral.
    tx.set(internalRef(db, contractId), {late_payments: admin.firestore.FieldValue.arrayUnion({
      subscription_id: subscription.id, state_at_payment: contract.state, event_id: eventId, at: admin.firestore.Timestamp.now(),
    })}, {merge: true});
    return {kind: "late", contract, stateAtPayment: contract.state};
  });

  if (decision.kind === "already") return {outcome: "contract_already_active", contractId};
  if (decision.kind === "unmatched") {
    // Aucune action sur l'argent : l'abonnement reste tel quel chez Stripe,
    // l'admin decide (trace + alerte ecrites par le webhook, une fois par evenement).
    return {outcome: "unmatched_contract_payment", reason: decision.reason, contractId, subscriptionId: subscription.id};
  }
  if (decision.kind === "activated") {
    await syncContractSubscription(db, subscription, eventId);
    const mirror = (await db.collection(kEnseigneSubscriptionsCollection).doc(decision.contract.enseigne_id).get()).data() || {};
    await mail.sendAndRecord(db, contractId, "activation", emails.activationNotice(decision.contract, contractId, {
      activatedMs: millisOf(decision.contract.activated_at), periodEndMs: millisOf(mirror.current_period_end),
    }));
    return {outcome: "contract_activated", contractId};
  }
  const reason = `paiement_non_attendu_${decision.stateAtPayment}`;
  const records = await refundAndCancel(db, stripe, {contractId, subscriptionId: subscription.id, reason});
  await mail.raiseAdminAlert(db, {kind: "paiement_tardif_rembourse", contractId,
    detail: `Paiement reçu pour un contrat à l'état « ${decision.stateAtPayment} » : remboursé intégralement (${records.length} facture(s)), abonnement annulé.`});
  if (decision.contract.owner_email) {
    await mail.sendAndRecord(db, contractId, "late_payment_refund", emails.latePaymentRefundNotice(decision.contract, contractId));
    await eventRef(db, contractId).set({type: "late_payment_refunded", at: admin.firestore.FieldValue.serverTimestamp(),
      subscription_id: subscription.id, refunds: records.length, state_at_payment: decision.stateAtPayment});
  }
  return {outcome: "contract_late_payment_refunded", contractId};
}

/** checkout.session.completed : session relue chez Stripe, payee, abonnement. */
async function onCheckoutCompleted(db, sessionId, subscription, eventId) {
  const stripe = stripeClientModule.getStripeClient();
  const session = await stripe.checkout.sessions.retrieve(sessionId);
  if (!session || session.livemode !== expectedLivemode()) return {outcome: "ignored_livemode_mismatch"};
  if (session.payment_status !== "paid") return {outcome: "contract_checkout_unpaid", contractId: subscription.metadata.contractId};
  return onInitialPayment(db, stripe, subscription, eventId);
}

/** invoice.paid : creation -> paiement initial ; renouvellement -> miroir. */
async function onInvoicePaid(db, invoiceId, subscription, eventId) {
  const stripe = stripeClientModule.getStripeClient();
  const invoice = await stripe.invoices.retrieve(invoiceId);
  if (invoice?.billing_reason === "subscription_create") return onInitialPayment(db, stripe, subscription, eventId);
  const sync = await syncContractSubscription(db, subscription, eventId);
  if (invoice?.billing_reason === "subscription_cycle" && sync.outcome === "contract_synced") {
    const contract = (await db.collection(kContractsCollection).doc(subscription.metadata.contractId).get()).data();
    await db.collection(kEnseigneSubscriptionsCollection).doc(contract.enseigne_id).set({
      last_renewal_paid_at: tsFromSeconds(invoice.status_transitions?.paid_at) || admin.firestore.Timestamp.now(),
      unpaid_invoice_url: null, last_failed_invoice_id: null,
    }, {merge: true});
  }
  return sync;
}

/**
 * invoice.payment_failed : miroir (delai de grace) et notification immediate
 * du commercant (art. 11), une seule fois par facture.
 */
async function onInvoicePaymentFailed(db, invoiceId, subscription, eventId) {
  const stripe = stripeClientModule.getStripeClient();
  const invoice = await stripe.invoices.retrieve(invoiceId);
  const sync = await syncContractSubscription(db, subscription, eventId);
  if (sync.outcome !== "contract_synced" || invoice?.billing_reason !== "subscription_cycle") return sync;
  const contractId = subscription.metadata.contractId;
  const contract = (await db.collection(kContractsCollection).doc(contractId).get()).data();
  const mirrorRef = db.collection(kEnseigneSubscriptionsCollection).doc(contract.enseigne_id);
  await mirrorRef.set({last_payment_failed_at: admin.firestore.Timestamp.now(), last_failed_invoice_id: invoice.id,
    unpaid_invoice_url: invoice.hosted_invoice_url || null}, {merge: true});
  const first = await db.runTransaction(async (tx) => {
    const ref = internalRef(db, contractId);
    const notified = (await tx.get(ref)).data()?.renewal_failures?.[invoice.id];
    if (notified) return false;
    tx.set(ref, {renewal_failures: {[invoice.id]: {notified_at: admin.firestore.Timestamp.now(), event_id: eventId}}}, {merge: true});
    return true;
  });
  if (first) {
    const mirror = (await mirrorRef.get()).data() || {};
    await mail.sendAndRecord(db, contractId, `renewal_failed_${invoice.id}`, emails.renewalFailedNotice(contract, contractId, {
      graceUntilMs: millisOf(mirror.grace_until), invoiceUrl: invoice.hosted_invoice_url || null,
    }));
  }
  return {...sync, outcome: first ? "contract_renewal_failed_notified" : "contract_renewal_failed"};
}

/**
 * Authentification bancaire requise (3-D Secure) sur une facture d'un
 * abonnement de contrat : Stripe envoie lui-meme le lien au client (e-mail a
 * activer dans le Dashboard). ProxiPlay alerte l'admin, une fois par facture ;
 * aucun e-mail au commercant, aucune action sur l'argent.
 */
async function onInvoicePaymentActionRequired(db, invoice, subscription, eventId) {
  const sync = await syncContractSubscription(db, subscription, eventId);
  if (sync.outcome !== "contract_synced") return sync;
  const contractId = subscription.metadata.contractId;
  const first = await db.runTransaction(async (tx) => {
    const ref = internalRef(db, contractId);
    if ((await tx.get(ref)).data()?.action_required?.[invoice.id]) return false;
    tx.set(ref, {action_required: {[invoice.id]: {alerted_at: admin.firestore.Timestamp.now(), event_id: eventId}}}, {merge: true});
    return true;
  });
  if (first) {
    await mail.raiseAdminAlert(db, {kind: "authentification_bancaire_requise", contractId,
      detail: `Facture ${invoice.id} (${invoice.billing_reason || "?"}) : authentification bancaire requise par la banque du ` +
        "commerçant. Stripe envoie le lien au client si l'e-mail correspondant est activé ; vérifier dans Stripe et relancer si besoin."});
  }
  return {...sync, outcome: first ? "contract_action_required_alerted" : "contract_action_required"};
}

/**
 * Evenement Stripe qu'on ne sait pas rattacher (ou paiement de contrat sans
 * action sur l'argent) : trace stripe_unmatched_events/{eventId} (identifiants
 * seulement, lecture admin) et alerte admin, une seule fois par evenement.
 */
async function recordUnmatchedEvent(db, event, result) {
  const object = event?.data?.object || {};
  const ref = db.collection(kUnmatchedEventsCollection).doc(String(event.id));
  const created = await db.runTransaction(async (tx) => {
    if ((await tx.get(ref)).exists) return false;
    tx.set(ref, {
      event_id: event.id,
      event_type: event.type,
      object_id: typeof object.id === "string" ? object.id : null,
      outcome: result?.outcome || null,
      reason: result?.reason || null,
      contract_id: result?.contractId || null,
      subscription_id: result?.subscriptionId || null,
      livemode: event.livemode === true,
      resolved: false,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (created) {
    await mail.raiseAdminAlert(db, {kind: "stripe_evenement_non_rattache", contractId: result?.contractId || null,
      detail: `Événement Stripe ${event.type} (${event.id}) non rattaché : ${result?.outcome || "?"}` +
        `${result?.reason ? ` (${result.reason})` : ""}. Aucune action sur l'argent : décision manuelle.`});
  }
  return created;
}

/** Remboursement ou litige sur un abonnement de contrat : trace et alerte (jamais la logique de parrainage V1). */
async function onChargeEvent(db, type, subscription, chargeId) {
  const contractId = subscription.metadata.contractId;
  await internalRef(db, contractId).set({charge_events: admin.firestore.FieldValue.arrayUnion({
    type, charge_id: chargeId, subscription_id: subscription.id, at: admin.firestore.Timestamp.now(),
  })}, {merge: true});
  if (type === "charge.dispute.created") {
    await mail.raiseAdminAlert(db, {kind: "litige_paiement", contractId, detail: `Litige ouvert sur le paiement ${chargeId}.`});
  }
  return {outcome: type === "charge.refunded" ? "contract_refund_recorded" : "contract_dispute_recorded", contractId};
}

module.exports = {
  kEnseigneSubscriptionsCollection,
  kUnmatchedEventsCollection,
  kAutoRefundStates,
  recordUnmatchedEvent,
  refundInvoice,
  settleRenewalInvoice,
  periodOf,
  idOf,
  refundAndCancel,
  syncContractSubscription,
  onInitialPayment,
  onCheckoutCompleted,
  onInvoicePaid,
  onInvoicePaymentFailed,
  onInvoicePaymentActionRequired,
  onChargeEvent,
};

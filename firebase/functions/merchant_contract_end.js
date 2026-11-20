// Phase 1, tranche 2b, lot 1.12 : fins de contrat (CGV B2B V2.1).
//
// - disableMerchantRenewal (commercant, bouton « Désactiver le
//   renouvellement », art. 9), par contrat donc par enseigne :
//     * aucune facture de renouvellement en attente : cancel_at_period_end,
//       fin a l'echeance, service jusqu'a la fin de la periode payee ;
//     * facture de renouvellement en brouillon (l'heure entre l'echeance et
//       le prelevement) : procedure validee par l'essai du 2026-11-19
//       (auto_advance=false, finalisation, void), puis annulation immediate ;
//     * facture ouverte apres un echec de prelevement (delai de l'art. 11) :
//       void et annulation immediate, aucune penalite ;
//     * avant toute annulation de facture, son statut est relu chez Stripe ;
//       si elle est payee (prelevement passe entre-temps), bascule sur le
//       remboursement integral (avoir si l'option est activee).
// - adminRefundRenewal (art. 9, dernier alinea) : renouvellement preleve
//   alors que le rappel des 45 jours est marque missed (ou absent), demande
//   du commercant dans les 30 jours du prelevement : remboursement integral,
//   annulation immediate.
// - adminEndContract (decision 15 : decisions manuelles de l'admin) :
//     * provider_breach (art. 10) : remboursement fixe par l'admin ;
//     * unpaid_termination (art. 11) : apres la fin du delai de
//       regularisation et une mise en demeure (date et reference saisies,
//       envoyee hors du systeme) ; aucun remboursement ; facture impayee
//       laissee due mais sans nouvelle tentative de prelevement ;
//     * breach (art. 18) : apres notification (date et reference) ou mesure
//       immediate motivee ; aucun remboursement ;
//     * force_majeure (art. 23) : empechement de plus de 60 jours ;
//       remboursement au prorata de la periode non executee, calcule par le
//       serveur.
// Chaque fin : actions Stripe d'abord (motif de fin pose avant, pour le
// webhook), puis contrat ended, journal, e-mail.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {assertMerchantCaller} = require("./merchant_billing_access");
const {
  kFunctionsRegion,
  kContractsCollection,
  kStates,
  httpsError,
  assertTransition,
  readContractsConfig,
  assertAdminCaller,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const {expectedLivemode} = require("./stripe_mode");
const stripeClientModule = require("./stripe_client");
const billing = require("./merchant_contract_billing");
const {kGraceStatuses} = require("./merchant_publication_access");
const {parisDate, addDays, endOfParisDay} = require("./paris_time");
const {parseSentAt} = require("./merchant_contract_withdrawal");
const schedule = require("./merchant_contract_schedule");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

const kEnseigneSubscriptionsCollection = "enseigne_subscriptions";
const kLockMs = 60 * 1000;
const kRefundRequestDays = 30; // art. 9 : demande sous 30 jours apres le prelevement
const kForceMajeureDays = 60; // art. 23 : empechement de plus de 60 jours
const kAdminEndReasons = Object.freeze(["provider_breach", "unpaid_termination", "breach", "force_majeure"]);

function refuse(reason, message, code = "failed-precondition") {
  return httpsError(code, message, {reason});
}

function invoiceSubscriptionId(invoice) {
  return billing.idOf(invoice?.subscription) || billing.idOf(invoice?.parent?.subscription_details?.subscription);
}

/** Debut de la periode facturee par une facture d'abonnement (date de renouvellement pour un cycle). */
function invoicePeriodStartMs(invoice) {
  const line = invoice?.lines?.data?.[0];
  const seconds = line?.period?.start ?? (invoice?.billing_reason === "subscription_cycle" ? invoice?.period_end : invoice?.period_start);
  return typeof seconds === "number" ? seconds * 1000 : null;
}

function contractIdOf(data) {
  const id = typeof data?.contractId === "string" ? data.contractId.trim() : "";
  if (!id) throw refuse("invalid_field", "Souscription inconnue.", "invalid-argument");
  return id;
}

/** Contrat actif avec son abonnement suivi, et verrou court contre le double clic. */
async function lockActiveContract(db, contractId, {ownerUid = null, nowMs = Date.now()} = {}) {
  const ref = db.collection(kContractsCollection).doc(contractId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || (ownerUid && snap.data().owner_uid !== ownerUid)) {
      throw refuse("contract_not_found", "Souscription inconnue.", "not-found");
    }
    const contract = snap.data();
    if (contract.state !== kStates.ACTIVE) throw refuse("not_active", "Cette souscription n'est pas un abonnement actif.");
    const internal = (await tx.get(internalRef(db, contractId))).data() || {};
    const subscriptionId = internal.billing?.stripe_subscription_id;
    if (!subscriptionId) throw refuse("no_subscription", "Aucun abonnement Stripe rattaché à cette souscription.");
    const lockAt = millisOf(internal.end_lock_at);
    if (lockAt && nowMs - lockAt < kLockMs) {
      throw refuse("end_in_progress", "Une opération est déjà en cours sur cet abonnement : réessayez dans un instant.", "aborted");
    }
    tx.set(internalRef(db, contractId), {end_lock_at: admin.firestore.Timestamp.fromMillis(nowMs)}, {merge: true});
    return {contract, internal, subscriptionId};
  });
}

async function releaseLock(db, contractId) {
  await internalRef(db, contractId).set({end_lock_at: admin.firestore.FieldValue.delete()}, {merge: true});
}

async function retrieveSubscription(stripe, subscriptionId) {
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  if (!subscription || subscription.livemode !== expectedLivemode()) {
    throw refuse("stripe_mode_mismatch", "Abonnement Stripe introuvable ou d'un autre mode (TEST/LIVE).");
  }
  return subscription;
}

async function cancelNow(stripe, subscriptionId) {
  await stripe.subscriptions.cancel(subscriptionId, {prorate: false, invoice_now: false}, {idempotencyKey: `cancel-${subscriptionId}`});
}

/** Passage active -> ended, journal et trace interne, dans une transaction. */
async function markEnded(db, contractId, {endReason, actor, record, nowMs}) {
  const ref = db.collection(kContractsCollection).doc(contractId);
  return db.runTransaction(async (tx) => {
    const contract = (await tx.get(ref)).data();
    const nowTs = admin.firestore.Timestamp.fromMillis(nowMs);
    if (contract.state === kStates.ACTIVE) {
      assertTransition(contract.state, kStates.ENDED);
      tx.update(ref, {state: kStates.ENDED, state_version: (contract.state_version || 1) + 1, ended_at: nowTs,
        end_reason: endReason, updated_at: admin.firestore.FieldValue.serverTimestamp()});
    }
    tx.set(internalRef(db, contractId), {end: {...record, end_reason: endReason, actor, at: nowTs}}, {merge: true});
    tx.set(eventRef(db, contractId), {type: "ended", at: nowTs, actor, end_reason: endReason});
    return contract;
  });
}

async function setPendingEndReason(db, contractId, endReason) {
  await internalRef(db, contractId).set({pending_end_reason: endReason}, {merge: true});
}

// --- Art. 9 : bouton « Désactiver le renouvellement » ------------------------------

async function disableRenewal(db, contractId, {actor, ownerUid, nowMs = Date.now()}) {
  const {contract, subscriptionId} = await lockActiveContract(db, contractId, {ownerUid, nowMs});
  try {
    const stripe = stripeClientModule.getStripeClient();
    const config = await readContractsConfig(db);
    const subscription = await retrieveSubscription(stripe, subscriptionId);
    if (["canceled", "incomplete_expired"].includes(subscription.status)) return {outcome: "already_ended"};
    const periodEndMs = (billing.periodOf(subscription).end || 0) * 1000;
    const latestId = billing.idOf(subscription.latest_invoice);
    const latest = latestId ? await stripe.invoices.retrieve(latestId) : null;
    const pendingRenewal = latest?.billing_reason === "subscription_cycle" && ["draft", "open"].includes(latest.status);
    const mirrorRef = db.collection(kEnseigneSubscriptionsCollection).doc(contract.enseigne_id);

    if (!pendingRenewal) {
      // Cas general : fin a l'echeance, rien n'est annule ni rembourse.
      if (subscription.cancel_at_period_end === true) return {outcome: "already_disabled", endsAt: periodEndMs};
      await setPendingEndReason(db, contractId, "non_renewal");
      await stripe.subscriptions.update(subscriptionId, {cancel_at_period_end: true},
        {idempotencyKey: `disable-renewal-${subscriptionId}-${Math.floor(periodEndMs / 1000)}`});
      const nowTs = admin.firestore.Timestamp.fromMillis(nowMs);
      await mirrorRef.set({cancel_at_period_end: true, renewal_disabled_at: nowTs, updated_at: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
      await internalRef(db, contractId).set({renewal_disable: {at: nowTs, actor, mode: "period_end",
        period_end: admin.firestore.Timestamp.fromMillis(periodEndMs)}}, {merge: true});
      await eventRef(db, contractId).set({type: "renewal_disabled", at: nowTs, actor, mode: "period_end"});
      await mail.sendAndRecord(db, contractId, `renewal_disabled_${Math.floor(periodEndMs / 1000)}`,
        emails.renewalDisabledNotice(contract, contractId, {periodEndMs}));
      return {outcome: "disabled_at_period_end", endsAt: periodEndMs};
    }

    // Facture de renouvellement en attente : l'abonnement prend fin maintenant.
    const duringGrace = latest.status === "open" && (kGraceStatuses.includes(subscription.status) || (latest.attempt_count || 0) > 0);
    const endReason = duringGrace ? "deactivated_during_grace" : "non_renewal";
    await setPendingEndReason(db, contractId, endReason);
    const settled = await billing.settleRenewalInvoice(stripe, latest.id);
    const refunds = [];
    if (settled.status === "paid") {
      // Le prelevement est passe pendant la procedure : la demande etait anterieure, remboursement integral.
      refunds.push(await billing.refundInvoice(stripe, {invoice: settled.invoice, contractId, reason: "desactivation_art9",
        creditNotes: config.creditNotesEnabled}));
    } else if (!["void", "uncollectible"].includes(settled.status)) {
      await mail.raiseAdminAlert(db, {kind: "desactivation_echec", contractId,
        detail: `Désactivation demandée : facture ${latest.id} restée « ${settled.status} » après la procédure (${settled.steps.join(", ")}). Abonnement non annulé : action manuelle.`});
      throw refuse("invoice_not_settled", "La désactivation n'a pas pu aboutir : ProxiPlay est prévenu et vous recontacte.", "unavailable");
    }
    await cancelNow(stripe, subscriptionId);
    const nowTs = admin.firestore.Timestamp.fromMillis(nowMs);
    await mirrorRef.set({renewal_disabled_at: nowTs, updated_at: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    await markEnded(db, contractId, {endReason, actor, nowMs, record: {kind: "renewal_disable", invoice_id: latest.id,
      invoice_status_final: settled.status, steps: settled.steps, refunds}});
    await internalRef(db, contractId).set({renewal_disable: {at: nowTs, actor, mode: duringGrace ? "during_grace" : "at_renewal"},
      ...(refunds.length ? {refunds: admin.firestore.FieldValue.arrayUnion(...refunds.map((r) => ({...r, reason: "desactivation_art9", at: nowTs})))} : {}),
    }, {merge: true});
    await mail.sendAndRecord(db, contractId, `renewal_stopped_${latest.id}`, emails.renewalStoppedNotice(contract, contractId, {
      duringGrace, refundedCents: refunds.reduce((sum, r) => sum + r.amount, 0)}));
    return {outcome: duringGrace ? "ended_during_grace" : "ended_at_renewal", refunded: refunds.length, invoiceStatus: settled.status};
  } finally {
    await releaseLock(db, contractId);
  }
}

async function disableMerchantRenewalHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  // Contrat existant : hors interrupteur (pause des nouvelles ventes seulement).
  return disableRenewal(db, contractIdOf(data), {actor: `merchant:${context.auth.uid}`, ownerUid: context.auth.uid});
}

// --- Art. 9 : rappel des 45 jours manque -----------------------------------------------

/** true si le rappel J-45 de ce renouvellement est missed, ou n'a laisse aucune trace d'envoi a temps. */
async function renewalReminderMissed(db, {contractId, subscriptionId, renewalMs, internal}) {
  const doc = (await db.collection(schedule.kRenewalRemindersCollection).doc(schedule.reminderDocId(subscriptionId, renewalMs)).get()).data();
  if (doc?.j45?.missed === true) return true;
  if (doc?.j45?.missed === false) return false;
  const deadlineMs = schedule.renewalReminderDeadline(renewalMs, 45);
  const sentMs = millisOf(internal.emails?.[schedule.renewalReminderKey(45, renewalMs)]?.sent_at);
  return !(sentMs && sentMs <= deadlineMs);
}

async function adminRefundRenewalHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const contractId = contractIdOf(data);
  const invoiceId = typeof data?.invoiceId === "string" ? data.invoiceId.trim() : "";
  if (!/^in_/.test(invoiceId)) throw refuse("invalid_field", "Facture de renouvellement requise (in_…).", "invalid-argument");
  const requestedMs = parseSentAt(data?.requestedAt);
  const reference = typeof data?.reference === "string" && data.reference.trim() ? data.reference.trim().slice(0, 200) : null;
  if (!reference) throw refuse("invalid_field", "Référence de la demande du commerçant requise.", "invalid-argument");
  const nowMs = Date.now();
  const {contract, internal, subscriptionId} = await lockActiveContract(db, contractId, {nowMs});
  try {
    const stripe = stripeClientModule.getStripeClient();
    const config = await readContractsConfig(db);
    const invoice = await stripe.invoices.retrieve(invoiceId);
    if (!invoice || invoice.livemode !== expectedLivemode() || invoiceSubscriptionId(invoice) !== subscriptionId ||
        invoice.billing_reason !== "subscription_cycle") {
      throw refuse("invoice_mismatch", "Cette facture n'est pas un renouvellement de cet abonnement.");
    }
    if (invoice.status !== "paid" || !(invoice.amount_paid > 0)) throw refuse("invoice_not_paid", "Ce renouvellement n'a pas été prélevé.");
    const paidMs = (invoice.status_transitions?.paid_at || 0) * 1000;
    const limitMs = endOfParisDay(addDays(parisDate(paidMs), kRefundRequestDays));
    if (!paidMs || requestedMs < paidMs - 24 * 3600 * 1000 || requestedMs > limitMs) {
      throw refuse("refund_request_out_of_time", "La demande doit être faite dans les trente jours suivant le prélèvement (art. 9).");
    }
    const renewalMs = invoicePeriodStartMs(invoice);
    if (!renewalMs || !(await renewalReminderMissed(db, {contractId, subscriptionId, renewalMs, internal}))) {
      throw refuse("reminder_not_missed", "Le rappel des quarante-cinq jours a été envoyé à temps : aucun remboursement au titre de l'art. 9.");
    }
    await setPendingEndReason(db, contractId, "renewal_refunded");
    const refund = await billing.refundInvoice(stripe, {invoice, contractId, reason: "rappel_45_jours_manque",
      creditNotes: config.creditNotesEnabled, keySuffix: "-art9"});
    await cancelNow(stripe, subscriptionId);
    await markEnded(db, contractId, {endReason: "renewal_refunded", actor: `admin:${adminUid}`, nowMs, record: {
      kind: "renewal_refund", invoice_id: invoiceId, requested_at: admin.firestore.Timestamp.fromMillis(requestedMs), reference, refunds: [refund]}});
    await internalRef(db, contractId).set({refunds: admin.firestore.FieldValue.arrayUnion({...refund, reason: "rappel_45_jours_manque",
      at: admin.firestore.Timestamp.fromMillis(nowMs)})}, {merge: true});
    await mail.sendAndRecord(db, contractId, `renewal_refund_${invoiceId}`, emails.renewalRefundNotice(contract, contractId, {refundedCents: refund.amount}));
    return {outcome: "renewal_refunded", refundedCents: refund.amount};
  } finally {
    await releaseLock(db, contractId);
  }
}

// --- Art. 10, 11, 18, 23 : fins decidees par l'admin --------------------------------------

function optionalDate(raw, field) {
  if (raw === undefined || raw === null || raw === "") return null;
  try {
    return parseSentAt(raw);
  } catch (error) {
    throw refuse("invalid_field", `Date invalide : ${field}.`, "invalid-argument");
  }
}

function text(raw, max) {
  return typeof raw === "string" && raw.trim() ? raw.trim().slice(0, max) : null;
}

/** Validation des pieces exigees par chaque motif (aucun appel Stripe ici). */
function parseEndRequest(data, nowMs) {
  const reason = data?.reason;
  if (!kAdminEndReasons.includes(reason)) throw refuse("invalid_field", "Motif de fin inconnu.", "invalid-argument");
  const detail = text(data?.detail, 1000);
  if (!detail) throw refuse("invalid_field", "Exposé des faits requis.", "invalid-argument");
  const noticeSentMs = optionalDate(data?.noticeSentAt, "noticeSentAt");
  const noticeReference = text(data?.noticeReference, 200);
  const request = {reason, detail, noticeSentMs, noticeReference, immediate: data?.immediate === true, refundCents: null, impedimentStartMs: null};
  if (reason === "unpaid_termination" && (!noticeSentMs || !noticeReference)) {
    throw refuse("notice_required", "Résiliation pour impayé : date et référence de la mise en demeure requises (art. 11).", "invalid-argument");
  }
  if (reason === "breach" && !request.immediate && (!noticeSentMs || !noticeReference)) {
    throw refuse("notice_required", "Manquement : date et référence de la notification requises, sauf mesure immédiate motivée (art. 18).",
      "invalid-argument");
  }
  if (reason === "provider_breach") {
    const cents = data?.refundCents === undefined || data?.refundCents === null ? 0 : data.refundCents;
    if (!Number.isInteger(cents) || cents < 0) throw refuse("invalid_field", "Montant de remboursement invalide (centimes).", "invalid-argument");
    request.refundCents = cents;
  }
  if (reason === "force_majeure") {
    request.impedimentStartMs = optionalDate(data?.impedimentStartedAt, "impedimentStartedAt");
    if (!request.impedimentStartMs) throw refuse("invalid_field", "Date de début de l'empêchement requise (art. 23).", "invalid-argument");
    if (nowMs - request.impedimentStartMs <= kForceMajeureDays * 86400000) {
      throw refuse("force_majeure_under_60_days", "L'empêchement doit dépasser soixante jours (art. 23).");
    }
  }
  return request;
}

/** Facture de la periode en cours (debut de ligne = debut de periode de l'abonnement). */
async function currentPeriodInvoice(stripe, subscription) {
  const startMs = (billing.periodOf(subscription).start || 0) * 1000;
  const invoices = (await stripe.invoices.list({subscription: subscription.id, limit: 20})).data || [];
  return invoices.find((inv) => invoicePeriodStartMs(inv) === startMs &&
    ["subscription_create", "subscription_cycle"].includes(inv.billing_reason)) || null;
}

/** Art. 23 : part non executee de la periode, en centimes (arrondi inferieur). */
function prorataCents(amountPaid, periodStartMs, periodEndMs, nowMs) {
  if (!(periodEndMs > periodStartMs) || nowMs >= periodEndMs) return 0;
  const remaining = Math.min(1, (periodEndMs - Math.max(nowMs, periodStartMs)) / (periodEndMs - periodStartMs));
  return Math.floor(amountPaid * remaining);
}

async function adminEndContractHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const contractId = contractIdOf(data);
  const nowMs = Date.now();
  const request = parseEndRequest(data, nowMs);
  const {contract, subscriptionId} = await lockActiveContract(db, contractId, {nowMs});
  try {
    const stripe = stripeClientModule.getStripeClient();
    const config = await readContractsConfig(db);
    const subscription = await retrieveSubscription(stripe, subscriptionId);
    const mirror = (await db.collection(kEnseigneSubscriptionsCollection).doc(contract.enseigne_id).get()).data() || {};
    if (request.reason === "unpaid_termination") {
      const graceUntilMs = millisOf(mirror.grace_until);
      if (!kGraceStatuses.includes(subscription.status) || !graceUntilMs) {
        throw refuse("not_unpaid", "Aucun impayé en cours sur cet abonnement (art. 11).");
      }
      if (nowMs <= graceUntilMs) throw refuse("grace_running", "Le délai de régularisation de quinze jours n'est pas expiré (art. 11).");
      if (request.noticeSentMs <= graceUntilMs - 15 * 86400000) {
        throw refuse("notice_before_failure", "La mise en demeure doit suivre l'échec du prélèvement.");
      }
    }
    const period = billing.periodOf(subscription);
    const periodStartMs = (period.start || 0) * 1000;
    const periodEndMs = (period.end || 0) * 1000;
    const invoice = await currentPeriodInvoice(stripe, subscription);
    let invoiceOutcome = invoice?.status || "none";
    // Controle avant toute action Stripe : jamais plus que le montant paye pour la periode.
    const paidBefore = invoice?.status === "paid" ? invoice.amount_paid || 0 : 0;
    if (request.reason === "provider_breach" && request.refundCents > paidBefore) {
      throw refuse("refund_above_paid", `Remboursement supérieur au montant payé pour la période en cours (${paidBefore} centimes).`);
    }

    await setPendingEndReason(db, contractId, request.reason);
    if (invoice && ["draft", "open"].includes(invoice.status)) {
      if (request.reason === "unpaid_termination") {
        // La somme reste due (art. 11) : la facture reste ouverte, sans nouvelle tentative de prelevement.
        await stripe.invoices.update(invoice.id, {auto_advance: false}, {idempotencyKey: `no-advance-${invoice.id}`});
        invoiceOutcome = "open_no_retry";
      } else {
        invoiceOutcome = (await billing.settleRenewalInvoice(stripe, invoice.id)).status;
      }
    }
    // Montant a rembourser, sur la facture payee de la periode en cours, relue.
    const paid = invoice ? await stripe.invoices.retrieve(invoice.id) : null;
    const paidCents = paid?.status === "paid" ? paid.amount_paid || 0 : 0;
    let refundCents = 0;
    if (request.reason === "provider_breach") refundCents = request.refundCents;
    if (request.reason === "force_majeure") refundCents = prorataCents(paidCents, periodStartMs, periodEndMs, nowMs);
    if (refundCents > paidCents) {
      throw refuse("refund_above_paid", `Remboursement supérieur au montant payé pour la période en cours (${paidCents} centimes).`);
    }
    const refunds = refundCents > 0 ? [await billing.refundInvoice(stripe, {invoice: paid, amountCents: refundCents, contractId,
      reason: request.reason, creditNotes: config.creditNotesEnabled, keySuffix: `-${request.reason}`})] : [];
    await cancelNow(stripe, subscriptionId);
    const record = {
      kind: "admin_end",
      detail: request.detail,
      notice_sent_at: request.noticeSentMs ? admin.firestore.Timestamp.fromMillis(request.noticeSentMs) : null,
      notice_reference: request.noticeReference,
      immediate: request.immediate,
      impediment_started_at: request.impedimentStartMs ? admin.firestore.Timestamp.fromMillis(request.impedimentStartMs) : null,
      invoice_id: invoice?.id || null,
      invoice_outcome: invoiceOutcome,
      refunds,
    };
    await markEnded(db, contractId, {endReason: request.reason, actor: `admin:${adminUid}`, nowMs, record});
    if (refunds.length) {
      await internalRef(db, contractId).set({refunds: admin.firestore.FieldValue.arrayUnion(...refunds.map((r) => ({...r,
        reason: request.reason, at: admin.firestore.Timestamp.fromMillis(nowMs)})))}, {merge: true});
    }
    await mail.sendAndRecord(db, contractId, `contract_end_${request.reason}`, emails.contractEndNotice(contract, contractId, {
      reason: request.reason, refundedCents: refundCents, endedMs: nowMs}));
    return {outcome: "ended", endReason: request.reason, refundedCents: refundCents, invoiceOutcome};
  } finally {
    await releaseLock(db, contractId);
  }
}

const callable = (handler) => functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
  .https.onCall(handler);

module.exports = {
  kAdminEndReasons,
  invoicePeriodStartMs,
  prorataCents,
  parseEndRequest,
  renewalReminderMissed,
  disableRenewal,
  disableMerchantRenewalHandler,
  adminRefundRenewalHandler,
  adminEndContractHandler,
  disableMerchantRenewal: callable(disableMerchantRenewalHandler),
  adminRefundRenewal: callable(adminRefundRenewalHandler),
  adminEndContract: callable(adminEndContractHandler),
};

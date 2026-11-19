// Phase 1, tranche 2a, lot 1.5 : retractation des souscriptions demarchees
// (CGV B2B V2.1, art. 7).
//
// - Qui : souscription demarchee (des l'origine ou apres signalement de
//   visite, art. 4.2), jusqu'a withdrawal_deadline : fin, a Paris, du 14e
//   jour suivant la conclusion (art. 7.2).
// - Canaux (art. 7.3) : fonction « Me rétracter » de l'espace commercant ;
//   e-mail ou courrier saisis par l'admin, avec la DATE D'ENVOI (decision 5)
//   comme date de retractation. Prolongation legale (L221-20) : saisie admin
//   apres le delai avec un motif obligatoire.
// - Effets : etat withdrawn ; liens de paiement revoques ; session Checkout
//   ouverte expiree ; si un paiement a deja eu lieu (signalement tardif) :
//   remboursement integral (avoir si l'option est activee) et annulation
//   immediate de l'abonnement. Accuse de reception immediat sur support
//   durable (e-mail), information de l'admin.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {assertMerchantCaller} = require("./merchant_billing_access");
const {
  kFunctionsRegion,
  kContractsCollection,
  kStates,
  httpsError,
  assertTransition,
  assertContractsEnabled,
  readContractsConfig,
  assertAdminCaller,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const {visitReportDeadline, parisLocalToUtc} = require("./paris_time");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

const kWithdrawableStates = Object.freeze([kStates.WITHDRAWAL_PENDING, kStates.PAYMENT_INVITED, kStates.ACTIVE]);
const kChannels = Object.freeze(["online", "email", "courrier"]);

function deadlineOf(contract) {
  return millisOf(contract.withdrawal_deadline) ||
    (millisOf(contract.confirmed_at) ? visitReportDeadline(millisOf(contract.confirmed_at)) : null);
}

/** Enregistre la retractation puis applique ses effets Stripe et ses e-mails. */
async function performWithdrawal(db, contractId, {channel, sentAtMs, receivedAtMs = null, reference = null, lateReason = null, actor}) {
  if (!kChannels.includes(channel)) throw httpsError("invalid-argument", "Canal inconnu.", {reason: "invalid_field", field: "channel"});
  const ref = db.collection(kContractsCollection).doc(contractId);
  const recorded = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
    const contract = snap.data();
    if (contract.state === kStates.WITHDRAWN) return {already: true, contract};
    if (contract.origin?.type !== "demarchee") {
      throw httpsError("failed-precondition",
        "Le droit de rétractation de l'article 7 concerne les souscriptions démarchées.", {reason: "not_demarchee"});
    }
    if (!kWithdrawableStates.includes(contract.state)) {
      throw httpsError("failed-precondition", "Aucune rétractation possible dans l'état actuel de la souscription.", {reason: "not_withdrawable"});
    }
    const deadline = deadlineOf(contract);
    if (!deadline || (sentAtMs > deadline && !lateReason)) {
      throw httpsError("failed-precondition",
        "Le délai de rétractation de quatorze jours est expiré (art. 7.2).", {reason: "withdrawal_deadline_passed"});
    }
    assertTransition(contract.state, kStates.WITHDRAWN);
    const internal = (await tx.get(internalRef(db, contractId))).data() || {};
    const open = await tx.get(db.collection("payment_tokens").where("contract_id", "==", contractId).where("revoked_at", "==", null));
    const now = admin.firestore.Timestamp.now();
    tx.update(ref, {state: kStates.WITHDRAWN, state_version: (contract.state_version || 1) + 1,
      withdrawn_at: admin.firestore.Timestamp.fromMillis(sentAtMs), updated_at: admin.firestore.FieldValue.serverTimestamp()});
    tx.set(internalRef(db, contractId), {withdrawal: {
      channel,
      sent_at: admin.firestore.Timestamp.fromMillis(sentAtMs),
      received_at: receivedAtMs ? admin.firestore.Timestamp.fromMillis(receivedAtMs) : null,
      reference,
      late_reason: lateReason,
      recorded_by: actor,
      recorded_at: now,
      state_before: contract.state,
    }}, {merge: true});
    open.docs.forEach((doc) => tx.update(doc.ref, {revoked_at: now}));
    tx.set(eventRef(db, contractId), {type: "withdrawn", at: now, actor, channel, state_before: contract.state,
      ...(lateReason ? {late_reason: lateReason} : {})});
    return {already: false, contract, wasActive: contract.state === kStates.ACTIVE,
      subscriptionId: internal.billing?.stripe_subscription_id || null};
  });
  if (recorded.already) return {state: kStates.WITHDRAWN, already: true};

  // Effets Stripe : uniquement s'il existe une session ou un abonnement.
  let refunded = [];
  const internal = (await internalRef(db, contractId).get()).data() || {};
  try {
    if (internal.checkout?.session_id) await require("./merchant_contract_checkout").expireOpenSessions(db, contractId);
    if (recorded.wasActive && recorded.subscriptionId) {
      const stripe = require("./stripe_client").getStripeClient();
      refunded = await require("./merchant_contract_billing").refundAndCancel(db, stripe,
        {contractId, subscriptionId: recorded.subscriptionId, reason: "retractation"});
    }
  } catch (error) {
    // La retractation est acquise ; l'effet Stripe manquant est signale pour action manuelle.
    await mail.raiseAdminAlert(db, {kind: "retractation_stripe_echec", contractId,
      detail: `Rétractation enregistrée, mais l'effet Stripe a échoué (session ou remboursement) : ${String(error?.message || error).slice(0, 200)}`});
  }
  const config = await readContractsConfig(db);
  const forMail = {...recorded.contract, admin_alert_email: config.adminAlertEmail};
  await mail.sendAndRecord(db, contractId, "withdrawal_ack", emails.withdrawalAcknowledgement(forMail, contractId, {
    sentMs: sentAtMs, channel, refundedCents: refunded.reduce((sum, r) => sum + (r.amount || 0), 0),
  }));
  await mail.sendAndRecord(db, contractId, "withdrawal_admin", emails.adminWithdrawalNotice(forMail, contractId, {channel, sentMs: sentAtMs,
    refunds: refunded.length}));
  return {state: kStates.WITHDRAWN, already: false, refunded: refunded.length};
}

/** Commercant : fonction « Me rétracter » (art. 7.3). */
async function withdrawMerchantContractHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  await assertContractsEnabled(db);
  const contractId = typeof data?.contractId === "string" ? data.contractId.trim() : "";
  const snap = contractId ? await db.collection(kContractsCollection).doc(contractId).get() : null;
  if (!snap?.exists || snap.data().owner_uid !== context.auth.uid) {
    throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
  }
  return performWithdrawal(db, contractId, {channel: "online", sentAtMs: Date.now(), actor: `merchant:${context.auth.uid}`});
}

/** Date d'envoi : jour seul (AAAA-MM-JJ, midi a Paris) ou date-heure ISO. */
function parseSentAt(raw) {
  const text = typeof raw === "string" ? raw.trim() : "";
  const day = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  const ms = day ? parisLocalToUtc(Number(day[1]), Number(day[2]), Number(day[3]), 12) : Date.parse(text);
  if (!Number.isFinite(ms)) throw httpsError("invalid-argument", "Date d'envoi invalide.", {reason: "invalid_field", field: "sentAt"});
  if (ms > Date.now() + 24 * 3600 * 1000) {
    throw httpsError("invalid-argument", "Date d'envoi dans le futur.", {reason: "invalid_field", field: "sentAt"});
  }
  return ms;
}

/** Admin : retractation recue par e-mail ou courrier (date d'envoi, decision 5). */
async function adminRecordWithdrawalHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const contractId = typeof data?.contractId === "string" ? data.contractId.trim() : "";
  if (!contractId) throw httpsError("invalid-argument", "Demande inconnue.", {reason: "invalid_field", field: "contractId"});
  const channel = data?.channel;
  if (!["email", "courrier"].includes(channel)) {
    throw httpsError("invalid-argument", "Canal : e-mail ou courrier.", {reason: "invalid_field", field: "channel"});
  }
  const sentAtMs = parseSentAt(data?.sentAt);
  const receivedAtMs = data?.receivedAt ? parseSentAt(data.receivedAt) : null;
  if (receivedAtMs !== null && receivedAtMs < sentAtMs - 24 * 3600 * 1000) {
    throw httpsError("invalid-argument", "Réception antérieure à l'envoi.", {reason: "invalid_field", field: "receivedAt"});
  }
  const reference = typeof data?.reference === "string" && data.reference.trim() ? data.reference.trim().slice(0, 200) : null;
  if (!reference) throw httpsError("invalid-argument", "Référence de la pièce requise (e-mail, lettre).", {reason: "invalid_field", field: "reference"});
  const lateReason = typeof data?.lateReason === "string" && data.lateReason.trim() ? data.lateReason.trim().slice(0, 500) : null;
  return performWithdrawal(db, contractId, {channel, sentAtMs, receivedAtMs, reference, lateReason, actor: `admin:${adminUid}`});
}

const callable = (handler) => functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
  .https.onCall(handler);

module.exports = {
  kWithdrawableStates,
  deadlineOf,
  parseSentAt,
  performWithdrawal,
  withdrawMerchantContractHandler,
  adminRecordWithdrawalHandler,
  withdrawMerchantContract: callable(withdrawMerchantContractHandler),
  adminRecordWithdrawal: callable(adminRecordWithdrawalHandler),
};

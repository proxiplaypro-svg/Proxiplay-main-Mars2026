// Phase 1, tranche 2b, lot 1.9 : taches planifiees du parcours de souscription
// (CGV B2B V2.1), en heure de Paris, idempotentes. Fonction de 2e generation
// (firebase-functions/v2/scheduler), une execution par heure.
//
// Inertes tant que app_config/merchant_contracts.enabled n'est pas true :
// aucune lecture de contrat, aucune ecriture, aucun e-mail, aucun appel Stripe.
//
// Taches :
//   1. fin du delai de retractation : withdrawal_pending -> payment_invited,
//      l'invitation part (art. 7.4, 8.1) ;
//   2. rappel de paiement a J+10 (date de Paris) de la premiere invitation ;
//   3. cloture a 15 jours : lien expire, rappel parti, ET derniere session
//      Checkout du contrat relue chez Stripe et non ouverte (decision du
//      2026-11-20) -> closed_unpaid, jetons revoques, e-mail « rien n'est
//      facture » ;
//   4. rappels de renouvellement a J-45 (art. 9) et J-15 (courtoisie, non
//      prevu aux CGV) ; un rappel J-45 non parti a temps est marque missed
//      (ouvre le remboursement de l'art. 9, lot 1.12) ;
//   5. relances amiables pendant la grace (art. 11) : J0 (notification du
//      webhook, renvoyee ici si elle manque), J+5, J+10 ;
//   6. fin de grace sans paiement : suspended_at pose sur le miroir, commercant
//      notifie, admin alerte (decision 10 : suspension notifiee seulement ;
//      blocage effectif au lot 1.11).
//
// Aucune tache ne deplace d'argent : la seule lecture Stripe est celle de la
// derniere session Checkout avant une cloture.

const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  kFunctionsRegion,
  kContractsCollection,
  kStates,
  readContractsConfig,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const {parisDate, addDays, endOfParisDay} = require("./paris_time");
const {kGraceStatuses} = require("./merchant_publication_access");
const payment = require("./merchant_contract_payment");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");
const stripeClientModule = require("./stripe_client");

const kEnseigneSubscriptionsCollection = "enseigne_subscriptions";
const kRenewalRemindersCollection = "renewal_reminders";
const kPaymentReminderDay = 10; // J+10 apres l'invitation (decision 3)
const kRenewalReminderDays = Object.freeze([45, 15]); // J-45 (art. 9), J-15 (decision 14)
const kRenewalSendLeadDays = 1; // le rappel J-45 part des J-46, pour tenir l'echeance
const kGraceReminderDays = Object.freeze([5, 10]); // relances J+5 et J+10 (decision 9)
const kCheckoutLockMs = 60 * 1000;

const ymdUtc = (ymd) => Date.UTC(ymd.y, ymd.m - 1, ymd.d);
/** Jours calendaires (Paris) de la date de fromMs a celle de toMs. */
function parisDaysBetween(fromMs, toMs) {
  return Math.round((ymdUtc(parisDate(toMs)) - ymdUtc(parisDate(fromMs))) / 86400000);
}

/** Echeance d'un rappel « au moins N jours avant » : fin du jour de Paris echeance - N. */
function renewalReminderDeadline(renewalMs, days) {
  return endOfParisDay(addDays(parisDate(renewalMs), -days));
}

function renewalReminderKey(days, renewalMs) {
  return `renewal_reminder_${days}_${Math.floor(renewalMs / 1000)}`;
}

function reminderDocId(subscriptionId, renewalMs) {
  return `${subscriptionId}_${Math.floor(renewalMs / 1000)}`;
}

/** Une alerte admin par tache, objet et jour de Paris (pas de rafale horaire). */
async function alertOnce(db, {task, id, contractId = null, detail, nowMs}) {
  const day = parisDate(nowMs);
  const ref = db.collection("schedule_alerts").doc(`${task}_${id}_${day.y}${String(day.m).padStart(2, "0")}${String(day.d).padStart(2, "0")}`);
  const created = await db.runTransaction(async (tx) => {
    if ((await tx.get(ref)).exists) return false;
    tx.set(ref, {task, object_id: id, contract_id: contractId, at: admin.firestore.Timestamp.fromMillis(nowMs)});
    return true;
  });
  if (created) await mail.raiseAdminAlert(db, {kind: `planifie_${task}`, contractId, detail});
}

async function eachDoc(docs, stats, fn) {
  for (const doc of docs) {
    try {
      const outcome = await fn(doc);
      if (outcome) stats[outcome] = (stats[outcome] || 0) + 1;
    } catch (error) {
      stats.errors = (stats.errors || 0) + 1;
      console.error(`[merchant_contracts] tache planifiee : echec sur ${doc.ref.path}`, String(error?.message || error).slice(0, 300));
    }
  }
  return stats;
}

// --- 1. Fin du delai de retractation -----------------------------------------

async function endWithdrawalPeriods(db, nowMs) {
  const snap = await db.collection(kContractsCollection).where("state", "==", kStates.WITHDRAWAL_PENDING).get();
  return eachDoc(snap.docs, {}, async (doc) => {
    const deadline = millisOf(doc.data().withdrawal_deadline);
    if (!deadline || nowMs <= deadline) return "waiting";
    await payment.inviteAfterWithdrawalPeriod(db, doc.id, {actor: "schedule", nowMs});
    return "invited";
  });
}

// --- 2. Rappel de paiement a J+10 -----------------------------------------------

async function sendPaymentReminders(db, nowMs) {
  const snap = await db.collection(kContractsCollection).where("state", "==", kStates.PAYMENT_INVITED).get();
  return eachDoc(snap.docs, {}, async (doc) => {
    const contract = doc.data();
    const invitedMs = millisOf(contract.payment_invited_at);
    const expiresMs = millisOf(contract.payment_link_expires_at);
    if (!invitedMs || !expiresMs) return "not_invited_yet";
    if (parisDaysBetween(invitedMs, nowMs) < kPaymentReminderDay) return "waiting";
    const invitation = (await internalRef(db, doc.id).get()).data()?.payment_invitation || {};
    if (invitation.reminder_sent_at || invitation.reminder_queued_at) return "already";
    if (nowMs > expiresMs) {
      await alertOnce(db, {task: "rappel_paiement", id: doc.id, contractId: doc.id, nowMs,
        detail: "Lien de paiement expiré sans rappel envoyé : clôture impossible (art. 8.1). Décision manuelle."});
      return "expired_without_reminder";
    }
    const outcome = await payment.issuePaymentInvitation(db, doc.id, {actor: "schedule", reminder: true});
    return outcome.sent ? "reminded" : "queued";
  });
}

// --- 3. Cloture a 15 jours ----------------------------------------------------------

/** Derniere session Checkout du contrat, relue chez Stripe : true si elle ne peut plus etre payee. */
async function lastSessionClosed(internal, nowMs) {
  const checkout = internal.checkout || {};
  const lockAt = millisOf(checkout.lock_at);
  if (lockAt && nowMs - lockAt < kCheckoutLockMs) return {closed: false, why: "checkout_in_progress"};
  if (!checkout.session_id) return {closed: true, sessionId: null};
  const session = await stripeClientModule.getStripeClient().checkout.sessions.retrieve(checkout.session_id);
  if (session?.status === "expired") return {closed: true, sessionId: checkout.session_id};
  // open : peut encore etre payee ; complete : paiement en cours de traitement par le webhook.
  return {closed: false, why: `session_${session?.status || "inconnue"}`};
}

async function closeUnpaidContracts(db, nowMs) {
  const snap = await db.collection(kContractsCollection).where("state", "==", kStates.PAYMENT_INVITED).get();
  return eachDoc(snap.docs, {}, async (doc) => {
    const expiresMs = millisOf(doc.data().payment_link_expires_at);
    if (!expiresMs || nowMs <= expiresMs) return "waiting";
    const internal = (await internalRef(db, doc.id).get()).data() || {};
    if (!internal.payment_invitation?.reminder_sent_at) {
      await alertOnce(db, {task: "cloture", id: doc.id, contractId: doc.id, nowMs,
        detail: "Lien expiré mais aucun rappel envoyé : la souscription n'est pas close (art. 8.1). Décision manuelle."});
      return "no_reminder";
    }
    const session = await lastSessionClosed(internal, nowMs);
    if (!session.closed) return "session_open";
    const closed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const freshInternal = (await tx.get(internalRef(db, doc.id))).data() || {};
      const contract = fresh.data();
      if (contract.state !== kStates.PAYMENT_INVITED) return null;
      // Une session creee depuis la lecture Stripe : on attend la prochaine execution.
      if ((freshInternal.checkout?.session_id || null) !== session.sessionId || freshInternal.checkout?.lock_at) return null;
      const nowTs = admin.firestore.Timestamp.fromMillis(nowMs);
      const revocations = await payment.revokeOpenTokens(tx, db, doc.id, nowTs);
      revocations.forEach((revoke) => revoke());
      tx.update(doc.ref, {state: kStates.CLOSED_UNPAID, state_version: (contract.state_version || 1) + 1,
        closed_at: nowTs, updated_at: admin.firestore.FieldValue.serverTimestamp()});
      tx.set(eventRef(db, doc.id), {type: "closed_unpaid", at: nowTs, actor: "schedule", last_session_id: session.sessionId});
      return contract;
    });
    if (!closed) return "changed";
    await mail.sendAndRecord(db, doc.id, "closure", emails.closureNotice(closed, doc.id, {expiresMs}));
    return "closed";
  });
}

// --- 4. Rappels de renouvellement J-45 et J-15 ------------------------------------

async function sendRenewalReminders(db, nowMs) {
  const snap = await db.collection(kEnseigneSubscriptionsCollection).where("status", "==", "active").get();
  return eachDoc(snap.docs, {}, async (doc) => {
    const mirror = doc.data();
    const renewalMs = millisOf(mirror.current_period_end);
    if (!mirror.contract_id || !mirror.stripe_subscription_id || !renewalMs || renewalMs <= nowMs) return "skipped";
    if (mirror.cancel_at_period_end === true || millisOf(mirror.cancel_at)) return "renewal_disabled";
    const daysLeft = parisDaysBetween(nowMs, renewalMs);
    const due = kRenewalReminderDays.filter((days) => daysLeft <= days + (days === 45 ? kRenewalSendLeadDays : 0));
    if (due.length === 0) return "waiting";
    const contractSnap = await db.collection(kContractsCollection).doc(mirror.contract_id).get();
    const contract = contractSnap.data();
    if (!contract || contract.state !== kStates.ACTIVE) return "contract_not_active";
    const ref = db.collection(kRenewalRemindersCollection).doc(reminderDocId(mirror.stripe_subscription_id, renewalMs));
    let sentAny = false;
    // Le plus proche de l'echeance seulement (un seul e-mail par execution).
    const days = Math.min(...due);
    const field = `j${days}`;
    const claimed = await db.runTransaction(async (tx) => {
      const current = (await tx.get(ref)).data() || {};
      if (current[field]) return null;
      // J-15 deja du : le J-45 reste trace (missed s'il n'est jamais parti), sans second e-mail.
      const deadlineMs = renewalReminderDeadline(renewalMs, days);
      tx.set(ref, {
        contract_id: mirror.contract_id,
        enseigne_id: doc.id,
        subscription_id: mirror.stripe_subscription_id,
        renewal_at: admin.firestore.Timestamp.fromMillis(renewalMs),
        [field]: {
          mail_key: renewalReminderKey(days, renewalMs),
          deadline_at: admin.firestore.Timestamp.fromMillis(deadlineMs),
          started_at: admin.firestore.Timestamp.fromMillis(nowMs),
          status: "sending",
        },
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return {deadlineMs};
    });
    if (!claimed) return "already";
    const offer = contract.offer || {};
    const sent = await mail.sendAndRecord(db, mirror.contract_id, renewalReminderKey(days, renewalMs), emails.renewalReminder(contract,
      mirror.contract_id, {renewalMs, amountTtcCents: offer.renewal_ttc_cents, amountHtCents: offer.renewal_ht_cents, days}));
    const late = sent && nowMs > claimed.deadlineMs;
    await ref.set({[field]: {
      status: sent ? "sent" : "queued",
      ...(sent ? {sent_at: admin.firestore.Timestamp.fromMillis(nowMs)} : {}),
      ...(days === 45 && late ? {missed: true, missed_reason: "envoye_apres_echeance"} : {}),
    }}, {merge: true});
    if (days === 45 && late) {
      await mail.raiseAdminAlert(db, {kind: "rappel_renouvellement_manque", contractId: mirror.contract_id,
        detail: `Rappel des 45 jours envoyé après l'échéance du rappel (art. 9) : remboursement possible sur demande sous 30 jours après le prélèvement.`});
    }
    sentAny = true;
    return sentAny ? `reminded_j${days}` : "already";
  });
}

/**
 * Rappel J-45 dont l'echeance est passee : on le declare envoye a temps
 * (internal.emails[cle].sent_at <= echeance, envoi direct ou par la file de
 * reprise) ou missed. Un abonnement actif sans rappel trace est missed aussi.
 */
async function markMissedRenewalReminders(db, nowMs) {
  const stats = {};
  const pending = await db.collection(kRenewalRemindersCollection).get();
  await eachDoc(pending.docs, stats, async (doc) => {
    const j45 = doc.data().j45;
    if (!j45 || j45.missed === true || j45.missed === false) return "settled";
    const deadlineMs = millisOf(j45.deadline_at);
    if (!deadlineMs || nowMs <= deadlineMs) return "waiting";
    const record = (await internalRef(db, doc.data().contract_id).get()).data()?.emails?.[j45.mail_key];
    const sentMs = millisOf(record?.sent_at);
    const onTime = !!sentMs && sentMs <= deadlineMs;
    await doc.ref.set({j45: {missed: !onTime, ...(onTime ? {sent_at: record.sent_at} : {missed_reason: "non_envoye_a_temps"})}}, {merge: true});
    if (!onTime) {
      await mail.raiseAdminAlert(db, {kind: "rappel_renouvellement_manque", contractId: doc.data().contract_id,
        detail: "Rappel des 45 jours non envoyé à temps (art. 9) : remboursement possible sur demande sous 30 jours après le prélèvement."});
    }
    return onTime ? "on_time" : "missed";
  });
  // Abonnements actifs dont l'echeance du rappel J-45 est passee sans aucune trace.
  const active = await db.collection(kEnseigneSubscriptionsCollection).where("status", "==", "active").get();
  await eachDoc(active.docs, stats, async (doc) => {
    const mirror = doc.data();
    const renewalMs = millisOf(mirror.current_period_end);
    if (!mirror.contract_id || !mirror.stripe_subscription_id || !renewalMs) return "skipped";
    if (mirror.cancel_at_period_end === true || millisOf(mirror.cancel_at)) return "renewal_disabled";
    const deadlineMs = renewalReminderDeadline(renewalMs, 45);
    if (nowMs <= deadlineMs || nowMs > renewalMs) return "skipped";
    const ref = db.collection(kRenewalRemindersCollection).doc(reminderDocId(mirror.stripe_subscription_id, renewalMs));
    const created = await db.runTransaction(async (tx) => {
      if ((await tx.get(ref)).data()?.j45) return false;
      tx.set(ref, {contract_id: mirror.contract_id, enseigne_id: doc.id, subscription_id: mirror.stripe_subscription_id,
        renewal_at: admin.firestore.Timestamp.fromMillis(renewalMs),
        j45: {mail_key: renewalReminderKey(45, renewalMs), deadline_at: admin.firestore.Timestamp.fromMillis(deadlineMs),
          status: "absent", missed: true, missed_reason: "aucun_envoi"},
        updated_at: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
      return true;
    });
    if (!created) return "traced";
    await mail.raiseAdminAlert(db, {kind: "rappel_renouvellement_manque", contractId: mirror.contract_id,
      detail: "Aucun rappel des 45 jours envoyé avant l'échéance du rappel (art. 9) : remboursement possible sur demande sous 30 jours après le prélèvement."});
    return "missed_absent";
  });
  return stats;
}

// --- 5. Relances pendant la grace et 6. fin de grace --------------------------------

async function graceMirrors(db) {
  return (await db.collection(kEnseigneSubscriptionsCollection).where("status", "in", [...kGraceStatuses]).get()).docs;
}

async function sendGraceReminders(db, nowMs, docs) {
  return eachDoc(docs, {}, async (doc) => {
    const mirror = doc.data();
    const invoiceId = mirror.last_failed_invoice_id;
    const startedMs = millisOf(mirror.grace_started_at);
    const graceUntilMs = millisOf(mirror.grace_until);
    if (!mirror.contract_id || !invoiceId || !startedMs || !graceUntilMs || nowMs > graceUntilMs) return "skipped";
    const contract = (await db.collection(kContractsCollection).doc(mirror.contract_id).get()).data();
    if (!contract || contract.state !== kStates.ACTIVE) return "contract_not_active";
    const elapsed = parisDaysBetween(startedMs, nowMs);
    const due = [0, ...kGraceReminderDays].filter((day) => elapsed >= day);
    const day = Math.max(...due);
    const ref = internalRef(db, mirror.contract_id);
    const claimed = await db.runTransaction(async (tx) => {
      const internal = (await tx.get(ref)).data() || {};
      const sentDays = internal.grace_reminders?.[invoiceId] || {};
      // J0 : la notification immediate du webhook (art. 11) vaut relance J0.
      const j0Done = !!internal.renewal_failures?.[invoiceId] || !!sentDays.d0;
      if (day === 0 && j0Done) return null;
      if (day > 0 && sentDays[`d${day}`]) return null;
      tx.set(ref, {grace_reminders: {[invoiceId]: {[`d${day}`]: admin.firestore.Timestamp.fromMillis(nowMs)}},
        ...(day === 0 ? {renewal_failures: {[invoiceId]: {notified_at: admin.firestore.Timestamp.fromMillis(nowMs), by: "schedule"}}} : {}),
      }, {merge: true});
      return true;
    });
    if (!claimed) return "already";
    await mail.sendAndRecord(db, mirror.contract_id, `grace_${invoiceId}_d${day}`, emails.graceReminder(contract, mirror.contract_id, {
      day, graceUntilMs, invoiceUrl: mirror.unpaid_invoice_url || null,
    }));
    return `reminded_d${day}`;
  });
}

async function endGracePeriods(db, nowMs, docs) {
  return eachDoc(docs, {}, async (doc) => {
    const graceUntilMs = millisOf(doc.data().grace_until);
    if (!doc.data().contract_id || !graceUntilMs || nowMs <= graceUntilMs) return "waiting";
    const mirror = await db.runTransaction(async (tx) => {
      const fresh = (await tx.get(doc.ref)).data();
      if (fresh.suspended_at || !kGraceStatuses.includes(fresh.status)) return null;
      tx.update(doc.ref, {suspended_at: admin.firestore.Timestamp.fromMillis(nowMs), updated_at: admin.firestore.FieldValue.serverTimestamp()});
      return fresh;
    });
    if (!mirror) return "already";
    const contractId = mirror.contract_id;
    const contract = (await db.collection(kContractsCollection).doc(contractId).get()).data();
    await eventRef(db, contractId).set({type: "grace_ended", at: admin.firestore.Timestamp.fromMillis(nowMs), actor: "schedule",
      invoice_id: mirror.last_failed_invoice_id || null});
    if (contract?.owner_email) {
      await mail.sendAndRecord(db, contractId, `grace_ended_${mirror.last_failed_invoice_id || "x"}`, emails.graceEndedNotice(contract,
        contractId, {graceUntilMs, invoiceUrl: mirror.unpaid_invoice_url || null}));
    }
    await mail.raiseAdminAlert(db, {kind: "fin_de_grace", contractId,
      detail: "Délai de régularisation expiré sans paiement : suspension notifiée (art. 11). Résiliation possible après mise en demeure (lot 1.12)."});
    return "suspended";
  });
}

/** Execution complete ; inerte si l'interrupteur n'est pas strictement true. */
async function runMerchantContractSchedule({db = admin.firestore(), nowMs = Date.now()} = {}) {
  const config = await readContractsConfig(db);
  if (config.enabled !== true) return {skipped: "disabled"};
  const stats = {};
  stats.withdrawal_end = await endWithdrawalPeriods(db, nowMs);
  stats.payment_reminders = await sendPaymentReminders(db, nowMs);
  stats.closures = await closeUnpaidContracts(db, nowMs);
  stats.renewal_reminders = await sendRenewalReminders(db, nowMs);
  stats.renewal_missed = await markMissedRenewalReminders(db, nowMs);
  const grace = await graceMirrors(db);
  stats.grace_reminders = await sendGraceReminders(db, nowMs, grace);
  stats.grace_end = await endGracePeriods(db, nowMs, grace);
  return stats;
}

const merchantContractSchedule = onSchedule({
  schedule: "0 * * * *",
  timeZone: "Europe/Paris",
  region: kFunctionsRegion,
  memory: "256MiB",
  timeoutSeconds: 300,
  secrets: ["STRIPE_SECRET_KEY"],
}, async () => {
  const stats = await runMerchantContractSchedule();
  console.log("[merchant_contracts] taches planifiees", JSON.stringify(stats));
});

module.exports = {
  kRenewalRemindersCollection,
  kRenewalReminderDays,
  kGraceReminderDays,
  parisDaysBetween,
  renewalReminderDeadline,
  renewalReminderKey,
  reminderDocId,
  runMerchantContractSchedule,
  merchantContractSchedule,
};

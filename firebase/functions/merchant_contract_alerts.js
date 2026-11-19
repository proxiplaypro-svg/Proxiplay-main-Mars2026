// Phase 1, tranche 1, lot 1.3 : alertes administratives sur les demandes en
// attente de verification (CGV B2B V2.1, art. 4.1 ; checklist A) :
//   - alerte apres un jour ouvre sans decision ;
//   - alerte prioritaire au-dela de deux jours ouvres (delai depasse).
// Jours ouvres : lundi a vendredi hors jours feries francais, heure de Paris.
// Aucune validation tacite, aucun refus automatique : la tache ne fait
// qu'alerter. Chaque alerte part au plus une fois (marqueur dans les donnees
// internes du dossier, pose en transaction avant l'envoi).

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {
  kFunctionsRegion,
  kContractsCollection,
  kStates,
  readContractsConfig,
  internalRef,
  millisOf,
} = require("./merchant_contracts_model");
const {addBusinessDays} = require("./paris_time");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

const kClaimTtlMs = 15 * 60 * 1000;

function dueDates(submittedMs) {
  return {firstDue: addBusinessDays(submittedMs, 1), deadline: addBusinessDays(submittedMs, 2)};
}

function levelFor(nowMs, {firstDue, deadline}) {
  if (nowMs > deadline) return "priority";
  if (nowMs >= firstDue) return "first";
  return null;
}

/** Pose le marqueur d'envoi ; renvoie false si deja envoye, en cours ou plus utile. */
async function claimAlert(db, contractId, level, nowMs) {
  return db.runTransaction(async (tx) => {
    const contract = await tx.get(db.collection(kContractsCollection).doc(contractId));
    const internal = await tx.get(internalRef(db, contractId));
    if (!contract.exists || contract.data().state !== kStates.SUBMITTED) return false;
    const alerts = internal.exists ? internal.data().alerts || {} : {};
    if (alerts[level]?.sent_at || alerts.priority?.sent_at) return false;
    const claimedAt = millisOf(alerts[level]?.claimed_at);
    if (claimedAt && nowMs - claimedAt < kClaimTtlMs) return false;
    tx.set(internalRef(db, contractId), {alerts: {[level]: {claimed_at: admin.firestore.Timestamp.fromMillis(nowMs)}}}, {merge: true});
    return true;
  });
}

async function runMerchantContractAlerts({db = admin.firestore(), nowMs = Date.now()} = {}) {
  const config = await readContractsConfig(db);
  if (!config.enabled) return {skipped: "contracts_disabled"};
  const snap = await db.collection(kContractsCollection).where("state", "==", kStates.SUBMITTED).get();
  const stats = {pending: snap.size, first: 0, priority: 0, failed: 0};
  for (const doc of snap.docs) {
    const contract = doc.data();
    const submittedMs = millisOf(contract.submitted_at);
    if (!submittedMs) continue;
    const dates = dueDates(submittedMs);
    const level = levelFor(nowMs, dates);
    if (!level || !(await claimAlert(db, doc.id, level, nowMs))) continue;
    const message = emails.adminPendingAlert({...contract, admin_alert_email: config.adminAlertEmail}, doc.id,
      {level, submittedMs, deadlineMs: dates.deadline});
    const ref = internalRef(db, doc.id);
    try {
      const result = await mail.sendContractMail(message);
      await ref.set({alerts: {[level]: {
        sent_at: admin.firestore.Timestamp.fromMillis(nowMs),
        message_id: result?.messageId || null,
        claimed_at: admin.firestore.FieldValue.delete(),
      }}}, {merge: true});
      stats[level] += 1;
    } catch (error) {
      console.error(`[merchant_contracts] alerte ${level} non envoyee contrat=${doc.id}`, error?.message || error);
      await ref.set({alerts: {[level]: {
        failed_at: admin.firestore.Timestamp.fromMillis(nowMs),
        error: String(error?.message || error).slice(0, 300),
        claimed_at: admin.firestore.FieldValue.delete(),
      }}}, {merge: true});
      stats.failed += 1;
    }
  }
  return stats;
}

exports.merchantContractAlerts = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 300, memory: "256MB"})
  .pubsub.schedule("every 60 minutes")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const stats = await runMerchantContractAlerts();
    console.log("[merchant_contracts] alertes", JSON.stringify(stats));
    return null;
  });

exports.runMerchantContractAlerts = runMerchantContractAlerts;
exports.dueDates = dueDates;
exports.levelFor = levelFor;

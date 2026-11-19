// Envoi des e-mails du parcours de souscription (phase 1). Reutilise le
// module SMTP existant (lib/notifications/email_sender.js). Sous emulateur,
// aucun e-mail ne part ; les tests remplacent l'envoi par un enregistreur
// (setSender). Le resultat de chaque envoi est trace dans les donnees
// internes du contrat (internal/record.emails), jamais visible du commercant.
//
// Le SMTP est un point de defaillance unique (les e-mails Stripe sont
// desactives) : tout echec est journalise, mis dans une file de reprise
// (mail_outbox) avec nouvelles tentatives espacees, et signale a
// l'administration (admin_alerts, visible dans la console, plus un e-mail
// d'alerte quand le SMTP le permet).

const admin = require("firebase-admin");
const emailSender = require("./lib/notifications/email_sender");
const {isFunctionsEmulator} = require("./lib/emulator_runtime");
const {internalRef} = require("./merchant_contracts_model");

const kOutboxCollection = "mail_outbox";
const kAdminAlertsCollection = "admin_alerts";
const kMaxAttempts = 5;
const kFirstRetryMs = 15 * 60 * 1000;
const kMaxRetryDelayMs = 6 * 60 * 60 * 1000;

let customSender = null;

/** Tests uniquement : remplace l'envoi (null = comportement normal). */
function setSender(sender) {
  customSender = typeof sender === "function" ? sender : null;
}

async function sendContractMail(message) {
  if (customSender) return customSender(message);
  if (isFunctionsEmulator() || process.env.FIRESTORE_EMULATOR_HOST) {
    console.log(`[merchant_contracts] e-mail non envoye (emulateur) to=${message.to} subject=${message.subject}`);
    return {suppressed: true, messageId: message.messageId || null};
  }
  await emailSender.sendTextEmail(message);
  return {messageId: message.messageId || null};
}

function retryDelayMs(attempts) {
  return Math.min(kFirstRetryMs * 2 ** Math.max(0, attempts - 1), kMaxRetryDelayMs);
}

function errorText(error) {
  return String(error?.message || error).slice(0, 300);
}

/**
 * Alerte administrative : document lu par la console (toujours), plus un
 * e-mail a l'adresse des alertes (souvent impossible si le SMTP est en panne :
 * son propre echec est seulement journalise, sans boucle).
 */
async function raiseAdminAlert(db, {kind, contractId = null, outboxId = null, detail}) {
  await db.collection(kAdminAlertsCollection).add({
    kind, contract_id: contractId, outbox_id: outboxId, detail: String(detail || "").slice(0, 500),
    resolved: false, created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  try {
    const {readContractsConfig} = require("./merchant_contracts_model");
    const config = await readContractsConfig(db);
    await sendContractMail({
      to: config.adminAlertEmail,
      subject: `[ProxiPlay] Alerte : ${kind}`,
      text: `${detail}\n\nDemande : ${contractId || "—"}\nFile de reprise : ${outboxId || "—"}\n` +
        "Détail dans la console admin (page Souscriptions, e-mails en échec).",
    });
  } catch (error) {
    console.error("[merchant_contracts] alerte admin non envoyee par e-mail", errorText(error));
  }
}

/** Met un envoi echoue dans la file de reprise et alerte l'administration. */
async function enqueueRetry(db, {kind, contractId, key, message = null, error}) {
  const ref = await db.collection(kOutboxCollection).add({
    kind, // "message" (texte stocke, sans secret) ou "payment_invitation" (regenere)
    contract_id: contractId,
    key,
    message: message ? {to: message.to, subject: message.subject, text: message.text} : null,
    status: "pending",
    attempts: 1,
    last_error: errorText(error),
    next_attempt_at: admin.firestore.Timestamp.fromMillis(Date.now() + retryDelayMs(1)),
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  await raiseAdminAlert(db, {kind: "email_echec", contractId, outboxId: ref.id,
    detail: `Échec d'envoi de l'e-mail « ${key} » ; nouvelle tentative programmée. Erreur : ${errorText(error)}`});
  return ref.id;
}

async function recordSent(db, contractId, key, result) {
  await internalRef(db, contractId).set({emails: {[key]: {
    sent_at: admin.firestore.FieldValue.serverTimestamp(),
    message_id: result?.messageId || null,
    suppressed: result?.suppressed === true,
    failed_at: admin.firestore.FieldValue.delete(),
    error: admin.firestore.FieldValue.delete(),
  }}}, {merge: true});
}

async function recordFailed(db, contractId, key, error) {
  await internalRef(db, contractId).set({emails: {[key]: {
    failed_at: admin.firestore.FieldValue.serverTimestamp(),
    error: errorText(error),
  }}}, {merge: true});
}

/**
 * Envoie et trace le resultat sans jamais faire echouer l'operation metier
 * deja enregistree. En cas d'echec : trace, file de reprise, alerte admin.
 */
async function sendAndRecord(db, contractId, key, message) {
  try {
    const result = await sendContractMail(message);
    await recordSent(db, contractId, key, result);
    return true;
  } catch (error) {
    console.error(`[merchant_contracts] echec e-mail ${key} contrat=${contractId}`, errorText(error));
    await recordFailed(db, contractId, key, error);
    await enqueueRetry(db, {kind: "message", contractId, key, message, error});
    return false;
  }
}

// Traitements de reprise par type (payment_invitation est enregistre par le
// lot 1.6 : le jeton n'est jamais stocke en clair, l'invitation est regeneree).
const retryHandlers = {
  message: async (db, item) => {
    const result = await sendContractMail(item.message);
    await recordSent(db, item.contract_id, item.key, result);
  },
};

function registerRetryHandler(kind, handler) {
  retryHandlers[kind] = handler;
}

/** Tache de reprise : une tentative par entree due, espacement croissant. */
async function runMailOutbox({db = admin.firestore(), nowMs = Date.now()} = {}) {
  // Egalite seule (pas d'index composite) ; l'echeance est filtree ici.
  const snap = await db.collection(kOutboxCollection).where("status", "==", "pending").get();
  const stats = {pending: snap.size, sent: 0, retried: 0, failed: 0};
  for (const doc of snap.docs) {
    const due = doc.data().next_attempt_at?.toMillis?.() ?? 0;
    if (due > nowMs) continue;
    // Bail : une seule execution traite une entree a la fois.
    const claimed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const item = fresh.data();
      if (item.status !== "pending" || (item.next_attempt_at?.toMillis?.() ?? 0) > nowMs) return null;
      tx.update(doc.ref, {next_attempt_at: admin.firestore.Timestamp.fromMillis(nowMs + kFirstRetryMs)});
      return item;
    });
    if (!claimed) continue;
    const handler = retryHandlers[claimed.kind];
    try {
      if (!handler) throw new Error(`type inconnu : ${claimed.kind}`);
      await handler(db, claimed);
      await doc.ref.update({status: "sent", sent_at: admin.firestore.Timestamp.fromMillis(nowMs),
        attempts: claimed.attempts + 1});
      stats.sent += 1;
    } catch (error) {
      const attempts = claimed.attempts + 1;
      const finalFailure = attempts >= kMaxAttempts;
      await doc.ref.update({
        attempts,
        last_error: errorText(error),
        status: finalFailure ? "failed" : "pending",
        next_attempt_at: admin.firestore.Timestamp.fromMillis(nowMs + retryDelayMs(attempts)),
      });
      if (finalFailure) {
        stats.failed += 1;
        await raiseAdminAlert(db, {kind: "email_abandonne", contractId: claimed.contract_id, outboxId: doc.id,
          detail: `E-mail « ${claimed.key} » non envoyé après ${attempts} tentatives : action manuelle requise.`});
      } else {
        stats.retried += 1;
      }
    }
  }
  return stats;
}

module.exports = {
  kOutboxCollection,
  kAdminAlertsCollection,
  kMaxAttempts,
  setSender,
  sendContractMail,
  sendAndRecord,
  enqueueRetry,
  raiseAdminAlert,
  recordSent,
  recordFailed,
  registerRetryHandler,
  runMailOutbox,
  retryDelayMs,
};

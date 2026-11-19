// Envoi des e-mails du parcours de souscription (phase 1). Reutilise le
// module SMTP existant (lib/notifications/email_sender.js). Sous emulateur,
// aucun e-mail ne part ; les tests remplacent l'envoi par un enregistreur
// (setSender). Le resultat de chaque envoi est trace dans les donnees
// internes du contrat (internal/record.emails), jamais visible du commercant.

const admin = require("firebase-admin");
const emailSender = require("./lib/notifications/email_sender");
const {isFunctionsEmulator} = require("./lib/emulator_runtime");
const {internalRef} = require("./merchant_contracts_model");

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

/**
 * Envoie et trace le resultat sans jamais faire echouer l'operation metier
 * deja enregistree (accuse de reception, alertes informatives).
 */
async function sendAndRecord(db, contractId, key, message) {
  const ref = internalRef(db, contractId);
  try {
    const result = await sendContractMail(message);
    await ref.set({emails: {[key]: {
      sent_at: admin.firestore.FieldValue.serverTimestamp(),
      message_id: result?.messageId || null,
      suppressed: result?.suppressed === true,
    }}}, {merge: true});
    return true;
  } catch (error) {
    console.error(`[merchant_contracts] echec e-mail ${key} contrat=${contractId}`, error?.message || error);
    await ref.set({emails: {[key]: {
      failed_at: admin.firestore.FieldValue.serverTimestamp(),
      error: String(error?.message || error).slice(0, 300),
    }}}, {merge: true});
    return false;
  }
}

module.exports = {setSender, sendContractMail, sendAndRecord};

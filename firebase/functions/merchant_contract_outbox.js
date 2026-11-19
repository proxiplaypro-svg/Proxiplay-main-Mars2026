// File de reprise des e-mails du parcours de souscription (SMTP = point de
// defaillance unique) : tache planifiee toutes les 15 minutes, actions admin
// (relancer maintenant, abandonner, marquer une alerte comme traitee).

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {kFunctionsRegion, httpsError, assertAdminCaller} = require("./merchant_contracts_model");
const mail = require("./merchant_contract_mail");
// Enregistre la reprise des invitations a payer (regeneration du jeton).
require("./merchant_contract_payment");

function idOf(data, field) {
  const id = typeof data?.[field] === "string" ? data[field].trim() : "";
  if (!id) throw httpsError("invalid-argument", `Champ requis : ${field}.`, {reason: "invalid_field", field});
  return id;
}

async function adminRetryMailOutboxHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const ref = db.collection(mail.kOutboxCollection).doc(idOf(data, "outboxId"));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpsError("not-found", "Entrée inconnue.", {reason: "outbox_not_found"});
    if (snap.data().status === "sent") throw httpsError("failed-precondition", "Déjà envoyé.", {reason: "already_sent"});
    tx.update(ref, {status: "pending", next_attempt_at: admin.firestore.Timestamp.now(), retried_by: adminUid});
  });
  return {status: "pending"};
}

async function adminAbandonMailOutboxHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const ref = db.collection(mail.kOutboxCollection).doc(idOf(data, "outboxId"));
  const snap = await ref.get();
  if (!snap.exists) throw httpsError("not-found", "Entrée inconnue.", {reason: "outbox_not_found"});
  if (snap.data().status === "sent") throw httpsError("failed-precondition", "Déjà envoyé.", {reason: "already_sent"});
  await ref.update({status: "abandoned", abandoned_by: adminUid, abandoned_at: admin.firestore.FieldValue.serverTimestamp()});
  return {status: "abandoned"};
}

async function adminResolveAlertHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const ref = db.collection(mail.kAdminAlertsCollection).doc(idOf(data, "alertId"));
  if (!(await ref.get()).exists) throw httpsError("not-found", "Alerte inconnue.", {reason: "alert_not_found"});
  await ref.update({resolved: true, resolved_by: adminUid, resolved_at: admin.firestore.FieldValue.serverTimestamp()});
  return {resolved: true};
}

const callable = (handler) => functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(handler);

module.exports = {
  adminRetryMailOutboxHandler,
  adminAbandonMailOutboxHandler,
  adminResolveAlertHandler,
  adminRetryMailOutbox: callable(adminRetryMailOutboxHandler),
  adminAbandonMailOutbox: callable(adminAbandonMailOutboxHandler),
  adminResolveAlert: callable(adminResolveAlertHandler),
  merchantMailOutbox: functions
    .region(kFunctionsRegion)
    .runWith({timeoutSeconds: 300, memory: "256MB"})
    .pubsub.schedule("every 15 minutes")
    .timeZone("Europe/Paris")
    .onRun(async () => {
      const stats = await mail.runMailOutbox();
      console.log("[merchant_contracts] file de reprise", JSON.stringify(stats));
      return null;
    }),
};

// Phase 1, tranche 1, lot 1.4b : origine d'une souscription (CGV B2B V2.1,
// art. 4.2). Une souscription est « demarchee » lorsqu'elle est realisee :
//   - au moyen d'un lien de souscription remis par un representant
//     (rep_links, empreinte SHA-256 du jeton : le jeton n'est jamais stocke) ;
//   - au moyen d'un code promotionnel remis par un representant
//     (promo_codes.rep_id) ;
//   - ou lorsque le Partenaire declare avoir recu la visite d'un representant.
// Les autres souscriptions sont « spontanees ». L'origine est fixee par le
// serveur a la demande. En cas de doute (lien non reconnu, lien d'un
// commercial desactive...), le regime le plus favorable au Partenaire
// s'applique : demarchee. Apres la conclusion, le Partenaire qui a recu une
// visite non enregistree peut la signaler dans les 14 jours : la
// souscription passe definitivement en « demarchee ».
//
// Les effets (aucun paiement avant la fin du delai de retractation,
// retractation, remboursement) relevent de la tranche 2.

const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {assertMerchantCaller} = require("./merchant_billing_access");
const {
  kFunctionsRegion,
  kContractsCollection,
  kSalesRepsCollection,
  kRepLinksCollection,
  kStates,
  httpsError,
  assertContractsEnabled,
  assertAdminCaller,
  normalizeSiret,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const {visitReportDeadline} = require("./paris_time");

const kTokenPattern = /^[A-Za-z0-9_-]{20,128}$/;

function hashToken(token) {
  return crypto.createHash("sha256").update(token, "utf8").digest("hex");
}

async function resolveOrigin(db, {tx = null, repLinkToken, promo = null, visitDeclared = false} = {}) {
  const sources = [];
  const evidence = {sources, rep_id: null, link_hash: null, code: null};
  let prefill = null;
  let linkRef = null;
  let linkFirstUse = false;
  const token = typeof repLinkToken === "string" ? repLinkToken.trim() : "";
  if (token) {
    if (kTokenPattern.test(token)) {
      const hash = hashToken(token);
      evidence.link_hash = hash;
      const ref = db.collection(kRepLinksCollection).doc(hash);
      const snap = tx ? await tx.get(ref) : await ref.get();
      if (snap.exists) {
        sources.push("link");
        evidence.rep_id = snap.data().rep_id || null;
        prefill = snap.data().prefill || null;
        linkRef = ref;
        linkFirstUse = !snap.data().first_used_at;
      } else {
        sources.push("link_unrecognized");
      }
    } else {
      sources.push("link_unrecognized");
    }
  }
  if (promo?.repId) {
    sources.push("code");
    evidence.code = promo.code;
    evidence.rep_id = evidence.rep_id || promo.repId;
  }
  if (visitDeclared === true) sources.push("declaration");
  return {
    type: sources.length ? "demarchee" : "spontanee",
    evidence,
    prefill: prefill ? {enseigneName: prefill.enseigne_name || null, siret: prefill.siret || null} : null,
    linkRef,
    linkFirstUse,
  };
}

/** Date de commande enregistree sur le lien nominatif (checklist B). */
function markRepLinkUsed(db, tx, resolved, contractId) {
  if (!resolved?.linkRef) return;
  const now = admin.firestore.FieldValue.serverTimestamp();
  tx.set(resolved.linkRef, {
    ...(resolved.linkFirstUse ? {first_used_at: now} : {}),
    last_used_at: now,
    last_contract_id: contractId,
    uses: admin.firestore.FieldValue.increment(1),
  }, {merge: true});
}

async function validateRepIdForCode(db, repId) {
  if (repId === undefined || repId === null || repId === "") return null;
  const snap = typeof repId === "string" ? await db.collection(kSalesRepsCollection).doc(repId).get() : null;
  if (!snap?.exists) {
    throw httpsError("invalid-argument", "Commercial inconnu.", {reason: "invalid_field", field: "repId"});
  }
  return repId;
}

function visitReportEmails(contract, contractId, config) {
  const emails = require("./merchant_contract_emails");
  return [
    ["visit_report_ack", emails.visitReportAcknowledgement(contract)],
    ["visit_report_admin", emails.adminVisitReport({...contract, admin_alert_email: config.adminAlertEmail}, contractId)],
  ];
}

/**
 * Commercant : signale la visite d'un representant non enregistree. Possible
 * avant la confirmation, puis jusqu'a la fin du 14e jour suivant la
 * conclusion (heure de Paris). Definitif ; idempotent.
 */
async function reportMerchantVisitHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  const config = await assertContractsEnabled(db);
  const uid = context.auth.uid;
  const contractId = typeof data?.contractId === "string" ? data.contractId.trim() : "";
  if (!contractId) throw httpsError("invalid-argument", "Demande inconnue.", {reason: "invalid_field", field: "contractId"});
  const ref = db.collection(kContractsCollection).doc(contractId);
  const nowMs = Date.now();
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().owner_uid !== uid) {
      throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
    }
    const contract = snap.data();
    if (![kStates.SUBMITTED, kStates.CONFIRMED].includes(contract.state)) {
      throw httpsError("failed-precondition", "Ce signalement n'est plus possible pour cette demande.", {reason: "not_reportable"});
    }
    if (contract.state === kStates.CONFIRMED) {
      const deadline = millisOf(contract.visit_report_deadline) || visitReportDeadline(millisOf(contract.confirmed_at));
      if (nowMs > deadline) {
        throw httpsError("failed-precondition",
          "Le délai de quatorze jours suivant la conclusion du contrat est dépassé (art. 4.2).", {reason: "report_deadline_passed"});
      }
    }
    if (contract.origin?.type === "demarchee") return {changed: false, contract};
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.update(ref, {
      "origin.type": "demarchee",
      "origin.reported_at": now,
      "state_version": (contract.state_version || 1) + 1,
      "updated_at": now,
    });
    tx.set(internalRef(db, contractId), {origin_evidence: {
      sources: admin.firestore.FieldValue.arrayUnion("report"),
      report: {at: now, previous_type: contract.origin?.type || null},
    }}, {merge: true});
    tx.set(eventRef(db, contractId), {type: "visit_reported", at: now, actor: "merchant", actor_uid: uid,
      previous_origin: contract.origin?.type || null});
    return {changed: true, contract: {...contract, origin: {...contract.origin, type: "demarchee"}}};
  });
  if (outcome.changed) {
    const mail = require("./merchant_contract_mail");
    for (const [key, message] of visitReportEmails(outcome.contract, contractId, config)) {
      await mail.sendAndRecord(db, contractId, key, message);
    }
  }
  return {origin: "demarchee", changed: outcome.changed};
}

function adminText(value, field, {min = 1, max = 120} = {}) {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (trimmed.length < min || trimmed.length > max) {
    throw httpsError("invalid-argument", `Champ invalide : ${field}.`, {reason: "invalid_field", field});
  }
  return trimmed;
}

/** Admin : cree ou modifie un commercial. */
async function adminUpsertSalesRepHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  // Fonction admin : utilisable interrupteur coupe, pour preparer l'ouverture.
  const name = adminText(data?.name, "name", {min: 2});
  const email = data?.email ? adminText(data.email, "email", {max: 200}) : null;
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw httpsError("invalid-argument", "E-mail invalide.", {reason: "invalid_field", field: "email"});
  }
  const ref = typeof data?.repId === "string" && data.repId.trim() ?
    db.collection(kSalesRepsCollection).doc(data.repId.trim()) : db.collection(kSalesRepsCollection).doc();
  await ref.set({
    name, email, active: data?.active !== false,
    updated_at: admin.firestore.FieldValue.serverTimestamp(), updated_by: adminUid,
  }, {merge: true});
  return {repId: ref.id};
}

/**
 * Admin : cree un lien de souscription nominatif pour un commercial et un
 * commercant. Le jeton n'est renvoye qu'une fois ; seule son empreinte est
 * stockee, avec le commercial, la date d'envoi et le preremplissage.
 */
async function adminCreateRepLinkHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  // Fonction admin : utilisable interrupteur coupe, pour preparer l'ouverture.
  const repId = typeof data?.repId === "string" ? data.repId.trim() : "";
  const rep = repId ? await db.collection(kSalesRepsCollection).doc(repId).get() : null;
  if (!rep?.exists || rep.data().active === false) {
    throw httpsError("invalid-argument", "Commercial inconnu ou desactive.", {reason: "invalid_field", field: "repId"});
  }
  const enseigneName = data?.enseigneName ? adminText(data.enseigneName, "enseigneName", {min: 2}) : null;
  const siret = data?.siret ? normalizeSiret(data.siret) : null;
  const sentAt = data?.sentAt ? new Date(data.sentAt) : new Date();
  if (Number.isNaN(sentAt.getTime())) {
    throw httpsError("invalid-argument", "Date d'envoi invalide.", {reason: "invalid_field", field: "sentAt"});
  }
  const token = crypto.randomBytes(24).toString("base64url");
  await db.collection(kRepLinksCollection).doc(hashToken(token)).create({
    rep_id: repId,
    prefill: {enseigne_name: enseigneName, siret},
    sent_at: admin.firestore.Timestamp.fromDate(sentAt),
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: adminUid,
    uses: 0,
    first_used_at: null,
  });
  return {token, path: `/espace-commercant/?lien=${token}`};
}

const callable = (handler) => functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(handler);

module.exports = {
  kTokenPattern,
  hashToken,
  resolveOrigin,
  markRepLinkUsed,
  validateRepIdForCode,
  reportMerchantVisitHandler,
  adminUpsertSalesRepHandler,
  adminCreateRepLinkHandler,
  reportMerchantVisit: callable(reportMerchantVisitHandler),
  adminUpsertSalesRep: callable(adminUpsertSalesRepHandler),
  adminCreateRepLink: callable(adminCreateRepLinkHandler),
};

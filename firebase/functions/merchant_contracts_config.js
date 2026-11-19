// Phase 1, tranche 1 (correction) : outil admin qui ecrit
// app_config/merchant_contracts (interrupteur, CGV en vigueur, adresse des
// alertes), avec validation et journal (merchant_contracts_config_log).
//
// Gardes :
//   - l'interrupteur ne peut passer a true que si des CGV sont configurees ;
//   - toute CGV enregistree (et toute ouverture) exige que le PDF lu dans
//     Storage au chemin indique ait exactement l'empreinte declaree ;
//   - chaque modification est journalisee (avant, apres, auteur, heure).

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {
  kFunctionsRegion,
  kConfigDocPath,
  httpsError,
  assertAdminCaller,
} = require("./merchant_contracts_model");
const cgvDocument = require("./merchant_cgv_document");

const kConfigLogCollection = "merchant_contracts_config_log";

function invalid(field, message) {
  return httpsError("invalid-argument", message, {reason: "invalid_field", field});
}

function readCgvInput(raw) {
  if (raw === null) return null;
  const version = typeof raw?.version === "string" ? raw.version.trim() : "";
  const sha256 = typeof raw?.sha256 === "string" ? raw.sha256.trim().toLowerCase() : "";
  const storagePath = typeof raw?.storagePath === "string" ? raw.storagePath.trim() : "";
  const url = typeof raw?.url === "string" ? raw.url.trim() : "";
  const effectiveDate = typeof raw?.effectiveDate === "string" ? raw.effectiveDate.trim() : "";
  if (!/^[0-9A-Za-z.\-]{1,20}$/.test(version)) throw invalid("cgv.version", "Version des CGV invalide.");
  if (!/^[0-9a-f]{64}$/.test(sha256)) throw invalid("cgv.sha256", "Empreinte SHA-256 invalide (64 caractères hexadécimaux).");
  if (!/^[A-Za-z0-9_\-./]{1,300}$/.test(storagePath) || storagePath.includes("..") || storagePath.startsWith("/") ||
      !storagePath.toLowerCase().endsWith(".pdf")) {
    throw invalid("cgv.storagePath", "Chemin Storage du PDF invalide.");
  }
  let parsed = null;
  try {
    parsed = new URL(url);
  } catch (_) {
    parsed = null;
  }
  if (!parsed || parsed.protocol !== "https:") throw invalid("cgv.url", "Adresse publique des CGV invalide (https requis).");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(effectiveDate) || Number.isNaN(Date.parse(`${effectiveDate}T00:00:00Z`))) {
    throw invalid("cgv.effectiveDate", "Date d'entrée en vigueur invalide (AAAA-MM-JJ).");
  }
  return {version, sha256, storage_path: storagePath, url, effective_date: effectiveDate};
}

async function assertPdfMatches(cgv) {
  let pdf;
  try {
    pdf = await cgvDocument.loadCgvPdf(cgv.storage_path);
  } catch (error) {
    throw httpsError("failed-precondition", "PDF des CGV introuvable dans Storage.", {reason: "cgv_pdf_missing"});
  }
  if (cgvDocument.sha256(pdf) !== cgv.sha256) {
    throw httpsError("failed-precondition", "Le PDF des CGV ne correspond pas à l'empreinte déclarée.", {reason: "cgv_pdf_mismatch"});
  }
}

/**
 * Admin : met a jour un ou plusieurs champs. Champs absents = inchanges.
 * {enabled?: boolean, cgv?: {...} | null, adminAlertEmail?: string | null}
 */
async function adminUpdateMerchantContractsConfigHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const changes = {};
  if (data && Object.prototype.hasOwnProperty.call(data, "enabled")) {
    if (typeof data.enabled !== "boolean") throw invalid("enabled", "L'interrupteur doit valoir true ou false.");
    changes.enabled = data.enabled;
  }
  if (data && Object.prototype.hasOwnProperty.call(data, "cgv")) {
    changes.cgv = readCgvInput(data.cgv);
  }
  if (data && Object.prototype.hasOwnProperty.call(data, "adminAlertEmail")) {
    const email = data.adminAlertEmail === null ? null :
      typeof data.adminAlertEmail === "string" ? data.adminAlertEmail.trim() : "";
    if (email !== null && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      throw invalid("adminAlertEmail", "Adresse des alertes invalide.");
    }
    changes.admin_alert_email = email;
  }
  if (!Object.keys(changes).length) throw invalid("config", "Aucune modification.");

  const ref = db.doc(kConfigDocPath);
  const current = (await ref.get()).data() || {};
  const next = {...current, ...changes};
  if (next.enabled === true && !next.cgv) {
    throw httpsError("failed-precondition", "Impossible d'ouvrir le parcours sans CGV configurées.", {reason: "cgv_not_configured"});
  }
  // Le PDF est verifie a chaque enregistrement de CGV et a chaque ouverture.
  if (next.cgv && (changes.cgv || (changes.enabled === true && current.enabled !== true))) {
    await assertPdfMatches(next.cgv);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const before = snap.exists ? snap.data() : {};
    const after = {...before, ...changes};
    tx.set(ref, {...changes, updated_at: now, updated_by: adminUid}, {merge: true});
    tx.set(db.collection(kConfigLogCollection).doc(), {
      at: now,
      by: adminUid,
      changes,
      before: {enabled: before.enabled ?? null, cgv: before.cgv ?? null, admin_alert_email: before.admin_alert_email ?? null},
      after: {enabled: after.enabled ?? null, cgv: after.cgv ?? null, admin_alert_email: after.admin_alert_email ?? null},
    });
  });
  return {enabled: next.enabled === true, cgv: next.cgv || null, adminAlertEmail: next.admin_alert_email || null};
}

exports.adminUpdateMerchantContractsConfig = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(adminUpdateMerchantContractsConfigHandler);

exports.adminUpdateMerchantContractsConfigHandler = adminUpdateMerchantContractsConfigHandler;
exports.kConfigLogCollection = kConfigLogCollection;

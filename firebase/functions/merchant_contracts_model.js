// Phase 1, tranche 1 : modele des demandes de souscription et des contrats
// commercants (CGV B2B V2.1). Un contrat = UNE enseigne (art. 3) ; le SIRET
// peut etre partage entre plusieurs enseignes ; le doublon d'enseigne est
// controle a la main par l'admin (lot 1.2-min).
//
// Organisation des donnees (ecrites UNIQUEMENT par les Cloud Functions) :
//   merchant_contracts/{id}                 vue filtree lisible par le
//                                            commercant proprietaire
//   merchant_contracts/{id}/internal/record donnees internes (verification,
//                                            motif interne, preuves, alertes,
//                                            envoi des e-mails) : admin seul
//   merchant_contracts/{id}/events/{id}     journal : admin seul
//   sales_reps, rep_links, promo_codes      admin seul
//   app_config/merchant_contracts           interrupteur + CGV : admin seul
//
// Interrupteur : app_config/merchant_contracts.enabled doit valoir
// strictement true pour ouvrir les NOUVELLES VENTES (apercu et envoi d'une
// demande). Absent, false ou toute autre valeur : nouvelles ventes en pause
// (refus avant toute ecriture, aucun e-mail). Les contrats existants restent
// suivis quel que soit l'interrupteur : espace commercant, signalement de
// visite, retractation, page de paiement d'un contrat deja invite, webhook,
// fonctions admin (confirmation comprise).

const functions = require("firebase-functions");
const {getOfferOrThrow} = require("./merchant_offers");
const {shopOwnerPath} = require("./merchant_ownership");
const {isTrustedAdmin} = require("./admin_identity");

const kFunctionsRegion = "us-central1";
const kContractsCollection = "merchant_contracts";
const kInternalSubcollection = "internal";
const kInternalDocId = "record";
const kEventsSubcollection = "events";
const kSalesRepsCollection = "sales_reps";
const kRepLinksCollection = "rep_links";
const kPromoCodesCollection = "promo_codes";
const kConfigDocPath = "app_config/merchant_contracts";
const kDefaultAdminAlertEmail = "contact@proxiplay.fr";

const kStates = Object.freeze({
  SUBMITTED: "submitted",
  CONFIRMED: "confirmed",
  REFUSED: "refused",
  // Tranche 2 : apres la conclusion.
  WITHDRAWAL_PENDING: "withdrawal_pending", // demarchee : delai de retractation en cours
  PAYMENT_INVITED: "payment_invited", // invitation a payer, lien de 15 jours
  ACTIVE: "active", // paiement confirme, service actif
  WITHDRAWN: "withdrawn", // retractation exercee (art. 7)
  CLOSED_UNPAID: "closed_unpaid", // close sans paiement (art. 8.1)
  ENDED: "ended", // contrat termine (end_reason)
});

// confirmed n'est qu'un passage : la confirmation aiguille aussitot vers
// withdrawal_pending (demarchee) ou payment_invited (spontanee, art. 8.1).
const kTransitions = Object.freeze({
  submitted: Object.freeze(["confirmed", "refused"]),
  confirmed: Object.freeze(["withdrawal_pending", "payment_invited"]),
  withdrawal_pending: Object.freeze(["payment_invited", "withdrawn"]),
  // retour a withdrawal_pending : visite signalee apres coup (art. 4.2).
  payment_invited: Object.freeze(["active", "withdrawn", "withdrawal_pending", "closed_unpaid"]),
  active: Object.freeze(["withdrawn", "ended"]),
  refused: Object.freeze([]),
  withdrawn: Object.freeze([]),
  closed_unpaid: Object.freeze([]),
  ended: Object.freeze([]),
});

// Etats qui occupent une enseigne : une seconde demande pour la meme
// enseigne est refusee tant que l'un d'eux existe.
const kOpenStates = Object.freeze(["submitted", "confirmed", "withdrawal_pending", "payment_invited", "active"]);

// Les 8 controles de la verification avant confirmation (checklist G).
const kChecks = Object.freeze([
  "siret", "identity", "activity", "duplicate", "offer", "origin", "cgv", "fraud",
]);
const kCheckResults = Object.freeze(["pass", "fail", "manual"]);

// TVA : taux normal (CGV V2.1 art. 5, a confirmer avec le comptable).
const kVatRateBasisPoints = 2000;

function httpsError(code, message, details) {
  return new functions.https.HttpsError(code, message, details);
}

function assertTransition(from, to) {
  const allowed = kTransitions[from] || [];
  if (!allowed.includes(to)) {
    throw httpsError("failed-precondition", `Transition interdite : ${from} -> ${to}.`, {reason: "invalid_transition"});
  }
}

function normalizeSiret(raw) {
  return typeof raw === "string" ? raw.replace(/[\s.]/g, "") : "";
}

// SIRET : 14 chiffres, cle de Luhn. Exception connue : La Poste (SIREN
// 356000000), dont les etablissements suivent une somme des chiffres
// multiple de 5. Controle hors ligne uniquement : l'entreprise active est
// verifiee a la main (Annuaire des entreprises) dans la premiere version.
function isValidSiret(raw) {
  const siret = normalizeSiret(raw);
  if (!/^\d{14}$/.test(siret)) return false;
  if (siret.startsWith("356000000")) {
    const sum = [...siret].reduce((total, digit) => total + Number(digit), 0);
    return sum % 5 === 0;
  }
  let sum = 0;
  for (let index = 0; index < 14; index++) {
    let digit = Number(siret[13 - index]);
    if (index % 2 === 1) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 === 0;
}

function ttcFromHt(amountHtCents) {
  return amountHtCents + Math.round(amountHtCents * kVatRateBasisPoints / 10000);
}

/**
 * Instantane du prix, toujours depuis le catalogue (jamais un montant fourni
 * par le client) : premiere annee (remise eventuelle) et renouvellement.
 */
function offerSnapshot(offerId, promo = null) {
  const offer = getOfferOrThrow(offerId);
  const discountHtCents = promo ? Math.min(promo.discountHtCents, offer.amountHtCents - 100) : 0;
  const firstYearHtCents = offer.amountHtCents - discountHtCents;
  return {
    id: offer.id,
    label: offer.label,
    currency: "eur",
    vat_rate_basis_points: kVatRateBasisPoints,
    catalog_ht_cents: offer.amountHtCents,
    discount_ht_cents: discountHtCents,
    first_year_ht_cents: firstYearHtCents,
    first_year_ttc_cents: ttcFromHt(firstYearHtCents),
    renewal_ht_cents: offer.amountHtCents,
    renewal_ttc_cents: ttcFromHt(offer.amountHtCents),
    duration_months: 12,
  };
}

async function readContractsConfig(db) {
  const snap = await db.doc(kConfigDocPath).get();
  const data = snap.exists ? snap.data() : {};
  const cgv = data.cgv && typeof data.cgv === "object" ? data.cgv : null;
  const cgvReady = !!cgv &&
    typeof cgv.version === "string" && cgv.version.trim() !== "" &&
    typeof cgv.sha256 === "string" && /^[0-9a-f]{64}$/.test(cgv.sha256) &&
    typeof cgv.storage_path === "string" && cgv.storage_path.trim() !== "" &&
    typeof cgv.url === "string" && /^https:\/\//.test(cgv.url);
  return {
    enabled: data.enabled === true,
    cgv: cgvReady ? {
      version: cgv.version.trim(),
      sha256: cgv.sha256,
      storagePath: cgv.storage_path.trim(),
      url: cgv.url,
      effectiveDate: typeof cgv.effective_date === "string" ? cgv.effective_date : null,
    } : null,
    adminAlertEmail: typeof data.admin_alert_email === "string" && data.admin_alert_email.includes("@") ?
      data.admin_alert_email.trim() : kDefaultAdminAlertEmail,
    // Tranche 2a (decision 16) : avoir avec chaque remboursement, sous reserve
    // de validation par le comptable. Desactive par defaut.
    creditNotesEnabled: data.credit_notes_enabled === true,
  };
}

/** Nouvelles ventes seulement : refus avant toute ecriture si elles sont en pause. */
async function assertContractsEnabled(db) {
  const config = await readContractsConfig(db);
  if (!config.enabled) {
    throw httpsError("failed-precondition", "Les nouvelles souscriptions en ligne sont momentanément suspendues.",
      {reason: "contracts_disabled"});
  }
  return config;
}

function assertCgvConfigured(config) {
  if (!config.cgv) {
    throw httpsError("failed-precondition", "Les conditions generales de vente ne sont pas encore publiees.",
      {reason: "cgv_not_configured"});
  }
  return config.cgv;
}

async function assertAdminCaller(db, context) {
  if (!context?.auth?.uid) {
    throw httpsError("unauthenticated", "Connexion requise.");
  }
  const snap = await db.collection("users").doc(context.auth.uid).get();
  if (!isTrustedAdmin(context.auth, snap.exists ? snap.data() : {})) {
    throw httpsError("permission-denied", "Reserve a l'administration.");
  }
  return context.auth.uid;
}

function ownsEnseigne(enseigneData, uid) {
  return !!uid && shopOwnerPath(enseigneData || {}) === `users/${uid}`;
}

async function findOpenContractForEnseigne(db, enseigneId, {tx = null, excludeContractId = null} = {}) {
  const query = db.collection(kContractsCollection)
    .where("enseigne_id", "==", enseigneId)
    .where("state", "in", kOpenStates);
  const snap = tx ? await tx.get(query) : await query.get();
  return snap.docs.find((doc) => doc.id !== excludeContractId) || null;
}

function internalRef(db, contractId) {
  return db.collection(kContractsCollection).doc(contractId)
    .collection(kInternalSubcollection).doc(kInternalDocId);
}

function eventRef(db, contractId) {
  return db.collection(kContractsCollection).doc(contractId).collection(kEventsSubcollection).doc();
}

function millisOf(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return typeof value === "number" ? value : null;
}

/**
 * Vue renvoyee au commercant : jamais les donnees internes (verification,
 * notes, journal, motif interne, preuves d'origine, adresse IP).
 */
function merchantView(id, data = {}) {
  return {
    id,
    state: data.state || null,
    enseigneId: data.enseigne_id || null,
    enseigneName: data.enseigne_name || data.enseigne_request?.name || null,
    siret: data.siret || null,
    raisonSociale: data.raison_sociale || null,
    offer: data.offer || null,
    promoCode: data.promo?.code || null,
    origin: data.origin?.type || null,
    originReportedAt: millisOf(data.origin?.reported_at),
    cgvVersion: data.cgv?.version || null,
    submittedAt: millisOf(data.submitted_at),
    confirmedAt: millisOf(data.confirmed_at),
    refusedAt: millisOf(data.refused_at),
    refusal: data.public_refusal ? {
      motif: data.public_refusal.motif || null,
      detail: data.public_refusal.detail || null,
    } : null,
    visitReportDeadline: millisOf(data.visit_report_deadline),
    // Tranche 2
    withdrawalDeadline: millisOf(data.withdrawal_deadline),
    withdrawnAt: millisOf(data.withdrawn_at),
    paymentInvitedAt: millisOf(data.payment_invited_at),
    paymentLinkExpiresAt: millisOf(data.payment_link_expires_at),
    activatedAt: millisOf(data.activated_at),
    endedAt: millisOf(data.ended_at),
    endReason: data.end_reason || null,
    closedAt: millisOf(data.closed_at), // lot 1.9
  };
}

module.exports = {
  kFunctionsRegion,
  kContractsCollection,
  kInternalSubcollection,
  kInternalDocId,
  kEventsSubcollection,
  kSalesRepsCollection,
  kRepLinksCollection,
  kPromoCodesCollection,
  kConfigDocPath,
  kDefaultAdminAlertEmail,
  kStates,
  kTransitions,
  kOpenStates,
  kChecks,
  kCheckResults,
  kVatRateBasisPoints,
  httpsError,
  assertTransition,
  normalizeSiret,
  isValidSiret,
  ttcFromHt,
  offerSnapshot,
  readContractsConfig,
  assertContractsEnabled,
  assertCgvConfigured,
  assertAdminCaller,
  ownsEnseigne,
  findOpenContractForEnseigne,
  internalRef,
  eventRef,
  millisOf,
  merchantView,
};

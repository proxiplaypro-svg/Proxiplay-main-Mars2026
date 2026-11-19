// Phase 1, tranche 1, lot 1.1 : demande de souscription (CGV B2B V2.1, art. 4).
//
// Le commercant connecte choisit une enseigne (une des siennes, ou une
// nouvelle enseigne decrite, que l'admin creera avant la confirmation), une
// offre du catalogue, un code eventuel ; il accepte les CGV (case non
// precochee, version et empreinte en vigueur) et la clause attributive de
// competence (art. 25). Le serveur fixe seul le prix (catalogue + miroir
// promo_codes), enregistre la preuve d'acceptation (heure serveur, adresse
// IP, version et empreinte des CGV) et cree la demande a l'etat
// "submitted". Rien n'est encaisse, aucun appel Stripe.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {assertMerchantCaller} = require("./merchant_billing_access");
const {getOfferOrThrow} = require("./merchant_offers");
const {
  kFunctionsRegion,
  kContractsCollection,
  kPromoCodesCollection,
  kStates,
  httpsError,
  assertContractsEnabled,
  assertCgvConfigured,
  assertAdminCaller,
  normalizeSiret,
  isValidSiret,
  offerSnapshot,
  ownsEnseigne,
  findOpenContractForEnseigne,
  internalRef,
  eventRef,
} = require("./merchant_contracts_model");
const origin = require("./merchant_contract_origin");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

const kMaxPendingPerOwner = 3;
const kPromoCodePattern = /^[A-Z0-9_-]{3,32}$/;

function text(value, {field, min = 1, max = 200, pattern = null}) {
  const trimmed = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  if (trimmed.length < min || trimmed.length > max || (pattern && !pattern.test(trimmed))) {
    throw httpsError("invalid-argument", `Champ invalide : ${field}.`, {reason: "invalid_field", field});
  }
  return trimmed;
}

function normalizePromoCode(raw) {
  if (raw === undefined || raw === null || raw === "") return null;
  const code = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  if (!kPromoCodePattern.test(code)) {
    throw httpsError("invalid-argument", "Code promotionnel invalide.", {reason: "promo_invalid"});
  }
  return code;
}

/**
 * Code promotionnel : miroir Firestore gere par l'admin (source unique, sens
 * Firestore vers Stripe en tranche 2). Remise sur la premiere annee seulement.
 */
async function resolvePromo(db, rawCode, offerId, {tx = null, nowMs = Date.now()} = {}) {
  const code = normalizePromoCode(rawCode);
  if (!code) return null;
  const ref = db.collection(kPromoCodesCollection).doc(code);
  const snap = tx ? await tx.get(ref) : await ref.get();
  const data = snap.exists ? snap.data() : null;
  const validUntil = data?.valid_until?.toMillis ? data.valid_until.toMillis() : null;
  const offers = Array.isArray(data?.offers) ? data.offers : [];
  const exhausted = Number.isInteger(data?.max_uses) && (data.uses || 0) >= data.max_uses;
  if (!data || data.active !== true || (validUntil !== null && validUntil <= nowMs) ||
      (offers.length && !offers.includes(offerId)) || exhausted) {
    throw httpsError("not-found", "Ce code promotionnel n'existe pas, a expiré ou ne s'applique pas à cette offre.",
      {reason: "promo_invalid"});
  }
  const catalog = getOfferOrThrow(offerId).amountHtCents;
  const discountHtCents = data.kind === "percent" ?
    Math.round(catalog * data.value / 100) : data.value_cents;
  return {code, discountHtCents, repId: typeof data.rep_id === "string" ? data.rep_id : null};
}

function readEnseigneRequest(raw) {
  return {
    name: text(raw?.name, {field: "enseigne.name", min: 2, max: 120}),
    address: text(raw?.address, {field: "enseigne.address", min: 5, max: 200}),
    postal_code: text(raw?.postalCode, {field: "enseigne.postalCode", pattern: /^\d{5}$/}),
    city: text(raw?.city, {field: "enseigne.city", min: 1, max: 100}),
  };
}

function clientIp(context) {
  const forwarded = context?.rawRequest?.headers?.["x-forwarded-for"];
  const first = typeof forwarded === "string" ? forwarded.split(",")[0].trim() : "";
  return first || context?.rawRequest?.ip || null;
}

/** Recapitulatif avant validation : prix et origine calcules par le serveur. */
async function previewMerchantContractHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  const config = await assertContractsEnabled(db);
  const cgv = assertCgvConfigured(config);
  const offerId = typeof data?.offerId === "string" ? data.offerId.trim() : "";
  getOfferOrThrow(offerId);
  const promo = await resolvePromo(db, data?.promoCode, offerId);
  const resolved = await origin.resolveOrigin(db, {
    repLinkToken: data?.repLinkToken, promo, visitDeclared: data?.visitDeclared === true,
  });
  return {
    offer: offerSnapshot(offerId, promo),
    promoCode: promo?.code || null,
    origin: resolved.type,
    prefill: resolved.prefill || null,
    cgv: {version: cgv.version, url: cgv.url, sha256: cgv.sha256},
  };
}

async function submitMerchantSubscriptionRequestHandler(data, context) {
  const db = admin.firestore();
  const user = await assertMerchantCaller(db, context);
  const config = await assertContractsEnabled(db);
  const cgv = assertCgvConfigured(config);
  const uid = context.auth.uid;

  if (data?.cgvAccepted !== true) {
    throw httpsError("invalid-argument", "Vous devez accepter les conditions générales de vente.", {reason: "cgv_not_accepted"});
  }
  if (data?.cgvVersion !== cgv.version || data?.cgvSha256 !== cgv.sha256) {
    throw httpsError("failed-precondition", "Les conditions générales de vente ont changé : rechargez la page.", {reason: "cgv_outdated"});
  }
  if (data?.jurisdictionClauseAccepted !== true) {
    throw httpsError("invalid-argument", "Vous devez accepter expressément la clause attributive de compétence (art. 25).",
      {reason: "jurisdiction_not_accepted"});
  }
  const siret = normalizeSiret(data?.siret);
  if (!isValidSiret(siret)) {
    throw httpsError("invalid-argument", "Numéro SIRET invalide.", {reason: "invalid_siret"});
  }
  const raisonSociale = text(data?.raisonSociale, {field: "raisonSociale", min: 2, max: 160});
  const offerId = typeof data?.offerId === "string" ? data.offerId.trim() : "";
  getOfferOrThrow(offerId);

  let enseigneId = null;
  let enseigneName = null;
  let enseigneRequest = null;
  if (typeof data?.enseigneId === "string" && data.enseigneId.trim()) {
    enseigneId = data.enseigneId.trim();
    const snap = await db.collection("enseignes").doc(enseigneId).get();
    if (!snap.exists || !ownsEnseigne(snap.data(), uid)) {
      throw httpsError("permission-denied", "Cette enseigne n'est pas rattachée à votre compte.", {reason: "enseigne_not_owned"});
    }
    enseigneName = snap.data().name || enseigneId;
  } else {
    enseigneRequest = readEnseigneRequest(data?.enseigneRequest);
    enseigneName = enseigneRequest.name;
  }

  const ownerEmail = context.auth.token?.email || user.email || "";
  if (!ownerEmail.includes("@")) {
    throw httpsError("failed-precondition", "Aucune adresse e-mail sur le compte.", {reason: "no_email"});
  }
  const ip = clientIp(context);
  const contractRef = db.collection(kContractsCollection).doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const contract = await db.runTransaction(async (tx) => {
    const promo = await resolvePromo(db, data?.promoCode, offerId, {tx});
    const resolved = await origin.resolveOrigin(db, {
      tx, repLinkToken: data?.repLinkToken, promo, visitDeclared: data?.visitDeclared === true,
    });
    const pending = await tx.get(db.collection(kContractsCollection)
      .where("owner_uid", "==", uid).where("state", "==", kStates.SUBMITTED));
    if (pending.size >= kMaxPendingPerOwner) {
      throw httpsError("resource-exhausted", "Trop de demandes en cours de vérification.", {reason: "too_many_pending"});
    }
    if (enseigneId && await findOpenContractForEnseigne(db, enseigneId, {tx})) {
      throw httpsError("already-exists", "Une demande ou un contrat existe déjà pour cette enseigne.", {reason: "enseigne_busy"});
    }
    const record = {
      owner_uid: uid,
      owner_email: ownerEmail,
      state: kStates.SUBMITTED,
      state_version: 1,
      enseigne_id: enseigneId,
      enseigne_name: enseigneName,
      enseigne_request: enseigneRequest,
      siret,
      raison_sociale: raisonSociale,
      offer: offerSnapshot(offerId, promo),
      promo: promo ? {code: promo.code, discount_ht_cents: offerSnapshot(offerId, promo).discount_ht_cents} : null,
      cgv: {version: cgv.version, sha256: cgv.sha256, url: cgv.url, accepted_at: now},
      jurisdiction_clause_accepted_at: now,
      origin: {type: resolved.type, decided_at: now},
      submitted_at: now,
      updated_at: now,
    };
    tx.set(contractRef, record);
    tx.set(internalRef(db, contractRef.id), {
      acceptance: {ip, cgv_version: cgv.version, cgv_sha256: cgv.sha256, jurisdiction_clause: true, accepted_at: now},
      origin_evidence: resolved.evidence,
      verification: {checks: {}},
      alerts: {},
      emails: {},
    });
    tx.set(eventRef(db, contractRef.id), {type: "submitted", at: now, actor: "merchant", actor_uid: uid, origin: resolved.type});
    origin.markRepLinkUsed(db, tx, resolved, contractRef.id);
    return record;
  });

  const forMail = {...contract, cgv: {version: cgv.version}, admin_alert_email: config.adminAlertEmail};
  await mail.sendAndRecord(db, contractRef.id, "request_ack", emails.requestAcknowledgement(forMail));
  await mail.sendAndRecord(db, contractRef.id, "admin_new_request", emails.adminNewRequest(forMail, contractRef.id));
  return {contractId: contractRef.id, state: kStates.SUBMITTED, origin: contract.origin.type};
}

/**
 * Admin : cree ou modifie un code du miroir promo_codes. Remise de premiere
 * annee seulement. Le code Stripe correspondant sera cree par le serveur en
 * tranche 2 (sens unique) : stripe_promotion_code_id n'est jamais saisi ici.
 */
async function adminUpsertPromoCodeHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  // Fonction admin : utilisable interrupteur coupe, pour preparer l'ouverture.
  const code = normalizePromoCode(data?.code);
  if (!code) throw httpsError("invalid-argument", "Code requis.", {reason: "promo_invalid"});
  const kind = data?.kind;
  const value = data?.value;
  if (!(kind === "percent" && Number.isInteger(value) && value >= 1 && value <= 100) &&
      !(kind === "amount" && Number.isInteger(value) && value >= 100)) {
    throw httpsError("invalid-argument", "Remise invalide (pourcentage 1 a 100, ou montant HT en centimes, au moins 100).",
      {reason: "invalid_field", field: "value"});
  }
  const offers = Array.isArray(data?.offers) ? data.offers : [];
  offers.forEach((offerId) => getOfferOrThrow(offerId));
  const validUntil = data?.validUntil ? new Date(data.validUntil) : null;
  if (validUntil && Number.isNaN(validUntil.getTime())) {
    throw httpsError("invalid-argument", "Date de fin invalide.", {reason: "invalid_field", field: "validUntil"});
  }
  const maxUses = data?.maxUses === undefined || data?.maxUses === null ? null : data.maxUses;
  if (maxUses !== null && !(Number.isInteger(maxUses) && maxUses >= 1)) {
    throw httpsError("invalid-argument", "Nombre d'utilisations invalide.", {reason: "invalid_field", field: "maxUses"});
  }
  const repId = await origin.validateRepIdForCode(db, data?.repId);
  const ref = db.collection(kPromoCodesCollection).doc(code);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    tx.set(ref, {
      code,
      kind,
      ...(kind === "percent" ? {value, value_cents: null} : {value: null, value_cents: value}),
      offers,
      valid_until: validUntil ? admin.firestore.Timestamp.fromDate(validUntil) : null,
      max_uses: maxUses,
      uses: snap.exists ? snap.data().uses || 0 : 0,
      rep_id: repId,
      active: data?.active !== false,
      first_year_only: true,
      stripe_promotion_code_id: snap.exists ? snap.data().stripe_promotion_code_id || null : null,
      ...(snap.exists ? {} : {created_at: admin.firestore.FieldValue.serverTimestamp()}),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_by: adminUid,
    });
  });
  return {code};
}

const callable = (handler) => functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(handler);

exports.previewMerchantContract = callable(previewMerchantContractHandler);
exports.submitMerchantSubscriptionRequest = callable(submitMerchantSubscriptionRequestHandler);
exports.adminUpsertPromoCode = callable(adminUpsertPromoCodeHandler);

exports.previewMerchantContractHandler = previewMerchantContractHandler;
exports.submitMerchantSubscriptionRequestHandler = submitMerchantSubscriptionRequestHandler;
exports.adminUpsertPromoCodeHandler = adminUpsertPromoCodeHandler;
exports.resolvePromo = resolvePromo;
exports.clientIp = clientIp;

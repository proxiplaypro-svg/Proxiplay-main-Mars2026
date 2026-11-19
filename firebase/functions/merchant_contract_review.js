// Phase 1, tranche 1, lot 1.2-min : verification manuelle avant confirmation
// (CGV B2B V2.1, art. 4.1 ; checklist G). Premiere version : toute demande
// est verifiee a la main. Aucune validation tacite, aucun refus automatique.
//
// - adminRecordMerchantContractChecks : saisit les 8 controles (resultat et
//   note interne) et rattache l'enseigne creee par l'admin avec l'outil
//   existant, au nom du demandeur.
// - adminRefuseMerchantContract : refus motive, possible uniquement avant la
//   confirmation ; le motif (art. 4.1) est communique au commercant, la note
//   interne ne l'est jamais.
// - adminFindSimilarEnseignes : aide au controle manuel du doublon
//   d'enseigne (nom normalise + code postal, fiche Google, SIRET).
//
// Chaque decision exige la version courante du dossier (expectedVersion) :
// deux admins ne peuvent pas decider sur un dossier perime.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {
  kFunctionsRegion,
  kContractsCollection,
  kStates,
  kChecks,
  kCheckResults,
  httpsError,
  assertTransition,
  assertAdminCaller,
  ownsEnseigne,
  findOpenContractForEnseigne,
  internalRef,
  eventRef,
} = require("./merchant_contracts_model");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

// Motifs de refus de l'art. 4.1 (communiques au commercant).
const kRefusalMotifs = Object.freeze({
  activity: "Activité incompatible avec les règles de PROXIPLAY",
  inaccurate: "Informations manifestement inexactes",
  fraud: "Risque de fraude",
  unavailable: "Indisponibilité de l'offre",
});

function contractIdOf(data) {
  const id = typeof data?.contractId === "string" ? data.contractId.trim() : "";
  if (!id) throw httpsError("invalid-argument", "Demande inconnue.", {reason: "invalid_field", field: "contractId"});
  return id;
}

function optionalText(value, field, max) {
  if (value === undefined || value === null || value === "") return null;
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed || trimmed.length > max) {
    throw httpsError("invalid-argument", `Champ invalide : ${field}.`, {reason: "invalid_field", field});
  }
  return trimmed;
}

/** Lit le dossier en transaction et verifie l'etat et la version attendue. */
async function loadForDecision(tx, db, contractId, expectedVersion) {
  const ref = db.collection(kContractsCollection).doc(contractId);
  const snap = await tx.get(ref);
  if (!snap.exists) throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
  const contract = snap.data();
  if (contract.state !== kStates.SUBMITTED) {
    throw httpsError("failed-precondition", "Cette demande n'est plus en attente de vérification.", {reason: "not_submitted"});
  }
  if (!Number.isInteger(expectedVersion) || expectedVersion !== contract.state_version) {
    throw httpsError("aborted", "Le dossier a changé depuis son affichage : rechargez-le.", {reason: "stale_version"});
  }
  return {ref, contract};
}

function readChecks(raw) {
  if (!raw || typeof raw !== "object") return {};
  const out = {};
  for (const [name, value] of Object.entries(raw)) {
    if (!kChecks.includes(name)) {
      throw httpsError("invalid-argument", `Contrôle inconnu : ${name}.`, {reason: "invalid_field", field: "checks"});
    }
    if (!kCheckResults.includes(value?.result)) {
      throw httpsError("invalid-argument", `Résultat invalide pour ${name}.`, {reason: "invalid_field", field: "checks"});
    }
    out[name] = {result: value.result, note: optionalText(value.note, `checks.${name}.note`, 500)};
  }
  return out;
}

async function adminRecordMerchantContractChecksHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  // Fonction admin : utilisable interrupteur coupe, pour preparer l'ouverture.
  const contractId = contractIdOf(data);
  const checks = readChecks(data?.checks);
  const enseigneId = typeof data?.enseigneId === "string" && data.enseigneId.trim() ? data.enseigneId.trim() : null;
  if (!Object.keys(checks).length && !enseigneId) {
    throw httpsError("invalid-argument", "Rien à enregistrer.", {reason: "invalid_field", field: "checks"});
  }
  return db.runTransaction(async (tx) => {
    const {ref, contract} = await loadForDecision(tx, db, contractId, data?.expectedVersion);
    let enseigneName = null;
    if (enseigneId) {
      const enseigne = await tx.get(db.collection("enseignes").doc(enseigneId));
      if (!enseigne.exists || !ownsEnseigne(enseigne.data(), contract.owner_uid)) {
        throw httpsError("failed-precondition", "L'enseigne doit exister et appartenir au demandeur.", {reason: "enseigne_not_owned"});
      }
      if (await findOpenContractForEnseigne(db, enseigneId, {tx, excludeContractId: contractId})) {
        throw httpsError("already-exists", "Une demande ou un contrat existe déjà pour cette enseigne.", {reason: "enseigne_busy"});
      }
      enseigneName = enseigne.data().name || enseigneId;
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const nextVersion = contract.state_version + 1;
    tx.update(ref, {
      state_version: nextVersion,
      updated_at: now,
      ...(enseigneId ? {enseigne_id: enseigneId, enseigne_name: enseigneName} : {}),
    });
    const stamped = Object.fromEntries(Object.entries(checks)
      .map(([name, value]) => [name, {...value, by: adminUid, at: now}]));
    tx.set(internalRef(db, contractId), {verification: {checks: stamped, reviewer_uid: adminUid}}, {merge: true});
    tx.set(eventRef(db, contractId), {
      type: "checks_recorded", at: now, actor: "admin", actor_uid: adminUid,
      checks: Object.fromEntries(Object.entries(checks).map(([name, value]) => [name, value.result])),
      ...(enseigneId ? {enseigne_id: enseigneId} : {}),
    });
    return {stateVersion: nextVersion};
  });
}

async function adminRefuseMerchantContractHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  // Fonction admin : utilisable interrupteur coupe, pour preparer l'ouverture.
  const contractId = contractIdOf(data);
  const motif = data?.motif;
  if (!Object.prototype.hasOwnProperty.call(kRefusalMotifs, motif)) {
    throw httpsError("invalid-argument", "Motif de refus requis (art. 4.1).", {reason: "invalid_field", field: "motif"});
  }
  const detail = optionalText(data?.detail, "detail", 300);
  const internalNote = optionalText(data?.internalNote, "internalNote", 1000);
  const refused = await db.runTransaction(async (tx) => {
    const {ref, contract} = await loadForDecision(tx, db, contractId, data?.expectedVersion);
    assertTransition(contract.state, kStates.REFUSED);
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.update(ref, {
      state: kStates.REFUSED,
      state_version: contract.state_version + 1,
      refused_at: now,
      public_refusal: {motif, detail},
      updated_at: now,
    });
    tx.set(internalRef(db, contractId), {refusal_reason: internalNote, refused_by: adminUid}, {merge: true});
    tx.set(eventRef(db, contractId), {type: "refused", at: now, actor: "admin", actor_uid: adminUid, motif});
    return contract;
  });
  const notified = await mail.sendAndRecord(db, contractId, "refusal",
    emails.refusalNotice({...refused, public_refusal: {motif, detail}}, kRefusalMotifs[motif]));
  return {state: kStates.REFUSED, notified};
}

function normalizeName(value) {
  return String(value || "").normalize("NFD").replace(/[̀-ͯ]/g, "")
    .toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

/** Aide au controle manuel du doublon : lecture seule. */
async function adminFindSimilarEnseignesHandler(data, context) {
  const db = admin.firestore();
  await assertAdminCaller(db, context);
  // Fonction admin : utilisable interrupteur coupe, pour preparer l'ouverture.
  const contractId = contractIdOf(data);
  const snap = await db.collection(kContractsCollection).doc(contractId).get();
  if (!snap.exists) throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
  const contract = snap.data();
  let name = contract.enseigne_request?.name || contract.enseigne_name || "";
  let postalCode = contract.enseigne_request?.postal_code || "";
  let placeId = null;
  if (contract.enseigne_id) {
    const current = await db.collection("enseignes").doc(contract.enseigne_id).get();
    if (current.exists) {
      name = current.data().name || name;
      postalCode = current.data().area_code || postalCode;
      placeId = current.data().google_place_id || null;
    }
  }
  const wanted = normalizeName(name);
  const enseignes = await db.collection("enseignes").select("name", "city", "area_code", "google_place_id", "owner", "owner_id").get();
  const similar = enseignes.docs.filter((doc) => {
    const e = doc.data();
    const sameName = wanted && normalizeName(e.name) === wanted;
    const samePostal = postalCode && String(e.area_code || "") === postalCode;
    const ownedByRequester = ownsEnseigne(e, contract.owner_uid);
    return (sameName && (samePostal || !postalCode)) || (placeId && e.google_place_id === placeId) || ownedByRequester;
  }).map((doc) => ({
    id: doc.id, name: doc.data().name || "", city: doc.data().city || "", postalCode: doc.data().area_code || "",
    ownedByRequester: ownsEnseigne(doc.data(), contract.owner_uid),
    samePlace: !!placeId && doc.data().google_place_id === placeId,
  }));
  const sameSiret = await db.collection(kContractsCollection).where("siret", "==", contract.siret).get();
  return {
    enseignes: similar,
    contractsWithSameSiret: sameSiret.docs.filter((doc) => doc.id !== contractId).map((doc) => ({
      id: doc.id, state: doc.data().state, enseigneName: doc.data().enseigne_name || null, ownerUid: doc.data().owner_uid,
    })),
  };
}

const callable = (handler) => functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(handler);

module.exports = {
  loadForDecision,
  kRefusalMotifs,
  normalizeName,
  adminRecordMerchantContractChecksHandler,
  adminRefuseMerchantContractHandler,
  adminFindSimilarEnseignesHandler,
  adminRecordMerchantContractChecks: callable(adminRecordMerchantContractChecksHandler),
  adminRefuseMerchantContract: callable(adminRefuseMerchantContractHandler),
  adminFindSimilarEnseignes: callable(adminFindSimilarEnseignesHandler),
};

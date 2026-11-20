// Phase 1, tranche 1, lot 1.4 : confirmation de souscription (CGV B2B V2.1,
// art. 4.1 et 4.3). Le contrat est conclu lorsque PROXIPLAY adresse la
// confirmation : la date de conclusion est l'heure d'envoi de l'e-mail.
//
// Conditions (toutes verifiees cote serveur, en transaction) :
//   - demande a l'etat submitted, version attendue (aucune decision perimee) ;
//   - les 8 controles saisis « pass » ;
//   - enseigne rattachee, existante, appartenant au demandeur, sans autre
//     demande ou contrat ouvert ;
//   - CGV acceptees = CGV en vigueur (version et empreinte) ;
//   - PDF des CGV lu dans Storage avec la meme empreinte (sinon : rien ne part).
//
// Envoi unique : un verrou est pose avant l'envoi ; l'envoi est trace des
// qu'il a eu lieu ; une reprise apres incident finalise sans renvoyer.
// Aucun paiement, aucune invitation a payer, aucun appel Stripe (tranche 2).

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {
  kFunctionsRegion,
  kPromoCodesCollection,
  kStates,
  kChecks,
  httpsError,
  assertTransition,
  assertCgvConfigured,
  assertAdminCaller,
  readContractsConfig,
  ownsEnseigne,
  findOpenContractForEnseigne,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const {loadForDecision} = require("./merchant_contract_review");
const {visitReportDeadline} = require("./paris_time");
const cgvDocument = require("./merchant_cgv_document");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

const kLockTtlMs = 10 * 60 * 1000;

async function claimConfirmation(db, contractId, expectedVersion, cgv, adminUid, nowMs) {
  return db.runTransaction(async (tx) => {
    const {ref, contract} = await loadForDecision(tx, db, contractId, expectedVersion);
    assertTransition(contract.state, kStates.CONFIRMED);
    const internalSnap = await tx.get(internalRef(db, contractId));
    const internal = internalSnap.exists ? internalSnap.data() : {};
    const checks = internal.verification?.checks || {};
    const missing = kChecks.filter((name) => checks[name]?.result !== "pass");
    if (missing.length) {
      throw httpsError("failed-precondition", "Les 8 contrôles doivent être conformes avant la confirmation.",
        {reason: "checks_incomplete", missing});
    }
    if (!contract.enseigne_id) {
      throw httpsError("failed-precondition", "Aucune enseigne rattachée : créez-la au nom du demandeur puis rattachez-la.",
        {reason: "enseigne_missing"});
    }
    const enseigne = await tx.get(db.collection("enseignes").doc(contract.enseigne_id));
    if (!enseigne.exists || !ownsEnseigne(enseigne.data(), contract.owner_uid)) {
      throw httpsError("failed-precondition", "L'enseigne doit exister et appartenir au demandeur.", {reason: "enseigne_not_owned"});
    }
    if (await findOpenContractForEnseigne(db, contract.enseigne_id, {tx, excludeContractId: contractId})) {
      throw httpsError("already-exists", "Une demande ou un contrat existe déjà pour cette enseigne.", {reason: "enseigne_busy"});
    }
    if (contract.cgv?.version !== cgv.version || contract.cgv?.sha256 !== cgv.sha256) {
      throw httpsError("failed-precondition",
        "Les CGV acceptées ne sont plus celles en vigueur : le commerçant doit refaire sa demande.", {reason: "cgv_changed"});
    }
    const confirmation = internal.confirmation || {};
    const lockAt = millisOf(confirmation.lock_at);
    if (!confirmation.email_sent_at && lockAt && nowMs - lockAt < kLockTtlMs) {
      throw httpsError("aborted", "Une confirmation est déjà en cours d'envoi.", {reason: "confirmation_in_progress"});
    }
    const nextVersion = contract.state_version + 1;
    // La version change des la prise du verrou : un refus concurrent sur
    // l'ancienne version echoue (stale_version).
    tx.update(ref, {state_version: nextVersion});
    tx.set(internalRef(db, contractId), {confirmation: {
      lock_at: admin.firestore.Timestamp.fromMillis(nowMs), lock_by: adminUid,
    }}, {merge: true});
    return {ref, contract: {...contract, state_version: nextVersion, enseigne_name: enseigne.data().name || contract.enseigne_name},
      alreadySent: confirmation.email_sent_at ? confirmation : null};
  });
}

async function releaseLock(db, contractId, error) {
  await internalRef(db, contractId).set({confirmation: {
    lock_at: admin.firestore.FieldValue.delete(),
    lock_by: admin.firestore.FieldValue.delete(),
    last_error: String(error?.message || error).slice(0, 300),
    last_error_at: admin.firestore.FieldValue.serverTimestamp(),
  }}, {merge: true});
}

async function adminConfirmMerchantContractHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  // Fonction admin : hors interrupteur (demande deja recue) ; CGV publiees exigees.
  const config = await readContractsConfig(db);
  const cgv = assertCgvConfigured(config);
  const contractId = typeof data?.contractId === "string" ? data.contractId.trim() : "";
  if (!contractId) throw httpsError("invalid-argument", "Demande inconnue.", {reason: "invalid_field", field: "contractId"});

  const claim = await claimConfirmation(db, contractId, data?.expectedVersion, cgv, adminUid, Date.now());
  let conclusionMs;
  if (claim.alreadySent) {
    // Reprise : l'e-mail est deja parti, on finalise sans le renvoyer.
    conclusionMs = millisOf(claim.alreadySent.email_sent_at);
  } else {
    try {
      const pdf = await cgvDocument.loadCgvPdf(cgv.storagePath);
      const hash = cgvDocument.sha256(pdf);
      if (hash !== cgv.sha256) {
        throw httpsError("failed-precondition", "Le PDF des CGV ne correspond pas à l'empreinte en vigueur : aucune confirmation n'est envoyée.",
          {reason: "cgv_pdf_mismatch"});
      }
      conclusionMs = Date.now();
      const message = emails.confirmationNotice(claim.contract, contractId, {
        conclusionMs,
        deadlineMs: visitReportDeadline(conclusionMs),
        cgv,
      });
      const result = await mail.sendContractMail({
        ...message,
        messageId: `<contrat-${contractId}@proxiplay.fr>`,
        attachments: [{filename: `CGV_PROXIPLAY_V${cgv.version}.pdf`, content: pdf, contentType: "application/pdf"}],
      });
      await internalRef(db, contractId).set({confirmation: {
        email_sent_at: admin.firestore.Timestamp.fromMillis(conclusionMs),
        message_id: result?.messageId || `<contrat-${contractId}@proxiplay.fr>`,
        cgv_version: cgv.version,
        cgv_sha256: hash,
      }}, {merge: true});
    } catch (error) {
      await releaseLock(db, contractId, error);
      if (error instanceof functions.https.HttpsError) throw error;
      throw httpsError("unavailable", "La confirmation n'a pas pu être envoyée : rien n'a été conclu. Réessayez.",
        {reason: "confirmation_failed"});
    }
  }

  // Tranche 2a (lot 1.6) : la confirmation aiguille aussitot vers
  // withdrawal_pending (demarchee : aucun paiement avant la fin du delai de
  // retractation, art. 4.2 et 7.4) ou payment_invited (spontanee :
  // invitation a payer envoyee avec la confirmation, art. 8.1).
  const finalState = await db.runTransaction(async (tx) => {
    const snap = await tx.get(claim.ref);
    const contract = snap.data();
    if (contract.state !== kStates.SUBMITTED) return null; // deja finalise
    assertTransition(contract.state, kStates.CONFIRMED);
    const target = contract.origin?.type === "demarchee" ? kStates.WITHDRAWAL_PENDING : kStates.PAYMENT_INVITED;
    assertTransition(kStates.CONFIRMED, target);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const deadline = admin.firestore.Timestamp.fromMillis(visitReportDeadline(conclusionMs));
    tx.update(claim.ref, {
      state: target,
      state_version: contract.state_version + 1,
      confirmed_at: admin.firestore.Timestamp.fromMillis(conclusionMs),
      visit_report_deadline: deadline,
      // Meme date : fin du 14e jour suivant la conclusion (art. 4.2 et 7.2).
      withdrawal_deadline: deadline,
      updated_at: now,
    });
    tx.set(internalRef(db, contractId), {confirmation: {
      confirmed_by: adminUid,
      lock_at: admin.firestore.FieldValue.delete(),
      lock_by: admin.firestore.FieldValue.delete(),
    }}, {merge: true});
    if (contract.promo?.code) {
      tx.set(db.collection(kPromoCodesCollection).doc(contract.promo.code),
        {uses: admin.firestore.FieldValue.increment(1)}, {merge: true});
    }
    tx.set(eventRef(db, contractId), {type: "confirmed", at: now, actor: "admin", actor_uid: adminUid,
      conclusion_at: admin.firestore.Timestamp.fromMillis(conclusionMs), next_state: target});
    return target;
  });
  let invitation = null;
  if (finalState === kStates.PAYMENT_INVITED) {
    // Echec d'envoi : file de reprise et alerte (le contrat reste conclu).
    invitation = await require("./merchant_contract_payment").issuePaymentInvitation(db, contractId, {actor: `admin:${adminUid}`});
  }
  const state = finalState || (await claim.ref.get()).data().state;
  return {state, confirmedAt: conclusionMs, invitation: invitation ? (invitation.sent ? "sent" : "queued") : null};
}

exports.adminConfirmMerchantContract = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .https.onCall(adminConfirmMerchantContractHandler);

exports.adminConfirmMerchantContractHandler = adminConfirmMerchantContractHandler;

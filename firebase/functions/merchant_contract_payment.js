// Phase 1, tranche 2a, lot 1.6 : invitation a payer et lien de 15 jours
// (CGV B2B V2.1, art. 8.1).
//
// - Jeton aleatoire (32 octets) ; seule son empreinte SHA-256 est stockee
//   (payment_tokens/{empreinte}). Jamais de lien de paiement Stripe : le lien
//   mene a une page ProxiPlay (espace commercant), qui cree la session
//   Checkout au clic (lot 1.7).
// - Validite : jusqu'a la fin du 15e jour suivant l'envoi, heure de Paris.
//   La date d'envoi est celle ou l'e-mail est effectivement parti.
// - Renvoi par l'admin : l'ancien jeton est revoque, la date d'expiration
//   reste inchangee.
// - Echec d'envoi : le jeton jamais remis est revoque ; l'invitation est mise
//   en file de reprise et regeneree a chaque tentative (le jeton n'est
//   jamais stocke en clair, meme dans la file).

const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {assertMerchantCaller} = require("./merchant_billing_access");
const {
  kFunctionsRegion,
  kContractsCollection,
  kStates,
  httpsError,
  assertTransition,
  readContractsConfig,
  assertAdminCaller,
  internalRef,
  eventRef,
  millisOf,
} = require("./merchant_contracts_model");
const {parisDate, addDays, endOfParisDay} = require("./paris_time");
const mail = require("./merchant_contract_mail");
const emails = require("./merchant_contract_emails");

const kPaymentTokensCollection = "payment_tokens";
const kPaymentLinkDays = 15;
const kTokenPattern = /^[A-Za-z0-9_-]{40,64}$/;
const kSiteOrigin = "https://www.proxiplay.fr";

function hashToken(token) {
  return crypto.createHash("sha256").update(token, "utf8").digest("hex");
}

/** Fin du 15e jour suivant l'envoi, heure de Paris. */
function paymentLinkExpiry(sentMs) {
  return endOfParisDay(addDays(parisDate(sentMs), kPaymentLinkDays));
}

function paymentLinkUrl(token) {
  return `${kSiteOrigin}/espace-commercant/?paiement=${token}`;
}

async function revokeOpenTokens(tx, db, contractId, nowTs) {
  const open = await tx.get(db.collection(kPaymentTokensCollection)
    .where("contract_id", "==", contractId).where("revoked_at", "==", null));
  return open.docs.map((doc) => () => tx.update(doc.ref, {revoked_at: nowTs}));
}

/**
 * Cree un jeton, envoie l'invitation, puis fixe les dates a l'heure d'envoi.
 * Le contrat doit etre a payment_invited. Renvoie {sent, queued}.
 */
async function issuePaymentInvitation(db, contractId, {actor = "system", keepExpiry = false, reminder = false} = {}) {
  // Rappel (lot 1.9) : nouveau lien, meme expiration, gabarit de rappel, cle propre.
  const key = reminder ? "payment_reminder" : "payment_invitation";
  if (reminder) keepExpiry = true;
  const token = crypto.randomBytes(32).toString("base64url");
  const tokenRef = db.collection(kPaymentTokensCollection).doc(hashToken(token));
  const contractRef = db.collection(kContractsCollection).doc(contractId);
  const prepared = await db.runTransaction(async (tx) => {
    const snap = await tx.get(contractRef);
    if (!snap.exists) throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
    const contract = snap.data();
    if (contract.state !== kStates.PAYMENT_INVITED) {
      throw httpsError("failed-precondition", "Aucune invitation a payer possible dans cet etat.", {reason: "not_payment_invited"});
    }
    const nowTs = admin.firestore.Timestamp.now();
    const revocations = await revokeOpenTokens(tx, db, contractId, nowTs);
    revocations.forEach((revoke) => revoke());
    tx.create(tokenRef, {
      contract_id: contractId,
      owner_uid: contract.owner_uid,
      enseigne_id: contract.enseigne_id || null,
      created_at: nowTs,
      sent_at: null,
      expires_at: null,
      revoked_at: null,
      first_used_at: null,
      last_session_id: null,
      issued_by: actor,
    });
    return contract;
  });

  const keptExpiryMs = keepExpiry ? millisOf(prepared.payment_link_expires_at) : null;
  const message = (reminder ? emails.paymentReminder : emails.paymentInvitation)(prepared, contractId, {
    url: paymentLinkUrl(token),
    // Date affichee : celle qui sera enregistree si l'envoi reussit maintenant.
    expiresMs: keptExpiryMs || paymentLinkExpiry(Date.now()),
  });
  let result;
  try {
    result = await mail.sendContractMail(message);
  } catch (error) {
    // Jamais remis : le jeton est revoque, l'invitation part en file de reprise.
    await tokenRef.update({revoked_at: admin.firestore.FieldValue.serverTimestamp(), send_failed: true});
    await mail.recordFailed(db, contractId, key, error);
    if (reminder) {
      await internalRef(db, contractId).set({payment_invitation: {reminder_queued_at: admin.firestore.FieldValue.serverTimestamp()}}, {merge: true});
    }
    await mail.enqueueRetry(db, {kind: "payment_invitation", contractId, key, error});
    return {sent: false, queued: true};
  }

  const sentMs = Date.now();
  const expiresMs = keptExpiryMs || paymentLinkExpiry(sentMs);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(contractRef);
    const contract = snap.data();
    tx.update(tokenRef, {
      sent_at: admin.firestore.Timestamp.fromMillis(sentMs),
      expires_at: admin.firestore.Timestamp.fromMillis(expiresMs),
    });
    tx.update(contractRef, {
      // Premier envoi horodate : point de depart du delai de 15 jours (art. 8.1).
      ...(contract.payment_invited_at ? {} : {payment_invited_at: admin.firestore.Timestamp.fromMillis(sentMs)}),
      payment_link_expires_at: admin.firestore.Timestamp.fromMillis(expiresMs),
      state_version: (contract.state_version || 1) + 1,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(internalRef(db, contractId), {payment_invitation: {
      last_sent_at: admin.firestore.Timestamp.fromMillis(sentMs),
      sends: admin.firestore.FieldValue.increment(1),
      ...(reminder ? {reminder_sent_at: admin.firestore.Timestamp.fromMillis(sentMs)} : {}),
    }}, {merge: true});
    tx.set(eventRef(db, contractId), {type: reminder ? "payment_reminder_sent" : "payment_invitation_sent", at: admin.firestore.FieldValue.serverTimestamp(),
      actor, expires_at: admin.firestore.Timestamp.fromMillis(expiresMs)});
  });
  await mail.recordSent(db, contractId, key, result);
  return {sent: true, queued: false, expiresMs};
}

// Reprise : l'invitation est regeneree (nouveau jeton) tant qu'elle reste due.
mail.registerRetryHandler("payment_invitation", async (db, item) => {
  const snap = await db.collection(kContractsCollection).doc(item.contract_id).get();
  if (!snap.exists || snap.data().state !== kStates.PAYMENT_INVITED) return; // plus due : rien a envoyer
  const reminder = item.key === "payment_reminder";
  // Rappel apres l'expiration du lien : sans objet (la cloture le signale a l'admin).
  if (reminder && (millisOf(snap.data().payment_link_expires_at) || 0) < Date.now()) return;
  const outcome = await issuePaymentInvitation(db, item.contract_id, {
    actor: "outbox", keepExpiry: !!snap.data().payment_link_expires_at, reminder,
  });
  if (!outcome.sent) throw new Error("invitation toujours non envoyee");
});

/**
 * Passage de withdrawal_pending a payment_invited (fin du delai de
 * retractation) puis envoi. Utilise par l'admin en tranche 2a et par la
 * tache planifiee du lot 1.9 ensuite.
 */
async function inviteAfterWithdrawalPeriod(db, contractId, {actor, nowMs = Date.now()}) {
  const ref = db.collection(kContractsCollection).doc(contractId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
    const contract = snap.data();
    assertTransition(contract.state, kStates.PAYMENT_INVITED);
    const deadline = millisOf(contract.withdrawal_deadline);
    if (contract.state === kStates.WITHDRAWAL_PENDING && (!deadline || nowMs <= deadline)) {
      throw httpsError("failed-precondition",
        "Le délai de rétractation n'est pas expiré : aucun paiement ne peut être demandé (art. 7.4).", {reason: "withdrawal_period_running"});
    }
    tx.update(ref, {state: kStates.PAYMENT_INVITED, state_version: (contract.state_version || 1) + 1,
      updated_at: admin.firestore.FieldValue.serverTimestamp()});
    tx.set(eventRef(db, contractId), {type: "withdrawal_period_ended", at: admin.firestore.FieldValue.serverTimestamp(), actor});
  });
  return issuePaymentInvitation(db, contractId, {actor});
}

/** Admin : renvoie l'invitation (meme expiration) ou l'envoie apres le delai de retractation. */
async function adminSendPaymentInvitationHandler(data, context) {
  const db = admin.firestore();
  const adminUid = await assertAdminCaller(db, context);
  const contractId = typeof data?.contractId === "string" ? data.contractId.trim() : "";
  const snap = contractId ? await db.collection(kContractsCollection).doc(contractId).get() : null;
  if (!snap?.exists) throw httpsError("not-found", "Demande inconnue.", {reason: "contract_not_found"});
  if (snap.data().state === kStates.WITHDRAWAL_PENDING) {
    return inviteAfterWithdrawalPeriod(db, contractId, {actor: `admin:${adminUid}`});
  }
  return issuePaymentInvitation(db, contractId, {actor: `admin:${adminUid}`, keepExpiry: !!snap.data().payment_link_expires_at});
}

/**
 * Lit un jeton pour la page de paiement : uniquement pour le compte
 * proprietaire. Renvoie {contract, expiresAt} ou un motif de refus.
 */
async function loadToken(db, rawToken, uid, nowMs = Date.now()) {
  const token = typeof rawToken === "string" ? rawToken.trim() : "";
  if (!kTokenPattern.test(token)) throw httpsError("not-found", "Lien de paiement inconnu.", {reason: "token_unknown"});
  const tokenRef = db.collection(kPaymentTokensCollection).doc(hashToken(token));
  const tokenSnap = await tokenRef.get();
  // Un lien d'un autre compte est indiscernable d'un lien inconnu.
  if (!tokenSnap.exists || tokenSnap.data().owner_uid !== uid) {
    throw httpsError("not-found", "Lien de paiement inconnu pour ce compte.", {reason: "token_unknown"});
  }
  const tokenData = tokenSnap.data();
  const contractSnap = await db.collection(kContractsCollection).doc(tokenData.contract_id).get();
  const contract = contractSnap.data();
  if (contract.state === kStates.ACTIVE) {
    throw httpsError("failed-precondition", "Ce paiement a déjà été effectué.", {reason: "already_paid"});
  }
  if (contract.state !== kStates.PAYMENT_INVITED) {
    throw httpsError("failed-precondition", "Cette souscription n'attend plus de paiement.", {reason: "not_payment_invited"});
  }
  if (tokenData.revoked_at) {
    throw httpsError("failed-precondition", "Ce lien a été remplacé par un lien plus récent : utilisez le dernier e-mail reçu.",
      {reason: "token_revoked"});
  }
  const expiresMs = millisOf(tokenData.expires_at);
  if (!expiresMs || nowMs > expiresMs) {
    throw httpsError("failed-precondition", "Ce lien de paiement a expiré (quinze jours, art. 8.1).", {reason: "token_expired"});
  }
  return {tokenRef, tokenData, contractId: tokenData.contract_id, contract, expiresMs};
}

async function getPaymentInvitationHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  // Contrat deja invite : page de paiement disponible meme ventes en pause.
  const config = await readContractsConfig(db);
  const {contractId, contract, expiresMs} = await loadToken(db, data?.token, context.auth.uid);
  return {
    contractId,
    enseigneName: contract.enseigne_name || null,
    offer: contract.offer,
    promoCode: contract.promo?.code || null,
    origin: contract.origin?.type || null,
    expiresAt: expiresMs,
    cgv: config.cgv ? {version: config.cgv.version, url: config.cgv.url} : null,
  };
}

const callable = (handler) => functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(handler);

module.exports = {
  kPaymentTokensCollection,
  kPaymentLinkDays,
  hashToken,
  paymentLinkExpiry,
  paymentLinkUrl,
  issuePaymentInvitation,
  inviteAfterWithdrawalPeriod,
  loadToken,
  revokeOpenTokens,
  readContractsConfig,
  adminSendPaymentInvitationHandler,
  getPaymentInvitationHandler,
  adminSendPaymentInvitation: callable(adminSendPaymentInvitationHandler),
  getPaymentInvitation: callable(getPaymentInvitationHandler),
};

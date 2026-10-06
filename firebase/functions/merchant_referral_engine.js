// Parrainage commercant (prime de 100 EUR), chantier paiement Stripe.
// Programme distinct du parrainage joueur existant (share_promo) : code,
// recompense et regles anti-fraude propres. La cle d'unicite d'une prime
// est le COMPTE commercant parraine (doc id = merchantUserId sous
// merchant_referrals), coherente avec la decision "un paiement par
// commercant" : impossible structurellement qu'un meme commercant genere
// deux primes, quel que soit le nombre d'enseignes qu'il possede.
//
// La recompense n'est JAMAIS acquise avant confirmation serveur du premier
// paiement Stripe (invoice.paid, billing_reason=subscription_create) --
// jamais a la saisie du code, la creation du compte ou du Checkout.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {isTrustedAdmin} = require("./admin_identity");

const kFunctionsRegion = "us-central1";
const kMerchantReferralsCollection = "merchant_referrals";
const kMerchantReferralCodesCollection = "merchant_referral_codes";
const kRewardAmountCents = 10000;
const kCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sans 0/O/1/I ambigus
const kCodeLength = 8;

function randomCode() {
  let code = "";
  for (let i = 0; i < kCodeLength; i++) {
    code += kCodeAlphabet[Math.floor(Math.random() * kCodeAlphabet.length)];
  }
  return code;
}

async function assertCallerIsAdmin(db, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const callerSnap = await db.collection("users").doc(context.auth.uid).get();
  if (!isTrustedAdmin(context.auth, callerSnap.data() || {})) {
    throw new functions.https.HttpsError("permission-denied", "Reserve a l'administration.");
  }
}

/**
 * Callable : un joueur signe obtient son code de parrainage commercant,
 * en creant un seul si aucun n'existe deja (idempotent, jamais deux codes
 * pour le meme parrain).
 */
async function generateMerchantReferralCodeHandler(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const db = admin.firestore();
  const inviterRef = db.doc(`users/${context.auth.uid}`);
  const existing = await db.collection(kMerchantReferralCodesCollection)
    .where("inviter_user_id", "==", inviterRef).limit(1).get();
  if (!existing.empty) {
    return {code: existing.docs[0].id};
  }
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomCode();
    const codeRef = db.collection(kMerchantReferralCodesCollection).doc(code);
    try {
      await codeRef.create({
        inviter_user_id: inviterRef,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {code};
    } catch (err) {
      if (err.code !== 6 && err.code !== "already-exists") throw err; // collision : on retente
    }
  }
  throw new functions.https.HttpsError("internal", "Impossible de generer un code, reessayez.");
}

/**
 * Appele par le webhook Stripe au premier paiement confirme d'une enseigne
 * (jamais au renouvellement). Idempotent : ne transitionne que depuis
 * 'linked' -- un replay d'evenement ou un appel apres rejet/annulation est
 * un no-op silencieux, jamais une double eligibilite.
 */
async function markReferralEligibleOnFirstPayment(db, {merchantUserId, subscriptionAmountHtCents, stripeSubscriptionId}) {
  const referralRef = db.collection(kMerchantReferralsCollection).doc(merchantUserId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(referralRef);
    if (!snap.exists) return; // pas de parrainage sur cette enseigne : rien a faire
    if (snap.data().status !== "linked") return; // deja traite, rejete ou annule : jamais rejoue
    tx.update(referralRef, {
      status: "eligible",
      first_payment_confirmed_at: admin.firestore.FieldValue.serverTimestamp(),
      eligible_at: admin.firestore.FieldValue.serverTimestamp(),
      subscription_amount_ht_cents: subscriptionAmountHtCents,
      stripe_subscription_id: stripeSubscriptionId,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/**
 * Appele par le webhook sur annulation d'abonnement / remboursement /
 * litige. Ne bloque que les primes pas encore payees (jamais de
 * recuperation automatique d'argent deja verse -- cf. section 9).
 */
async function cancelReferralIfNotYetPaid(db, merchantUserId, reason) {
  const referralRef = db.collection(kMerchantReferralsCollection).doc(merchantUserId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(referralRef);
    if (!snap.exists) return;
    const status = snap.data().status;
    if (status === "approved" || status === "paid") {
      console.warn("[MERCHANT_REFERRAL] evenement d'annulation recu pour une prime deja " +
        `${status} (merchantUserId=${merchantUserId}, reason=${reason}) -- aucune recuperation automatique.`);
      return;
    }
    if (status !== "linked" && status !== "eligible") return; // deja rejete/annule : no-op
    tx.update(referralRef, {
      status: "cancelled",
      cancelled_reason: reason,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function adminApproveMerchantReferralHandler(data, context) {
  const db = admin.firestore();
  await assertCallerIsAdmin(db, context);
  const merchantUserId = typeof data?.merchantUserId === "string" ? data.merchantUserId.trim() : "";
  if (!merchantUserId) throw new functions.https.HttpsError("invalid-argument", "merchantUserId requis.");
  const referralRef = db.collection(kMerchantReferralsCollection).doc(merchantUserId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(referralRef);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Parrainage introuvable.");
    if (snap.data().status !== "eligible") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Ce parrainage n'est pas eligible (statut actuel: ${snap.data().status}).`,
      );
    }
    tx.update(referralRef, {
      status: "approved",
      admin_decision: {
        decided_by: context.auth.uid,
        decided_at: admin.firestore.FieldValue.serverTimestamp(),
        action: "approved",
      },
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {status: "approved"};
}

async function adminRejectMerchantReferralHandler(data, context) {
  const db = admin.firestore();
  await assertCallerIsAdmin(db, context);
  const merchantUserId = typeof data?.merchantUserId === "string" ? data.merchantUserId.trim() : "";
  const reason = typeof data?.reason === "string" ? data.reason.trim() : "";
  if (!merchantUserId || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "merchantUserId et reason sont requis.");
  }
  const referralRef = db.collection(kMerchantReferralsCollection).doc(merchantUserId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(referralRef);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Parrainage introuvable.");
    if (!["linked", "eligible", "approved"].includes(snap.data().status)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Ce parrainage ne peut plus etre rejete (statut actuel: ${snap.data().status}).`,
      );
    }
    tx.update(referralRef, {
      status: "rejected",
      rejected_reason: reason,
      admin_decision: {
        decided_by: context.auth.uid,
        decided_at: admin.firestore.FieldValue.serverTimestamp(),
        action: "rejected",
      },
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {status: "rejected"};
}

async function adminMarkMerchantReferralPaidHandler(data, context) {
  const db = admin.firestore();
  await assertCallerIsAdmin(db, context);
  const merchantUserId = typeof data?.merchantUserId === "string" ? data.merchantUserId.trim() : "";
  const paidReference = typeof data?.paidReference === "string" ? data.paidReference.trim() : "";
  if (!merchantUserId || !paidReference) {
    throw new functions.https.HttpsError("invalid-argument", "merchantUserId et paidReference sont requis.");
  }
  const referralRef = db.collection(kMerchantReferralsCollection).doc(merchantUserId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(referralRef);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Parrainage introuvable.");
    if (snap.data().status !== "approved") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Ce parrainage doit etre approuve avant paiement (statut actuel: ${snap.data().status}).`,
      );
    }
    tx.update(referralRef, {
      status: "paid",
      paid_at: admin.firestore.FieldValue.serverTimestamp(),
      paid_reference: paidReference,
      reward_amount_cents: kRewardAmountCents,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {status: "paid"};
}

/**
 * Fixe (ou retire) un tarif negocie pour un commercant multi-enseignes.
 * Reserve a l'Admin : un commercant ou un joueur ne peut jamais choisir ou
 * modifier ce montant lui-meme (regles Firestore : write toujours false
 * sur merchant_custom_offers). amountHtCents=null retire le tarif negocie
 * (le commercant retombe sur le catalogue standard au prochain Checkout).
 */
async function adminSetMerchantCustomOfferHandler(data, context) {
  const db = admin.firestore();
  await assertCallerIsAdmin(db, context);
  const merchantUserId = typeof data?.merchantUserId === "string" ? data.merchantUserId.trim() : "";
  if (!merchantUserId) {
    throw new functions.https.HttpsError("invalid-argument", "merchantUserId requis.");
  }
  const customOfferRef = db.collection("merchant_custom_offers").doc(merchantUserId);
  if (data?.amountHtCents === null) {
    await customOfferRef.delete();
    return {status: "removed"};
  }
  const amountHtCents = Number(data?.amountHtCents);
  const label = typeof data?.label === "string" ? data.label.trim() : "";
  if (!Number.isInteger(amountHtCents) || amountHtCents <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "amountHtCents doit etre un entier positif (centimes).");
  }
  await customOfferRef.set({
    merchant_user_id: db.doc(`users/${merchantUserId}`),
    amount_ht_cents: amountHtCents,
    label: label || "Abonnement ProxiPlay (tarif negocie)",
    created_by: context.auth.uid,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {status: "set"};
}

exports.generateMerchantReferralCode = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(generateMerchantReferralCodeHandler);

exports.adminApproveMerchantReferral = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(adminApproveMerchantReferralHandler);

exports.adminRejectMerchantReferral = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(adminRejectMerchantReferralHandler);

exports.adminMarkMerchantReferralPaid = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(adminMarkMerchantReferralPaidHandler);

exports.adminSetMerchantCustomOffer = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(adminSetMerchantCustomOfferHandler);

// Exposes pour le webhook et les tests directs (hors onCall).
exports.markReferralEligibleOnFirstPayment = markReferralEligibleOnFirstPayment;
exports.cancelReferralIfNotYetPaid = cancelReferralIfNotYetPaid;
exports.generateMerchantReferralCodeHandler = generateMerchantReferralCodeHandler;
exports.adminApproveMerchantReferralHandler = adminApproveMerchantReferralHandler;
exports.adminRejectMerchantReferralHandler = adminRejectMerchantReferralHandler;
exports.adminMarkMerchantReferralPaidHandler = adminMarkMerchantReferralPaidHandler;
exports.adminSetMerchantCustomOfferHandler = adminSetMerchantCustomOfferHandler;
exports.kRewardAmountCents = kRewardAmountCents;

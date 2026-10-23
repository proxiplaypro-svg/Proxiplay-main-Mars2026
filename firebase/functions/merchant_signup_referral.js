// Parrainage commercant a l'inscription : le commercant saisit, en creant son
// compte, le code de la personne qui lui a recommande ProxiPlay. Programme
// commercant uniquement (merchant_referral_codes / merchant_referrals),
// jamais le parrainage joueur (share_promo).
//
// - Le code est verifie AVANT la creation du compte : un code inconnu,
//   indisponible ou un futur code partenaire ne cree jamais de compte.
// - Le compte et le rattachement sont crees par le serveur dans une operation
//   idempotente (requestId) : une nouvelle tentative, ou la creation du profil
//   a la premiere connexion, termine un rattachement interrompu. Aucune tache
//   planifiee ; les operations incompletes restent identifiables
//   (_merchant_signup_operations, status != 'completed').
// - Le rattachement ne donne droit a rien : la recompense ambassadeur (50 EUR
//   en bons cadeaux) suit le premier abonnement paye confirme puis
//   l'approbation Admin (merchant_referral_engine).
const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {kRewardAmountCents} = require("./merchant_referral_engine");
const {excluded} = require("./prize_integrity");

const kFunctionsRegion = "us-central1";
const kCodesCollection = "merchant_referral_codes";
const kReferralsCollection = "merchant_referrals";
const kOperationsCollection = "_merchant_signup_operations";

const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");

function normalizeMerchantSignupCode(raw) {
  return typeof raw === "string" ? raw.replace(/\s+/g, "").toUpperCase() : "";
}

/**
 * Resout un code saisi a l'inscription commercant. Un code sans `kind` est un
 * code ambassadeur (tous les codes existants). `partner` est reserve aux
 * futurs codes d'associations : refuse explicitement pour l'instant.
 */
async function resolveMerchantSignupCode(db, rawCode) {
  const code = normalizeMerchantSignupCode(rawCode);
  if (!/^[A-Z0-9-]{4,32}$/.test(code)) {
    throw new functions.https.HttpsError("not-found", "Code inconnu.", {reason: "code_not_found"});
  }
  const codeSnap = await db.collection(kCodesCollection).doc(code).get();
  if (!codeSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Code inconnu.", {reason: "code_not_found"});
  }
  const kind = codeSnap.data().kind || "ambassador";
  if (kind === "partner") {
    throw new functions.https.HttpsError("failed-precondition", "Code partenaire indisponible.",
      {reason: "partner_code_unavailable"});
  }
  if (kind !== "ambassador") {
    throw new functions.https.HttpsError("failed-precondition", "Code indisponible.", {reason: "code_unavailable"});
  }
  const inviterRef = codeSnap.data().inviter_user_id;
  const inviterSnap = inviterRef?.path ? await db.doc(inviterRef.path).get() : null;
  // Particulier ou commercant : le role du parrain n'est pas restreint, mais
  // son compte doit exister et ne pas etre supprime ni suspendu.
  if (!inviterSnap?.exists || excluded(inviterSnap.data())) {
    throw new functions.https.HttpsError("failed-precondition", "Code indisponible.", {reason: "code_unavailable"});
  }
  return {code, inviterPath: inviterRef.path, inviterKind: String(inviterSnap.data().user_role || "") || null};
}

async function enforceRate(db, collection, key, limit) {
  const ref = db.collection(collection).doc(hash(key));
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const previous = (await tx.get(ref)).data() || {};
    const start = Number(previous.start) || 0;
    const count = now >= start && now - start < 60000 ? Number(previous.count) || 0 : 0;
    if (count >= limit) throw new functions.https.HttpsError("resource-exhausted", "Trop de tentatives.");
    tx.set(ref, {start: count ? start : now, count: count + 1});
  });
}

/**
 * Cree (une seule fois) le rattachement d'un compte commercant cree par une
 * operation d'inscription. Idempotent : rejoue sans effet, jamais un second
 * parrain, jamais d'ecrasement d'un rattachement existant (Stripe ou Admin).
 */
async function completeMerchantSignupLink(db, operationRef) {
  return db.runTransaction(async (tx) => {
    const opSnap = await tx.get(operationRef);
    const op = opSnap.data();
    if (!op) throw new functions.https.HttpsError("failed-precondition", "Operation inconnue.");
    if (op.status === "completed") return {linked: op.outcome === "linked"};
    const referralRef = db.collection(kReferralsCollection).doc(op.uid);
    const referralSnap = await tx.get(referralRef);
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (referralSnap.exists) {
      const sameInviter = referralSnap.data().inviter_user_id?.path === op.inviter_path;
      tx.update(operationRef, {status: "completed", outcome: sameInviter ? "linked" : "already_linked", completed_at: now});
      return {linked: sameInviter};
    }
    const config = await tx.get(db.doc("app_config/merchant_referral"));
    if (config.data()?.enabled === false) {
      tx.update(operationRef, {status: "completed", outcome: "program_unavailable", completed_at: now});
      return {linked: false};
    }
    // Memes champs que le rattachement cree par la souscription Stripe.
    tx.create(referralRef, {
      merchant_user_id: db.doc(`users/${op.uid}`),
      inviter_user_id: db.doc(op.inviter_path),
      inviter_kind: op.inviter_kind || null,
      code: op.code,
      source: "merchant_signup",
      status: "linked",
      reward_amount_cents: kRewardAmountCents,
      linked_at: now,
      first_payment_confirmed_at: null,
      eligible_at: null,
      subscription_amount_ht_cents: null,
      stripe_subscription_id: null,
      payment_confirmation: null,
      admin_decision: null,
      rejected_reason: null,
      cancelled_reason: null,
      paid_at: null,
      paid_reference: null,
      created_at: now,
      updated_at: now,
    });
    tx.update(operationRef, {status: "completed", outcome: "linked", completed_at: now});
    return {linked: true};
  });
}

async function createMerchantAccountWithReferralHandler(data, context) {
  const db = admin.firestore();
  const requestId = typeof data?.requestId === "string" ? data.requestId : "";
  const email = typeof data?.email === "string" ? data.email.trim().toLowerCase() : "";
  const password = typeof data?.password === "string" ? data.password : "";
  if (!/^[0-9a-f-]{36}$/i.test(requestId) || !email.includes("@") || email.length > 254 ||
      password.length < 6 || password.length > 128 || !normalizeMerchantSignupCode(data?.code)) {
    throw new functions.https.HttpsError("invalid-argument", "Informations d'inscription invalides.");
  }
  const ip = context.rawRequest?.ip || context.rawRequest?.socket?.remoteAddress;
  if (!ip) throw new functions.https.HttpsError("unavailable", "Inscription indisponible.");
  await enforceRate(db, "_merchant_signup_rate", ip, 5);

  const operationRef = db.collection(kOperationsCollection).doc(hash(requestId));
  const uid = "msu_" + hash(requestId).slice(0, 48);
  let op = (await operationRef.get()).data();
  if (op) {
    // Nouvelle tentative : memes identifiants, meme code, sinon refus.
    if (op.uid !== uid || op.email_hash !== hash(email) || op.code !== normalizeMerchantSignupCode(data.code)) {
      throw new functions.https.HttpsError("failed-precondition", "Informations d'inscription modifiees.");
    }
  } else {
    const config = await db.doc("app_config/merchant_referral").get();
    if (config.data()?.enabled === false) {
      throw new functions.https.HttpsError("failed-precondition", "Programme indisponible.",
        {reason: "program_unavailable"});
    }
    const resolved = await resolveMerchantSignupCode(db, data.code);
    await enforceRate(db, "_merchant_signup_code_rate", resolved.code, 10);
    try {
      await operationRef.create({
        uid, email_hash: hash(email), code: resolved.code,
        inviter_path: resolved.inviterPath, inviter_kind: resolved.inviterKind,
        status: "pending", created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (error?.code !== 6) throw error; // 6 = ALREADY_EXISTS : appel simultane.
    }
    op = (await operationRef.get()).data();
  }
  if (op.status === "completed" && op.outcome === "email_exists") {
    throw new functions.https.HttpsError("already-exists", "Compte existant.",
      {reason: "email_exists", accountCreated: false});
  }

  try {
    await admin.auth().createUser({uid, email, password});
  } catch (error) {
    // Seul le compte de CETTE operation est repris, jamais un compte existant
    // trouve par son adresse.
    let user;
    try { user = await admin.auth().getUser(uid); } catch (_) { /* pas encore cree */ }
    if (!user || user.email?.trim().toLowerCase() !== email) {
      if (error?.code === "auth/email-already-exists") {
        await operationRef.update({status: "completed", outcome: "email_exists",
          completed_at: admin.firestore.FieldValue.serverTimestamp()});
        throw new functions.https.HttpsError("already-exists", "Compte existant.",
          {reason: "email_exists", accountCreated: false});
      }
      throw new functions.https.HttpsError("unavailable", "Creation du compte impossible.");
    }
  }
  if (op.status === "pending") {
    await operationRef.update({status: "account_created", account_created_at: admin.firestore.FieldValue.serverTimestamp()});
  }
  const result = await completeMerchantSignupLink(db, operationRef);
  return {success: true, linked: result.linked};
}

/**
 * Reprise a la premiere connexion : le profil users/{uid} est cree par l'app
 * juste apres la connexion. Si l'appel d'inscription a ete interrompu apres
 * la creation du compte, le rattachement est termine ici. Sans operation pour
 * ce compte : rien a faire (inscription sans code, joueur...).
 */
async function resumeMerchantSignupLinkForUser(db, uid) {
  const ops = await db.collection(kOperationsCollection).where("uid", "==", uid).limit(1).get();
  if (ops.empty || ops.docs[0].data().status === "completed") return {resumed: false};
  try {
    await admin.auth().getUser(uid);
  } catch (_) {
    return {resumed: false};
  }
  await ops.docs[0].ref.update({status: "account_created"});
  await completeMerchantSignupLink(db, ops.docs[0].ref);
  return {resumed: true};
}

exports.createMerchantAccountWithReferral = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(createMerchantAccountWithReferralHandler);

exports.resumeMerchantSignupReferral = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .firestore.document("users/{uid}")
  .onCreate((snap, context) => resumeMerchantSignupLinkForUser(admin.firestore(), context.params.uid));

exports.createMerchantAccountWithReferralHandler = createMerchantAccountWithReferralHandler;
exports.resumeMerchantSignupLinkForUser = resumeMerchantSignupLinkForUser;
exports.resolveMerchantSignupCode = resolveMerchantSignupCode;
exports.normalizeMerchantSignupCode = normalizeMerchantSignupCode;

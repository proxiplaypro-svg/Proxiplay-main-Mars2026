// Droit de publier et de relancer des jeux (abonnement commercant).
//
// Regle metier : inscription, connexion et preparation de la fiche sont
// gratuites ; la publication et la relance de jeux exigent l'un des droits
// suivants (statuts explicites) :
//   active   -> abonnement Stripe actif (y compris resiliation programmee
//               a la fin de la periode payee) ;
//   legacy   -> droit commercial existant avant l'abonnement (pose par le
//               script de transition, jamais retire automatiquement) ;
//   manual   -> activation manuelle Admin (eventuellement datee) ;
//   grace    -> renouvellement impaye, dans le delai de grace (14 jours par
//               defaut depuis l'echeance impayee).
// Statuts sans droit de publication : suspended (grace expiree), ended
// (abonnement termine), pending_payment (premier paiement non abouti),
// free (aucun abonnement).
//
// Rien n'est jamais supprime ni interrompu : un jeu deja en cours continue,
// seules la publication et la relance sont refusees.
//
// La meme regle est appliquee :
//   - dans firestore.rules (creation d'un jeu par un commercant,
//     hasMerchantPublicationAccess) ;
//   - ici, cote serveur, avant toute publication (generateInstantWinnersForGame).
// Elle ne s'applique que lorsque app_config/merchant_billing
// .enforce_publication_access === true (transition non destructive).

const functions = require("firebase-functions");
const {isManualAccessActive} = require("./merchant_billing_access");

const kDefaultGraceDays = 14;
const kGraceStatuses = Object.freeze(["past_due", "unpaid"]);
const kPublishingStatuses = Object.freeze(["active", "legacy", "manual", "grace"]);
const kBillingConfigPath = "app_config/merchant_billing";

const millis = (value) => (value?.toMillis ? value.toMillis() : (typeof value === "number" ? value : null));

function graceDays() {
  const text = String(process.env.MERCHANT_BILLING_GRACE_DAYS || "").trim();
  const raw = /^\d+$/.test(text) ? Number(text) : NaN; // absent ou invalide -> 14
  return Number.isInteger(raw) && raw >= 0 && raw <= 90 ? raw : kDefaultGraceDays;
}

/**
 * Fin du delai de grace pour un abonnement impaye : echeance impayee
 * (debut de la periode non reglee) + N jours. Une valeur deja posee n'est
 * jamais repoussee par une relance ou un evenement ulterieur.
 */
function graceUntilMs(existingGraceUntilMs, unpaidDueDateMs, days = graceDays()) {
  if (typeof existingGraceUntilMs === "number" && existingGraceUntilMs > 0) return existingGraceUntilMs;
  if (typeof unpaidDueDateMs !== "number" || unpaidDueDateMs <= 0) return null;
  return unpaidDueDateMs + days * 24 * 60 * 60 * 1000;
}

/**
 * Statut de publication a partir du miroir merchant_subscriptions/{uid}.
 * Fonction pure : aucun acces reseau.
 */
function computePublicationAccess(subscriptionDoc, nowMs = Date.now()) {
  const sub = subscriptionDoc || {};
  const status = sub.subscription_status || null;
  const graceUntil = millis(sub.grace_until);
  let access;
  if (status === "active" || status === "trialing") {
    access = {status: "active"};
  } else if (sub.legacy_access?.enabled === true) {
    access = {status: "legacy"};
  } else if (isManualAccessActive(sub.manual_access, nowMs)) {
    access = {status: "manual", until: millis(sub.manual_access.until)};
  } else if (kGraceStatuses.includes(status)) {
    access = graceUntil && nowMs < graceUntil ?
      {status: "grace", until: graceUntil} :
      {status: "suspended", since: graceUntil};
  } else if (status === "paused") {
    access = {status: "suspended", since: null};
  } else if (status === "canceled" || status === "incomplete_expired") {
    access = {status: "ended"};
  } else if (status === "incomplete") {
    access = {status: "pending_payment"};
  } else {
    access = {status: "free"};
  }
  return {...access, canPublish: kPublishingStatuses.includes(access.status)};
}

async function isPublicationEnforced(db) {
  const snap = await db.doc(kBillingConfigPath).get();
  return snap.exists && snap.data().enforce_publication_access === true;
}

async function getPublicationAccess(db, merchantUserId, nowMs = Date.now()) {
  const [enforced, subSnap] = await Promise.all([
    isPublicationEnforced(db),
    db.collection("merchant_subscriptions").doc(merchantUserId).get(),
  ]);
  const access = computePublicationAccess(subSnap.exists ? subSnap.data() : null, nowMs);
  return {...access, enforced, allowed: !enforced || access.canPublish};
}

/**
 * Refuse la publication d'un jeu si le commercant n'a pas de droit actif
 * (et seulement si le controle est active). Ne modifie aucune donnee.
 */
async function assertMerchantCanPublish(db, merchantUserId) {
  const access = await getPublicationAccess(db, merchantUserId);
  if (!access.allowed) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      access.status === "suspended" ?
        "Abonnement impaye : regularisez votre paiement depuis votre espace commercant pour publier ou relancer un jeu." :
        "Un abonnement actif est necessaire pour publier ou relancer un jeu.",
      {reason: "subscription_required", accessStatus: access.status},
    );
  }
  return access;
}

/**
 * Callable lue par l'app avant de creer un jeu : indique seulement si le
 * controle est actif et si l'acces de l'appelant (lui-meme) est refuse,
 * pour afficher le message "abonnement requis" au bon moment. Ne modifie
 * rien et ne remplace pas les controles (regles + serveur).
 */
async function getMerchantPublicationAccessHandler(data, context) {
  if (!context?.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const admin = require("firebase-admin");
  const access = await getPublicationAccess(admin.firestore(), context.auth.uid);
  return {enforced: access.enforced, allowed: access.allowed, status: access.status};
}

const getMerchantPublicationAccess = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 10, memory: "128MB"})
  .https.onCall(getMerchantPublicationAccessHandler);

module.exports = {
  getMerchantPublicationAccess,
  getMerchantPublicationAccessHandler,
  kDefaultGraceDays,
  kGraceStatuses,
  kPublishingStatuses,
  kBillingConfigPath,
  graceDays,
  graceUntilMs,
  computePublicationAccess,
  isPublicationEnforced,
  getPublicationAccess,
  assertMerchantCanPublish,
};

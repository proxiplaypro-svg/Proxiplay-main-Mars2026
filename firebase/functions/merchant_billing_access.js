// Regles communes du paiement commercant : qui peut payer, vers ou Stripe
// peut rediriger, et quels droits un statut Stripe ouvre.
//
// Droits : seul un statut lu cote serveur aupres de Stripe (webhook) ouvre
// des droits payants ; jamais la redirection success_url. Une activation
// manuelle (manual_access, posee par l'Admin) est conservee telle quelle et
// n'est jamais ecrite ni effacee par le webhook.

const functions = require("firebase-functions");
const {excluded} = require("./prize_integrity");
const {merchantBillingAllowedOrigins} = require("./stripe_secrets");

const kMerchantRole = "commercant";

// Statuts Stripe d'un abonnement encore "vivant" : aucun second abonnement
// ne doit etre cree tant que l'un d'eux existe.
const kOpenSubscriptionStatuses = Object.freeze(
  ["active", "trialing", "past_due", "unpaid", "incomplete", "paused"],
);

// Statuts qui ouvrent les droits payants. past_due (relances Stripe en cours
// apres un echec de renouvellement) est volontairement distingue : delai de
// grace a valider (voir docs/stripe-merchant-billing.md, decisions).
const kPaidAccessStatuses = Object.freeze(["active", "trialing"]);
const kGraceStatuses = Object.freeze(["past_due"]);

const kDefaultAllowedOrigins = Object.freeze([
  "https://www.proxiplay.fr",
  "https://proxiplay.fr",
  "https://proxi-play-odzp2e.web.app",
  "https://proxi-play-odzp2e.firebaseapp.com",
]);

function roleOf(user) {
  for (const key of ["user_role", "userRole"]) {
    const value = typeof user?.[key] === "string" ? user[key].trim().toLowerCase() : "";
    if (value) return value;
  }
  return "";
}

/**
 * Appelant authentifie, profil commercant existant, compte ni supprime, ni
 * rejete, ni suspendu. Un joueur ou un compte sans profil ne peut jamais
 * ouvrir de Checkout ni de portail.
 */
async function assertMerchantCaller(db, context) {
  if (!context?.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const userSnap = await db.collection("users").doc(context.auth.uid).get();
  const user = userSnap.exists ? userSnap.data() : null;
  if (!user || roleOf(user) !== kMerchantRole) {
    throw new functions.https.HttpsError("permission-denied", "Reserve aux comptes commercants.");
  }
  if (excluded(user)) {
    throw new functions.https.HttpsError("permission-denied", "Compte commercant indisponible.");
  }
  return user;
}

function allowedOrigins() {
  const configured = merchantBillingAllowedOrigins.value()
    .split(",").map((value) => value.trim().replace(/\/+$/, "")).filter(Boolean);
  return configured.length ? configured : kDefaultAllowedOrigins;
}

/**
 * URL de retour Stripe limitee aux origines ProxiPlay : jamais une
 * redirection ouverte vers un domaine choisi par l'appelant.
 */
function assertAllowedReturnUrl(rawUrl, fieldName) {
  let url;
  try {
    url = new URL(typeof rawUrl === "string" ? rawUrl : "");
  } catch (_) {
    throw new functions.https.HttpsError("invalid-argument", `${fieldName} invalide.`);
  }
  const isLocalDev = url.protocol === "http:" &&
    ["localhost", "127.0.0.1"].includes(url.hostname) &&
    Boolean(process.env.FUNCTIONS_EMULATOR || process.env.FIRESTORE_EMULATOR_HOST);
  if (!isLocalDev && (url.protocol !== "https:" || !allowedOrigins().includes(url.origin))) {
    throw new functions.https.HttpsError("invalid-argument", `${fieldName} hors domaine autorise.`);
  }
  return url.toString();
}

function stripeEntitlement(status) {
  if (kPaidAccessStatuses.includes(status)) return "active";
  if (kGraceStatuses.includes(status)) return "grace";
  return "none";
}

function isManualAccessActive(manualAccess, nowMs = Date.now()) {
  if (!manualAccess || manualAccess.enabled !== true) return false;
  const untilMs = manualAccess.until?.toMillis?.() ?? null;
  return untilMs === null || untilMs > nowMs;
}

module.exports = {
  kMerchantRole,
  kOpenSubscriptionStatuses,
  kPaidAccessStatuses,
  kGraceStatuses,
  assertMerchantCaller,
  assertAllowedReturnUrl,
  allowedOrigins,
  stripeEntitlement,
  isManualAccessActive,
  roleOf,
};

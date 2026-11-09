// Mode Stripe attendu (TEST ou LIVE), decide uniquement cote serveur a partir
// du projet Firebase qui execute le code -- jamais d'une valeur transmise par
// le navigateur, ni d'un champ Firestore.
//
//   projet "demo-*" (emulateurs isoles, jamais deploye) -> TEST uniquement ;
//   tout autre projet, dont proxi-play-odzp2e            -> LIVE uniquement.
//
// Un projet introuvable est traite comme la production (refus du mode TEST).
// Consequences :
//   - une cle sk_test_/rk_test_ est refusee en production (stripe_client.js) ;
//   - un evenement ou un abonnement Stripe TEST n'ecrit jamais de droit en
//     production (stripe_webhook.js) ;
//   - un miroir merchant_subscriptions issu de l'autre mode n'ouvre aucun
//     droit de publication (merchant_publication_access.js, firestore.rules).

function firebaseProjectId() {
  const fromEnv = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
  if (fromEnv) return String(fromEnv).trim();
  try {
    return String(JSON.parse(process.env.FIREBASE_CONFIG || "{}").projectId || "").trim();
  } catch (_) {
    return "";
  }
}

function isStripeSandbox() {
  return firebaseProjectId().startsWith("demo-");
}

function expectedLivemode() {
  return !isStripeSandbox();
}

function keyMode(key) {
  if (/^(sk|rk)_live_/.test(key || "")) return "live";
  if (/^(sk|rk)_test_/.test(key || "")) return "test";
  return null;
}

/**
 * Mode Stripe connu d'un miroir merchant_subscriptions : stripe_livemode
 * (ecrit par le webhook a partir de l'abonnement relu chez Stripe), a defaut
 * stripe_mode (ecrit au Checkout a partir de la cle serveur). null si le
 * document ne porte aucune donnee Stripe (droit legacy ou manuel seul).
 */
function mirrorLivemode(doc) {
  if (typeof doc?.stripe_livemode === "boolean") return doc.stripe_livemode;
  if (doc?.stripe_mode === "live") return true;
  if (doc?.stripe_mode === "test") return false;
  return null;
}

/** Donnees Stripe du miroir issues de l'autre mode : jamais reutilisees. */
function isForeignModeMirror(doc) {
  const livemode = mirrorLivemode(doc);
  return livemode !== null && livemode !== expectedLivemode();
}

/**
 * Le statut d'abonnement Stripe du miroir peut-il ouvrir des droits ici ?
 * LIVE confirme par Stripe, ou TEST dans un projet demo- uniquement.
 */
function isTrustedStripeMirror(doc, sandbox = isStripeSandbox()) {
  return doc?.stripe_livemode === true || (sandbox && doc?.stripe_sandbox === true);
}

/**
 * Champs Stripe d'un miroir de l'autre mode, a effacer avant d'y ecrire
 * l'abonnement du mode attendu (Checkout ou webhook). Les droits poses par
 * l'Admin (manual_access, legacy_access) et le parrainage ne sont pas touches.
 */
function foreignModeResetFields(FieldValue) {
  const del = FieldValue.delete();
  return {
    stripe_customer_id: null,
    stripe_subscription_id: null,
    stripe_checkout_session_id: null,
    stripe_price_id: null,
    subscription_status: null,
    stripe_entitlement: "none",
    publication_access_status: del,
    stripe_livemode: del,
    stripe_mode: del,
    stripe_sandbox: false,
    stripe_fetched_at_ms: 0,
    offer_id: null,
    pending_offer_id: null,
    checkout_status: null,
    checkout_expires_at: null,
    current_period_start: null,
    current_period_end: null,
    cancel_at_period_end: false,
    cancel_at: null,
    canceled_at: null,
    ended_at: null,
    grace_until: null,
    grace_started_at: null,
    last_payment_event_created: 0,
    first_payment_confirmed_at: null,
    last_payment_succeeded_at: null,
    last_renewal_paid_at: null,
    last_invoice_id: null,
    last_payment_failed_at: null,
    last_failed_invoice_id: null,
    unpaid_invoice_url: null,
    payment_attempt_count: null,
    next_payment_attempt_at: null,
    other_subscriptions: del,
    duplicate_subscription_alert: del,
  };
}

module.exports = {
  foreignModeResetFields,
  firebaseProjectId,
  isStripeSandbox,
  expectedLivemode,
  keyMode,
  mirrorLivemode,
  isForeignModeMirror,
  isTrustedStripeMirror,
};

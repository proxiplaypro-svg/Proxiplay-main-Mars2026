// Session Stripe Customer Portal et factures (espace commercant) :
// permet au commercant de consulter son abonnement (qui couvre toutes ses
// enseignes), gerer son moyen de paiement, telecharger ses factures Stripe
// et annuler le renouvellement. Toujours pour le compte de l'appelant
// authentifie lui-meme -- jamais un stripeCustomerId transmis par le client,
// jamais pour le compte d'un autre commercant.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const stripeClientModule = require("./stripe_client");
const {assertMerchantCaller, assertAllowedReturnUrl} = require("./merchant_billing_access");
const {isForeignModeMirror} = require("./stripe_mode");

const kFunctionsRegion = "us-central1";
const kMerchantSubscriptionsCollection = "merchant_subscriptions";
const kMaxInvoices = 24;

async function callerStripeCustomerId(db, uid) {
  const subscriptionSnap = await db.collection(kMerchantSubscriptionsCollection).doc(uid).get();
  if (!subscriptionSnap.exists) return null;
  const mirror = subscriptionSnap.data();
  // Customer de l'autre mode (ex. TEST en production) : jamais utilise.
  return isForeignModeMirror(mirror) ? null : mirror.stripe_customer_id || null;
}

// Customer inconnu de la cle actuelle (miroir ancien, autre mode) : traite
// comme absent plutot qu'en erreur interne.
const isMissingResource = (err) => err?.code === "resource_missing";

async function createMerchantBillingPortalSessionHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  const returnUrl = assertAllowedReturnUrl(data?.returnUrl, "returnUrl");

  const stripeCustomerId = await callerStripeCustomerId(db, context.auth.uid);
  if (!stripeCustomerId) {
    throw new functions.https.HttpsError("failed-precondition", "Aucun abonnement Stripe pour ce compte.");
  }

  const stripe = stripeClientModule.getStripeClient();
  let portalSession;
  try {
    portalSession = await stripe.billingPortal.sessions.create({
      customer: stripeCustomerId,
      return_url: returnUrl,
      locale: "fr",
    });
  } catch (err) {
    if (isMissingResource(err)) {
      throw new functions.https.HttpsError("failed-precondition", "Aucun abonnement Stripe pour ce compte.");
    }
    throw err;
  }

  return {portalUrl: portalSession.url};
}

/**
 * Factures Stripe du commercant appelant : uniquement des montants, dates,
 * statuts et liens Stripe heberges. Aucune donnee de carte.
 */
async function listMerchantInvoicesHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  const stripeCustomerId = await callerStripeCustomerId(db, context.auth.uid);
  if (!stripeCustomerId) return {invoices: []};

  const stripe = stripeClientModule.getStripeClient();
  let list;
  try {
    list = await stripe.invoices.list({customer: stripeCustomerId, limit: kMaxInvoices});
  } catch (err) {
    if (isMissingResource(err)) return {invoices: []};
    throw err;
  }
  const invoices = (list?.data || [])
    .filter((invoice) => invoice.status !== "draft")
    .map((invoice) => ({
      id: invoice.id,
      number: invoice.number || null,
      status: invoice.status || null,
      createdAt: invoice.created ? invoice.created * 1000 : null,
      totalCents: typeof invoice.total === "number" ? invoice.total : null,
      amountPaidCents: typeof invoice.amount_paid === "number" ? invoice.amount_paid : null,
      currency: invoice.currency || "eur",
      hostedInvoiceUrl: invoice.hosted_invoice_url || null,
      invoicePdfUrl: invoice.invoice_pdf || null,
    }));
  return {invoices};
}

exports.createMerchantBillingPortalSession = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
  .https.onCall(createMerchantBillingPortalSessionHandler);

exports.listMerchantInvoices = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB", secrets: ["STRIPE_SECRET_KEY"]})
  .https.onCall(listMerchantInvoicesHandler);

exports.createMerchantBillingPortalSessionHandler = createMerchantBillingPortalSessionHandler;
exports.listMerchantInvoicesHandler = listMerchantInvoicesHandler;

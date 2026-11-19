// Phase 1, tranche 1, lot 1.0 : ce que le commercant voit de ses demandes de
// souscription (vue filtree), plus ce dont le formulaire a besoin : ses
// enseignes, le catalogue, la version des CGV. Lecture seule.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {assertMerchantCaller} = require("./merchant_billing_access");
const {publicOfferCatalog} = require("./merchant_offers");
const {ownedShops} = require("./merchant_ownership");
const {
  kFunctionsRegion,
  kContractsCollection,
  readContractsConfig,
  merchantView,
  millisOf,
  ttcFromHt,
} = require("./merchant_contracts_model");

async function getMyMerchantContractsHandler(data, context) {
  const db = admin.firestore();
  await assertMerchantCaller(db, context);
  const config = await readContractsConfig(db);
  // Interrupteur coupe : rien d'autre n'est lu ni renvoye.
  if (!config.enabled) return {enabled: false};

  const uid = context.auth.uid;
  const [contractsSnap, shops, mirrorsSnap] = await Promise.all([
    db.collection(kContractsCollection).where("owner_uid", "==", uid).get(),
    ownedShops(db, uid),
    db.collection("enseigne_subscriptions").where("owner_uid", "==", uid).get(),
  ]);
  // Tranche 2a : abonnement Stripe de l'enseigne (miroir), sans identifiant Stripe.
  const mirrors = new Map(mirrorsSnap.docs.map((doc) => [doc.data().contract_id, doc.data()]));
  const contracts = contractsSnap.docs
    .map((doc) => {
      const mirror = mirrors.get(doc.id);
      return {...merchantView(doc.id, doc.data()), subscription: mirror && mirror.stripe_subscription_id ? {
        status: mirror.status || null,
        currentPeriodEnd: millisOf(mirror.current_period_end),
        cancelAtPeriodEnd: mirror.cancel_at_period_end === true,
        graceUntil: millisOf(mirror.grace_until),
        unpaidInvoiceUrl: mirror.unpaid_invoice_url || null,
      } : null};
    })
    .sort((a, b) => (b.submittedAt || 0) - (a.submittedAt || 0));
  return {
    enabled: true,
    cgv: config.cgv ? {version: config.cgv.version, url: config.cgv.url, effectiveDate: config.cgv.effectiveDate} : null,
    offers: publicOfferCatalog().map((offer) => ({...offer, amountTtcCents: ttcFromHt(offer.amountHtCents)})),
    enseignes: shops.map((doc) => ({id: doc.id, name: doc.data().name || "", city: doc.data().city || ""})),
    contracts,
  };
}

exports.getMyMerchantContracts = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(getMyMerchantContractsHandler);

exports.getMyMerchantContractsHandler = getMyMerchantContractsHandler;

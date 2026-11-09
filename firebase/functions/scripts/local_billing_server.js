// Serveur LOCAL de recette Stripe (mode test), sans deploiement.
//
// Sert les vrais handlers du paiement commercant (Callables + webhook) au
// protocole Firebase "callable", adosses aux emulateurs Auth et Firestore.
// Utile tant que l'emulateur Functions ne charge pas ce projet.
//
// Garde-fous : emulateurs + projet "demo-" obligatoires ; seules les cles
// Stripe de TEST sont acceptees ; les cles ne sont lues que depuis le
// terminal (jamais depuis un fichier).
//
//   firebase emulators:start --only auth,firestore --project demo-proxiplay-stripe
//   stripe listen --forward-to http://127.0.0.1:35001/stripeWebhook     (affiche whsec_...)
//   # autre terminal, PowerShell :
//   $env:STRIPE_SECRET_KEY="sk_test_..."; $env:STRIPE_WEBHOOK_SECRET="whsec_..."
//   $env:STRIPE_TAX_MODE="none"   # ou tax_rate + STRIPE_TAX_RATE_ID (TEST uniquement)
//   node scripts/local_billing_server.js
//   -> site : http://localhost:5500/espace-commercant/?emulator=1&functionsPort=35001

const http = require("http");
const path = require("path");
const fs = require("fs");

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-proxiplay-stripe";
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
process.env.FUNCTIONS_EMULATOR = "true"; // autorise les URL de retour http://localhost

const kPort = Number(process.env.LOCAL_BILLING_PORT || 35001);
const kAllowedOrigin = process.env.LOCAL_SITE_ORIGIN || "http://localhost:5500";

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!process.env.GCLOUD_PROJECT.startsWith("demo-")) fail("Projet demo- obligatoire (emulateurs uniquement).");
const key = String(process.env.STRIPE_SECRET_KEY || "").trim();
if (key && !/^(sk|rk)_test_/.test(key)) fail("Seule une cle Stripe de TEST est acceptee.");
if (process.env.STRIPE_LIVE_MODE_ENABLED === "true") fail("STRIPE_LIVE_MODE_ENABLED interdit en local.");

// Prix (non secrets) : depuis .env.local, sans ecraser le terminal.
const envFile = path.resolve(__dirname, "..", ".env.local");
if (fs.existsSync(envFile)) {
  fs.readFileSync(envFile, "utf8").split(/\r?\n/).forEach((line) => {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && !/SECRET/.test(match[1]) && process.env[match[1]] === undefined) process.env[match[1]] = match[2];
  });
}

const admin = require("firebase-admin");
admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});

const callables = {
  getMerchantBillingAccount: require("../merchant_billing_account").getMerchantBillingAccountHandler,
  createMerchantCheckoutSession: require("../merchant_checkout").createMerchantCheckoutSessionHandler,
  createMerchantBillingPortalSession: require("../merchant_billing_portal").createMerchantBillingPortalSessionHandler,
  listMerchantInvoices: require("../merchant_billing_portal").listMerchantInvoicesHandler,
  getMerchantPublicationAccess: require("../merchant_publication_access").getMerchantPublicationAccessHandler,
};
const {stripeWebhookHandler} = require("../stripe_webhook");

const corsHeaders = {
  "Access-Control-Allow-Origin": kAllowedOrigin,
  "Access-Control-Allow-Headers": "authorization,content-type,x-firebase-gmpid,x-client-version,x-firebase-appcheck,x-firebase-client",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

const server = http.createServer(async (req, res) => {
  const name = (req.url || "").split("?")[0].split("/").filter(Boolean).pop();
  if (req.method === "OPTIONS") {
    res.writeHead(204, corsHeaders);
    res.end();
    return;
  }
  const rawBody = await readBody(req);

  if (name === "stripeWebhook") {
    // Meme objet requete que Cloud Functions : rawBody pour la signature.
    const response = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      send(body) { res.writeHead(this.statusCode, {"Content-Type": "text/plain"}); res.end(String(body)); },
    };
    await stripeWebhookHandler({method: req.method, headers: req.headers, rawBody}, response);
    console.log(`webhook -> ${response.statusCode}`);
    return;
  }

  const send = (code, payload) => {
    res.writeHead(code, {...corsHeaders, "Content-Type": "application/json"});
    res.end(JSON.stringify(payload));
  };
  const handler = callables[name];
  if (!handler) {
    send(404, {error: {status: "NOT_FOUND", message: "Fonction inconnue."}});
    return;
  }
  try {
    let auth = null;
    const token = String(req.headers.authorization || "").replace(/^Bearer /, "");
    if (token) {
      const decoded = await admin.auth().verifyIdToken(token);
      auth = {uid: decoded.uid, token: decoded};
    }
    const data = rawBody.length ? JSON.parse(rawBody.toString("utf8")).data || {} : {};
    const result = await handler(data, {auth});
    console.log(`${name} -> OK`);
    send(200, {result});
  } catch (err) {
    const json = typeof err.toJSON === "function" ? err.toJSON() : {status: "INTERNAL", message: "Erreur interne."};
    console.log(`${name} -> ${json.status} ${json.message}`);
    send(err.httpErrorCode?.status || 500, {error: json});
  }
});

server.listen(kPort, "127.0.0.1", () => {
  console.log(`Recette Stripe locale sur http://127.0.0.1:${kPort} (projet ${process.env.GCLOUD_PROJECT})`);
  console.log(`  cle Stripe : ${key ? "TEST fournie" : "absente (paiement indisponible)"}`);
  console.log(`  webhook    : ${process.env.STRIPE_WEBHOOK_SECRET ? "secret fourni" : "secret absent"}`);
  console.log(`  fiscalite  : ${process.env.STRIPE_TAX_MODE || "non configuree (paiement ferme)"}`);
});

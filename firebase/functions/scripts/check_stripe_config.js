// Verification de la configuration Stripe des Functions, sans aucune
// ecriture (ni Firestore, ni Stripe).
//
//   node scripts/check_stripe_config.js                       # .env.proxi-play-odzp2e
//   node scripts/check_stripe_config.js --env=.env.local
//
// Option : verifier les prix chez Stripe (lecture seule, MODE TEST
// uniquement) en fournissant la cle dans le terminal, jamais dans un fichier :
//   STRIPE_SECRET_KEY=sk_test_... node scripts/check_stripe_config.js
// (PowerShell : $env:STRIPE_SECRET_KEY="sk_test_..."; node scripts/check_stripe_config.js)

const fs = require("fs");
const path = require("path");

function parseEnvFile(file) {
  const values = {};
  fs.readFileSync(file, "utf8").split(/\r?\n/).forEach((line) => {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match) values[match[1]] = match[2].replace(/^["']|["']$/g, "");
  });
  return values;
}

function check(env) {
  const problems = [];
  const notes = [];
  for (const name of ["STRIPE_PRICE_AUTONOME", "STRIPE_PRICE_ACCOMPAGNEE"]) {
    if (!/^price_[A-Za-z0-9]+$/.test(env[name] || "")) problems.push(`${name} absent ou invalide`);
  }
  if (env.STRIPE_PRICE_AUTONOME && env.STRIPE_PRICE_AUTONOME === env.STRIPE_PRICE_ACCOMPAGNEE) {
    problems.push("les deux offres pointent vers le meme prix");
  }
  for (const name of ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"]) {
    if (env[name]) problems.push(`${name} ne doit jamais figurer dans un fichier .env (Secret Manager)`);
  }
  const mode = env.STRIPE_TAX_MODE || "";
  if (!mode) notes.push("STRIPE_TAX_MODE absent : paiement volontairement ferme (TVA non validee).");
  else if (!["tax_rate", "automatic", "none"].includes(mode)) problems.push(`STRIPE_TAX_MODE invalide : ${mode}`);
  else if (mode === "tax_rate" && !/^txr_/.test(env.STRIPE_TAX_RATE_ID || "")) {
    problems.push("STRIPE_TAX_RATE_ID (txr_...) requis avec STRIPE_TAX_MODE=tax_rate");
  }
  if (env.STRIPE_LIVE_MODE_ENABLED === "true") notes.push("ATTENTION : STRIPE_LIVE_MODE_ENABLED=true (cles LIVE acceptees).");
  return {problems, notes};
}

module.exports = {parseEnvFile, check};

if (require.main === module) {
  const envArg = (process.argv.find((arg) => arg.startsWith("--env=")) || "").split("=")[1];
  const file = path.resolve(__dirname, "..", envArg || ".env.proxi-play-odzp2e");
  if (!fs.existsSync(file)) {
    console.error(`Fichier introuvable : ${file}`);
    process.exit(1);
  }
  const env = parseEnvFile(file);
  const {problems, notes} = check(env);
  console.log(`Configuration : ${path.basename(file)}`);

  // Resolution reelle par le code des Functions (aucune valeur en dur).
  Object.assign(process.env, env);
  const {kOffers, getStripePriceIdOrThrow, assertStripePriceMatchesOffer} = require("../merchant_offers");
  const resolved = Object.values(kOffers).map((offer) => {
    let priceId = null;
    try { priceId = getStripePriceIdOrThrow(offer); } catch (_) { /* signale ci-dessous */ }
    console.log(`  ${offer.label.padEnd(12)} ${(offer.amountHtCents / 100).toFixed(2)} EUR HT/an -> ${priceId || "NON CONFIGURE"}`);
    return {offer, priceId};
  });
  notes.forEach((note) => console.log(`  note : ${note}`));
  problems.forEach((problem) => console.log(`  PROBLEME : ${problem}`));

  (async () => {
    const key = String(process.env.STRIPE_SECRET_KEY || "").trim();
    if (!key) {
      console.log("  (prix non verifies chez Stripe : aucune cle de test fournie dans le terminal)");
    } else if (!/^(sk|rk)_test_/.test(key)) {
      console.error("  Cle refusee : seule une cle de TEST (sk_test_/rk_test_) est acceptee ici.");
      process.exit(1);
    } else {
      const stripe = new (require("stripe"))(key, {apiVersion: require("../stripe_client").kStripeApiVersion});
      for (const {offer, priceId} of resolved) {
        if (!priceId) continue;
        try {
          const price = await stripe.prices.retrieve(priceId);
          assertStripePriceMatchesOffer(price, offer);
          if (price.livemode !== false) throw new Error("prix LIVE");
          console.log(`  OK Stripe : ${offer.label} = ${price.unit_amount / 100} ${price.currency.toUpperCase()} / ${price.recurring.interval} (test)`);
        } catch (err) {
          problems.push(`${offer.label} : ${err.message}`);
          console.log(`  PROBLEME Stripe : ${offer.label} : ${err.message}`);
        }
      }
    }
    process.exit(problems.length ? 1 : 0);
  })();
}

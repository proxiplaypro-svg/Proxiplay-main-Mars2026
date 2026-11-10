#!/usr/bin/env node
// Publication des conditions du parrainage commercant (1.1.4), en attendant
// l'ecran de l'Admin. Meme code que la callable
// adminPublishMerchantReferralConditions (validation, historique, `enabled`
// jamais modifie).
//
// Par defaut : apercu, rien n'est ecrit.
// Ecriture : --apply --confirm --project=<id> --reason="..." --published-by=users/<uid>
// Options : --text-file=<chemin> (defaut : merchant_referral_conditions_v1.txt),
//           --expected-version=<n> (defaut 0 : premiere publication).
// Voir docs/merchant-referral-conditions-1.1.4.md.
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const {
  kDefaultConditionsTitle,
  publishMerchantReferralConditions,
} = require("../merchant_referral_conditions");

function parseArgs(argv) {
  const flags = new Set(argv.slice(2));
  const value = (name, fallback = "") => {
    const arg = argv.find((entry) => entry.startsWith(`${name}=`));
    return arg ? arg.slice(name.length + 1) : fallback;
  };
  return {
    apply: flags.has("--apply"),
    confirm: flags.has("--confirm"),
    projectId: value("--project"),
    reason: value("--reason", "Apercu"),
    publishedBy: value("--published-by"),
    textFile: value("--text-file", path.join(__dirname, "..", "merchant_referral_conditions_v1.txt")),
    expectedVersion: Number.parseInt(value("--expected-version", "0"), 10),
  };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.apply && (!args.confirm || !args.projectId || !args.publishedBy.startsWith("users/"))) {
    throw new Error("--apply exige --confirm, --project=<id> et --published-by=users/<uid>.");
  }
  admin.initializeApp(args.projectId ? {projectId: args.projectId} : undefined);
  const result = await publishMerchantReferralConditions(admin.firestore(), {
    title: kDefaultConditionsTitle,
    text: fs.readFileSync(args.textFile, "utf8"),
    reason: args.reason,
    expectedVersion: args.expectedVersion,
    publishedBy: args.publishedBy || "script/publish_merchant_referral_conditions",
    dryRun: !args.apply,
  });
  console.log(JSON.stringify(result, null, 2));
  if (!args.apply) console.log("Apercu : rien n'a ete ecrit.");
  if (!["preview", "published"].includes(result.status)) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});

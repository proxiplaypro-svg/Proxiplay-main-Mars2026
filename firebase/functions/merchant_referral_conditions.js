// Conditions du programme de parrainage commercant (1.1.4), modifiables
// sans nouvelle version de l'app.
//
// Stockage (voir docs/merchant-referral-conditions-1.1.4.md) :
//  - app_config/merchant_referral.conditions : version en vigueur, lue par
//    l'app ;
//  - app_config/merchant_referral/conditions_versions/{version} : historique
//    immuable de chaque version publiee.
//
// Securite :
//  - seule la callable adminPublishMerchantReferralConditions publie ; les
//    regles interdisent aux clients d'ecrire `conditions` et l'historique ;
//  - la publication n'ecrit JAMAIS `enabled`, et elle est refusee si
//    `enabled` n'est pas un booleen deja enregistre : une publication ne
//    cree jamais le document et ne change jamais l'etat du programme
//    (ouvert seulement si enabled === true, partout) ;
//  - elle ne touche ni aux codes, ni aux parrainages, ni aux recompenses.
//
// Format du texte (format "plain_v1"), identique cote app
// (lib/utils/merchant_referral_conditions.dart) :
//  - paragraphes separes par une ligne vide ;
//  - une ligne commencant par "- " est un element de liste.
const admin = require("firebase-admin");
const functions = require("firebase-functions");
const fs = require("fs");
const path = require("path");
const {isTrustedAdmin} = require("./admin_identity");

const kConfigPath = "app_config/merchant_referral";
const kVersionsCollection = "conditions_versions";
const kConditionsFormat = "plain_v1";
const kTitleMaxLength = 120;
const kTextMinLength = 100;
const kTextMaxLength = 8000;
const kMaxBlocks = 40;
const kMaxLineLength = 600;
const kReasonMinLength = 5;
const kReasonMaxLength = 200;

const kDefaultConditionsTitle = "Conditions du programme de parrainage commerçant";
// Texte initial (version 1), valide le 10/11/2026. La meme copie est
// integree a l'app comme secours signale (test croise).
const kInitialConditionsText = fs.readFileSync(
  path.join(__dirname, "merchant_referral_conditions_v1.txt"), "utf8",
).replace(/\r\n/g, "\n").trim();

function normalizeText(value) {
  return String(value ?? "").replace(/\r\n?/g, "\n").replace(/[ \t]+$/gm, "").trim();
}

/** Decoupe le texte en blocs {type: "paragraph", text} | {type: "list", items}. */
function parseConditionsText(text) {
  const blocks = [];
  for (const chunk of normalizeText(text).split(/\n\s*\n/)) {
    const lines = chunk.split("\n").map((line) => line.trim()).filter(Boolean);
    let paragraph = [];
    let items = [];
    const flushParagraph = () => {
      if (paragraph.length) blocks.push({type: "paragraph", text: paragraph.join(" ")});
      paragraph = [];
    };
    const flushList = () => {
      if (items.length) blocks.push({type: "list", items});
      items = [];
    };
    for (const line of lines) {
      if (line.startsWith("- ")) {
        flushParagraph();
        items.push(line.slice(2).trim());
      } else {
        flushList();
        paragraph.push(line);
      }
    }
    flushParagraph();
    flushList();
  }
  return blocks;
}

/** Erreurs de validation (liste vide = texte publiable). */
function validateConditions({title, text}) {
  const errors = [];
  const cleanTitle = normalizeText(title);
  const cleanText = normalizeText(text);
  if (!cleanTitle || cleanTitle.length > kTitleMaxLength || cleanTitle.includes("\n")) {
    errors.push(`Titre obligatoire, une ligne, ${kTitleMaxLength} caracteres au plus.`);
  }
  if (cleanText.length < kTextMinLength || cleanText.length > kTextMaxLength) {
    errors.push(`Texte de ${kTextMinLength} a ${kTextMaxLength} caracteres.`);
  }
  // Caracteres de controle (hors saut de ligne et tabulation) et balises.
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(cleanText + cleanTitle)) {
    errors.push("Caracteres de controle interdits.");
  }
  if (/<\s*\/?\s*[a-z][^>]*>/i.test(cleanText + cleanTitle)) {
    errors.push("Balises HTML interdites : texte simple seulement.");
  }
  const blocks = parseConditionsText(cleanText);
  if (!blocks.length || blocks.length > kMaxBlocks) {
    errors.push(`Entre 1 et ${kMaxBlocks} paragraphes ou listes.`);
  }
  const lines = blocks.flatMap((block) => block.type === "list" ? block.items : [block.text]);
  if (lines.some((line) => !line || line.length > kMaxLineLength)) {
    errors.push(`Chaque paragraphe ou element de liste : ${kMaxLineLength} caracteres au plus, jamais vide.`);
  }
  return {errors, title: cleanTitle, text: cleanText, blocks};
}

function timestampMillis(value) {
  if (!value) return NaN;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return NaN;
}

/**
 * Version applicable a un parrainage enregistre a `date` (linked_at ou
 * created_at) : la derniere version entree en vigueur avant cette date.
 * null si aucune version n'etait publiee (parrainage anterieur au systeme).
 */
function conditionsVersionAt(versions, date) {
  const at = timestampMillis(date);
  if (!Number.isFinite(at)) return null;
  let best = null;
  for (const version of versions) {
    const effective = timestampMillis(version.effective_at);
    if (Number.isFinite(effective) && effective <= at &&
        (!best || Number(version.version) > Number(best.version))) {
      best = version;
    }
  }
  return best;
}

/**
 * Publie une nouvelle version, ou la simule (dryRun). Ecritures dans une
 * transaction : historique cree avec create() (jamais reecrit), puis seul
 * le champ `conditions` du document de configuration est mis a jour.
 */
async function publishMerchantReferralConditions(db, {
  title = kDefaultConditionsTitle,
  text,
  reason,
  expectedVersion,
  publishedBy,
  dryRun = false,
}) {
  const checked = validateConditions({title, text});
  const cleanReason = normalizeText(reason).replace(/\s+/g, " ");
  if (cleanReason.length < kReasonMinLength || cleanReason.length > kReasonMaxLength) {
    checked.errors.push(`Motif obligatoire (${kReasonMinLength} a ${kReasonMaxLength} caracteres).`);
  }
  if (!Number.isInteger(expectedVersion) || expectedVersion < 0) {
    checked.errors.push("Version attendue invalide.");
  }
  if (checked.errors.length) {
    return {status: "invalid", errors: checked.errors};
  }

  const configRef = db.doc(kConfigPath);
  return db.runTransaction(async (tx) => {
    const configSnap = await tx.get(configRef);
    const data = configSnap.exists ? configSnap.data() : null;
    if (!data || typeof data.enabled !== "boolean") {
      // Ne jamais creer le document ni le laisser sans `enabled`.
      return {status: "config_missing_enabled"};
    }
    const currentVersion = Number.isInteger(data.conditions?.version) ? data.conditions.version : 0;
    if (currentVersion !== expectedVersion) {
      return {status: "version_conflict", currentVersion};
    }
    const version = currentVersion + 1;
    if (dryRun) {
      return {status: "preview", version, title: checked.title, blocks: checked.blocks};
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const conditions = {
      version,
      format: kConditionsFormat,
      title: checked.title,
      text: checked.text,
      effective_at: now,
      updated_at: now,
    };
    tx.create(configRef.collection(kVersionsCollection).doc(String(version)), {
      ...conditions,
      published_by: publishedBy,
      reason: cleanReason,
      previous_version: currentVersion || null,
    });
    tx.update(configRef, {conditions});
    return {status: "published", version};
  });
}

async function adminPublishMerchantReferralConditionsHandler(data, context = {}) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const db = admin.firestore();
  const callerSnap = await db.collection("users").doc(context.auth.uid).get();
  if (!isTrustedAdmin(context.auth, callerSnap.data() || {})) {
    throw new functions.https.HttpsError("permission-denied", "Reserve a l'administration.");
  }
  const result = await publishMerchantReferralConditions(db, {
    title: data?.title ?? kDefaultConditionsTitle,
    text: data?.text,
    reason: data?.reason,
    expectedVersion: data?.expectedVersion,
    publishedBy: `users/${context.auth.uid}`,
    dryRun: data?.dryRun === true,
  });
  if (result.status === "invalid") {
    throw new functions.https.HttpsError("invalid-argument", result.errors.join(" "), {errors: result.errors});
  }
  if (result.status === "config_missing_enabled") {
    throw new functions.https.HttpsError("failed-precondition",
      "Le document app_config/merchant_referral doit d'abord avoir un champ enabled.");
  }
  if (result.status === "version_conflict") {
    throw new functions.https.HttpsError("aborted",
      "Les conditions ont ete modifiees entre-temps. Rechargez avant de publier.",
      {currentVersion: result.currentVersion});
  }
  return result;
}

const adminPublishMerchantReferralConditions = functions.https.onCall(
  adminPublishMerchantReferralConditionsHandler,
);

module.exports = {
  adminPublishMerchantReferralConditions,
  adminPublishMerchantReferralConditionsHandler,
  conditionsVersionAt,
  kConditionsFormat,
  kDefaultConditionsTitle,
  kInitialConditionsText,
  parseConditionsText,
  publishMerchantReferralConditions,
  validateConditions,
};

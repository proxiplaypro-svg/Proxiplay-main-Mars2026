// Systeme publicitaire ProxiPlay (vendu en direct, pas AdMob). La config
// de chaque emplacement (ads/open, ads/home_banner,
// ads/home_banner_referral) est lue directement
// par le client (regles: read:true). Une campagne "reservee aux majeurs" n'y
// met jamais sa creation : l'image et le lien sont dans
// ads_restricted/{placement} (aucune lecture client) et ne sont remis que par
// getRestrictedAdCreative a un compte connecte et majeur.
//
// recordAdEvent reste ouvert aux invites (ils voient les bandeaux), mais ne
// compte que ce qui correspond a une exposition legitime : campagne en cours
// sur l'emplacement, une impression par personne/emplacement/campagne par
// fenetre, un clic seulement apres une impression, et un debit limite.
// Aucune donnee personnelle n'est conservee : seules des empreintes salees et
// non reversibles servent au dedoublonnage, avec une date d'expiration.

const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");

const kFunctionsRegion = "us-central1";
const kAdsCollection = "ads";
const kRestrictedCollection = "ads_restricted";
const kCampaignsCollection = "ad_campaigns";
const kExposuresCollection = "_ad_exposures";
const kRateCollection = "_ad_event_rate";
const kValidPlacements = new Set([
  "open",
  "home_banner",
  "home_banner_referral",
]);
const kValidEventTypes = new Set(["impression", "click"]);
// A new exposure of the same campaign to the same person counts again after
// this window (a refresh or a revisit within it does not).
const kExposureWindowMs = 30 * 60 * 1000;
const kMaxEventsPerMinute = 60;

const text = (value) => typeof value === "string" ? value.trim() : "";
const fingerprint = (value) =>
  crypto.createHash("sha256").update("proxiplay-ads|" + value).digest("hex");

function nowMs() {
  return Date.now();
}

// Who is exposed: the account when signed in, otherwise the network origin
// (address + browser signature), only ever stored as a salted hash.
function exposureIdentity(context) {
  const uid = context?.auth?.uid;
  if (uid) return "uid:" + uid;
  const request = context?.rawRequest;
  const forwarded = text(request?.headers?.["x-forwarded-for"]).split(",")[0].trim();
  const ip = text(request?.ip) || forwarded;
  if (!ip) return "";
  return "net:" + ip + "|" + text(request?.headers?.["user-agent"]);
}

function isLivePlacement(data, now) {
  if (!data || data.enabled !== true) return false;
  const start = data.start_at?.toMillis?.();
  const end = data.end_at?.toMillis?.();
  return (start == null || start <= now) && (end == null || end >= now);
}

async function isAdultAccount(db, context, now, transaction = null) {
  const uid = context?.auth?.uid;
  if (!uid) return false;
  const ref = db.doc(`users/${uid}`);
  const snap = transaction ? await transaction.get(ref) : await ref.get();
  const {isAdultFromBirthday} = require("./participate_in_game_transaction");
  return isAdultFromBirthday(snap.data()?.birthday, new Date(now));
}

async function enforceRate(db, identity, now) {
  const ref = db.collection(kRateCollection).doc(fingerprint(identity || "anonymous"));
  await db.runTransaction(async (transaction) => {
    const previous = (await transaction.get(ref)).data() || {};
    const start = Number(previous.start) || 0;
    const count = now >= start && now - start < 60000 ? Number(previous.count) || 0 : 0;
    // Callers without any identity share one bucket, sized accordingly.
    const limit = identity ? kMaxEventsPerMinute : kMaxEventsPerMinute * 10;
    if (count >= limit) {
      throw new functions.https.HttpsError("resource-exhausted", "Trop d'evenements publicitaires.");
    }
    transaction.set(ref, {start: count ? start : now, count: count + 1,
      expires_at: admin.firestore.Timestamp.fromMillis(now + 120000)});
  });
}

async function recordAdEventHandler(data, context = {}) {
  const placement = text(data?.placement);
  const type = text(data?.type);
  if (!kValidPlacements.has(placement)) {
    throw new functions.https.HttpsError("invalid-argument", "placement invalide.");
  }
  if (!kValidEventTypes.has(type)) {
    throw new functions.https.HttpsError("invalid-argument", "type invalide.");
  }
  const campaignId = text(data?.campaign_id);
  if (campaignId.length > 128 || campaignId.includes("/")) {
    throw new functions.https.HttpsError("invalid-argument", "campagne invalide.");
  }

  const db = admin.firestore();
  const now = nowMs();
  const identity = exposureIdentity(context);
  await enforceRate(db, identity, now);

  const field = type === "impression" ? "impressions" : "clicks";
  const placementRef = db.doc(`${kAdsCollection}/${placement}`);
  return db.runTransaction(async (transaction) => {
    const placementData = (await transaction.get(placementRef)).data();
    // Only the campaign currently published on this placement is credited;
    // the client never chooses another one.
    if (!isLivePlacement(placementData, now)) return {status: "ignored", reason: "inactive"};
    const configuredCampaign = text(placementData.campaign_id);
    if (configuredCampaign !== campaignId) return {status: "ignored", reason: "stale_campaign"};
    if (placementData.adults_only === true && !(await isAdultAccount(db, context, now, transaction))) {
      return {status: "ignored", reason: "adults_only"};
    }

    // One impression per person, placement and campaign per window; a click
    // only counts after an impression, once per impression.
    let exposureRef = null;
    let exposure = {};
    if (identity) {
      exposureRef = db.collection(kExposuresCollection)
        .doc(fingerprint(`${identity}|${placement}|${configuredCampaign}`));
      exposure = (await transaction.get(exposureRef)).data() || {};
    }
    const lastImpression = exposure.last_impression_at?.toMillis?.() ?? null;
    const lastClick = exposure.last_click_at?.toMillis?.() ?? null;
    const exposed = lastImpression != null && now - lastImpression < kExposureWindowMs;
    if (exposureRef && type === "impression" && exposed) {
      return {status: "ignored", reason: "duplicate_impression"};
    }
    if (exposureRef && type === "click" && !exposed) {
      return {status: "ignored", reason: "click_without_impression"};
    }
    if (exposureRef && type === "click" && lastClick != null && lastClick >= lastImpression) {
      return {status: "ignored", reason: "duplicate_click"};
    }

    const at = admin.firestore.Timestamp.fromMillis(now);
    if (exposureRef) {
      transaction.set(exposureRef, {
        ...(type === "impression" ? {last_impression_at: at} : {last_click_at: at}),
        expires_at: admin.firestore.Timestamp.fromMillis(now + kExposureWindowMs * 2),
      }, {merge: true});
    }
    transaction.set(placementRef, {[field]: admin.firestore.FieldValue.increment(1)}, {merge: true});
    if (configuredCampaign) {
      transaction.set(db.collection(kCampaignsCollection).doc(configuredCampaign), {
        [field]: admin.firestore.FieldValue.increment(1),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    return {status: "recorded"};
  });
}

// The creative of an adults-only campaign, for a signed-in adult only.
// Anyone else simply gets nothing (never an error that could be retried).
async function getRestrictedAdCreativeHandler(data, context = {}) {
  const placement = text(data?.placement);
  if (!kValidPlacements.has(placement)) {
    throw new functions.https.HttpsError("invalid-argument", "placement invalide.");
  }
  const db = admin.firestore();
  const now = nowMs();
  const unavailable = {available: false};
  if (!context?.auth?.uid) return unavailable;
  const [placementSnap, restrictedSnap] = await Promise.all([
    db.doc(`${kAdsCollection}/${placement}`).get(),
    db.doc(`${kRestrictedCollection}/${placement}`).get(),
  ]);
  const placementData = placementSnap.data();
  const restricted = restrictedSnap.data();
  if (!isLivePlacement(placementData, now) || placementData.adults_only !== true || !restricted ||
      text(restricted.campaign_id) !== text(placementData.campaign_id) || !text(restricted.image_url)) {
    return unavailable;
  }
  if (!(await isAdultAccount(db, context, now))) return unavailable;
  return {
    available: true,
    campaign_id: text(placementData.campaign_id),
    image_url: text(restricted.image_url),
    destination_url: text(restricted.destination_url),
  };
}

exports.recordAdEvent = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 10, memory: "128MB"})
  .https.onCall(recordAdEventHandler);

exports.getRestrictedAdCreative = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 10, memory: "128MB"})
  .https.onCall(getRestrictedAdCreativeHandler);

exports.recordAdEventHandler = recordAdEventHandler;
exports.getRestrictedAdCreativeHandler = getRestrictedAdCreativeHandler;
exports.kExposureWindowMs = kExposureWindowMs;

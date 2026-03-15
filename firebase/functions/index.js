const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
admin.initializeApp();

const kFcmTokensCollection = "fcm_tokens";
const kPushNotificationsCollection = "ff_push_notifications";
const firestore = admin.firestore();
const kSystemJobsCollection = "_system_jobs";
const kMainPrizeBackfillDocId = "games_has_main_prize_backfill";
const kPrizeNotificationsJobDocId = "prize_notifications";
const kPrizeNotificationsEntriesCollection = "entries";
const kDailyPartsResetBatchSize = 450;
const kParisTimeZone = "Europe/Paris";
const kInvalidFcmErrorCodes = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

const kPushNotificationRuntimeOpts = {
  timeoutSeconds: 540,
  memory: "2GB",
};

function inferLegacyHasMainPrize(gameData) {
  return (
    (typeof gameData.name === "string" && gameData.name.trim().length > 0) ||
    (typeof gameData.description === "string" &&
      gameData.description.trim().length > 0) ||
    (gameData.prize_value !== null &&
      typeof gameData.prize_value !== "undefined")
  );
}

function hasHasMainPrizeField(gameData) {
  return Object.prototype.hasOwnProperty.call(gameData || {}, "hasMainPrize");
}

function resolveHasMainPrize(gameData) {
  if (gameData.hasMainPrize === true) {
    return true;
  }
  if (gameData.hasMainPrize === false) {
    return false;
  }
  return inferLegacyHasMainPrize(gameData);
}

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function toDocRef(value) {
  if (!value) {
    return null;
  }
  if (typeof value === "string") {
    const path = getTrimmedString(value);
    if (path && path.includes("/")) {
      return firestore.doc(path);
    }
    return null;
  }
  if (typeof value.path === "string" && typeof value.get === "function") {
    return value;
  }
  if (typeof value.path === "string") {
    return firestore.doc(value.path);
  }
  if (
    value._path &&
    Array.isArray(value._path.segments) &&
    value._path.segments.length >= 2
  ) {
    return firestore.doc(value._path.segments.join("/"));
  }
  return null;
}

function getUserUidFromRef(userRef) {
  if (!userRef || typeof userRef.path !== "string") {
    return "";
  }
  const pathParts = userRef.path.split("/");
  if (pathParts.length >= 2 && pathParts[0] === "users") {
    return getTrimmedString(pathParts[1]);
  }
  return getTrimmedString(userRef.id);
}

async function getDocData(ref) {
  if (!ref) {
    return null;
  }
  const snap = await ref.get();
  return snap.exists ? snap.data() : null;
}

async function resolveUserEmail(userRef, userData) {
  const emailFromDoc = getTrimmedString(userData && userData.email);
  if (emailFromDoc) {
    return emailFromDoc;
  }

  const uid = getUserUidFromRef(userRef);
  if (!uid) {
    return "";
  }

  try {
    const authUser = await admin.auth().getUser(uid);
    return getTrimmedString(authUser.email);
  } catch (e) {
    console.log(`resolveUserEmail: unable to read auth email for ${uid}: ${e}`);
    return "";
  }
}

function toBoolean(value, defaultValue = false) {
  if (typeof value === "boolean") {
    return value;
  }
  const parsed = getTrimmedString(value).toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(parsed)) {
    return true;
  }
  if (["0", "false", "no", "n", "off"].includes(parsed)) {
    return false;
  }
  return defaultValue;
}

function timestampToMillis(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function isPublishedGame(gameData) {
  return toBoolean(gameData && gameData.visible_public, false);
}

function getNestedValue(source, path) {
  let current = source;
  for (const segment of path) {
    if (!current || typeof current !== "object" || !(segment in current)) {
      return undefined;
    }
    current = current[segment];
  }
  return current;
}

function getFirstDefinedBooleanValue(source, candidatePaths) {
  for (const path of candidatePaths) {
    const value = getNestedValue(source, path);
    if (typeof value !== "undefined") {
      return toBoolean(value, true);
    }
  }
  return null;
}

function isUserPushPreferenceEnabled(userData, preferenceKey) {
  const globalPreference = getFirstDefinedBooleanValue(userData, [
    ["push_notifications_enabled"],
    ["notifications_enabled"],
    ["allow_push_notifications"],
    ["pushEnabled"],
    ["notificationsEnabled"],
    ["notification_preferences", "enabled"],
    ["notificationSettings", "enabled"],
    ["pushPreferences", "enabled"],
  ]);
  if (globalPreference === false) {
    return false;
  }

  const preferenceCandidatesByKey = {
    favoriteMerchantNewGame: [
      ["favorite_merchant_new_game_notifications_enabled"],
      ["notify_new_games_from_favorites"],
      ["push_new_games_from_favorites"],
      ["notification_preferences", "favoriteMerchantNewGame"],
      ["notification_preferences", "newGamesFromFavorites"],
      ["notificationSettings", "favoriteMerchantNewGame"],
      ["notificationSettings", "newGamesFromFavorites"],
      ["pushPreferences", "favoriteMerchantNewGame"],
    ],
    followedGameEndingSoon: [
      ["followed_game_ending_soon_notifications_enabled"],
      ["notify_followed_game_ending_soon"],
      ["push_followed_game_ending_soon"],
      ["notification_preferences", "followedGameEndingSoon"],
      ["notification_preferences", "gameEndingReminder"],
      ["notificationSettings", "followedGameEndingSoon"],
      ["notificationSettings", "gameEndingReminder"],
      ["pushPreferences", "followedGameEndingSoon"],
    ],
  };

  const categoryPreference = getFirstDefinedBooleanValue(
    userData,
    preferenceCandidatesByKey[preferenceKey] || [],
  );
  if (categoryPreference === false) {
    return false;
  }
  return true;
}

function getTimeZoneOffsetMillis(date, timeZone) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    timeZoneName: "shortOffset",
  });
  const timeZoneNamePart = formatter
    .formatToParts(date)
    .find((part) => part.type === "timeZoneName");
  const offsetText = (timeZoneNamePart && timeZoneNamePart.value) || "GMT+0";
  const match = offsetText.match(/GMT([+-])(\d{1,2})(?::?(\d{2}))?/i);
  if (!match) {
    return 0;
  }
  const sign = match[1] === "-" ? -1 : 1;
  const hours = Number(match[2] || 0);
  const minutes = Number(match[3] || 0);
  return sign * ((hours * 60 + minutes) * 60 * 1000);
}

function getTimeZoneDayBounds(baseDate, timeZone, dayOffset = 0) {
  const targetDate = new Date(baseDate.getTime() + dayOffset * 24 * 60 * 60 * 1000);
  const dateParts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(targetDate);
  const year = Number(dateParts.find((part) => part.type === "year").value);
  const month =
    Number(dateParts.find((part) => part.type === "month").value) - 1;
  const day = Number(dateParts.find((part) => part.type === "day").value);
  const startUtcGuess = new Date(Date.UTC(year, month, day, 0, 0, 0, 0));
  const startOffset = getTimeZoneOffsetMillis(startUtcGuess, timeZone);
  const start = new Date(startUtcGuess.getTime() - startOffset);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return { start, end };
}

async function queueUserScopedPushNotification({
  docId,
  title,
  body,
  userUid,
  createdBy,
  initialPageName = "",
  parameterData = "",
}) {
  const ref = firestore.collection(kPushNotificationsCollection).doc(docId);
  const existing = await ref.get();
  if (existing.exists) {
    return false;
  }

  await ref.set({
    notification_title: title,
    notification_text: body,
    notification_image_url: "",
    notification_sound: "",
    parameter_data: parameterData,
    initial_page_name: initialPageName,
    target_audience: "All",
    target_user_group: "All",
    user_refs: `users/${userUid}`,
    status: "started",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: createdBy,
  });
  return true;
}

async function loadUserSnapshotsByRef(userRefs) {
  if (!userRefs.length) {
    return [];
  }
  const snapshots = await firestore.getAll(...userRefs);
  return snapshots.filter((snapshot) => snapshot.exists);
}

async function queueFavoriteMerchantNewGameNotifications(gameDoc, gameData) {
  const enseigneRef = toDocRef(gameData.enseigne_id);
  if (!enseigneRef) {
    console.log(`[favoriteMerchantNewGame] skip game=${gameDoc.id} reason=missing_enseigne_ref`);
    return;
  }

  const favoriteSnap = await firestore
    .collectionGroup("favorite_enseignes")
    .where("enseigne_id", "==", enseigneRef)
    .get();

  if (favoriteSnap.empty) {
    console.log(`[favoriteMerchantNewGame] game=${gameDoc.id} favorites=0 queued=0`);
    return;
  }

  const userRefsByUid = new Map();
  favoriteSnap.docs.forEach((favoriteDoc) => {
    const userRef = favoriteDoc.ref.parent.parent;
    const uid = getUserUidFromRef(userRef);
    if (userRef && uid) {
      userRefsByUid.set(uid, userRef);
    }
  });

  const userSnaps = await loadUserSnapshotsByRef(Array.from(userRefsByUid.values()));
  let queued = 0;
  let skippedPrefs = 0;
  let duplicates = 0;

  await Promise.all(
    userSnaps.map(async (userSnap) => {
      const userUid = getUserUidFromRef(userSnap.ref);
      if (!userUid || !isUserPushPreferenceEnabled(userSnap.data(), "favoriteMerchantNewGame")) {
        skippedPrefs += 1;
        return;
      }

      const gameName = getTrimmedString(gameData.name) || "un nouveau jeu";
      const enseigneName =
        getTrimmedString(gameData.enseigne_name) || getTrimmedString(gameData.name);
      const queuedNow = await queueUserScopedPushNotification({
        docId: `favorite_merchant_new_game_${gameDoc.id}_${userUid}`,
        title: "Nouveau jeu disponible",
        body: enseigneName
          ? `${enseigneName} vient de publier ${gameName}.`
          : `Un commerçant favori vient de publier ${gameName}.`,
        userUid,
        createdBy: `system/favorite_merchant_new_game/${gameDoc.id}`,
      });

      if (queuedNow) {
        queued += 1;
      } else {
        duplicates += 1;
      }
    }),
  );

  console.log(
    `[favoriteMerchantNewGame] game=${gameDoc.id} favorites=${favoriteSnap.size} users=${userSnaps.length} queued=${queued} duplicates=${duplicates} skippedPrefs=${skippedPrefs}`,
  );
}

async function queueFollowedGameEndingSoonNotifications(gameDoc) {
  const gameData = gameDoc.data() || {};
  const favoriteSnap = await firestore
    .collectionGroup("favorite_games")
    .where("game_id", "==", gameDoc.ref)
    .get();

  if (favoriteSnap.empty) {
    console.log(`[followedGameEndingSoon] game=${gameDoc.id} followers=0 queued=0`);
    return;
  }

  const userRefsByUid = new Map();
  favoriteSnap.docs.forEach((favoriteDoc) => {
    const userRef = favoriteDoc.ref.parent.parent;
    const uid = getUserUidFromRef(userRef);
    if (userRef && uid) {
      userRefsByUid.set(uid, userRef);
    }
  });

  const userSnaps = await loadUserSnapshotsByRef(Array.from(userRefsByUid.values()));
  let queued = 0;
  let skippedPrefs = 0;
  let duplicates = 0;

  await Promise.all(
    userSnaps.map(async (userSnap) => {
      const userUid = getUserUidFromRef(userSnap.ref);
      if (!userUid || !isUserPushPreferenceEnabled(userSnap.data(), "followedGameEndingSoon")) {
        skippedPrefs += 1;
        return;
      }

      const gameName = getTrimmedString(gameData.name) || "ce jeu";
      const enseigneName = getTrimmedString(gameData.enseigne_name);
      const queuedNow = await queueUserScopedPushNotification({
        docId: `followed_game_ending_soon_${gameDoc.id}_${userUid}`,
        title: "Jeu bientot termine",
        body: enseigneName
          ? `${gameName} chez ${enseigneName} se termine dans 3 jours.`
          : `${gameName} se termine dans 3 jours.`,
        userUid,
        createdBy: `system/followed_game_ending_soon/${gameDoc.id}`,
      });

      if (queuedNow) {
        queued += 1;
      } else {
        duplicates += 1;
      }
    }),
  );

  console.log(
    `[followedGameEndingSoon] game=${gameDoc.id} followers=${favoriteSnap.size} users=${userSnaps.length} queued=${queued} duplicates=${duplicates} skippedPrefs=${skippedPrefs}`,
  );
}

async function cleanupInvalidFcmTokens(tokenRefsByToken, responses, tokensBatch) {
  const refsToDelete = [];
  responses.forEach((response, index) => {
    if (response.success) {
      return;
    }
    const code = response.error && response.error.code;
    if (!kInvalidFcmErrorCodes.has(code)) {
      return;
    }
    const token = tokensBatch[index];
    const refs = tokenRefsByToken.get(token) || [];
    refs.forEach((ref) => refsToDelete.push(ref));
  });

  if (!refsToDelete.length) {
    return 0;
  }

  await Promise.all(
    refsToDelete.map(async (ref) => {
      try {
        await ref.delete();
      } catch (error) {
        console.log(`Unable to delete invalid FCM token doc ${ref.path}: ${error}`);
      }
    }),
  );

  return refsToDelete.length;
}

function normalizeExternalUrl(url) {
  const trimmed = getTrimmedString(url);
  if (!trimmed) {
    return "";
  }
  if (/^https?:\/\//i.test(trimmed)) {
    return trimmed;
  }
  return `https://${trimmed}`;
}

function buildGoogleMapsLink(enseigneData) {
  const address = getTrimmedString(enseigneData && enseigneData.address);
  const city = getTrimmedString(enseigneData && enseigneData.city);
  const rawAddress = [address, city].filter((v) => v).join(", ");
  if (!rawAddress) {
    return "";
  }
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
    rawAddress,
  )}`;
}

/**
 * Reset player daily parts at midnight France time.
 * - Sets users.remaining_part to 3
 * - Sets users.part_last_update to server timestamp
 * - Paginates users and commits in Firestore-safe batch sizes
 */
exports.resetDailyRemainingParts = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    let totalUsersReset = 0;
    let totalBatches = 0;
    let totalBatchErrors = 0;
    let pageCount = 0;
    let lastDoc = null;

    console.log(
      "[resetDailyRemainingParts] start",
      JSON.stringify({
        schedule: "0 0 * * *",
        timezone: "Europe/Paris",
        batchSize: kDailyPartsResetBatchSize,
      }),
    );

    while (true) {
      let query = firestore
        .collection("users")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(kDailyPartsResetBatchSize);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const usersSnap = await query.get();
      if (usersSnap.empty) {
        break;
      }

      pageCount += 1;
      const batch = firestore.batch();

      usersSnap.docs.forEach((userDoc) => {
        batch.update(userDoc.ref, {
          remaining_part: 3,
          part_last_update: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      try {
        await batch.commit();
        totalBatches += 1;
        totalUsersReset += usersSnap.size;
        console.log(
          `[resetDailyRemainingParts] page=${pageCount} batchCommitted size=${usersSnap.size}`,
        );
      } catch (e) {
        totalBatchErrors += 1;
        console.error(
          `[resetDailyRemainingParts] batchError page=${pageCount} size=${usersSnap.size}: ${e}`,
        );
      }

      lastDoc = usersSnap.docs[usersSnap.docs.length - 1];
      if (usersSnap.size < kDailyPartsResetBatchSize) {
        break;
      }
    }

    console.log(
      "[resetDailyRemainingParts] done",
      JSON.stringify({
        usersReset: totalUsersReset,
        batches: totalBatches,
        batchErrors: totalBatchErrors,
        pages: pageCount,
      }),
    );

    return null;
  });

function buildShopLink(enseigneData) {
  const website = normalizeExternalUrl(enseigneData && enseigneData.site_web_url);
  if (website) {
    return website;
  }
  const mapLink = buildGoogleMapsLink(enseigneData);
  if (mapLink) {
    return mapLink;
  }
  return "Lien indisponible";
}

function splitDisplayName(displayName) {
  const normalized = getTrimmedString(displayName).replace(/\s+/g, " ");
  if (!normalized) {
    return { firstName: "", lastName: "" };
  }
  const chunks = normalized.split(" ");
  return {
    firstName: chunks[0] || "",
    lastName: chunks.slice(1).join(" "),
  };
}

function buildUserNameParts(userData, fallbackFirstName = "Utilisateur") {
  const firstName = getTrimmedString(userData && userData.first_name);
  const lastName = getTrimmedString(userData && userData.last_name);
  if (firstName || lastName) {
    return {
      firstName: firstName || fallbackFirstName,
      lastName,
    };
  }

  const displayName =
    getTrimmedString(userData && userData.display_name) ||
    getTrimmedString(userData && userData.pseudo);
  const split = splitDisplayName(displayName);
  return {
    firstName: split.firstName || fallbackFirstName,
    lastName: split.lastName,
  };
}

function buildMerchantName(ownerData) {
  const firstName = getTrimmedString(ownerData && ownerData.first_name);
  const lastName = getTrimmedString(ownerData && ownerData.last_name);
  const fromParts = [firstName, lastName].filter((v) => v).join(" ");
  if (fromParts) {
    return fromParts;
  }
  const fromDisplayName =
    getTrimmedString(ownerData && ownerData.display_name) ||
    getTrimmedString(ownerData && ownerData.pseudo);
  return fromDisplayName || "Commerçant";
}

function getSmtpSettings() {
  const smtpConfig = functions.config().smtp || {};
  const host = getTrimmedString(smtpConfig.host);
  const port = Number(smtpConfig.port || 587);
  const secure = toBoolean(smtpConfig.secure, port === 465);
  const user = getTrimmedString(smtpConfig.user);
  const pass = typeof smtpConfig.pass === "string" ? smtpConfig.pass : "";
  const fromEmail = getTrimmedString(smtpConfig.from_email);
  const fromName = getTrimmedString(smtpConfig.from_name);
  const replyTo = getTrimmedString(smtpConfig.reply_to);

  const missing = [];
  if (!host) missing.push("smtp.host");
  if (!Number.isFinite(port) || port <= 0) missing.push("smtp.port");
  if (!user) missing.push("smtp.user");
  if (!pass) missing.push("smtp.pass");
  if (!fromEmail) missing.push("smtp.from_email");
  if (!fromName) missing.push("smtp.from_name");
  if (missing.length > 0) {
    throw new Error(`Missing SMTP config: ${missing.join(", ")}`);
  }

  return {
    host,
    port,
    secure,
    user,
    pass,
    fromEmail,
    fromName,
    replyTo,
  };
}

function createSmtpMailer() {
  const settings = getSmtpSettings();
  const transporter = nodemailer.createTransport({
    host: settings.host,
    port: settings.port,
    secure: settings.secure,
    auth: {
      user: settings.user,
      pass: settings.pass,
    },
  });
  return {
    transporter,
    from: `${settings.fromName} <${settings.fromEmail}>`,
    replyTo: settings.replyTo,
  };
}

async function sendEmailNotification(mailer, to, subject, text) {
  await mailer.transporter.sendMail({
    from: mailer.from,
    to,
    subject,
    text,
    ...(mailer.replyTo ? { replyTo: mailer.replyTo } : {}),
  });
}

function isChannelDone(statusData, sentField, skippedField) {
  return statusData[sentField] === true || statusData[skippedField] === true;
}

function getPrizeNotificationStatusRef(prizeId) {
  return firestore
    .collection(kSystemJobsCollection)
    .doc(kPrizeNotificationsJobDocId)
    .collection(kPrizeNotificationsEntriesCollection)
    .doc(prizeId);
}

async function queuePrizePushNotification({
  docId,
  title,
  body,
  userRefPath,
  createdBy = "system/prize_notifications",
}) {
  const ref = firestore.collection(kPushNotificationsCollection).doc(docId);
  const existing = await ref.get();
  if (existing.exists) {
    return;
  }
  await ref.set({
    notification_title: title,
    notification_text: body,
    notification_image_url: "",
    notification_sound: "",
    parameter_data: "",
    initial_page_name: "",
    target_audience: "All",
    target_user_group: "All",
    user_refs: userRefPath,
    status: "started",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: createdBy,
  });
}

exports.addFcmToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    return "Failed: Unauthenticated calls are not allowed.";
  }
  const userDocPath = data.userDocPath;
  const fcmToken = data.fcmToken;
  const deviceType = data.deviceType;
  if (
    typeof userDocPath === "undefined" ||
    typeof fcmToken === "undefined" ||
    typeof deviceType === "undefined" ||
    userDocPath.split("/").length <= 1 ||
    fcmToken.length === 0 ||
    deviceType.length === 0
  ) {
    return "Invalid arguments encoutered when adding FCM token.";
  }
  if (context.auth.uid != userDocPath.split("/")[1]) {
    return "Failed: Authenticated user doesn't match user provided.";
  }
  const existingTokens = await firestore
    .collectionGroup(kFcmTokensCollection)
    .where("fcm_token", "==", fcmToken)
    .get();
  var userAlreadyHasToken = false;
  for (var doc of existingTokens.docs) {
    const user = doc.ref.parent.parent;
    if (user.path != userDocPath) {
      // Should never have the same FCM token associated with multiple users.
      await doc.ref.delete();
    } else {
      userAlreadyHasToken = true;
    }
  }
  if (userAlreadyHasToken) {
    return "FCM token already exists for this user. Ignoring...";
  }

  // Best-effort: denormalize user role onto the token doc so we can target
  // notifications by role without expensive joins later.
  let userRole = "";
  try {
    const userSnap = await firestore.doc(userDocPath).get();
    userRole = (userSnap.exists && userSnap.data().user_role) || "";
  } catch (e) {
    console.log(`Warning: unable to read user role for ${userDocPath}: ${e}`);
  }

  await getUserFcmTokensCollection(userDocPath).doc().set({
    fcm_token: fcmToken,
    device_type: deviceType,
    user_role: userRole,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  return "Successfully added FCM token!";
});

async function assertIsAdmin(uid) {
  const userSnap = await firestore.doc(`users/${uid}`).get();
  const role = (userSnap.exists && userSnap.data().user_role) || "";
  if (role !== "admin") {
    throw new Error("permission-denied: admin required");
  }
}

function firstNonEmptyString(source, keys) {
  for (const key of keys) {
    const value = getTrimmedString(source && source[key]);
    if (value) {
      return value;
    }
  }
  return "";
}

function normalizeFirstName(value) {
  const normalized = getTrimmedString(value);
  if (!normalized) {
    return "";
  }
  return normalized.split(/\s+/)[0] || "";
}

function extractWinnerRefFromGameData(gameData) {
  const candidates = [
    gameData && gameData.main_prize_winner,
    gameData && gameData.winnerUserRef,
    gameData && gameData.winner_user_ref,
    gameData && gameData.winner_id,
    gameData && gameData.winnerRef,
  ];
  for (const candidate of candidates) {
    const ref = toDocRef(candidate);
    if (ref) {
      return ref;
    }
  }
  return null;
}

function extractWinnerDisplayFromGameData(gameData) {
  const firstName = normalizeFirstName(
    firstNonEmptyString(gameData, [
      "winnerFirstName",
      "winner_first_name",
      "winnerName",
      "winner_name",
      "winner_name_first",
    ]),
  );
  const city = firstNonEmptyString(gameData, [
    "winnerCity",
    "winner_city",
    "winnerVille",
    "winner_ville",
    "winnerTown",
    "winner_town",
  ]);
  return { firstName, city };
}

function extractWinnerDisplayFromUserData(userData) {
  const explicitFirstName = firstNonEmptyString(userData, [
    "first_name",
    "firstName",
  ]);
  const fallbackName = firstNonEmptyString(userData, [
    "display_name",
    "displayName",
    "pseudo",
    "name",
    "winner_name",
  ]);
  const firstName = normalizeFirstName(explicitFirstName || fallbackName);
  const city = firstNonEmptyString(userData, ["city", "ville", "town"]);
  return { firstName, city };
}

exports.backfillWinnerDisplayFields = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    try {
      await assertIsAdmin(context.auth.uid);
    } catch (e) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Admin role required.",
      );
    }

    const dryRun = toBoolean(data && data.dryRun, false);
    const pageSizeInput = Number(data && data.pageSize);
    const maxPagesInput = Number(data && data.maxPages);
    const pageSize = Math.max(
      1,
      Math.min(300, Number.isFinite(pageSizeInput) ? Math.trunc(pageSizeInput) : 200),
    );
    const maxPages = Math.max(
      1,
      Math.min(200, Number.isFinite(maxPagesInput) ? Math.trunc(maxPagesInput) : 10),
    );
    const cursorDocId = getTrimmedString(data && data.cursorDocId);
    const nowMs = Date.now();

    let processedGames = 0;
    let eligibleGames = 0;
    let attemptedUpdates = 0;
    let appliedUpdates = 0;
    let pageCount = 0;
    let hasMore = false;
    let lastDocId = cursorDocId;

    console.log(
      "[backfillWinnerDisplayFields] start",
      JSON.stringify({ dryRun, pageSize, maxPages, cursorDocId }),
    );

    for (let page = 0; page < maxPages; page += 1) {
      let query = firestore
        .collection("games")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);
      if (lastDocId) {
        query = query.startAfter(lastDocId);
      }

      const snap = await query.get();
      if (snap.empty) {
        hasMore = false;
        break;
      }

      pageCount += 1;
      processedGames += snap.size;
      const batch = firestore.batch();
      let pageAppliedUpdates = 0;

      for (const gameDoc of snap.docs) {
        const gameData = gameDoc.data() || {};
        lastDocId = gameDoc.id;

        const winnerRef = extractWinnerRefFromGameData(gameData);
        const hasWinnerSignal = gameData.hasWinner === true || !!winnerRef;
        if (!hasWinnerSignal) {
          continue;
        }

        const endDate = gameData.end_date;
        const endDateMs =
          endDate && typeof endDate.toMillis === "function"
            ? endDate.toMillis()
            : null;
        const isEnded = endDateMs === null || endDateMs <= nowMs;
        if (!isEnded) {
          continue;
        }

        eligibleGames += 1;

        const gameDisplay = extractWinnerDisplayFromGameData(gameData);
        if (gameDisplay.firstName && gameDisplay.city) {
          continue;
        }

        let userDisplay = { firstName: "", city: "" };
        if (winnerRef) {
          const winnerData = await getDocData(winnerRef);
          userDisplay = extractWinnerDisplayFromUserData(winnerData || {});
        }

        const resolvedFirstName = gameDisplay.firstName || userDisplay.firstName;
        const resolvedCity = gameDisplay.city || userDisplay.city;
        const patch = {};

        if (!gameDisplay.firstName && resolvedFirstName) {
          patch.winnerFirstName = resolvedFirstName;
        }
        if (!gameDisplay.city && resolvedCity) {
          patch.winnerCity = resolvedCity;
        }
        if ((resolvedFirstName && resolvedCity) || gameData.winnerDisplayReady === true) {
          patch.winnerDisplayReady = true;
        }

        if (Object.keys(patch).length === 0) {
          continue;
        }

        attemptedUpdates += 1;
        if (!dryRun) {
          batch.update(gameDoc.ref, patch);
          appliedUpdates += 1;
          pageAppliedUpdates += 1;
        }
      }

      if (!dryRun && pageAppliedUpdates > 0) {
        await batch.commit();
      }

      hasMore = snap.size === pageSize;
      console.log(
        "[backfillWinnerDisplayFields] page",
        JSON.stringify({
          page: page + 1,
          pageSize: snap.size,
          processedGames,
          eligibleGames,
          attemptedUpdates,
          appliedUpdates,
          lastDocId,
          dryRun,
        }),
      );

      if (!hasMore) {
        break;
      }
    }

    const result = {
      ok: true,
      dryRun,
      pageSize,
      maxPages,
      pagesProcessed: pageCount,
      processedGames,
      eligibleGames,
      attemptedUpdates,
      appliedUpdates,
      hasMore,
      nextCursorDocId: hasMore ? lastDocId : "",
      serverTimestamp: Date.now(),
    };
    console.log("[backfillWinnerDisplayFields] done", JSON.stringify(result));
    return result;
  });

/**
 * Create a push notification request (stored in ff_push_notifications) that will be sent
 * by sendPushNotificationsTrigger (immediate) or by the scheduled processor (scheduled/repeat).
 *
 * Inputs:
 *  - title, body (required)
 *  - imageUrl (optional)
 *  - targetDevice: "All" | "Android" | "iOS" (optional, default "All")
 *  - targetUserGroup: "All" | "Admins" | "NormalUsers" (optional, default "All")
 *  - userRefs (optional): array of "users/<uid>" to target specific users
 *  - scheduledTimeMs (optional): unix ms for scheduled send
 *  - repeatEveryMinutes (optional): integer minutes
 *  - repeatCount (optional): integer, 0/undefined means infinite
 */
exports.createAdminPushNotification = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);

    const title = (data.title || "").toString().trim();
    const body = (data.body || "").toString().trim();
    const imageUrl = (data.imageUrl || "").toString().trim();
    const targetDevice = (data.targetDevice || "All").toString();
    const targetUserGroup = (data.targetUserGroup || "All").toString();
    const userRefs = Array.isArray(data.userRefs)
      ? data.userRefs.map((s) => (s || "").toString().trim()).filter((s) => s)
      : [];
    const scheduledTimeMs = data.scheduledTimeMs;
    const repeatEveryMinutes = data.repeatEveryMinutes;
    const repeatCount = data.repeatCount;

    if (!title || !body) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "title and body are required",
      );
    }

    const doc = {
      notification_title: title,
      notification_text: body,
      notification_image_url: imageUrl,
      notification_sound: "",
      parameter_data: "",
      initial_page_name: "",
      target_audience: targetDevice, // existing field (device_type)
      target_user_group: targetUserGroup, // new field (role targeting)
      user_refs: userRefs.length ? userRefs.join(",") : "",
      status: "started",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      created_by: `users/${context.auth.uid}`,
      ...(Number.isFinite(repeatEveryMinutes)
        ? { repeat_every_minutes: Number(repeatEveryMinutes) }
        : {}),
      ...(Number.isFinite(repeatCount) ? { repeat_count: Number(repeatCount) } : {}),
    };

    if (Number.isFinite(scheduledTimeMs) && Number(scheduledTimeMs) > 0) {
      doc.scheduled_time = admin.firestore.Timestamp.fromMillis(
        Number(scheduledTimeMs),
      );
      doc.status = "scheduled";
    }

    const ref = await firestore.collection(kPushNotificationsCollection).add(doc);
    return { ok: true, id: ref.id };
  },
);

exports.sendPushNotificationsTrigger = functions
  .runWith(kPushNotificationRuntimeOpts)
  .firestore.document(`${kPushNotificationsCollection}/{id}`)
  .onCreate(async (snapshot, _) => {
    try {
      // Ignore scheduled push notifications on create
      const scheduledTime = snapshot.data().scheduled_time || "";
      if (scheduledTime) {
        return;
      }

      await sendPushNotifications(snapshot);
    } catch (e) {
      console.log(`Error: ${e}`);
      await snapshot.ref.update({ status: "failed", error: `${e}` });
    }
  });

exports.notifyFavoriteMerchantNewGame = functions
  .runWith(kPushNotificationRuntimeOpts)
  .firestore.document("games/{gameId}")
  .onWrite(async (change, context) => {
    const beforeExists = change.before.exists;
    const afterExists = change.after.exists;
    if (!afterExists) {
      return null;
    }

    const beforeData = beforeExists ? change.before.data() || {} : {};
    const afterData = change.after.data() || {};
    const wasPublished = beforeExists ? isPublishedGame(beforeData) : false;
    const isNowPublished = isPublishedGame(afterData);
    if (!isNowPublished || wasPublished) {
      return null;
    }

    try {
      await queueFavoriteMerchantNewGameNotifications(change.after, afterData);
    } catch (error) {
      console.error(
        `[favoriteMerchantNewGame] game=${context.params.gameId} error=${error.message || error}`,
      );
    }
    return null;
  });

async function sendPushNotifications(snapshot) {
  const notificationData = snapshot.data();
  const title = notificationData.notification_title || "";
  const body = notificationData.notification_text || "";
  const imageUrl = notificationData.notification_image_url || "";
  const sound = notificationData.notification_sound || "";
  const parameterData = notificationData.parameter_data || "";
  const targetAudience = notificationData.target_audience || "";
  const targetUserGroup = notificationData.target_user_group || "All";
  const initialPageName = notificationData.initial_page_name || "";
  const userRefsStr = notificationData.user_refs || "";
  const batchIndex = notificationData.batch_index || 0;
  const numBatches = notificationData.num_batches || 0;
  const status = notificationData.status || "";

  if (status !== "" && status !== "started") {
    console.log(`Already processed ${snapshot.ref.path}. Skipping...`);
    return;
  }

  if (title === "" || body === "") {
    await snapshot.ref.update({ status: "failed" });
    return;
  }

  const userRefs = userRefsStr === "" ? [] : userRefsStr.trim().split(",");
  var tokens = new Set();
  const tokenRefsByToken = new Map();
  const rememberTokenRef = (token, ref) => {
    if (!token || !ref) {
      return;
    }
    const existingRefs = tokenRefsByToken.get(token) || [];
    existingRefs.push(ref);
    tokenRefsByToken.set(token, existingRefs);
  };
  if (userRefsStr) {
    for (var userRef of userRefs) {
      const userTokens = await firestore
        .doc(userRef)
        .collection(kFcmTokensCollection)
        .get();
      userTokens.docs.forEach((token) => {
        const data = token.data();
        if (typeof data.fcm_token === "undefined" || !data.fcm_token) return;
        tokens.add(data.fcm_token);
        rememberTokenRef(data.fcm_token, token.ref);
      });
    }
  } else {
    var userTokensQuery = firestore.collectionGroup(kFcmTokensCollection);
    // Handle batched push notifications by splitting tokens up by document
    // id.
    if (numBatches > 0) {
      userTokensQuery = userTokensQuery
        .orderBy(admin.firestore.FieldPath.documentId())
        .startAt(getDocIdBound(batchIndex, numBatches))
        .endBefore(getDocIdBound(batchIndex + 1, numBatches));
    }
    const userTokens = await userTokensQuery.get();
    // Filter by device audience + (optionally) by user role group.
    await Promise.all(
      userTokens.docs.map(async (tokenDoc) => {
        const data = tokenDoc.data();
        const audienceMatches =
          targetAudience === "All" || data.device_type === targetAudience;
        if (!audienceMatches || typeof data.fcm_token === "undefined") return;

        if (!targetUserGroup || targetUserGroup === "All") {
          tokens.add(data.fcm_token);
          rememberTokenRef(data.fcm_token, tokenDoc.ref);
          return;
        }

        let role = data.user_role || "";
        if (!role) {
          // Backward compatibility: older token docs may not have user_role.
          try {
            const userRef = tokenDoc.ref.parent.parent;
            const userSnap = await userRef.get();
            role = (userSnap.exists && userSnap.data().user_role) || "";
          } catch (_) {
            role = "";
          }
        }

        const isAdmin = role === "admin";
        const isProfessional = role === "commercant";
        const roleMatches =
          targetUserGroup === "Admins"
            ? isAdmin
            : targetUserGroup === "Professionals"
              ? isProfessional
              : targetUserGroup === "NormalUsers"
                ? !isAdmin
                : true;
        if (roleMatches) {
          tokens.add(data.fcm_token);
          rememberTokenRef(data.fcm_token, tokenDoc.ref);
        }
      }),
    );
  }

  const tokensArr = Array.from(tokens);
  console.log(
    `Preparing push notification ${snapshot.id}: tokens=${tokensArr.length}, ` +
      `audience=${targetAudience}, group=${targetUserGroup}, ` +
      `userRefs=${userRefsStr ? userRefs.length : 0}`,
  );
  if (tokensArr.length === 0) {
    await snapshot.ref.update({
      status: "failed",
      error: "no_tokens",
      num_sent: 0,
    });
    return;
  }
  var messageBatches = [];
  for (let i = 0; i < tokensArr.length; i += 500) {
    const tokensBatch = tokensArr.slice(i, Math.min(i + 500, tokensArr.length));
    const messages = {
      notification: {
        title,
        body,
        ...(imageUrl && { imageUrl: imageUrl }),
      },
      data: {
        initialPageName,
        parameterData,
      },
      android: {
        notification: {
          ...(sound && { sound: sound }),
        },
      },
      apns: {
        payload: {
          aps: {
            ...(sound && { sound: sound }),
          },
        },
      },
      tokens: tokensBatch,
    };
    messageBatches.push(messages);
  }

  var numSent = 0;
  let invalidTokensDeleted = 0;
  await Promise.all(
    messageBatches.map(async (messages) => {
      const response = await admin.messaging().sendEachForMulticast(messages);
      numSent += response.successCount;
      if (response.failureCount > 0) {
        const errorCodes = response.responses
          .filter((r) => !r.success)
          .map((r) => r.error && r.error.code)
          .filter((code) => !!code);
        if (errorCodes.length) {
          console.log(
            `Push send errors for ${snapshot.id}: ${errorCodes
              .slice(0, 10)
              .join(", ")}`,
          );
        }
        invalidTokensDeleted += await cleanupInvalidFcmTokens(
          tokenRefsByToken,
          response.responses,
          messages.tokens,
        );
      }
    }),
  );

  await snapshot.ref.update({
    status: "succeeded",
    num_sent: numSent,
    invalid_tokens_deleted: invalidTokensDeleted,
  });
}

exports.notifyPrizeWon = functions
  .runWith(kPushNotificationRuntimeOpts)
  .firestore.document("prizes/{prizeId}")
  .onCreate(async (snapshot, context) => {
    const prizeId = context.params.prizeId;
    const statusRef = getPrizeNotificationStatusRef(prizeId);
    const statusSnap = await statusRef.get();
    const statusData = statusSnap.exists ? statusSnap.data() || {} : {};

    const playerEmailDone = isChannelDone(
      statusData,
      "player_email_sent",
      "player_email_skipped",
    );
    const merchantEmailDone = isChannelDone(
      statusData,
      "merchant_email_sent",
      "merchant_email_skipped",
    );
    const playerPushDone = isChannelDone(
      statusData,
      "player_push_queued",
      "player_push_skipped",
    );
    const merchantPushDone = isChannelDone(
      statusData,
      "merchant_push_queued",
      "merchant_push_skipped",
    );

    if (playerEmailDone && merchantEmailDone && playerPushDone && merchantPushDone) {
      return null;
    }

    const prizeData = snapshot.data() || {};
    const winnerRef = toDocRef(prizeData.winner_id);
    const gameRef = toDocRef(prizeData.game_id);
    let ownerRef = toDocRef(prizeData.owner_id);
    let enseigneRef = toDocRef(prizeData.enseigne_id);

    const [winnerDataRaw, gameDataRaw, ownerDataFirst, enseigneDataFirst] =
      await Promise.all([
        getDocData(winnerRef),
        getDocData(gameRef),
        getDocData(ownerRef),
        getDocData(enseigneRef),
      ]);

    const gameData = gameDataRaw || {};
    if (!ownerRef && gameData.create_by) {
      ownerRef = toDocRef(gameData.create_by);
    }
    if (!enseigneRef && gameData.enseigne_id) {
      enseigneRef = toDocRef(gameData.enseigne_id);
    }

    const [ownerDataRaw, enseigneDataRaw] = await Promise.all([
      ownerDataFirst || getDocData(ownerRef),
      enseigneDataFirst || getDocData(enseigneRef),
    ]);

    const winnerData = winnerDataRaw || {};
    const enseigneData = enseigneDataRaw || {};

    if (!ownerRef && enseigneData.owner) {
      ownerRef = toDocRef(enseigneData.owner);
    }

    let ownerData = ownerDataRaw || {};
    if ((!ownerDataRaw || Object.keys(ownerDataRaw).length === 0) && ownerRef) {
      ownerData = (await getDocData(ownerRef)) || {};
    }

    const winnerName = buildUserNameParts(winnerData, "Joueur");
    const winnerFirstName = winnerName.firstName || "Joueur";
    const winnerLastName = winnerName.lastName || "";
    const winnerFullName = [winnerFirstName, winnerLastName]
      .filter((v) => v)
      .join(" ");
    const winnerCity = getTrimmedString(winnerData.city) || "ville inconnue";
    const merchantName = buildMerchantName(ownerData);
    const gameName = getTrimmedString(gameData.name) || "Jeu ProxiPlay";
    const prizeName = getTrimmedString(prizeData.name) || "Lot gagné";
    const claimCode = getTrimmedString(prizeData.claim_code) || "N/A";
    const shopName =
      getTrimmedString(prizeData.enseigne_name) ||
      getTrimmedString(enseigneData.name) ||
      "votre enseigne";
    const shopLink = buildShopLink(enseigneData);

    const merchantEmailSubject = `Un gagnant pour votre jeu "${gameName}"`;
    const merchantEmailBody = [
      `Bonjour ${merchantName},`,
      `${winnerFirstName} de ${winnerCity} a remporté ${prizeName} sur ProxiPlay :`,
      `Code à vérifier : ${claimCode}`,
      "Le gagnant devra présenter ce code en boutique pour validation.",
      "Merci de participer à la dynamisation du commerce local !",
      "L’équipe ProxiPlay",
    ].join("\n");

    const playerEmailSubject = `Bravo ${winnerFirstName}, vous avez gagné !`;
    const playerEmailBody = [
      `Bonjour ${winnerFirstName},`,
      `Félicitations, vous avez remporté ${prizeName} offert par ${shopName}`,
      `Votre code à présenter en boutique : ${claimCode}`,
      `Retrouvez la boutique ici : ${shopLink}`,
      "Continuez à jouer chaque jour pour multiplier vos chances !",
      "À très vite sur ProxiPlay",
    ].join("\n");

    const playerPushTitle = "Vous avez gagné !";
    const playerPushBody = `Vous avez gagné ${prizeName} chez ${shopName}\nCode : ${claimCode}`;
    const merchantPushTitle = "Nouveau gagnant";
    const merchantPushBody =
      `${winnerFullName} de (${winnerCity}) a gagné ${prizeName}\n` +
      `Code : ${claimCode}`;

    const updates = {
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      ...(statusSnap.exists
        ? {}
        : { created_at: admin.firestore.FieldValue.serverTimestamp() }),
    };
    const errors = [];
    let mailer = null;
    const getMailer = () => {
      if (!mailer) {
        mailer = createSmtpMailer();
      }
      return mailer;
    };

    if (!playerEmailDone) {
      const playerEmail = await resolveUserEmail(winnerRef, winnerData);
      if (!playerEmail) {
        updates.player_email_skipped = true;
        updates.player_email_skip_reason = "missing_player_email";
      } else {
        try {
          await sendEmailNotification(
            getMailer(),
            playerEmail,
            playerEmailSubject,
            playerEmailBody,
          );
          updates.player_email_sent = true;
          updates.player_email_skipped = admin.firestore.FieldValue.delete();
          updates.player_email_skip_reason = admin.firestore.FieldValue.delete();
        } catch (e) {
          errors.push(`player_email: ${e.message || e}`);
          updates.player_email_sent = false;
        }
      }
    }

    if (!merchantEmailDone) {
      const merchantEmail = await resolveUserEmail(ownerRef, ownerData);
      if (!merchantEmail) {
        updates.merchant_email_skipped = true;
        updates.merchant_email_skip_reason = "missing_merchant_email";
      } else {
        try {
          await sendEmailNotification(
            getMailer(),
            merchantEmail,
            merchantEmailSubject,
            merchantEmailBody,
          );
          updates.merchant_email_sent = true;
          updates.merchant_email_skipped = admin.firestore.FieldValue.delete();
          updates.merchant_email_skip_reason = admin.firestore.FieldValue.delete();
        } catch (e) {
          errors.push(`merchant_email: ${e.message || e}`);
          updates.merchant_email_sent = false;
        }
      }
    }

    if (!playerPushDone) {
      const winnerRefPath = winnerRef && winnerRef.path ? winnerRef.path : "";
      if (!winnerRefPath) {
        updates.player_push_skipped = true;
        updates.player_push_skip_reason = "missing_winner_ref";
      } else {
        try {
          await queuePrizePushNotification({
            docId: `prize_${prizeId}_player_push`,
            title: playerPushTitle,
            body: playerPushBody,
            userRefPath: winnerRefPath,
          });
          updates.player_push_queued = true;
          updates.player_push_skipped = admin.firestore.FieldValue.delete();
          updates.player_push_skip_reason = admin.firestore.FieldValue.delete();
        } catch (e) {
          errors.push(`player_push: ${e.message || e}`);
          updates.player_push_queued = false;
        }
      }
    }

    if (!merchantPushDone) {
      const ownerRefPath = ownerRef && ownerRef.path ? ownerRef.path : "";
      if (!ownerRefPath) {
        updates.merchant_push_skipped = true;
        updates.merchant_push_skip_reason = "missing_owner_ref";
      } else {
        try {
          await queuePrizePushNotification({
            docId: `prize_${prizeId}_merchant_push`,
            title: merchantPushTitle,
            body: merchantPushBody,
            userRefPath: ownerRefPath,
          });
          updates.merchant_push_queued = true;
          updates.merchant_push_skipped = admin.firestore.FieldValue.delete();
          updates.merchant_push_skip_reason = admin.firestore.FieldValue.delete();
        } catch (e) {
          errors.push(`merchant_push: ${e.message || e}`);
          updates.merchant_push_queued = false;
        }
      }
    }

    updates.last_error =
      errors.length > 0
        ? errors.join(" | ")
        : admin.firestore.FieldValue.delete();
    await statusRef.set(updates, { merge: true });

    if (errors.length > 0) {
      throw new Error(
        `notifyPrizeWon partial failure for ${prizeId}: ${errors.join(" | ")}`,
      );
    }
    return null;
  });

/**
 * Scheduled processing for push notifications:
 * - finds documents in ff_push_notifications with scheduled_time <= now and status == "scheduled"
 * - sends them, then marks succeeded, or reschedules if repeat_every_minutes is set.
 *
 * NOTE: Requires deployment. Runs every minute.
 */
exports.processScheduledPushNotifications = functions
  .runWith(kPushNotificationRuntimeOpts)
  .pubsub.schedule("every 1 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await firestore
      .collection(kPushNotificationsCollection)
      .where("status", "==", "scheduled")
      .where("scheduled_time", "<=", now)
      .limit(20)
      .get();

    await Promise.all(
      snap.docs.map(async (doc) => {
        try {
          await sendPushNotifications(doc);
          const data = doc.data();
          const repeatEvery = Number(data.repeat_every_minutes || 0);
          let repeatCount = Number(data.repeat_count || 0);
          if (repeatEvery > 0) {
            // 0/undefined = infinite repeats
            if (repeatCount > 0) {
              repeatCount -= 1;
            }
            if (repeatCount === 0 && Number(data.repeat_count || 0) > 0) {
              // finished
              return;
            }
            const nextTime = admin.firestore.Timestamp.fromMillis(
              Date.now() + repeatEvery * 60 * 1000,
            );
            await doc.ref.update({
              status: "scheduled",
              scheduled_time: nextTime,
              ...(Number(data.repeat_count || 0) > 0 ? { repeat_count: repeatCount } : {}),
            });
          }
        } catch (e) {
          console.log(`Error processing scheduled notification ${doc.id}: ${e}`);
          await doc.ref.update({ status: "failed", error: `${e}` });
        }
      }),
    );
  });

exports.notifyFollowedGamesEndingSoon = functions
  .runWith(kPushNotificationRuntimeOpts)
  .pubsub.schedule("0 9 * * *")
  .timeZone(kParisTimeZone)
  .onRun(async () => {
    const now = new Date();
    const { start, end } = getTimeZoneDayBounds(now, kParisTimeZone, 3);
    const startTimestamp = admin.firestore.Timestamp.fromDate(start);
    const endTimestamp = admin.firestore.Timestamp.fromDate(end);

    console.log(
      `[followedGameEndingSoon] start windowStart=${start.toISOString()} windowEnd=${end.toISOString()}`,
    );

    const gamesSnap = await firestore
      .collection("games")
      .where("end_date", ">=", startTimestamp)
      .where("end_date", "<", endTimestamp)
      .get();

    let processed = 0;
    let skippedUnpublished = 0;
    for (const gameDoc of gamesSnap.docs) {
      const gameData = gameDoc.data() || {};
      if (!isPublishedGame(gameData)) {
        skippedUnpublished += 1;
        continue;
      }
      processed += 1;
      try {
        await queueFollowedGameEndingSoonNotifications(gameDoc);
      } catch (error) {
        console.error(
          `[followedGameEndingSoon] game=${gameDoc.id} error=${error.message || error}`,
        );
      }
    }

    console.log(
      `[followedGameEndingSoon] completed matched=${gamesSnap.size} processed=${processed} skippedUnpublished=${skippedUnpublished}`,
    );
    return null;
  });

// Automatically select a main prize winner after game end.
// Runs hourly to avoid load; processes completed games and enforces
// "no main prize => no main-prize winner" consistency.
exports.pickMainPrizeWinners = functions.pubsub
  .schedule("every 60 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const [gamesSnap, gamesWithWinnerSnap] = await Promise.all([
      firestore
        .collection("games")
        .where("hasWinner", "==", false)
        .where("end_date", "<=", now)
        .limit(20)
        .get(),
      firestore
        .collection("games")
        .where("hasWinner", "==", true)
        .where("end_date", "<=", now)
        .limit(20)
        .get(),
    ]);

    const cleanupPromises = [];
    for (const gameDoc of [...gamesSnap.docs, ...gamesWithWinnerSnap.docs]) {
      const gameData = gameDoc.data();
      const hasMainPrize = resolveHasMainPrize(gameData);
      const hasMainPrizeField = hasHasMainPrizeField(gameData);
      const hasInvalidWinnerState =
        gameData.hasWinner === true || !!gameData.main_prize_winner;
      const cleanupPatch = {};

      if (!hasMainPrizeField) {
        cleanupPatch.hasMainPrize = hasMainPrize;
      }
      if (!hasMainPrize && hasInvalidWinnerState) {
        cleanupPatch.hasWinner = false;
        cleanupPatch.main_prize_winner = null;
      }

      if (Object.keys(cleanupPatch).length > 0) {
        cleanupPromises.push(gameDoc.ref.update(cleanupPatch));
      }
    }

    if (cleanupPromises.length > 0) {
      await Promise.all(cleanupPromises);
    }

    if (gamesSnap.empty) {
      return null;
    }

    await Promise.all(
      gamesSnap.docs.map(async (gameDoc) => {
        const gameData = gameDoc.data();
        const hasMainPrize = resolveHasMainPrize(gameData);

        if (!hasMainPrize || gameData.main_prize_winner) {
          return null;
        }

        const participantsSnap = await gameDoc.ref
          .collection("participants")
          .get();

        if (participantsSnap.empty) {
          return null;
        }

        const participants = participantsSnap.docs;
        const winnerDoc =
          participants[Math.floor(Math.random() * participants.length)];
        const winnerRef = winnerDoc.data().user_id;

        if (!winnerRef) {
          return null;
        }

        const prizeRef = firestore.collection("prizes").doc();
        const claimCode = `${Date.now().toString(36).toUpperCase()}`;
        const ownerRef = gameData.create_by
          ? firestore.doc(gameData.create_by.path)
          : null;
        const enseigneRef = gameData.enseigne_id
          ? firestore.doc(gameData.enseigne_id.path)
          : null;

        await firestore.runTransaction(async (transaction) => {
          const freshGameDoc = await transaction.get(gameDoc.ref);
          if (!freshGameDoc.exists) {
            return;
          }
          const freshGameData = freshGameDoc.data();
          const freshHasMainPrize = resolveHasMainPrize(freshGameData);
          const freshHasMainPrizeField = hasHasMainPrizeField(freshGameData);
          const freshHasInvalidWinnerState =
            freshGameData.hasWinner === true || !!freshGameData.main_prize_winner;
          const freshPatch = {};

          if (!freshHasMainPrizeField) {
            freshPatch.hasMainPrize = freshHasMainPrize;
          }

          if (!freshHasMainPrize) {
            if (freshHasInvalidWinnerState) {
              freshPatch.hasWinner = false;
              freshPatch.main_prize_winner = null;
            }
            if (Object.keys(freshPatch).length > 0) {
              transaction.update(gameDoc.ref, freshPatch);
            }
            return;
          }

          if (Object.keys(freshPatch).length > 0) {
            transaction.update(gameDoc.ref, freshPatch);
          }

          if (freshGameData.hasWinner || freshGameData.main_prize_winner) {
            return;
          }

          transaction.update(gameDoc.ref, {
            hasWinner: true,
            main_prize_winner: winnerRef,
          });

          transaction.set(prizeRef, {
            prize_type: "principal",
            name: gameData.name || "Lot principal",
            description: gameData.description || "",
            winner_id: winnerRef,
            game_id: gameDoc.ref,
            enseigne_id: enseigneRef,
            enseigne_name: gameData.enseigne_name || "",
            owner_id: ownerRef,
            claim_code: claimCode,
            claimed: false,
            win_date: admin.firestore.FieldValue.serverTimestamp(),
          });

          const userLotRef = winnerRef
            .collection("my_lots")
            .doc(prizeRef.id);
          transaction.set(userLotRef, {
            prize_id: prizeRef,
          });
        });

        return null;
      }),
    );

    return null;
  });

// One-way migration job:
// progressively backfills `hasMainPrize` on existing games and cleans
// invalid winner state on games without a main prize.
exports.backfillGamesHasMainPrize = functions.pubsub
  .schedule("every 30 minutes")
  .onRun(async () => {
    const stateRef = firestore
      .collection(kSystemJobsCollection)
      .doc(kMainPrizeBackfillDocId);
    const stateSnap = await stateRef.get();
    const state = stateSnap.exists ? stateSnap.data() : {};

    if (state.completed === true) {
      return null;
    }

    let query = firestore
      .collection("games")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(300);

    if (typeof state.lastDocId === "string" && state.lastDocId.length > 0) {
      query = query.startAfter(state.lastDocId);
    }

    const gamesSnap = await query.get();

    if (gamesSnap.empty) {
      await stateRef.set(
        {
          completed: true,
          completed_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return null;
    }

    const batch = firestore.batch();
    let updatedCount = 0;

    for (const gameDoc of gamesSnap.docs) {
      const gameData = gameDoc.data();
      const hasMainPrize = resolveHasMainPrize(gameData);
      const hasMainPrizeField = hasHasMainPrizeField(gameData);
      const hasInvalidWinnerState =
        !hasMainPrize &&
        (gameData.hasWinner === true || !!gameData.main_prize_winner);
      const patch = {};

      if (!hasMainPrizeField) {
        patch.hasMainPrize = hasMainPrize;
      }
      if (hasInvalidWinnerState) {
        patch.hasWinner = false;
        patch.main_prize_winner = null;
      }

      if (Object.keys(patch).length > 0) {
        batch.update(gameDoc.ref, patch);
        updatedCount += 1;
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
    }

    await stateRef.set(
      {
        completed: false,
        lastDocId: gamesSnap.docs[gamesSnap.docs.length - 1].id,
        processed_count: admin.firestore.FieldValue.increment(gamesSnap.size),
        updated_count: admin.firestore.FieldValue.increment(updatedCount),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return null;
  });

function getUserFcmTokensCollection(userDocPath) {
  return firestore.doc(userDocPath).collection(kFcmTokensCollection);
}

function getDocIdBound(index, numBatches) {
  if (index <= 0) {
    return "users/(";
  }
  if (index >= numBatches) {
    return "users/}";
  }
  const numUidChars = 62;
  const twoCharOptions = Math.pow(numUidChars, 2);

  var twoCharIdx = (index * twoCharOptions) / numBatches;
  var firstCharIdx = Math.floor(twoCharIdx / numUidChars);
  var secondCharIdx = Math.floor(twoCharIdx % numUidChars);
  const firstChar = getCharForIndex(firstCharIdx);
  const secondChar = getCharForIndex(secondCharIdx);
  return "users/" + firstChar + secondChar;
}

function getCharForIndex(charIdx) {
  if (charIdx < 10) {
    return String.fromCharCode(charIdx + "0".charCodeAt(0));
  } else if (charIdx < 36) {
    return String.fromCharCode("A".charCodeAt(0) + charIdx - 10);
  } else {
    return String.fromCharCode("a".charCodeAt(0) + charIdx - 36);
  }
}
exports.onUserDeleted = functions.auth.user().onDelete(async (user) => {
  let firestore = admin.firestore();
  let userRef = firestore.doc("users/" + user.uid);
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        await doc.ref
          .collection("enseigne_game")
          .get()
          .then(async (q) => {
            for (var d of q.docs) {
              console.log(
                `Deleting document ${d.id} from collection enseigne_game`,
              );
              await d.ref.delete();
            }
          });
      }
    });
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        await doc.ref
          .collection("horaires")
          .get()
          .then(async (q) => {
            for (var d of q.docs) {
              console.log(`Deleting document ${d.id} from collection horaires`);
              await d.ref.delete();
            }
          });
      }
    });
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        await doc.ref
          .collection("images")
          .get()
          .then(async (q) => {
            for (var d of q.docs) {
              console.log(`Deleting document ${d.id} from collection images`);
              await d.ref.delete();
            }
          });
      }
    });
  await firestore.collection("users").doc(user.uid).delete();
  await firestore
    .collection("enseignes")
    .where("owner", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        console.log(`Deleting document ${doc.id} from collection enseignes`);
        await doc.ref.delete();
      }
    });
  await firestore
    .collection("games")
    .where("create_by", "==", userRef)
    .get()
    .then(async (querySnapshot) => {
      for (var doc of querySnapshot.docs) {
        console.log(`Deleting document ${doc.id} from collection games`);
        await doc.ref.delete();
      }
    });
});

try {
  Object.assign(exports, require("./lib/share_promo"));
} catch (error) {
  console.log("share_promo TypeScript bundle not loaded yet:", error.message);
}

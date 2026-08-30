const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const nodemailer = require("nodemailer");
const {isFunctionsEmulator} = require("./lib/emulator_runtime");
admin.initializeApp();
const participateInGameTransaction = require("./participate_in_game_transaction.js");
const {
  expandSecondaryPrizes,
  planInstantWinnerReconciliation,
  toMillis,
} = require("./lib/instant_winners_core");
const {sendTextEmail} = require("./lib/notifications/email_sender");
const {
  queuePushNotificationRequest,
} = require("./push_notification_request.js");
const {
  getMonthlyChallengeStateCallable,
  getMonthlyChallengesStateCallable,
  adminGetMonthlyChallengeConfigCallable,
  adminUpsertMonthlyChallengeCallable,
  adminGetMonthlyChallengeStatsCallable,
  adminRunMonthlyChallengeDrawCallable,
  drawMonthlyChallengeWinnerScheduled,
} = require("./monthly_challenge");

const kFcmTokensCollection = "fcm_tokens";
const kPushNotificationsCollection = "ff_push_notifications";
const firestore = admin.firestore();
const kSystemJobsCollection = "_system_jobs";
const kMainPrizeBackfillDocId = "games_has_main_prize_backfill";
const kPrizeNotificationsJobDocId = "prize_notifications";
const kPrizeNotificationsEntriesCollection = "entries";
const kDailyPartsResetBatchSize = 450;
const kParisTimeZone = "Europe/Paris";
const kFunctionsRegion = "us-central1";
const kGameDedupeWindowMs = 20 * 1000;
const kGameDedupeGroupsCollection = "_game_dedupe_groups";
const kGameDedupeReviewsCollection = "_game_dedupe_reviews";
const kGlobalStatsDocPath = "stats/global";
const kInvalidFcmErrorCodes = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

const kPushNotificationRuntimeOpts = {
  timeoutSeconds: 540,
  memory: "2GB",
};

function logHasWinnerWrite({
  gameId,
  previousValue,
  newValue,
  sourceFunction,
  winnerType,
  hasMainPrize,
  endDate,
}) {
  console.log("[HAS_WINNER WRITE]", {
    gameId,
    previousValue,
    newValue,
    sourceFunction,
    winnerType,
    hasMainPrize,
    endDate,
    now: new Date().toISOString(),
  });
}

exports.participateInGameTransaction =
  participateInGameTransaction.participateInGameTransaction;

const generateInstantWinnersForGameCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }

    const gameId = getTrimmedString(data && data.gameId);
    if (!gameId || gameId.includes("/")) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid gameId is required.",
      );
    }

    const gameRef = firestore.collection("games").doc(gameId);
    const gameSnap = await gameRef.get();
    if (!gameSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Game not found.");
    }

    const gameData = gameSnap.data() || {};
    const callerRef = firestore.collection("users").doc(context.auth.uid);
    const isCallerAdmin = (await callerRef.get()).data()?.user_role === "admin";
    const createByRef = toDocRef(gameData.create_by);
    const ownerRef = createByRef || toDocRef(gameData.owner_id);

    if (
      !isCallerAdmin &&
      (!ownerRef || ownerRef.path !== callerRef.path)
    ) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the game owner can generate instant winners.",
      );
    }

    const startDateMs = toMillis(gameData.start_date);
    const endDateMs = toMillis(gameData.end_date);
    const expandedSecondaryPrizes = expandSecondaryPrizes(gameData.secondary_prizes);

    if (expandedSecondaryPrizes.length === 0) {
      return {
        ok: true,
        gameId,
        status: "skip_no_secondary_prizes",
        createdCount: 0,
        desiredCount: 0,
      };
    }

    const instantWinnersRef = gameRef.collection("instant_winners");
    try {
      planInstantWinnerReconciliation({
        gameId,
        startDateMs,
        endDateMs,
        secondaryPrizes: gameData.secondary_prizes,
        existingEntries: [],
      });
    } catch (error) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        error.message || "Unable to generate instant winners.",
      );
    }

    const gameAlreadyStarted = nowMs >= startDateMs;
    const transactionResult = await firestore.runTransaction(async (transaction) => {
      const [freshGameSnap, existingSnap] = await Promise.all([
        transaction.get(gameRef),
        transaction.get(instantWinnersRef),
      ]);

      if (!freshGameSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Game not found.");
      }

      const freshGameData = freshGameSnap.data() || {};
      const freshPlan = planInstantWinnerReconciliation({
        gameId,
        startDateMs: toMillis(freshGameData.start_date),
        endDateMs: toMillis(freshGameData.end_date),
        secondaryPrizes: freshGameData.secondary_prizes,
        existingEntries: existingSnap.docs.map((doc) => ({
          id: doc.id,
          ...doc.data(),
        })),
      });
      const hasAssignedInstantWinner = existingSnap.docs.some((doc) => {
        const data = doc.data() || {};
        return data.hasWinner === true || !!data.player_id;
      });
      const freshStartDateMs = toMillis(freshGameData.start_date);
      const freshGameAlreadyStarted =
        Number.isFinite(freshStartDateMs) && Date.now() >= freshStartDateMs;

      if (freshGameAlreadyStarted && freshPlan.missingPayloads.length > 0) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Instant winners cannot be completed after the game start.",
        );
      }

      if (hasAssignedInstantWinner && freshPlan.missingPayloads.length > 0) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Instant winners cannot be changed after a secondary prize has been assigned.",
        );
      }

      freshPlan.missingPayloads.forEach(({docId, payload}) => {
        logHasWinnerWrite({
          gameId,
          previousValue: null,
          newValue: false,
          sourceFunction: "generateInstantWinnersForGame",
          winnerType: "gain-instantane",
          hasMainPrize: resolveHasMainPrize(freshGameData),
          endDate:
            freshGameData.end_date?.toDate?.()?.toISOString?.() ||
            freshGameData.end_date ||
            null,
        });
        transaction.create(instantWinnersRef.doc(docId), {
          date: admin.firestore.Timestamp.fromMillis(payload.dateMs),
          hasWinner: false,
          claimed: false,
          secondary_prize_index: payload.secondary_prize_index,
          secondary_prize_occurrence_index:
            payload.secondary_prize_occurrence_index,
          secondary_prize_name: payload.secondary_prize_name,
          ...(payload.secondary_prize_presentation
            ? {
                secondary_prize_presentation:
                  payload.secondary_prize_presentation,
              }
            : {}),
        });
      });

      // Un jeu duplique (bug de creation) puis nettoye peut avoir des lots
      // instant_winners generes avec l'ancienne description du jeu d'origine.
      // On rattrape ici le texte des occurrences pas encore gagnees pour
      // qu'il suive la description actuelle du jeu.
      freshPlan.staleTextEntries.forEach(({docId, patch}) => {
        transaction.update(instantWinnersRef.doc(docId), patch);
      });

      return {
        desiredCount: freshPlan.desiredCount,
        existingCount: freshPlan.existingCount,
        createdCount: freshPlan.missingPayloads.length,
        refreshedTextCount: freshPlan.staleTextEntries.length,
        duplicateExistingKeys: freshPlan.duplicateExistingKeys,
        unexpectedExistingCount: freshPlan.unexpectedExistingEntries.length,
        hasAssignedInstantWinner,
      };
    });

    return {
      ok: true,
      gameId,
      status:
        transactionResult.createdCount > 0
          ? transactionResult.existingCount > 0
            ? "completed_missing_occurrences"
            : "created"
          : transactionResult.refreshedTextCount > 0
            ? "refreshed_stale_text"
            : "already_complete",
      createdCount: transactionResult.createdCount,
      refreshedTextCount: transactionResult.refreshedTextCount,
      desiredCount: transactionResult.desiredCount,
      existingCount: transactionResult.existingCount,
      duplicateExistingKeys: transactionResult.duplicateExistingKeys,
      unexpectedExistingCount: transactionResult.unexpectedExistingCount,
      hasAssignedInstantWinner: transactionResult.hasAssignedInstantWinner,
      idStrategy:
        "instant_{gameId}_spi_{secondary_prize_index}_occ_{secondary_prize_occurrence_index}",
    };
  });

// Renvoie nom/ville/email/telephone du gagnant d'un lot au commercant
// proprietaire (ou a un admin) uniquement, verifie cote serveur. Permet aux
// ecrans de validation de lot commercant de ne plus jamais lire directement
// le document users/{winner_id} d'un autre utilisateur.
const getPrizeWinnerContactForMerchantCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }

    const prizeId = getTrimmedString(data && data.prizeId);
    if (!prizeId || prizeId.includes("/")) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid prizeId is required.",
      );
    }

    const prizeRef = firestore.collection("prizes").doc(prizeId);
    const prizeSnap = await prizeRef.get();
    if (!prizeSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Prize not found.");
    }
    const prizeData = prizeSnap.data() || {};

    const callerRef = firestore.collection("users").doc(context.auth.uid);
    const isCallerAdmin =
      (await callerRef.get()).data()?.user_role === "admin";

    const enseigneRef = toDocRef(prizeData.enseigne_id);
    const enseigneData = enseigneRef
      ? (await getDocData(enseigneRef)) || {}
      : {};
    const enseigneOwnerRef = toDocRef(enseigneData.owner);
    const prizeOwnerRef = toDocRef(prizeData.owner_id);

    const isOwner =
      (enseigneOwnerRef && enseigneOwnerRef.path === callerRef.path) ||
      (prizeOwnerRef && prizeOwnerRef.path === callerRef.path);

    if (!isCallerAdmin && !isOwner) {
      console.error("[GET_PRIZE_WINNER_CONTACT_BLOCKED]", {
        prizeId,
        callerUid: context.auth.uid,
      });
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the merchant owning this prize can view the winner's contact info.",
      );
    }

    const winnerRef = toDocRef(prizeData.winner_id);
    if (!winnerRef) {
      throw new functions.https.HttpsError(
        "not-found",
        "No winner recorded for this prize.",
      );
    }
    const winnerData = (await getDocData(winnerRef)) || {};

    console.log("[GET_PRIZE_WINNER_CONTACT_OK]", {
      prizeId,
      callerUid: context.auth.uid,
    });

    return {
      firstName: getTrimmedString(
        winnerData.first_name || winnerData.firstName,
      ),
      lastName: getTrimmedString(winnerData.last_name || winnerData.lastName),
      city: getTrimmedString(winnerData.city),
      email: getTrimmedString(winnerData.email),
      phoneNumber: getTrimmedString(
        winnerData.phone_number || winnerData.phoneNumber,
      ),
    };
  });

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

// Windows-1252 byte -> Unicode codepoint mapping for 0x80-0x9F (the range
// where it differs from plain Latin-1). Used to undo "UTF-8 saved as
// windows-1252" mojibake in Firestore-sourced text (names, enseigne/game
// titles, etc.) before it lands in outgoing emails.
const kCp1252HighBytes = {
  0x80: 0x20ac, 0x82: 0x201a, 0x83: 0x0192, 0x84: 0x201e, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02c6, 0x89: 0x2030, 0x8a: 0x0160,
  0x8b: 0x2039, 0x8c: 0x0152, 0x8e: 0x017d, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201c, 0x94: 0x201d, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02dc, 0x99: 0x2122, 0x9a: 0x0161, 0x9b: 0x203a, 0x9c: 0x0153,
  0x9e: 0x017e, 0x9f: 0x0178,
};
const kCp1252Reverse = new Map();
for (const [byteHex, codepoint] of Object.entries(kCp1252HighBytes)) {
  kCp1252Reverse.set(String.fromCodePoint(codepoint), Number(byteHex));
}

function mojibakeCharToByte(ch) {
  const code = ch.codePointAt(0);
  if (code <= 0x7f || (code >= 0xa0 && code <= 0xff)) return code;
  if (kCp1252Reverse.has(ch)) return kCp1252Reverse.get(ch);
  return -1;
}

// Undoes one layer of "this text was UTF-8, mis-decoded as windows-1252"
// corruption. Returns null if the input isn't representable as raw bytes
// this way, or if re-encoding the result doesn't reproduce those exact
// bytes -- i.e. it wasn't actually mojibake, so the caller should leave it
// untouched rather than risk corrupting already-correct text.
function undoOneMojibakeLayer(s) {
  const bytes = [];
  for (const ch of s) {
    const b = mojibakeCharToByte(ch);
    if (b === -1) return null;
    bytes.push(b);
  }
  const buf = Buffer.from(bytes);
  const decoded = buf.toString("utf8");
  if (!Buffer.from(decoded, "utf8").equals(buf)) return null;
  return decoded;
}

const kMojibakeRun = new RegExp(
  "[\\u0080-\\u00FF\\u0152\\u0153\\u0160\\u0161\\u0178\\u017D\\u017E" +
    "\\u0192\\u02C6\\u02DC\\u2013\\u2014\\u2018\\u2019\\u201A\\u201C" +
    "\\u201D\\u201E\\u2020-\\u2022\\u2026\\u2030\\u2039\\u203A\\u2122]+",
  "g",
);

// Best-effort repair of mojibake-corrupted French text pulled from
// Firestore (user/enseigne/game names) before it's used in an email.
// Leaves already-correct text untouched; unwinds up to a few layers of
// corruption for strings that went through the bad encode/decode cycle
// more than once.
function repairMojibakeText(value) {
  const source = typeof value === "string" ? value : "";
  if (!source) return source;
  return source.replace(kMojibakeRun, (run) => {
    let best = run;
    let current = run;
    for (let i = 0; i < 4; i += 1) {
      const next = undoOneMojibakeLayer(current);
      if (next === null || next === current) break;
      current = next;
      best = next;
    }
    return best;
  });
}

function normalizeClaimCode(value) {
  return getTrimmedString(value)
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
}

function generateClaimCode() {
  const timePart = Date.now().toString(36).toUpperCase();
  const randomPart = crypto.randomBytes(2).toString("hex").toUpperCase();
  return `${timePart}${randomPart}`;
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

function normalizeGameText(value) {
  return getTrimmedString(value).toLowerCase().replace(/\s+/g, " ");
}

function normalizeInteger(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(getTrimmedString(value), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeRemainingPartValue(value) {
  return normalizeInteger(value);
}

function describeRemainingPartState(value) {
  if (value === null || typeof value === "undefined") {
    return "absent";
  }
  return normalizeRemainingPartValue(value) === null ? "invalid" : "valid";
}

function normalizePrizeValueCents(value) {
  if (value === null || typeof value === "undefined") {
    return null;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return null;
  }
  return Math.round(parsed * 100);
}

function normalizeSecondaryPrizesForFingerprint(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((entry) => {
      if (!entry || typeof entry !== "object") {
        return null;
      }
      return {
        name: normalizeGameText(entry.name),
        presentation: normalizeGameText(entry.presentation),
        count: normalizeInteger(entry.count) || 0,
      };
    })
    .filter((entry) => entry && (entry.name || entry.presentation || entry.count > 0));
}

function getSnapshotCreateMillis(snapshot) {
  if (!snapshot) {
    return null;
  }
  if (snapshot.createTime && typeof snapshot.createTime.toMillis === "function") {
    return snapshot.createTime.toMillis();
  }
  return null;
}

function buildGameDedupeSignature(gameData, snapshot) {
  const createByRef = toDocRef(gameData && gameData.create_by);
  const enseigneRef = toDocRef(gameData && gameData.enseigne_id);
  const name = normalizeGameText(gameData && gameData.name);
  const gameType = normalizeGameText(gameData && gameData.game_type);
  const startDateMs = timestampToMillis(gameData && gameData.start_date);
  const endDateMs = timestampToMillis(gameData && gameData.end_date);
  const createdMs =
    timestampToMillis(gameData && gameData.created_time) ||
    getSnapshotCreateMillis(snapshot);

  if (
    !createByRef ||
    !enseigneRef ||
    !name ||
    !gameType ||
    !Number.isFinite(startDateMs) ||
    !Number.isFinite(endDateMs) ||
    !Number.isFinite(createdMs)
  ) {
    return null;
  }

  const payload = {
    createByPath: createByRef.path,
    enseignePath: enseigneRef.path,
    name,
    description: normalizeGameText(gameData && gameData.description),
    startDateMs,
    endDateMs,
    gameType,
    hasMainPrize: resolveHasMainPrize(gameData),
    prizeValueCents: normalizePrizeValueCents(gameData && gameData.prize_value),
    prohibitedForMinors: toBoolean(
      gameData && gameData.prohibited_for_minors,
      false,
    ),
    secondaryPrizes: normalizeSecondaryPrizesForFingerprint(
      gameData && gameData.secondary_prizes,
    ),
  };

  return {
    createdMs,
    fingerprint: crypto
      .createHash("sha256")
      .update(JSON.stringify(payload))
      .digest("hex"),
    payload,
  };
}

function buildGameDedupeReviewPayload({
  status,
  gameId,
  fingerprint,
  signaturePayload,
  createdMs,
  primaryGameId,
  reason,
  autoDeleted,
  deleteAttempted,
  note,
}) {
  return {
    status,
    game_id: gameId,
    primary_game_id: primaryGameId || gameId,
    fingerprint,
    reason,
    checked_at: admin.firestore.FieldValue.serverTimestamp(),
    created_ms: createdMs,
    auto_deleted: autoDeleted === true,
    delete_attempted: deleteAttempted === true,
    note: note || "",
    match_summary: signaturePayload,
  };
}

function shouldAutoDeleteDuplicateGame(gameData) {
  const views = normalizeInteger(gameData && gameData.views) || 0;
  const favorites = normalizeInteger(gameData && gameData.favorites) || 0;
  const participations = normalizeInteger(gameData && gameData.participations) || 0;

  return (
    views === 0 &&
    favorites === 0 &&
    participations === 0 &&
    gameData &&
    gameData.hasWinner !== true &&
    !gameData.main_prize_winner
  );
}

function comparePrimaryCandidate(current, existing) {
  if (!existing || !Number.isFinite(existing.createdMs)) {
    return -1;
  }
  if (current.createdMs < existing.createdMs) {
    return -1;
  }
  if (current.createdMs > existing.createdMs) {
    return 1;
  }
  return current.gameId.localeCompare(existing.gameId);
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

  await ref.set(
    buildPushNotificationRequestData({
      title,
      body,
      userRefs: `users/${userUid}`,
      createdBy,
      initialPageName,
      parameterData,
    }),
  );
  return true;
}

function buildPushNotificationRequestData({
  title,
  body,
  imageUrl = "",
  parameterData = "",
  initialPageName = "",
  targetAudience = "All",
  targetUserGroup = "All",
  userRefs = "",
  status = "started",
  createdBy = "",
  createdAt = admin.firestore.FieldValue.serverTimestamp(),
}) {
  return {
    notification_title: title,
    notification_text: body,
    notification_image_url: imageUrl,
    notification_sound: "",
    parameter_data: parameterData,
    initial_page_name: initialPageName,
    target_audience: targetAudience,
    target_user_group: targetUserGroup,
    user_refs: userRefs,
    status,
    created_at: createdAt,
    created_by: createdBy,
  };
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
          : `Un commer\u00E7ant favori vient de publier ${gameName}.`,
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

async function queueFollowedGameEndingSoonNotifications(gameDoc, config) {
  const gameData = gameDoc.data() || {};
  const gameId = gameDoc.id;

  // Config avec fallbacks
  const enabled = config && config.game_ending_enabled === true;
  const targetStatuses = Array.isArray(config?.game_ending_target_statuses)
    ? config.game_ending_target_statuses
    : ["actif", "a_relancer"];
  const useCityFilter = config && config.game_ending_use_city_filter === true;
  const daysBefore = config?.game_ending_days_before || 3;

  if (!enabled) {
    console.log(`[followedGameEndingSoon] game=${gameId} disabled in config, skipping`);
    return;
  }

  // Récupérer city du commerce si filtrage activé
  let enseigneCity = null;
  if (useCityFilter) {
    const enseigneRef = toDocRef(gameData.enseigne_id);
    if (enseigneRef) {
      const enseigneSnap = await enseigneRef.get();
      if (enseigneSnap.exists) {
        enseigneCity = getTrimmedString(enseigneSnap.data().city);
      }
    }
  }

  // Requête: tous les joueurs éligibles (pas seulement followers)
  let usersQuery = firestore
    .collection("users")
    .where("user_role", "==", "joueur")
    .where("player_status_cached", "in", targetStatuses);

  if (useCityFilter && enseigneCity) {
    usersQuery = usersQuery.where("city", "==", enseigneCity);
  }

  const userSnaps = await usersQuery.get();

  if (userSnaps.empty) {
    console.log(`[followedGameEndingSoon] game=${gameId} no eligible users, skipping`);
    return;
  }

  let queued = 0;
  let skippedDuplicate = 0;
  let skippedNoToken = 0;
  let skippedPrefs = 0;

  const gameName = getTrimmedString(gameData.name) || "ce jeu";
  const enseigneName = getTrimmedString(gameData.enseigne_name) || "un commerce";

  await Promise.all(
    userSnaps.map(async (userSnap) => {
      const userData = userSnap.data() || {};
      const userUid = userData.uid || userSnap.id;
      const userCity = userData.city || "";

      // Vérifier les préférences push
      if (!isUserPushPreferenceEnabled(userData, "followedGameEndingSoon")) {
        skippedPrefs += 1;
        return;
      }

      // Vérifier au moins 1 FCM token
      const tokensSnap = await firestore
        .doc(`users/${userUid}`)
        .collection(kFcmTokensCollection)
        .get();

      if (tokensSnap.empty) {
        skippedNoToken += 1;
        return;
      }

      // ===== ANTI-DOUBLON AVANT ENVOI =====
      const antiDuplicateRef = firestore
        .doc(`users/${userUid}/notifications`)
        .collection("by_game")
        .doc(`${gameId}_ending`);
      const existingSnap = await antiDuplicateRef.get();

      if (existingSnap.exists) {
        console.log(
          `[followedGameEndingSoon] uid=${userUid} game=${gameId} already notified, skipping`
        );
        skippedDuplicate++;
        return;
      }

      // ===== CRÉER NOTIFICATION via FF_PUSH_NOTIFICATIONS =====
      const notificationBody = useCityFilter && enseigneCity
        ? `${gameName} chez ${enseigneName} se termine dans ${daysBefore} jours.`
        : `${gameName} se termine dans ${daysBefore} jours.`;

      const queuedNow = await queueUserScopedPushNotification({
        docId: `game_ending_${gameId}_${userUid}_${Date.now()}`,
        title: "Tic tac ⏳",
        body: notificationBody,
        userUid,
        createdBy: `system/game_ending/${gameId}`,
      });

      if (queuedNow) {
        // ===== CRÉER LOG ANTI-DOUBLON =====
        await antiDuplicateRef.set({
          type: "game_ending_soon",
          game_id: gameId,
          game_name: gameName,
          enseigne_id: gameData.enseigne_id ? gameData.enseigne_id.path : "",
          enseigne_name: enseigneName,
          notification_title: "Tic tac ⏳",
          notification_text: notificationBody,
          player_status: userData.player_status_cached || "unknown",
          city_filtered: useCityFilter,
          user_city: userCity,
          enseigne_city: enseigneCity || "",
          sent_at: admin.firestore.FieldValue.serverTimestamp(),
          viewed: false,
        });

        queued += 1;
      }
    }),
  );

  console.log(
    `[followedGameEndingSoon] game=${gameId} eligible=${userSnaps.size} queued=${queued} skippedDuplicate=${skippedDuplicate} skippedNoToken=${skippedNoToken} skippedPrefs=${skippedPrefs}`
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

function summarizePushFailures(responses) {
  const codeCounts = new Map();
  const sampleErrors = [];

  responses.forEach((response) => {
    if (response.success) {
      return;
    }
    const rawCode = response.error && response.error.code;
    const code = getTrimmedString(rawCode) || "unknown";
    codeCounts.set(code, (codeCounts.get(code) || 0) + 1);

    if (sampleErrors.length < 5) {
      sampleErrors.push({
        code,
        message: getTrimmedString(response.error && response.error.message),
      });
    }
  });

  const sortedCodeEntries = Array.from(codeCounts.entries()).sort((a, b) => {
    if (b[1] !== a[1]) {
      return b[1] - a[1];
    }
    return a[0].localeCompare(b[0]);
  });

  return {
    totalFailures: responses.filter((response) => !response.success).length,
    errorCodeCounts: Object.fromEntries(sortedCodeEntries),
    topErrorCodes: sortedCodeEntries.slice(0, 10).map(([code]) => code),
    sampleErrors,
  };
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

function isTickerStatsActiveGame(gameData, nowMs) {
  if (!isPublishedGame(gameData)) {
    return false;
  }

  const enseigneRef = toDocRef(gameData && gameData.enseigne_id);
  if (!enseigneRef) {
    return false;
  }

  const startDateMs = timestampToMillis(gameData && gameData.start_date);
  if (Number.isFinite(startDateMs) && startDateMs > nowMs) {
    return false;
  }

  const endDateMs = timestampToMillis(gameData && gameData.end_date);
  if (!Number.isFinite(endDateMs) || endDateMs <= nowMs) {
    return false;
  }

  return true;
}

function buildDailyTickerWinnerMessage(firstName, prizeName, enseigneName) {
  const normalizedFirstName = getTrimmedString(firstName) || "Un joueur";
  const normalizedPrizeName = getTrimmedString(prizeName);
  const normalizedEnseigneName = getTrimmedString(enseigneName);
  if (!normalizedPrizeName) {
    return "";
  }
  if (normalizedEnseigneName) {
    return `${normalizedFirstName} a gagné ${normalizedPrizeName} chez ${normalizedEnseigneName}`;
  }
  return `${normalizedFirstName} a gagné ${normalizedPrizeName}`;
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
        .where("user_role", "==", "joueur")
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

/**
 * Initialize secure player counters at profile creation time.
 * This keeps remaining_part and part_last_update server-controlled.
 */
async function initializePlayerRemainingPartsIfNeeded(userRef, uid, userData, source) {
  const safeUserData = userData || {};
  const userRole = getTrimmedString(safeUserData.user_role);
  const currentRemainingPart = normalizeRemainingPartValue(
    safeUserData.remaining_part,
  );
  const currentRemainingPartState = describeRemainingPartState(
    safeUserData.remaining_part,
  );

  console.log(
    `[initializePlayerRemainingPartsIfNeeded] source=${source} uid=${uid} role=${userRole || "unknown"} remaining_part_state=${currentRemainingPartState} remaining_part=${currentRemainingPart}`,
  );

  if (userRole !== "joueur") {
    console.log(
      `[initializePlayerRemainingPartsIfNeeded] ignored uid=${uid} reason=role role=${userRole || "unknown"}`,
    );
    return false;
  }

  if (currentRemainingPart !== null) {
    console.log(
      `[initializePlayerRemainingPartsIfNeeded] ignored uid=${uid} reason=remaining_part_exists value=${currentRemainingPart}`,
    );
    return false;
  }

  console.log("Initializing remaining_part");
  await userRef.set(
    {
      remaining_part: 3,
      part_last_update: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  console.log(
    `[initializePlayerRemainingPartsIfNeeded] initialized uid=${uid} fields=remaining_part,part_last_update`,
  );
  return true;
}

async function initializeMerchantAccountStatusIfNeeded(userRef, uid, userData, source) {
  const safeUserData = userData || {};
  const userRole = getTrimmedString(safeUserData.user_role);
  const currentAccountStatus = getTrimmedString(safeUserData.account_status);

  console.log(
    `[initializeMerchantAccountStatusIfNeeded] source=${source} uid=${uid} role=${userRole || "unknown"} account_status=${currentAccountStatus || "<absent>"}`,
  );

  if (userRole !== "commercant") {
    console.log(
      `[initializeMerchantAccountStatusIfNeeded] ignored uid=${uid} reason=role role=${userRole || "unknown"}`,
    );
    return false;
  }

  if (currentAccountStatus) {
    console.log(
      `[initializeMerchantAccountStatusIfNeeded] ignored uid=${uid} reason=account_status_exists value=${currentAccountStatus}`,
    );
    return false;
  }

  console.log("Initializing merchant account_status");
  await userRef.set(
    {
      account_status: "pendingValidation",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  console.log(
    `[initializeMerchantAccountStatusIfNeeded] initialized uid=${uid} fields=account_status,updatedAt`,
  );

  await notifyAdminsOfPendingMerchant(uid, safeUserData);

  return true;
}

async function notifyAdminsOfPendingMerchant(uid, userData) {
  const merchantName = [
    getTrimmedString(userData.first_name),
    getTrimmedString(userData.last_name),
  ]
    .filter((part) => part)
    .join(" ") || getTrimmedString(userData.email) || uid;

  try {
    await firestore.collection(kPushNotificationsCollection).add(
      buildPushNotificationRequestData({
        title: "Nouveau commerçant à valider",
        body: `${merchantName} vient de créer un compte commerçant et attend une validation.`,
        targetUserGroup: "Admins",
        initialPageName: "ValidationCommercantsAdminPage",
        createdBy: "system:initializeMerchantAccountStatusIfNeeded",
      }),
    );
  } catch (error) {
    console.error(
      `[notifyAdminsOfPendingMerchant] push notification failed uid=${uid}`,
      error,
    );
  }

  try {
    const adminsSnap = await firestore
      .collection("users")
      .where("user_role", "==", "admin")
      .get();
    const adminEmails = adminsSnap.docs
      .map((doc) => getTrimmedString(doc.data().email))
      .filter((email) => email);

    if (adminEmails.length === 0) {
      console.log(
        `[notifyAdminsOfPendingMerchant] no admin email found, skipping email for uid=${uid}`,
      );
      return;
    }

    await Promise.all(
      adminEmails.map((to) =>
        sendTextEmail({
          to,
          subject: "Nouveau commerçant à valider",
          text: `${merchantName} (${getTrimmedString(userData.email) || "email inconnu"}) vient de créer un compte commerçant sur ProxiPlay et attend une validation.\n\nRendez-vous sur l'espace admin pour valider ou rejeter ce compte.`,
        }),
      ),
    );
    console.log(
      `[notifyAdminsOfPendingMerchant] email sent uid=${uid} recipients=${adminEmails.length}`,
    );
  } catch (error) {
    console.error(
      `[notifyAdminsOfPendingMerchant] email failed uid=${uid}`,
      error,
    );
  }
}

async function notifyMerchantOfAccountStatus(uid, userData, status) {
  const isApproved = status === "approved";
  const title = isApproved ? "Compte validé !" : "Compte non validé";
  const pushBody = isApproved
    ? "Votre compte commerçant a été validé. Vous pouvez maintenant créer votre enseigne et vos jeux."
    : "Votre compte commerçant n'a pas été validé. Contactez le support pour plus d'informations.";

  try {
    await queuePushNotificationRequest(firestore, {
      title,
      body: pushBody,
      userRefOrPath: firestore.collection("users").doc(uid),
      createdBy: "system:notifyMerchantOfAccountStatusChange",
    });
  } catch (error) {
    console.error(
      `[notifyMerchantOfAccountStatus] push notification failed uid=${uid}`,
      error,
    );
  }

  try {
    const email = getTrimmedString(userData.email);
    if (!email) {
      console.log(
        `[notifyMerchantOfAccountStatus] no email for uid=${uid}, skipping email`,
      );
      return;
    }

    await sendTextEmail({
      to: email,
      subject: title,
      text: isApproved
        ? "Bonne nouvelle : votre compte commerçant ProxiPlay a été validé. Vous pouvez maintenant créer votre enseigne et publier vos jeux."
        : "Votre compte commerçant ProxiPlay n'a pas été validé par notre équipe. Pour en savoir plus, contactez-nous à contact@proxiplay.fr.",
    });
    console.log(
      `[notifyMerchantOfAccountStatus] email sent uid=${uid} status=${status}`,
    );
  } catch (error) {
    console.error(
      `[notifyMerchantOfAccountStatus] email failed uid=${uid}`,
      error,
    );
  }
}

// Callable plutôt que trigger Firestore : la base est en région multi
// "eur3", qui ne supporte plus la création de nouveaux triggers Firestore
// 1ère génération. Appelée directement par les écrans admin juste après
// avoir mis à jour account_status (validation_commercants_admin_page,
// commercant_admin_detail_page).
exports.notifyMerchantAccountStatus = functions
  .region(kFunctionsRegion)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Vous devez être connecté.",
      );
    }
    await assertIsAdmin(context.auth.uid);

    const uid = (data.uid || "").toString().trim();
    if (!uid) {
      throw new functions.https.HttpsError("invalid-argument", "uid requis.");
    }

    const userSnap = await firestore.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Utilisateur introuvable.",
      );
    }

    const userData = userSnap.data() || {};
    const status = getTrimmedString(userData.account_status);

    if (status !== "approved" && status !== "rejected") {
      console.log(
        `[notifyMerchantAccountStatus] ignored uid=${uid} status=${status || "<absent>"}`,
      );
      return {ok: false, reason: "status-not-final"};
    }

    console.log(`[notifyMerchantAccountStatus] uid=${uid} status=${status}`);
    await notifyMerchantOfAccountStatus(uid, userData, status);
    return {ok: true};
  });

exports.initializeNewPlayerRemainingParts = functions.firestore
  .document("users/{uid}")
  .onCreate(async (snapshot, context) => {
    const uid = context.params.uid;

    try {
      const userData = snapshot.data() || {};
      console.log("New user doc", uid, userData);
      console.log("user_role", userData.user_role);
      await initializePlayerRemainingPartsIfNeeded(
        snapshot.ref,
        uid,
        userData,
        "onCreate",
      );
      return null;
    } catch (error) {
      console.error(
        `[initializeNewPlayerRemainingParts] failed uid=${uid}`,
        error,
      );
      throw error;
    }
  });

exports.initializeNewMerchantAccountStatus = functions.firestore
  .document("users/{uid}")
  .onCreate(async (snapshot, context) => {
    const uid = context.params.uid;

    try {
      const userData = snapshot.data() || {};
      console.log("New merchant candidate doc", uid, userData);
      console.log("merchant user_role", userData.user_role);
      await initializeMerchantAccountStatusIfNeeded(
        snapshot.ref,
        uid,
        userData,
        "onCreate",
      );
      return null;
    } catch (error) {
      console.error(
        `[initializeNewMerchantAccountStatus] failed uid=${uid}`,
        error,
      );
      throw error;
    }
  });

exports.initializePlayerRemainingPartsOnRoleAssignment = functions.firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const uid = context.params.uid;

    try {
      const beforeData = change.before.data() || {};
      const afterData = change.after.data() || {};
      const beforeRole = getTrimmedString(beforeData.user_role);
      const afterRole = getTrimmedString(afterData.user_role);
      const currentRemainingPart = normalizeRemainingPartValue(
        afterData.remaining_part,
      );
      const currentRemainingPartState = describeRemainingPartState(
        afterData.remaining_part,
      );

      console.log(
        `[initializePlayerRemainingPartsOnRoleAssignment] uid=${uid} before_role=${beforeRole || "unknown"} after_role=${afterRole || "unknown"} remaining_part_state=${currentRemainingPartState} remaining_part=${currentRemainingPart}`,
      );

      if (afterRole !== "joueur") {
        console.log(
          `[initializePlayerRemainingPartsOnRoleAssignment] ignored uid=${uid} reason=role role=${afterRole || "unknown"}`,
        );
        return null;
      }

      if (currentRemainingPart !== null) {
        console.log(
          `[initializePlayerRemainingPartsOnRoleAssignment] ignored uid=${uid} reason=remaining_part_exists value=${currentRemainingPart}`,
        );
        return null;
      }

      if (beforeRole === afterRole && beforeRole === "joueur") {
        console.log(
          `[initializePlayerRemainingPartsOnRoleAssignment] role already joueur uid=${uid} proceeding because remaining_part is absent`,
        );
      } else {
        console.log(
          `[initializePlayerRemainingPartsOnRoleAssignment] role detected uid=${uid} role=${afterRole}`,
        );
      }

      await initializePlayerRemainingPartsIfNeeded(
        change.after.ref,
        uid,
        afterData,
        "onUpdate",
      );
      return null;
    } catch (error) {
      console.error(
        `[initializePlayerRemainingPartsOnRoleAssignment] failed uid=${uid}`,
        error,
      );
      throw error;
    }
  });

exports.initializeMerchantAccountStatusOnRoleAssignment = functions.firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const uid = context.params.uid;

    try {
      const beforeData = change.before.data() || {};
      const afterData = change.after.data() || {};
      const beforeRole = getTrimmedString(beforeData.user_role);
      const afterRole = getTrimmedString(afterData.user_role);
      const currentAccountStatus = getTrimmedString(afterData.account_status);

      console.log(
        `[initializeMerchantAccountStatusOnRoleAssignment] uid=${uid} before_role=${beforeRole || "unknown"} after_role=${afterRole || "unknown"} account_status=${currentAccountStatus || "<absent>"}`,
      );

      if (afterRole !== "commercant") {
        console.log(
          `[initializeMerchantAccountStatusOnRoleAssignment] ignored uid=${uid} reason=role role=${afterRole || "unknown"}`,
        );
        return null;
      }

      if (currentAccountStatus) {
        console.log(
          `[initializeMerchantAccountStatusOnRoleAssignment] ignored uid=${uid} reason=account_status_exists value=${currentAccountStatus}`,
        );
        return null;
      }

      if (beforeRole === afterRole && beforeRole === "commercant") {
        console.log(
          `[initializeMerchantAccountStatusOnRoleAssignment] role already commercant uid=${uid} proceeding because account_status is absent`,
        );
      } else {
        console.log(
          `[initializeMerchantAccountStatusOnRoleAssignment] role detected uid=${uid} role=${afterRole}`,
        );
      }

      await initializeMerchantAccountStatusIfNeeded(
        change.after.ref,
        uid,
        afterData,
        "onUpdate",
      );
      return null;
    } catch (error) {
      console.error(
        `[initializeMerchantAccountStatusOnRoleAssignment] failed uid=${uid}`,
        error,
      );
      throw error;
    }
  });

exports.refreshGlobalStats = functions
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .pubsub.schedule("0 3 * * *")
  .timeZone(kParisTimeZone)
  .onRun(async () => {
    const startedAt = Date.now();
    console.log(
      "[refreshGlobalStats] start",
      JSON.stringify({
        schedule: "0 3 * * *",
        timezone: kParisTimeZone,
        targetDoc: kGlobalStatsDocPath,
      }),
    );

    const totalPlayersAgg = await firestore
      .collection("users")
      .where("user_role", "==", "joueur")
      .count()
      .get();
    const totalPlayers = totalPlayersAgg.data().count || 0;

    const gamesSnap = await firestore.collection("games").get();
    let totalGamesPlayed = 0;
    const activeMerchants = new Set();
    const nowMs = Date.now();

    gamesSnap.docs.forEach((gameDoc) => {
      const gameData = gameDoc.data() || {};
      totalGamesPlayed += normalizeInteger(gameData.participations) || 0;

      if (isTickerStatsActiveGame(gameData, nowMs)) {
        const enseigneRef = toDocRef(gameData.enseigne_id);
        if (enseigneRef) {
          activeMerchants.add(enseigneRef.path);
        }
      }
    });

    const prizesSnap = await firestore
      .collection("prizes")
      .orderBy("win_date", "desc")
      .limit(12)
      .get();

    const recentWinnerMessages = [];
    const winnerCache = new Map();
    let winnerUserLookups = 0;

    for (const prizeDoc of prizesSnap.docs) {
      if (recentWinnerMessages.length >= 8) {
        break;
      }

      const prizeData = prizeDoc.data() || {};
      const prizeName = getTrimmedString(prizeData.name);
      if (!prizeName || !prizeData.win_date) {
        continue;
      }

      let winnerFirstName = normalizeFirstName(
        firstNonEmptyString(prizeData, [
          "winner_first_name",
          "winnerFirstName",
          "winner_name",
          "winnerName",
        ]),
      );

      const winnerRef = toDocRef(prizeData.winner_id);
      if (!winnerFirstName && winnerRef) {
        if (!winnerCache.has(winnerRef.path)) {
          winnerUserLookups += 1;
          winnerCache.set(winnerRef.path, getDocData(winnerRef));
        }
        const winnerData = (await winnerCache.get(winnerRef.path)) || {};
        winnerFirstName = normalizeFirstName(
          firstNonEmptyString(winnerData, [
            "first_name",
            "firstName",
            "display_name",
            "displayName",
            "pseudo",
          ]),
        );
      }

      const message = buildDailyTickerWinnerMessage(
        winnerFirstName,
        prizeName,
        prizeData.enseigne_name,
      );
      if (message) {
        recentWinnerMessages.push(message);
      }
    }

    await firestore.doc(kGlobalStatsDocPath).set(
      {
        totalPlayers,
        totalGamesPlayed,
        totalMerchants: activeMerchants.size,
        recentWinnerMessages,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    console.log(
      "[refreshGlobalStats] completed",
      JSON.stringify({
        totalPlayers,
        totalGamesPlayed,
        totalMerchants: activeMerchants.size,
        tickerMessages: recentWinnerMessages.length,
        estimatedBackendReads: {
          playersAggregate: 1,
          gamesDocuments: gamesSnap.size,
          prizesDocuments: prizesSnap.size,
          winnerUserLookups,
        },
        elapsedMs: Date.now() - startedAt,
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
  return fromDisplayName || "Commer\u00E7ant";
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
  if (isFunctionsEmulator()) {
    return {
      transporter: {sendMail: async () => ({suppressed: true})},
      from: "Proxiplay Local <no-reply@proxiplay.local>",
      replyTo: "",
    };
  }
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

function stripHtmlToText(html) {
  return getTrimmedString(html)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function applyTemplateVariables(template, variables = {}) {
  let output = typeof template === "string" ? template : "";
  for (const [key, value] of Object.entries(variables)) {
    const safeValue = value == null ? "" : String(value);
    output = output.replace(new RegExp(`{{\\s*${key}\\s*}}`, "gi"), safeValue);
  }
  return output;
}

async function sendEmailNotification(mailer, to, subject, text, html = "") {
  if (isFunctionsEmulator()) {
    console.log(`[LOCAL_FIREBASE_EMULATORS] email suppressed to=${to} subject=${subject}`);
    return;
  }
  await mailer.transporter.sendMail({
    from: mailer.from,
    to,
    subject,
    text,
    ...(html ? { html } : {}),
    ...(mailer.replyTo ? { replyTo: mailer.replyTo } : {}),
  });
}

function isChannelDone(statusData, sentField, skippedField) {
  return statusData[sentField] === true || statusData[skippedField] === true;
}

function isMerchantEmailSendingStale(statusData, now) {
  const updatedAt = statusData.merchant_email_status_updated_at;
  if (!updatedAt || typeof updatedAt.toMillis !== "function") {
    return true;
  }
  const ageMs = now.toMillis() - updatedAt.toMillis();
  return ageMs > 5 * 60 * 1000; // 5 minutes
}

async function acquireMerchantEmailSendRight(statusRef) {
  const now = admin.firestore.Timestamp.now();
  return firestore.runTransaction(async (transaction) => {
    const statusSnap = await transaction.get(statusRef);
    const statusData = statusSnap.exists ? statusSnap.data() || {} : {};

    if (isChannelDone(statusData, "merchant_email_sent", "merchant_email_skipped")) {
      return { acquired: false, reason: "done" };
    }

    if (
      statusData.merchant_email_status === "sending" &&
      !isMerchantEmailSendingStale(statusData, now)
    ) {
      return { acquired: false, reason: "sending_in_progress" };
    }

    transaction.set(
      statusRef,
      {
        merchant_email_status: "sending",
        merchant_email_status_updated_at: now,
      },
      { merge: true },
    );

    return { acquired: true };
  });
}

async function markMerchantEmailSent(statusRef) {
  const now = admin.firestore.Timestamp.now();
  await statusRef.set(
    {
      merchant_email_status: "sent",
      merchant_email_status_updated_at: now,
      merchant_email_sent: true,
      merchant_email_skipped: admin.firestore.FieldValue.delete(),
    },
    { merge: true },
  );
}

async function markMerchantEmailFailed(statusRef, error) {
  const now = admin.firestore.Timestamp.now();
  await statusRef.set(
    {
      merchant_email_status: "failed",
      merchant_email_status_updated_at: now,
      merchant_email_sent: false,
      merchant_email_error: String(error),
    },
    { merge: true },
  );
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
  await ref.set(
    buildPushNotificationRequestData({
      title,
      body,
      userRefs: userRefPath,
      createdBy,
    }),
  );
}

const kNotificationsConfigDocId = "notifications";
const kNotificationsAutoConfigDocId = "notifications_auto";
const kPrizeReminderRunsCollection = "prize_reminder_runs";
const kPrizeReminderLogsSubcollection = "prize_reminder_logs";
const kDefaultPrizeReminderDelaysDays = [7, 21, 35];
const PRIZE_EMAILS_DISABLED = false;
const kPrizeEmailEmergencyDisabled = PRIZE_EMAILS_DISABLED;
const kPrizeEmailEmergencyDisabledReason =
  "Emergency stop: prize-related emails temporarily disabled while investigating incorrect recipient attribution.";
const kPrizeReminderEmergencyDisabled = true;
const kPrizeReminderEmergencyDisabledReason =
  "Emergency stop: prize reminders temporarily disabled while investigating incorrect recipient attribution.";
const kTerminalPrizeStatuses = new Set([
  "claimed",
  "used",
  "expired",
  "cancelled",
]);

function getNotificationsConfigRef() {
  return firestore.collection("app_config").doc(kNotificationsConfigDocId);
}

function getNotificationsAutoConfigRef() {
  return firestore.collection("app_config").doc(kNotificationsAutoConfigDocId);
}

function getPrizeReminderDefaultConfig() {
  return {
    prizeReminderEnabled: false,
    prizeReminderPushEnabled: true,
    prizeReminderEmailEnabled: true,
    prizeReminderPushTitle: "Votre lot vous attend \u{1F381}",
    prizeReminderPushMessage:
      "Vous avez gagn\u00E9 un lot sur Proxiplay. Pensez \u00E0 le retirer ou \u00E0 l\u2019utiliser avant qu\u2019il n\u2019expire.",
    prizeReminderEmailSubject: "Votre lot Proxiplay vous attend \u{1F381}",
    prizeReminderEmailBody: [
      "<p>Bonjour,</p>",
      "<p>Vous avez gagn\u00E9 un lot sur Proxiplay.</p>",
      "<p>Jeu : {{game_name}}<br>Code : {{claim_code}}</p>",
      "<p>Pensez \u00E0 le retirer ou \u00E0 l\u2019utiliser avant qu\u2019il n\u2019expire.</p>",
      "<p>\u00C0 bient\u00F4t,<br>L\u2019\u00E9quipe Proxiplay</p>",
    ].join(""),
    prizeReminderDelaysDays: [...kDefaultPrizeReminderDelaysDays],
    prizeReminderLastRunAt: null,
    prizeReminderLastRunPushSentCount: 0,
    prizeReminderLastRunEmailSentCount: 0,
    prizeReminderLastRunErrorCount: 0,
    prizeReminderUpdatedAt: null,
    prizeReminderUpdatedBy: "",
  };
}

function normalizeReminderDelays(value) {
  if (!Array.isArray(value)) {
    return [...kDefaultPrizeReminderDelaysDays];
  }
  const normalized = Array.from(
    new Set(
      value
        .map((entry) => Number(entry))
        .filter((entry) => Number.isFinite(entry) && entry > 0)
        .map((entry) => Math.trunc(entry)),
    ),
  ).sort((a, b) => a - b);
  if (normalized.length === 0) {
    return [...kDefaultPrizeReminderDelaysDays];
  }
  return normalized.slice(0, 3);
}

function normalizePrizeReminderConfig(rawConfig = {}) {
  const defaults = getPrizeReminderDefaultConfig();
  return {
    ...defaults,
    prizeReminderEnabled: toBoolean(
      rawConfig.prizeReminderEnabled,
      defaults.prizeReminderEnabled,
    ),
    prizeReminderPushEnabled: toBoolean(
      rawConfig.prizeReminderPushEnabled,
      defaults.prizeReminderPushEnabled,
    ),
    prizeReminderEmailEnabled: toBoolean(
      rawConfig.prizeReminderEmailEnabled,
      defaults.prizeReminderEmailEnabled,
    ),
    prizeReminderPushTitle:
      getTrimmedString(rawConfig.prizeReminderPushTitle) ||
      defaults.prizeReminderPushTitle,
    prizeReminderPushMessage:
      getTrimmedString(rawConfig.prizeReminderPushMessage) ||
      defaults.prizeReminderPushMessage,
    prizeReminderEmailSubject:
      getTrimmedString(rawConfig.prizeReminderEmailSubject) ||
      defaults.prizeReminderEmailSubject,
    prizeReminderEmailBody:
      getTrimmedString(rawConfig.prizeReminderEmailBody) ||
      defaults.prizeReminderEmailBody,
    prizeReminderDelaysDays: normalizeReminderDelays(
      rawConfig.prizeReminderDelaysDays,
    ),
    prizeReminderLastRunAt: rawConfig.prizeReminderLastRunAt || null,
    prizeReminderLastRunPushSentCount: Number.isFinite(
      Number(rawConfig.prizeReminderLastRunPushSentCount),
    )
      ? Math.trunc(Number(rawConfig.prizeReminderLastRunPushSentCount))
      : 0,
    prizeReminderLastRunEmailSentCount: Number.isFinite(
      Number(rawConfig.prizeReminderLastRunEmailSentCount),
    )
      ? Math.trunc(Number(rawConfig.prizeReminderLastRunEmailSentCount))
      : 0,
    prizeReminderLastRunErrorCount: Number.isFinite(
      Number(rawConfig.prizeReminderLastRunErrorCount),
    )
      ? Math.trunc(Number(rawConfig.prizeReminderLastRunErrorCount))
      : 0,
    prizeReminderUpdatedAt: rawConfig.prizeReminderUpdatedAt || null,
    prizeReminderUpdatedBy:
      getTrimmedString(rawConfig.prizeReminderUpdatedBy) || "",
  };
}

function getDateKeyInTimeZone(date, timeZone = kParisTimeZone) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function diffCalendarDaysInTimeZone(startMs, endMs, timeZone = kParisTimeZone) {
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs)) {
    return null;
  }
  const startKey = getDateKeyInTimeZone(new Date(startMs), timeZone);
  const endKey = getDateKeyInTimeZone(new Date(endMs), timeZone);
  const startKeyMs = Date.parse(`${startKey}T00:00:00.000Z`);
  const endKeyMs = Date.parse(`${endKey}T00:00:00.000Z`);
  if (!Number.isFinite(startKeyMs) || !Number.isFinite(endKeyMs)) {
    return null;
  }
  return Math.round((endKeyMs - startKeyMs) / (24 * 60 * 60 * 1000));
}

function getPrizeReminderLogRef(prizeRef, delayDays) {
  return prizeRef.collection(kPrizeReminderLogsSubcollection).doc(`${delayDays}d`);
}

function getPrizeReminderRunsRef(runId) {
  return getNotificationsConfigRef().collection(kPrizeReminderRunsCollection).doc(runId);
}

async function inspectPrizeAssignmentConsistency(prizeRef, winnerRef) {
  if (!prizeRef || !winnerRef) {
    return {
      ok: false,
      reason: "missing_prize_or_winner_ref",
      winnerLotPath: "",
      winnerLotPrizePath: "",
    };
  }

  const winnerLotRef = winnerRef.collection("my_lots").doc(prizeRef.id);
  const winnerLotSnap = await winnerLotRef.get();
  if (!winnerLotSnap.exists) {
    return {
      ok: false,
      reason: "winner_my_lot_missing",
      winnerLotPath: winnerLotRef.path,
      winnerLotPrizePath: "",
    };
  }

  const winnerLotData = winnerLotSnap.data() || {};
  const winnerLotPrizeRef = toDocRef(winnerLotData.prize_id);
  if (!winnerLotPrizeRef || winnerLotPrizeRef.path !== prizeRef.path) {
    return {
      ok: false,
      reason: "winner_my_lot_prize_mismatch",
      winnerLotPath: winnerLotRef.path,
      winnerLotPrizePath: serializeRefPath(winnerLotPrizeRef),
    };
  }

  return {
    ok: true,
    winnerLotPath: winnerLotRef.path,
    winnerLotPrizePath: winnerLotPrizeRef.path,
  };
}

async function validatePrizeEmailRecipient({
  prizeRef,
  prizeId = "",
  winnerRef,
  resolvedEmail = "",
  resolvedUserId = "",
  sourceFunction = "",
}) {
  const expectedWinnerId = getUserUidFromRef(winnerRef);
  if (!expectedWinnerId) {
    console.error("[PRIZE_EMAIL_BLOCKED_MISMATCH]", {
      prizeId,
      expectedWinnerId: null,
      resolvedUserId: resolvedUserId || null,
      email: resolvedEmail || "",
      sourceFunction,
    });
    return {
      ok: false,
      reason: "missing_expected_winner_id",
      expectedWinnerId: "",
    };
  }

  if (resolvedUserId !== expectedWinnerId) {
    console.error("[PRIZE_EMAIL_BLOCKED_MISMATCH]", {
      prizeId,
      expectedWinnerId,
      resolvedUserId: resolvedUserId || null,
      email: resolvedEmail || "",
      sourceFunction,
    });
    return {
      ok: false,
      reason: "resolved_user_mismatch",
      expectedWinnerId,
    };
  }

  const assignmentCheck = await inspectPrizeAssignmentConsistency(prizeRef, winnerRef);
  if (!assignmentCheck.ok) {
    console.error("[PRIZE_EMAIL_BLOCKED_NO_USER_LOT]", {
      prizeId,
      winnerId: expectedWinnerId,
      sourceFunction,
      reason: assignmentCheck.reason,
    });
    return {
      ok: false,
      reason: assignmentCheck.reason || "winner_my_lot_missing",
      expectedWinnerId,
    };
  }

  console.log("[PRIZE_EMAIL_READY_TO_SEND]", {
    prizeId,
    winnerId: expectedWinnerId,
    email: resolvedEmail || "",
    sourceFunction,
  });
  return {
    ok: true,
    expectedWinnerId,
  };
}

async function validatePrizeEmailMerchantRecipient({
  prizeId = "",
  ownerRef,
  enseigneRef,
  enseigneData = {},
  gameRef,
  gameData = {},
  resolvedEmail = "",
  resolvedUserId = "",
  sourceFunction = "",
}) {
  const expectedOwnerId = getUserUidFromRef(ownerRef);
  if (!expectedOwnerId) {
    console.error("[PRIZE_EMAIL_BLOCKED_MISMATCH]", {
      prizeId,
      expectedOwnerId: null,
      resolvedUserId: resolvedUserId || null,
      email: resolvedEmail || "",
      sourceFunction,
    });
    return {
      ok: false,
      reason: "missing_expected_owner_id",
      expectedOwnerId: "",
    };
  }

  if (resolvedUserId !== expectedOwnerId) {
    console.error("[PRIZE_EMAIL_BLOCKED_MISMATCH]", {
      prizeId,
      expectedOwnerId,
      resolvedUserId: resolvedUserId || null,
      email: resolvedEmail || "",
      sourceFunction,
    });
    return {
      ok: false,
      reason: "resolved_user_mismatch",
      expectedOwnerId,
    };
  }

  // The enseigne tied to this prize must be currently registered to the
  // same owner we're about to email -- guards against a stale/fallback
  // owner_id (prize.owner_id / game.create_by) pointing at someone who no
  // longer owns (or never owned) that enseigne.
  const enseigneOwnerId = getUserUidFromRef(toDocRef(enseigneData.owner));
  if (enseigneRef && enseigneOwnerId && enseigneOwnerId !== expectedOwnerId) {
    console.error("[PRIZE_EMAIL_BLOCKED_MISMATCH]", {
      prizeId,
      expectedOwnerId,
      enseigneId: enseigneRef.id,
      enseigneOwnerId,
      sourceFunction,
      reason: "enseigne_owner_mismatch",
    });
    return {
      ok: false,
      reason: "enseigne_owner_mismatch",
      expectedOwnerId,
    };
  }

  // If the prize's game names a specific enseigne, make sure it's the same
  // one we validated ownership against above.
  const gameEnseigneRef = toDocRef(gameData.enseigne_id);
  if (gameRef && enseigneRef && gameEnseigneRef && gameEnseigneRef.path !== enseigneRef.path) {
    console.error("[PRIZE_EMAIL_BLOCKED_MISMATCH]", {
      prizeId,
      expectedOwnerId,
      enseigneId: enseigneRef.id,
      gameEnseigneId: gameEnseigneRef.id,
      sourceFunction,
      reason: "game_enseigne_mismatch",
    });
    return {
      ok: false,
      reason: "game_enseigne_mismatch",
      expectedOwnerId,
    };
  }

  console.log("[PRIZE_EMAIL_READY_TO_SEND]", {
    prizeId,
    ownerId: expectedOwnerId,
    email: resolvedEmail || "",
    sourceFunction,
  });
  return {
    ok: true,
    expectedOwnerId,
  };
}

function serializeRefPath(ref) {
  return ref && typeof ref.path === "string" ? ref.path : "";
}

function logPrizeEmailAudit({
  prizeId = "",
  gameId = "",
  winnerRef = null,
  winnerUserId = "",
  resolvedEmail = "",
  resolvedUserId = "",
  sourceFunction = "",
}) {
  console.log(
    "[prize_email_audit]",
    JSON.stringify({
      prizeId,
      gameId,
      winnerRef: serializeRefPath(winnerRef),
      winnerUserId,
      resolvedEmail,
      resolvedUserId,
      sourceFunction,
    }),
  );
}

function getPrizeStatus(prizeData = {}) {
  const explicitStatus = getTrimmedString(prizeData.prize_status).toLowerCase();
  if (explicitStatus) {
    return explicitStatus;
  }
  return prizeData.claimed === true ? "claimed" : "won";
}

function getPrizeWonAtMillis(prizeData = {}) {
  return (
    timestampToMillis(prizeData.prize_won_at) ||
    timestampToMillis(prizeData.win_date)
  );
}

async function inspectPrizeReminderTarget(prizeRef, delaysDays, nowMs = Date.now()) {
  const prizeSnap = await prizeRef.get();
  if (!prizeSnap.exists) {
    return {
      ok: false,
      reason: "prize_not_found",
      message: "Lot introuvable.",
    };
  }

  const prizeData = prizeSnap.data() || {};
  const prizeStatus = getPrizeStatus(prizeData);
  if (prizeData.claimed === true || kTerminalPrizeStatuses.has(prizeStatus)) {
    return {
      ok: false,
      reason: "claimed_or_final_status",
      message: `Lot non éligible: status=${prizeStatus || "claimed"}.`,
      prizeSnap,
      prizeData,
    };
  }

  const prizeWonAtMs = getPrizeWonAtMillis(prizeData);
  if (!Number.isFinite(prizeWonAtMs)) {
    return {
      ok: false,
      reason: "missing_won_at",
      message: "Date de gain introuvable.",
      prizeSnap,
      prizeData,
    };
  }

  const ageDays = diffCalendarDaysInTimeZone(prizeWonAtMs, nowMs, kParisTimeZone);
  const matchedDelay = delaysDays.find((delayDays) => delayDays === ageDays);
  if (!matchedDelay) {
    return {
      ok: false,
      reason: "delay_not_reached",
      message: `Le lot n'est pas sur un palier de relance aujourd'hui (ageDays=${ageDays}).`,
      prizeSnap,
      prizeData,
      ageDays,
    };
  }

  const reminderLogRef = getPrizeReminderLogRef(prizeRef, matchedDelay);
  const reminderLogSnap = await reminderLogRef.get();
  if (reminderLogSnap.exists) {
    return {
      ok: false,
      reason: "already_reminded",
      message: `Le rappel ${matchedDelay}d existe d\u00E9j\u00E0 pour ce lot.`,
      prizeSnap,
      prizeData,
      matchedDelay,
      ageDays,
    };
  }

  return {
    ok: true,
    prizeSnap,
    prizeData,
    prizeStatus,
    matchedDelay,
    ageDays,
  };
}

async function resolveAdminAuditIdentity(uid) {
  if (!uid) {
    return "admin_inconnu";
  }
  try {
    const authUser = await admin.auth().getUser(uid);
    return getTrimmedString(authUser.email) || `users/${uid}`;
  } catch (error) {
    console.log(
      `[prize_reminders] resolveAdminAuditIdentity uid=${uid} error=${error.message || error}`,
    );
    return `users/${uid}`;
  }
}

async function loadUnifiedNotificationsConfig() {
  const [notificationsSnap, notificationsAutoSnap] = await Promise.all([
    getNotificationsConfigRef().get(),
    getNotificationsAutoConfigRef().get(),
  ]);

  const notificationsData = notificationsSnap.exists
    ? notificationsSnap.data() || {}
    : {};
  const notificationsAutoData = notificationsAutoSnap.exists
    ? notificationsAutoSnap.data() || {}
    : {};
  const prizeReminderConfig = normalizePrizeReminderConfig(notificationsData);

  return {
    dailyRemainingChancesReminderEnabled:
      notificationsData.dailyRemainingChancesReminderEnabled !== false,
    ...prizeReminderConfig,
    game_ending_enabled: notificationsAutoData.game_ending_enabled === true,
    game_ending_days_before: Number.isFinite(
      Number(notificationsAutoData.game_ending_days_before),
    )
      ? Math.trunc(Number(notificationsAutoData.game_ending_days_before))
      : 3,
    game_ending_target_statuses: Array.isArray(
      notificationsAutoData.game_ending_target_statuses,
    )
      ? notificationsAutoData.game_ending_target_statuses
      : ["actif", "a_relancer"],
    game_ending_use_city_filter:
      notificationsAutoData.game_ending_use_city_filter === true,
    inactive_relaunch_enabled:
      notificationsAutoData.inactive_relaunch_enabled === true,
    inactive_relaunch_frequency_days: Number.isFinite(
      Number(notificationsAutoData.inactive_relaunch_frequency_days),
    )
      ? Math.trunc(Number(notificationsAutoData.inactive_relaunch_frequency_days))
      : 7,
    new_game_enabled: notificationsAutoData.new_game_enabled === true,
    new_game_target_statuses: Array.isArray(
      notificationsAutoData.new_game_target_statuses,
    )
      ? notificationsAutoData.new_game_target_statuses
      : ["actif", "a_relancer"],
    new_game_use_city_filter:
      notificationsAutoData.new_game_use_city_filter === true,
  };
}

async function runPrizeReminderJob({
  dryRun = false,
  onlyPrizeIds = [],
  limit = 0,
  trigger = "scheduled",
} = {}) {
  const unifiedConfig = await loadUnifiedNotificationsConfig();
  const prizeReminderConfig = normalizePrizeReminderConfig(unifiedConfig);
  const nowMs = Date.now();
  const delaysDays = normalizeReminderDelays(
    prizeReminderConfig.prizeReminderDelaysDays,
  );
  const onlyPrizeIdsSet =
    Array.isArray(onlyPrizeIds) && onlyPrizeIds.length > 0
      ? new Set(
          onlyPrizeIds
            .map((entry) => getTrimmedString(entry))
            .filter((entry) => entry.length > 0),
        )
      : null;
  const normalizedLimit = Number.isFinite(Number(limit))
    ? Math.max(0, Math.min(500, Math.trunc(Number(limit))))
    : 0;

  const summary = {
    dryRun: dryRun === true,
    trigger,
    enabled: prizeReminderConfig.prizeReminderEnabled === true,
    emergencyDisabled: kPrizeReminderEmergencyDisabled === true,
    delaysDays,
    scannedPrizes: 0,
    eligiblePrizes: 0,
    remindersAttempted: 0,
    pushSentCount: 0,
    emailSentCount: 0,
    errorCount: 0,
    skippedClaimedOrFinalStatus: 0,
    skippedMissingWinner: 0,
    skippedMissingWonAt: 0,
    skippedDelayNotReached: 0,
    skippedAlreadyReminded: 0,
    skippedUserNotFound: 0,
    skippedNoChannel: 0,
    skippedNoPushToken: 0,
    skippedNoEmail: 0,
    skippedAssignmentMismatch: 0,
    processedPrizeIds: [],
  };

  console.log(
    "[prize_reminders] start",
    JSON.stringify({
      dryRun: summary.dryRun,
      trigger,
      enabled: summary.enabled,
      delaysDays,
      onlyPrizeIds: onlyPrizeIdsSet ? Array.from(onlyPrizeIdsSet) : [],
      limit: normalizedLimit,
      emergencyDisabled: kPrizeReminderEmergencyDisabled === true,
    }),
  );

  if (kPrizeReminderEmergencyDisabled === true) {
    summary.enabled = false;
    console.log(
      `[prize_reminders] emergency_disabled reason=${kPrizeReminderEmergencyDisabledReason}`,
    );
  }

  const processPrizeDoc = async (prizeDoc, mailerFactory) => {
    const prizeData = prizeDoc.data() || {};
    summary.scannedPrizes += 1;

    const prizeStatus = getPrizeStatus(prizeData);
    if (prizeData.claimed === true || kTerminalPrizeStatuses.has(prizeStatus)) {
      summary.skippedClaimedOrFinalStatus += 1;
      console.log(
        `[prize_reminders] prize=${prizeDoc.id} skip=final_status status=${prizeStatus}`,
      );
      return;
    }

    const winnerRef = toDocRef(prizeData.winner_id);
    if (!winnerRef) {
      summary.skippedMissingWinner += 1;
      console.log(`[prize_reminders] prize=${prizeDoc.id} skip=missing_winner`);
      return;
    }

    const prizeWonAtMs = getPrizeWonAtMillis(prizeData);
    if (!Number.isFinite(prizeWonAtMs)) {
      summary.skippedMissingWonAt += 1;
      console.log(`[prize_reminders] prize=${prizeDoc.id} skip=missing_won_at`);
      return;
    }

    const ageDays = diffCalendarDaysInTimeZone(prizeWonAtMs, nowMs, kParisTimeZone);
    const matchedDelay = delaysDays.find((delayDays) => delayDays === ageDays);
    if (!matchedDelay) {
      summary.skippedDelayNotReached += 1;
      console.log(
        `[prize_reminders] prize=${prizeDoc.id} skip=delay_not_reached ageDays=${ageDays}`,
      );
      return;
    }

    const reminderLogRef = getPrizeReminderLogRef(prizeDoc.ref, matchedDelay);
    const reminderLogSnap = await reminderLogRef.get();
    if (reminderLogSnap.exists) {
      summary.skippedAlreadyReminded += 1;
      console.log(
        `[prize_reminders] prize=${prizeDoc.id} skip=already_reminded delayDays=${matchedDelay}`,
      );
      return;
    }

    const winnerSnap = await winnerRef.get();
    if (!winnerSnap.exists) {
      summary.skippedUserNotFound += 1;
      console.log(
        `[prize_reminders] prize=${prizeDoc.id} skip=user_not_found winner=${winnerRef.path}`,
      );
      return;
    }

    const winnerData = winnerSnap.data() || {};
    const assignmentCheck = await inspectPrizeAssignmentConsistency(
      prizeDoc.ref,
      winnerRef,
    );
    if (!assignmentCheck.ok) {
      summary.skippedAssignmentMismatch += 1;
      console.log(
        `[prize_reminders] prize=${prizeDoc.id} skip=assignment_mismatch reason=${assignmentCheck.reason} winner=${winnerRef.path} owner=${serializeRefPath(toDocRef(prizeData.owner_id))} winnerLotPath=${assignmentCheck.winnerLotPath || ""} winnerLotPrizePath=${assignmentCheck.winnerLotPrizePath || ""}`,
      );
      await reminderLogRef.set(
        {
          trigger,
          delayDays: matchedDelay,
          ageDays,
          status: "skipped_assignment_mismatch",
          prizeId: prizeDoc.id,
          prizePath: prizeDoc.ref.path,
          gamePath: serializeRefPath(toDocRef(prizeData.game_id)),
          userPath: winnerRef.path,
          ownerPath: serializeRefPath(toDocRef(prizeData.owner_id)),
          winnerLotPath: assignmentCheck.winnerLotPath || "",
          winnerLotPrizePath: assignmentCheck.winnerLotPrizePath || "",
          reason: assignmentCheck.reason,
          push_sent: false,
          email_sent: false,
          error_push: "",
          error_email: "",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return;
    }
    const prizeName = getTrimmedString(prizeData.name) || "Lot ProxiPlay";
    const gameRef = toDocRef(prizeData.game_id);
    const enseigneRef = toDocRef(prizeData.enseigne_id);
    const claimCode = getTrimmedString(prizeData.claim_code);
    let gameName = "Jeu ProxiPlay";
    if (gameRef) {
      try {
        const gameSnap = await gameRef.get();
        if (gameSnap.exists) {
          const gameData = gameSnap.data() || {};
          gameName = getTrimmedString(gameData.name) || gameName;
        }
      } catch (error) {
        console.log(
          `[prize_reminders] prize=${prizeDoc.id} game_lookup_error=${error.message || error}`,
        );
      }
    }
    let enseigneData = {};
    if (enseigneRef) {
      try {
        const enseigneSnap = await enseigneRef.get();
        if (enseigneSnap.exists) {
          enseigneData = enseigneSnap.data() || {};
        }
      } catch (error) {
        console.log(
          `[prize_reminders] prize=${prizeDoc.id} enseigne_lookup_error=${error.message || error}`,
        );
      }
    }
    const shopName =
      getTrimmedString(prizeData.enseigne_name) ||
      getTrimmedString(enseigneData.name) ||
      "Boutique ProxiPlay";
    const shopStreet =
      getTrimmedString(enseigneData.address) ||
      getTrimmedString(enseigneData.adresse) ||
      getTrimmedString(enseigneData.street) ||
      getTrimmedString(enseigneData.rue);
    const shopPostalCode =
      getTrimmedString(enseigneData.area_code) ||
      getTrimmedString(enseigneData.postal_code) ||
      getTrimmedString(enseigneData.code_postal);
    const shopCity =
      getTrimmedString(enseigneData.city) ||
      getTrimmedString(enseigneData.ville);
    const shopAddressFromParts = [shopStreet, [shopPostalCode, shopCity].filter((v) => v).join(" ")]
      .filter((v) => v)
      .join(", ");
    const shopAddress =
      getTrimmedString(enseigneData.full_address) ||
      shopAddressFromParts ||
      getTrimmedString(enseigneData.address) ||
      getTrimmedString(enseigneData.adresse) ||
      "Adresse non disponible";
    console.log("[PRIZE_EMAIL_SHOP_INFO]", {
      prizeId: prizeDoc.id,
      shopName,
      shopAddress,
    });

    let hasPushToken = false;
    if (prizeReminderConfig.prizeReminderPushEnabled) {
      const tokenSnap = await winnerRef.collection(kFcmTokensCollection).limit(1).get();
      hasPushToken = !tokenSnap.empty;
      if (!hasPushToken) {
        summary.skippedNoPushToken += 1;
      }
    }

    let winnerEmail = "";
    if (prizeReminderConfig.prizeReminderEmailEnabled) {
      winnerEmail = await resolveUserEmail(winnerRef, winnerData);
      logPrizeEmailAudit({
        prizeId: prizeDoc.id,
        gameId: gameRef ? gameRef.id : "",
        winnerRef,
        winnerUserId: getUserUidFromRef(winnerRef),
        resolvedEmail: winnerEmail,
        resolvedUserId: getUserUidFromRef(winnerRef),
        sourceFunction: "runPrizeReminderJob:resolveWinnerEmail",
      });
      if (!winnerEmail) {
        summary.skippedNoEmail += 1;
      }
    }

    const canPush =
      prizeReminderConfig.prizeReminderPushEnabled === true && hasPushToken;
    const canEmail =
      prizeReminderConfig.prizeReminderEmailEnabled === true && !!winnerEmail;
    if (!canPush && !canEmail) {
      summary.skippedNoChannel += 1;
      console.log(
        `[prize_reminders] prize=${prizeDoc.id} skip=no_channel pushEnabled=${prizeReminderConfig.prizeReminderPushEnabled} hasPushToken=${hasPushToken} emailEnabled=${prizeReminderConfig.prizeReminderEmailEnabled} hasEmail=${winnerEmail.length > 0}`,
      );
      return;
    }

    const pushResult = {
      status: prizeReminderConfig.prizeReminderPushEnabled
        ? hasPushToken
          ? summary.dryRun
            ? "dry_run"
            : "queued"
          : "skipped_no_token"
        : "disabled",
      error: "",
    };
    const emailResult = {
      status: prizeReminderConfig.prizeReminderEmailEnabled
        ? winnerEmail
          ? summary.dryRun
            ? "dry_run"
            : "sent"
          : "skipped_no_email"
        : "disabled",
      error: "",
    };
    const emailTemplateVariables = {
      game_name: gameName,
      claim_code: claimCode,
      prize_name: prizeName,
      shop_name: shopName,
      shop_address: shopAddress,
    };
    const localizedPrizeReminderEmailBody = prizeReminderConfig.prizeReminderEmailBody
      .replace(
        /Jeu\s*:\s*{{\s*game_name\s*}}/gi,
        "Lot : {{prize_name}}<br>Boutique : {{shop_name}}<br>Adresse : {{shop_address}}",
      );
    const emailSubject = applyTemplateVariables(
      prizeReminderConfig.prizeReminderEmailSubject,
      emailTemplateVariables,
    );
    const emailHtmlBody = applyTemplateVariables(
      localizedPrizeReminderEmailBody,
      emailTemplateVariables,
    );
    const emailTextBody = stripHtmlToText(emailHtmlBody);

    if (summary.dryRun) {
      summary.eligiblePrizes += 1;
      summary.remindersAttempted += 1;
      summary.processedPrizeIds.push(prizeDoc.id);
      if (canPush) {
        summary.pushSentCount += 1;
      }
      if (canEmail) {
        summary.emailSentCount += 1;
      }
      console.log("[PRIZE_EMAIL_CONTENT_CHECK]", {
        prizeId: prizeDoc.id,
        winnerId: winnerRef && winnerRef.id ? winnerRef.id : null,
        claimCode: prizeData.claim_code,
        prizeNameFromDB: prizeData.name,
        emailPrizeNameUsed: prizeName,
        emailGameNameUsed: gameName,
        sourceFunction: "runPrizeReminderJob",
      });
      console.log(
        `[prize_reminders] dry_run prize=${prizeDoc.id} delayDays=${matchedDelay} prizeName=${prizeName}`,
      );
      return;
    }

    const reservation = await firestore.runTransaction(async (transaction) => {
      const freshPrizeSnap = await transaction.get(prizeDoc.ref);
      if (!freshPrizeSnap.exists) {
        return {ok: false, reason: "prize_not_found"};
      }

      const freshPrizeData = freshPrizeSnap.data() || {};
      const freshPrizeStatus = getPrizeStatus(freshPrizeData);
      if (
        freshPrizeData.claimed === true ||
        kTerminalPrizeStatuses.has(freshPrizeStatus)
      ) {
        return {
          ok: false,
          reason: "claimed_or_final_status",
          status: freshPrizeStatus,
        };
      }

      const freshReminderLogSnap = await transaction.get(reminderLogRef);
      if (freshReminderLogSnap.exists) {
        return {
          ok: false,
          reason: "already_reminded",
        };
      }

      const currentReminderCount = Number.isFinite(
        Number(freshPrizeData.prize_reminder_count),
      )
        ? Math.trunc(Number(freshPrizeData.prize_reminder_count))
        : 0;

      transaction.set(
        prizeDoc.ref,
        {
          ...(freshPrizeData.prize_status
            ? {}
            : {prize_status: freshPrizeStatus || "won"}),
          ...(freshPrizeData.prize_won_at
            ? {}
            : {
                prize_won_at:
                  freshPrizeData.win_date ||
                  admin.firestore.FieldValue.serverTimestamp(),
              }),
          prize_reminder_count: currentReminderCount + 1,
          last_prize_reminder_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      transaction.create(reminderLogRef, {
        trigger,
        delayDays: matchedDelay,
        ageDays,
        status: "reserved",
        prizeId: prizeDoc.id,
        prizePath: prizeDoc.ref.path,
        gamePath: serializeRefPath(gameRef),
        userPath: winnerRef.path,
        prizeStatusBefore: freshPrizeStatus,
        push: {
          channelEnabled: prizeReminderConfig.prizeReminderPushEnabled === true,
          planned: canPush,
          status: "pending",
        },
        email: {
          channelEnabled: prizeReminderConfig.prizeReminderEmailEnabled === true,
          planned: canEmail,
          status: "pending",
        },
        push_sent: false,
        email_sent: false,
        error_push: "",
        error_email: "",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {ok: true};
    });

    if (!reservation.ok) {
      if (reservation.reason === "claimed_or_final_status") {
        summary.skippedClaimedOrFinalStatus += 1;
      } else if (reservation.reason === "already_reminded") {
        summary.skippedAlreadyReminded += 1;
      }
      console.log(
        `[prize_reminders] prize=${prizeDoc.id} reservation_skip=${reservation.reason || "unknown"}`,
      );
      return;
    }

    summary.eligiblePrizes += 1;
    summary.remindersAttempted += 1;

    if (!summary.dryRun && canPush) {
      try {
        await queuePrizePushNotification({
          docId: `prize_reminder_${prizeDoc.id}_${matchedDelay}d`,
          title: prizeReminderConfig.prizeReminderPushTitle,
          body: prizeReminderConfig.prizeReminderPushMessage,
          userRefPath: winnerRef.path,
          createdBy: "system/prize_reminders",
        });
        summary.pushSentCount += 1;
      } catch (error) {
        pushResult.status = "failed";
        pushResult.error = `${error.message || error}`;
        summary.errorCount += 1;
      }
    }

    if (!summary.dryRun && canEmail) {
      const emailRecipientCheck = await validatePrizeEmailRecipient({
        prizeRef: prizeDoc.ref,
        prizeId: prizeDoc.id,
        winnerRef,
        resolvedEmail: winnerEmail,
        resolvedUserId: getUserUidFromRef(winnerRef),
        sourceFunction: "runPrizeReminderJob",
      });
      if (!emailRecipientCheck.ok) {
        emailResult.status = "blocked_recipient_guard";
        emailResult.error = emailRecipientCheck.reason || "recipient_guard_blocked";
      } else {
      console.log("[PRIZE_EMAIL_CONTENT_CHECK]", {
        prizeId: prizeDoc.id,
        winnerId: winnerRef && winnerRef.id ? winnerRef.id : null,
        claimCode: prizeData.claim_code,
        prizeNameFromDB: prizeData.name,
        emailPrizeNameUsed: prizeName,
        emailGameNameUsed: gameName,
        sourceFunction: "runPrizeReminderJob",
      });
      if (kPrizeEmailEmergencyDisabled === true) {
        emailResult.status = "disabled_emergency_stop";
        emailResult.error = kPrizeEmailEmergencyDisabledReason;
        console.log(
          `[prize_reminders] prize=${prizeDoc.id} email_disabled reason=${kPrizeEmailEmergencyDisabledReason}`,
        );
      } else {
        try {
          const mailer = mailerFactory();
          await sendEmailNotification(
            mailer,
            winnerEmail,
            emailSubject,
            emailTextBody,
            emailHtmlBody,
          );
          summary.emailSentCount += 1;
          logPrizeEmailAudit({
            prizeId: prizeDoc.id,
            gameId: gameRef ? gameRef.id : "",
            winnerRef,
            winnerUserId: getUserUidFromRef(winnerRef),
            resolvedEmail: winnerEmail,
            resolvedUserId: getUserUidFromRef(winnerRef),
            sourceFunction: "runPrizeReminderJob:sendWinnerEmail",
          });
        } catch (error) {
          emailResult.status = "failed";
          emailResult.error = `${error.message || error}`;
          summary.errorCount += 1;
        }
      }
      }
    }

    const reminderStatus =
      pushResult.status === "failed" && emailResult.status === "failed"
        ? "failed"
        : "completed";

    summary.processedPrizeIds.push(prizeDoc.id);

    console.log(
      `[prize_reminders] prize=${prizeDoc.id} processed delayDays=${matchedDelay} push=${pushResult.status} email=${emailResult.status}`,
    );

    await reminderLogRef.set(
      {
        status: reminderStatus,
        push: pushResult,
        email: emailResult,
        push_sent: pushResult.status === "queued",
        email_sent: emailResult.status === "sent",
        error_push: pushResult.error,
        error_email: emailResult.error,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  };

  const mailerFactory = (() => {
    let mailer = null;
    return () => {
      if (!mailer) {
        mailer = createSmtpMailer();
      }
      return mailer;
    };
  })();

  if (summary.enabled !== true) {
    console.log("[prize_reminders] skipped prizeReminderEnabled=false");
  } else if (onlyPrizeIdsSet && onlyPrizeIdsSet.size > 0) {
    let processed = 0;
    for (const prizeId of onlyPrizeIdsSet) {
      if (normalizedLimit > 0 && processed >= normalizedLimit) {
        break;
      }
      const prizeSnap = await firestore.collection("prizes").doc(prizeId).get();
      if (!prizeSnap.exists) {
        continue;
      }
      processed += 1;
      await processPrizeDoc(prizeSnap, mailerFactory);
    }
  } else if (summary.enabled === true) {
    const batchSize =
      normalizedLimit > 0 ? Math.min(normalizedLimit, 200) : 200;
    let lastDoc = null;
    let processed = 0;

    while (true) {
      let query = firestore
        .collection("prizes")
        .where("claimed", "==", false)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(batchSize);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snap = await query.get();
      if (snap.empty) {
        break;
      }

      for (const prizeDoc of snap.docs) {
        if (normalizedLimit > 0 && processed >= normalizedLimit) {
          break;
        }
        processed += 1;
        await processPrizeDoc(prizeDoc, mailerFactory);
      }

      lastDoc = snap.docs[snap.docs.length - 1];
      if (snap.size < batchSize || (normalizedLimit > 0 && processed >= normalizedLimit)) {
        break;
      }
    }
  }

  if (!summary.dryRun) {
    await getNotificationsConfigRef().set(
      {
        prizeReminderLastRunAt: admin.firestore.FieldValue.serverTimestamp(),
        prizeReminderLastRunPushSentCount: summary.pushSentCount,
        prizeReminderLastRunEmailSentCount: summary.emailSentCount,
        prizeReminderLastRunErrorCount: summary.errorCount,
      },
      {merge: true},
    );

    const runRef = getPrizeReminderRunsRef(
      getNotificationsConfigRef().collection(kPrizeReminderRunsCollection).doc().id,
    );
    await runRef.set({
      trigger,
      status: "completed",
      dryRun: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      summary,
    });
  }

  console.log(
    "[prize_reminders] done",
    JSON.stringify({
      enabled: summary.enabled,
      dryRun: summary.dryRun,
      eligiblePrizes: summary.eligiblePrizes,
      pushSentCount: summary.pushSentCount,
      emailSentCount: summary.emailSentCount,
      errorCount: summary.errorCount,
    }),
  );

  return summary;
}

const adminGetNotificationsConfigCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);
    const config = await loadUnifiedNotificationsConfig();
    return {
      ...config,
      prizeReminderLastRunAt:
        timestampToMillis(config.prizeReminderLastRunAt) || null,
      prizeReminderUpdatedAt:
        timestampToMillis(config.prizeReminderUpdatedAt) || null,
    };
  });

const adminSetNotificationsConfigCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);
    const updatedBy = await resolveAdminAuditIdentity(context.auth.uid);
    const currentNotificationsSnap = await getNotificationsConfigRef().get();
    const currentNotificationsData = currentNotificationsSnap.exists
      ? currentNotificationsSnap.data() || {}
      : {};

    const notificationsPatch = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy,
    };
    if (Object.prototype.hasOwnProperty.call(data || {}, "dailyRemainingChancesReminderEnabled")) {
      notificationsPatch.dailyRemainingChancesReminderEnabled =
        data.dailyRemainingChancesReminderEnabled !== false;
    }
    const prizeReminderKeys = [
      "prizeReminderEnabled",
      "prizeReminderPushEnabled",
      "prizeReminderEmailEnabled",
      "prizeReminderPushTitle",
      "prizeReminderPushMessage",
      "prizeReminderEmailSubject",
      "prizeReminderEmailBody",
      "prizeReminderDelaysDays",
    ];
    const shouldUpdatePrizeReminder = prizeReminderKeys.some((key) =>
      Object.prototype.hasOwnProperty.call(data || {}, key),
    );
    if (shouldUpdatePrizeReminder) {
      const nextReminderConfig = normalizePrizeReminderConfig({
        ...currentNotificationsData,
        ...(data || {}),
      });
      notificationsPatch.prizeReminderEnabled = nextReminderConfig.prizeReminderEnabled;
      notificationsPatch.prizeReminderPushEnabled =
        nextReminderConfig.prizeReminderPushEnabled;
      notificationsPatch.prizeReminderEmailEnabled =
        nextReminderConfig.prizeReminderEmailEnabled;
      notificationsPatch.prizeReminderPushTitle =
        nextReminderConfig.prizeReminderPushTitle;
      notificationsPatch.prizeReminderPushMessage =
        nextReminderConfig.prizeReminderPushMessage;
      notificationsPatch.prizeReminderEmailSubject =
        nextReminderConfig.prizeReminderEmailSubject;
      notificationsPatch.prizeReminderEmailBody =
        nextReminderConfig.prizeReminderEmailBody;
      notificationsPatch.prizeReminderDelaysDays =
        nextReminderConfig.prizeReminderDelaysDays;
      notificationsPatch.prizeReminderUpdatedAt =
        admin.firestore.FieldValue.serverTimestamp();
      notificationsPatch.prizeReminderUpdatedBy = updatedBy;
    }

    const notificationsAutoPatch = {
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_by: updatedBy,
    };
    const autoKeys = [
      "game_ending_enabled",
      "game_ending_days_before",
      "game_ending_target_statuses",
      "game_ending_use_city_filter",
      "inactive_relaunch_enabled",
      "inactive_relaunch_frequency_days",
      "new_game_enabled",
      "new_game_target_statuses",
      "new_game_use_city_filter",
    ];
    const shouldUpdateAuto = autoKeys.some((key) =>
      Object.prototype.hasOwnProperty.call(data || {}, key),
    );
    if (Object.prototype.hasOwnProperty.call(data || {}, "game_ending_enabled")) {
      notificationsAutoPatch.game_ending_enabled = data.game_ending_enabled === true;
    }
    if (Object.prototype.hasOwnProperty.call(data || {}, "game_ending_days_before")) {
      const parsed = Number(data.game_ending_days_before);
      notificationsAutoPatch.game_ending_days_before = Number.isFinite(parsed)
        ? Math.max(1, Math.trunc(parsed))
        : 3;
    }
    if (
      Object.prototype.hasOwnProperty.call(data || {}, "game_ending_target_statuses")
    ) {
      notificationsAutoPatch.game_ending_target_statuses = Array.isArray(
        data.game_ending_target_statuses,
      )
        ? data.game_ending_target_statuses
        : ["actif", "a_relancer"];
    }
    if (
      Object.prototype.hasOwnProperty.call(data || {}, "game_ending_use_city_filter")
    ) {
      notificationsAutoPatch.game_ending_use_city_filter =
        data.game_ending_use_city_filter === true;
    }
    if (
      Object.prototype.hasOwnProperty.call(data || {}, "inactive_relaunch_enabled")
    ) {
      notificationsAutoPatch.inactive_relaunch_enabled =
        data.inactive_relaunch_enabled === true;
    }
    if (
      Object.prototype.hasOwnProperty.call(
        data || {},
        "inactive_relaunch_frequency_days",
      )
    ) {
      const parsed = Number(data.inactive_relaunch_frequency_days);
      notificationsAutoPatch.inactive_relaunch_frequency_days = Number.isFinite(parsed)
        ? Math.max(1, Math.trunc(parsed))
        : 7;
    }
    if (Object.prototype.hasOwnProperty.call(data || {}, "new_game_enabled")) {
      notificationsAutoPatch.new_game_enabled = data.new_game_enabled === true;
    }
    if (
      Object.prototype.hasOwnProperty.call(data || {}, "new_game_target_statuses")
    ) {
      notificationsAutoPatch.new_game_target_statuses = Array.isArray(
        data.new_game_target_statuses,
      )
        ? data.new_game_target_statuses
        : ["actif", "a_relancer"];
    }
    if (
      Object.prototype.hasOwnProperty.call(data || {}, "new_game_use_city_filter")
    ) {
      notificationsAutoPatch.new_game_use_city_filter =
        data.new_game_use_city_filter === true;
    }

    await getNotificationsConfigRef().set(notificationsPatch, {merge: true});
    if (shouldUpdateAuto) {
      await getNotificationsAutoConfigRef().set(notificationsAutoPatch, {merge: true});
    }

    return {
      ok: true,
      updatedBy,
    };
  });

const adminSendPrizeReminderPushTestCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);
    if (kPrizeReminderEmergencyDisabled === true) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        kPrizeReminderEmergencyDisabledReason,
      );
    }
    const config = normalizePrizeReminderConfig(
      await loadUnifiedNotificationsConfig(),
    );
    const winnerRefPath = `users/${context.auth.uid}`;
    const tokensSnap = await firestore
      .collection("users")
      .doc(context.auth.uid)
      .collection(kFcmTokensCollection)
      .limit(1)
      .get();
    if (tokensSnap.empty) {
      return {
        ok: false,
        message: "Aucun token FCM valide trouvé pour cet admin.",
      };
    }
    await queuePrizePushNotification({
      docId: `prize_reminder_test_push_${context.auth.uid}_${Date.now()}`,
      title: config.prizeReminderPushTitle,
      body: config.prizeReminderPushMessage,
      userRefPath: winnerRefPath,
      createdBy: `users/${context.auth.uid}`,
    });
    return {ok: true};
  });

const adminSendPrizeReminderEmailTestCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);
    if (kPrizeReminderEmergencyDisabled === true) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        kPrizeReminderEmergencyDisabledReason,
      );
    }
    const config = normalizePrizeReminderConfig(
      await loadUnifiedNotificationsConfig(),
    );
    const userRef = firestore.collection("users").doc(context.auth.uid);
    const userSnap = await userRef.get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const email = await resolveUserEmail(userRef, userData);
    if (!email) {
      return {
        ok: false,
        message: "Aucune adresse email valide trouvée pour cet admin.",
      };
    }
    const mailer = createSmtpMailer();
    await sendEmailNotification(
      mailer,
      email,
      config.prizeReminderEmailSubject,
      config.prizeReminderEmailBody,
    );
    return {ok: true};
  });

const adminRunPrizeReminderDryRunCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);
    const onlyPrizeIds = Array.isArray(data && data.onlyPrizeIds)
      ? data.onlyPrizeIds
      : [];
    const limit = data && data.limit;
    return runPrizeReminderJob({
      dryRun: true,
      onlyPrizeIds,
      limit,
      trigger: "admin_dry_run",
    });
  });

const adminRunPrizeReminderForPrizeTestCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);
    if (kPrizeReminderEmergencyDisabled === true) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        kPrizeReminderEmergencyDisabledReason,
      );
    }

    const prizeId = getTrimmedString(data && data.prizeId);
    if (!prizeId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "prizeId is required.",
      );
    }
    if (!data || data.dryRun !== false) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "This callable requires dryRun: false.",
      );
    }

    const unifiedConfig = await loadUnifiedNotificationsConfig();
    const prizeReminderConfig = normalizePrizeReminderConfig(unifiedConfig);
    if (prizeReminderConfig.prizeReminderEnabled !== true) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Prize reminder system is disabled in configuration.",
      );
    }

    const prizeRef = firestore.collection("prizes").doc(prizeId);
    const inspected = await inspectPrizeReminderTarget(
      prizeRef,
      normalizeReminderDelays(prizeReminderConfig.prizeReminderDelaysDays),
      Date.now(),
    );

    console.log(
      "[prize_reminders] admin_single_prize_test",
      JSON.stringify({
        prizeId,
        ok: inspected.ok === true,
        reason: inspected.reason || "",
        matchedDelay: inspected.matchedDelay || null,
        claimed: inspected.prizeData ? inspected.prizeData.claimed === true : null,
      }),
    );

    if (!inspected.ok) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        inspected.message || "Prize is not eligible for reminder test.",
      );
    }

    return runPrizeReminderJob({
      dryRun: false,
      onlyPrizeIds: [prizeId],
      limit: 1,
      trigger: "admin_single_prize_test",
    });
  });

const runPrizeRemindersDailyScheduled = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("0 10 * * *")
  .timeZone(kParisTimeZone)
  .onRun(async () => {
    console.log("runPrizeRemindersDaily started at 10:00 Europe/Paris");
    await runPrizeReminderJob({
      dryRun: false,
      trigger: "scheduled_daily",
    });
    return null;
  });

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

exports.incrementGameView = functions
  .region(kFunctionsRegion)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }

    const gameId = getTrimmedString(data && data.gameId);
    const screenName = getTrimmedString(data && data.screenName) || "unknown";
    const source = getTrimmedString(data && data.source) || "unknown";

    if (!gameId || gameId.includes("/")) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid gameId is required.",
      );
    }

    const gameRef = firestore.collection("games").doc(gameId);

    try {
      await gameRef.update({
        views: admin.firestore.FieldValue.increment(1),
      });
    } catch (error) {
      const message = getTrimmedString(error && error.message);
      if (message.toLowerCase().includes("no document to update")) {
        throw new functions.https.HttpsError(
          "not-found",
          "Game not found.",
        );
      }
      throw new functions.https.HttpsError(
        "internal",
        "Unable to increment game views.",
      );
    }

    // Keep structured logs so we can add rate-limiting / abuse detection later
    // without changing the client contract again.
    console.log(
      "[incrementGameView] success",
      JSON.stringify({
        gameId,
        uid: context.auth.uid,
        screenName,
        source,
      }),
    );

    return { success: true };
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

function normalizeSecondaryPrizeBackfillVariant(value) {
  return repairMojibakeText(getTrimmedString(value));
}

function extractSecondaryPrizeVariantsFromGame(gameData = {}) {
  if (!Array.isArray(gameData.secondary_prizes)) {
    return [];
  }

  const variants = [];
  gameData.secondary_prizes.forEach((entry) => {
    if (!entry || typeof entry !== "object") {
      return;
    }
    const name = normalizeSecondaryPrizeBackfillVariant(entry.name);
    const presentation = normalizeSecondaryPrizeBackfillVariant(
      entry.presentation || entry.description,
    );
    if (!name && !presentation) {
      return;
    }
    variants.push({name, presentation});
  });

  return variants;
}

function pickSingleSecondaryPrizeBackfillVariant(variants) {
  const normalizedVariants = [];
  const seen = new Set();

  (Array.isArray(variants) ? variants : []).forEach((variant) => {
    const normalized = {
      name: normalizeSecondaryPrizeBackfillVariant(variant && variant.name),
      presentation: normalizeSecondaryPrizeBackfillVariant(
        variant && variant.presentation,
      ),
    };
    if (!normalized.name && !normalized.presentation) {
      return;
    }
    const key = JSON.stringify(normalized);
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    normalizedVariants.push(normalized);
  });

  if (normalizedVariants.length !== 1) {
    return {
      ok: false,
      variants: normalizedVariants,
      reason:
        normalizedVariants.length === 0
          ? "missing_secondary_prize_source"
          : "multiple_secondary_prize_variants",
    };
  }

  return {
    ok: true,
    name: normalizedVariants[0].name || "Lot secondaire",
    presentation: normalizedVariants[0].presentation || "",
  };
}

function shouldBackfillWonSecondaryPrizeForGame({
  prizeData,
  expectedName,
  expectedPresentation,
}) {
  const currentName = normalizeSecondaryPrizeBackfillVariant(prizeData && prizeData.name);
  const currentDescription = normalizeSecondaryPrizeBackfillVariant(
    prizeData && prizeData.description,
  );

  if (
    currentName === expectedName &&
    currentDescription === expectedPresentation
  ) {
    return {
      shouldUpdate: false,
      reason: "already_up_to_date",
      patch: {},
    };
  }

  const nameLooksWrong =
    !currentName ||
    currentName === currentDescription ||
    (!!expectedPresentation && currentName === expectedPresentation);

  if (!nameLooksWrong) {
    return {
      shouldUpdate: false,
      reason: "ambiguous_existing_name",
      patch: {},
    };
  }

  const patch = {};
  if (expectedName && currentName !== expectedName) {
    patch.name = expectedName;
  }
  if (!currentDescription && expectedPresentation) {
    patch.description = expectedPresentation;
  }

  return {
    shouldUpdate: Object.keys(patch).length > 0,
    reason: Object.keys(patch).length > 0 ? "fallback_name_detected" : "no_patch_needed",
    patch,
  };
}

const adminBackfillWonSecondaryPrizesForGameCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Unauthenticated calls are not allowed.",
      );
    }
    await assertIsAdmin(context.auth.uid);

    const gameId = getTrimmedString(data && data.gameId);
    const dryRun = toBoolean(data && data.dryRun, true);

    if (!gameId || gameId.includes("/")) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid gameId is required.",
      );
    }

    const gameRef = firestore.collection("games").doc(gameId);
    const [gameSnap, prizesSnap, instantWinnersSnap] = await Promise.all([
      gameRef.get(),
      firestore.collection("prizes").where("game_id", "==", gameRef).get(),
      gameRef.collection("instant_winners").get(),
    ]);

    if (!gameSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Game not found.",
      );
    }

    const gameData = gameSnap.data() || {};
    const variants = [
      ...instantWinnersSnap.docs.map((doc) => {
        const instantWinnerData = doc.data() || {};
        return {
          name: instantWinnerData.secondary_prize_name,
          presentation: instantWinnerData.secondary_prize_presentation,
        };
      }),
      ...extractSecondaryPrizeVariantsFromGame(gameData),
    ];
    const source = pickSingleSecondaryPrizeBackfillVariant(variants);

    if (!source.ok) {
      return {
        ok: false,
        dryRun,
        gameId,
        reason: source.reason,
        variants: source.variants || [],
        message:
          source.reason === "multiple_secondary_prize_variants"
            ? "Multiple secondary prize variants found for this game; aborting to avoid incorrect rewrites."
            : "No reliable secondary prize source found for this game.",
      };
    }

    const summary = {
      ok: true,
      dryRun,
      gameId,
      expectedName: source.name,
      expectedPresentation: source.presentation,
      scannedPrizes: prizesSnap.size,
      scannedSecondaryPrizes: 0,
      updatablePrizes: 0,
      updatedPrizes: 0,
      skippedAlreadyUpToDate: 0,
      skippedAmbiguous: 0,
      skippedOtherPrizeTypes: 0,
      updatedPrizeIds: [],
      ambiguousPrizeIds: [],
    };

    let batch = firestore.batch();
    let batchOps = 0;
    const commitBatchIfNeeded = async (force = false) => {
      if (batchOps === 0) {
        return;
      }
      if (!force && batchOps < 400) {
        return;
      }
      await batch.commit();
      batch = firestore.batch();
      batchOps = 0;
    };

    for (const prizeDoc of prizesSnap.docs) {
      const prizeData = prizeDoc.data() || {};
      if (getTrimmedString(prizeData.prize_type).toLowerCase() !== "secondaire") {
        summary.skippedOtherPrizeTypes += 1;
        continue;
      }

      summary.scannedSecondaryPrizes += 1;
      const decision = shouldBackfillWonSecondaryPrizeForGame({
        prizeData,
        expectedName: source.name,
        expectedPresentation: source.presentation,
      });

      if (!decision.shouldUpdate) {
        if (decision.reason === "already_up_to_date") {
          summary.skippedAlreadyUpToDate += 1;
        } else if (decision.reason === "ambiguous_existing_name") {
          summary.skippedAmbiguous += 1;
          if (summary.ambiguousPrizeIds.length < 25) {
            summary.ambiguousPrizeIds.push(prizeDoc.id);
          }
        }
        continue;
      }

      summary.updatablePrizes += 1;
      if (summary.updatedPrizeIds.length < 50) {
        summary.updatedPrizeIds.push(prizeDoc.id);
      }

      if (!dryRun) {
        batch.update(prizeDoc.ref, decision.patch);
        batchOps += 1;
        summary.updatedPrizes += 1;
        await commitBatchIfNeeded(false);
      }
    }

    if (!dryRun) {
      await commitBatchIfNeeded(true);
    }

    console.log(
      "[adminBackfillWonSecondaryPrizesForGame]",
      JSON.stringify(summary),
    );

    return summary;
  });
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
      ...buildPushNotificationRequestData({
        title,
        body,
        imageUrl,
        targetAudience: targetDevice, // existing field (device_type)
        targetUserGroup, // new field (role targeting)
        userRefs: userRefs.length ? userRefs.join(",") : "",
        createdBy: `users/${context.auth.uid}`,
      }),
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

exports.dedupeRapidDuplicateGames = functions.firestore
  .document("games/{gameId}")
  .onCreate(async (snapshot, context) => {
    const gameId = context.params.gameId;
    const initialData = snapshot.data() || {};
    const initialSignature = buildGameDedupeSignature(initialData, snapshot);
    const reviewRef = firestore.collection(kGameDedupeReviewsCollection).doc(gameId);

    if (!initialSignature) {
      await reviewRef.set(
        {
          status: "skipped_missing_fields",
          game_id: gameId,
          reason: "rapid_duplicate_create",
          checked_at: admin.firestore.FieldValue.serverTimestamp(),
          note: "Missing reliable fields for strict dedupe.",
        },
        { merge: true },
      );
      console.log(
        `[GAME_DEDUPE] game=${gameId} skipped reason=missing_fields`,
      );
      return null;
    }

    const result = await firestore.runTransaction(async (transaction) => {
      const currentReviewSnap = await transaction.get(reviewRef);
      if (currentReviewSnap.exists) {
        const currentReview = currentReviewSnap.data() || {};
        const status = getTrimmedString(currentReview.status);
        if (status) {
          return { outcome: "already_processed", status };
        }
      }

      const currentGameSnap = await transaction.get(snapshot.ref);
      if (!currentGameSnap.exists) {
        transaction.set(
          reviewRef,
          {
            status: "skipped_missing_game",
            game_id: gameId,
            reason: "rapid_duplicate_create",
            checked_at: admin.firestore.FieldValue.serverTimestamp(),
            note: "Game document no longer exists when dedupe ran.",
          },
          { merge: true },
        );
        return { outcome: "missing_game" };
      }

      const currentGameData = currentGameSnap.data() || {};
      const currentSignature = buildGameDedupeSignature(
        currentGameData,
        currentGameSnap,
      );

      if (!currentSignature) {
        transaction.set(
          reviewRef,
          {
            status: "skipped_missing_fields",
            game_id: gameId,
            reason: "rapid_duplicate_create",
            checked_at: admin.firestore.FieldValue.serverTimestamp(),
            note: "Reliable fields missing after fresh read.",
          },
          { merge: true },
        );
        return { outcome: "missing_fields_after_read" };
      }

      const groupRef = firestore
        .collection(kGameDedupeGroupsCollection)
        .doc(currentSignature.fingerprint);
      const groupSnap = await transaction.get(groupRef);
      const groupData = groupSnap.exists ? groupSnap.data() || {} : {};
      const existingPrimaryGameId = getTrimmedString(groupData.primary_game_id);
      const existingPrimaryCreatedMs = Number.isFinite(groupData.primary_created_ms)
        ? Number(groupData.primary_created_ms)
        : null;

      const setGroupPrimary = () => {
        transaction.set(
          groupRef,
          {
            fingerprint: currentSignature.fingerprint,
            primary_game_id: gameId,
            primary_created_ms: currentSignature.createdMs,
            window_ms: kGameDedupeWindowMs,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            last_seen_game_id: gameId,
            last_seen_created_ms: currentSignature.createdMs,
          },
          { merge: true },
        );
      };

      const setCurrentPrimaryReview = (note = "") => {
        transaction.set(
          reviewRef,
          buildGameDedupeReviewPayload({
            status: "primary",
            gameId,
            fingerprint: currentSignature.fingerprint,
            signaturePayload: currentSignature.payload,
            createdMs: currentSignature.createdMs,
            primaryGameId: gameId,
            reason: "rapid_duplicate_create",
            autoDeleted: false,
            deleteAttempted: false,
            note,
          }),
          { merge: true },
        );
      };

      if (!existingPrimaryGameId || !Number.isFinite(existingPrimaryCreatedMs)) {
        setCurrentPrimaryReview("Initialized new dedupe cluster.");
        setGroupPrimary();
        return {
          outcome: "primary_new_cluster",
          primaryGameId: gameId,
        };
      }

      if (existingPrimaryGameId === gameId) {
        setCurrentPrimaryReview("Recovered missing review for existing primary.");
        setGroupPrimary();
        return {
          outcome: "primary_recovered",
          primaryGameId: gameId,
        };
      }

      const deltaMs = currentSignature.createdMs - existingPrimaryCreatedMs;
      const withinWindow = Math.abs(deltaMs) <= kGameDedupeWindowMs;

      if (!withinWindow) {
        if (deltaMs > kGameDedupeWindowMs) {
          setCurrentPrimaryReview("Started a new cluster outside dedupe window.");
          setGroupPrimary();
          return {
            outcome: "primary_new_cluster",
            primaryGameId: gameId,
          };
        }

        transaction.set(
          reviewRef,
          buildGameDedupeReviewPayload({
            status: "skipped_out_of_window",
            gameId,
            fingerprint: currentSignature.fingerprint,
            signaturePayload: currentSignature.payload,
            createdMs: currentSignature.createdMs,
            primaryGameId: gameId,
            reason: "rapid_duplicate_create",
            autoDeleted: false,
            deleteAttempted: false,
            note: "Older event arrived outside the active dedupe window.",
          }),
          { merge: true },
        );
        return {
          outcome: "skipped_out_of_window",
        };
      }

      const existingPrimaryRef = firestore.collection("games").doc(existingPrimaryGameId);
      const existingPrimaryGameSnap = await transaction.get(existingPrimaryRef);
      if (!existingPrimaryGameSnap.exists) {
        setCurrentPrimaryReview("Replaced a stale dedupe cluster with current game.");
        setGroupPrimary();
        return {
          outcome: "primary_replaced_stale_cluster",
          primaryGameId: gameId,
        };
      }

      const existingPrimarySignature = buildGameDedupeSignature(
        existingPrimaryGameSnap.data() || {},
        existingPrimaryGameSnap,
      );
      if (
        !existingPrimarySignature ||
        existingPrimarySignature.fingerprint !== currentSignature.fingerprint
      ) {
        setCurrentPrimaryReview("Replaced a mismatched dedupe cluster with current game.");
        setGroupPrimary();
        return {
          outcome: "primary_replaced_mismatched_cluster",
          primaryGameId: gameId,
        };
      }

      const primaryComparison = comparePrimaryCandidate(
        { createdMs: currentSignature.createdMs, gameId },
        {
          createdMs: existingPrimaryCreatedMs,
          gameId: existingPrimaryGameId,
        },
      );

      if (primaryComparison < 0) {
        const previousPrimaryRef = firestore.collection("games").doc(existingPrimaryGameId);
        const previousPrimaryReviewRef = firestore
          .collection(kGameDedupeReviewsCollection)
          .doc(existingPrimaryGameId);
        const previousPrimaryGameSnap = await transaction.get(previousPrimaryRef);

        let previousDeleted = false;
        if (previousPrimaryGameSnap.exists) {
          const previousPrimaryData = previousPrimaryGameSnap.data() || {};
          const previousPrimarySignature = buildGameDedupeSignature(
            previousPrimaryData,
            previousPrimaryGameSnap,
          );
          const sameFingerprint =
            previousPrimarySignature &&
            previousPrimarySignature.fingerprint === currentSignature.fingerprint;
          const shouldDeletePrevious =
            sameFingerprint && shouldAutoDeleteDuplicateGame(previousPrimaryData);

          transaction.set(
            previousPrimaryReviewRef,
            buildGameDedupeReviewPayload({
              status: "duplicate",
              gameId: existingPrimaryGameId,
              fingerprint: currentSignature.fingerprint,
              signaturePayload: previousPrimarySignature
                ? previousPrimarySignature.payload
                : currentSignature.payload,
              createdMs: previousPrimarySignature
                ? previousPrimarySignature.createdMs
                : existingPrimaryCreatedMs,
              primaryGameId: gameId,
              reason: "rapid_duplicate_create",
              autoDeleted: shouldDeletePrevious,
              deleteAttempted: shouldDeletePrevious,
              note: "Demoted because an older equivalent game was created in the same short window.",
            }),
            { merge: true },
          );

          if (shouldDeletePrevious) {
            transaction.delete(previousPrimaryRef);
            previousDeleted = true;
          }
        } else {
          transaction.set(
            previousPrimaryReviewRef,
            {
              status: "duplicate",
              game_id: existingPrimaryGameId,
              primary_game_id: gameId,
              fingerprint: currentSignature.fingerprint,
              reason: "rapid_duplicate_create",
              checked_at: admin.firestore.FieldValue.serverTimestamp(),
              note: "Previous primary was already missing when current older game won.",
            },
            { merge: true },
          );
        }

        setCurrentPrimaryReview("Promoted to primary inside dedupe window.");
        setGroupPrimary();

        return {
          outcome: "primary_promoted",
          primaryGameId: gameId,
          deletedDuplicateGameId: previousDeleted ? existingPrimaryGameId : "",
        };
      }

      const shouldDeleteCurrent = shouldAutoDeleteDuplicateGame(currentGameData);
      transaction.set(
        reviewRef,
        buildGameDedupeReviewPayload({
          status: "duplicate",
          gameId,
          fingerprint: currentSignature.fingerprint,
          signaturePayload: currentSignature.payload,
          createdMs: currentSignature.createdMs,
          primaryGameId: existingPrimaryGameId,
          reason: "rapid_duplicate_create",
          autoDeleted: shouldDeleteCurrent,
          deleteAttempted: shouldDeleteCurrent,
          note: "Equivalent game created too quickly after the primary game.",
        }),
        { merge: true },
      );
      transaction.set(
        groupRef,
        {
          fingerprint: currentSignature.fingerprint,
          primary_game_id: existingPrimaryGameId,
          primary_created_ms: existingPrimaryCreatedMs,
          window_ms: kGameDedupeWindowMs,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          last_seen_game_id: gameId,
          last_seen_created_ms: currentSignature.createdMs,
        },
        { merge: true },
      );

      if (shouldDeleteCurrent) {
        transaction.delete(snapshot.ref);
      }

      return {
        outcome: "duplicate",
        primaryGameId: existingPrimaryGameId,
        deletedDuplicateGameId: shouldDeleteCurrent ? gameId : "",
      };
    });

    console.log(
      `[GAME_DEDUPE] game=${gameId} outcome=${result.outcome || "unknown"} primary=${result.primaryGameId || ""} deleted=${result.deletedDuplicateGameId || ""}`,
    );
    return null;
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

/**
 * Notification "Nouveau jeu disponible" - Étape 4
 * - Déclenché quand visible_public passe de false â†’ true
 * - Cible joueurs éligibles: statut actif/a_relancer, optionnellement par ville
 * - Anti-doublon: vérification dans users/{uid}/notifications/by_game/{gameId} AVANT envoi
 * - Réutilise ff_push_notifications + sendPushNotificationsTrigger
 */
exports.notifyNewGameAvailableToAllEligible = functions
  .runWith(kPushNotificationRuntimeOpts)
  .firestore.document("games/{gameId}")
  .onWrite(async (change, context) => {
    const gameId = context.params.gameId;
    const beforeExists = change.before.exists;
    const afterExists = change.after.exists;

    if (!afterExists) {
      return null; // Jeu supprimé
    }

    // Vérifier la TRANSITION: false â†’ true (pas l'état seul)
    const beforeData = beforeExists ? change.before.data() || {} : {};
    const afterData = change.after.data() || {};
    const wasPublished = beforeExists ? isPublishedGame(beforeData) : false;
    const isNowPublished = isPublishedGame(afterData);

    if (!isNowPublished || wasPublished) {
      return null; // Pas une transition de publication
    }

    console.log(
      `[notifyNewGameAvailableToAllEligible] game=${gameId} transition detected`
    );

    try {
      // Lire config admin
      const configRef = firestore.collection("app_config").doc("notifications_auto");
      const configSnap = await configRef.get();
      const configData = configSnap.exists ? configSnap.data() || {} : {};
      const newGameEnabled = configData.new_game_enabled === true;
      const targetStatuses = Array.isArray(configData.new_game_target_statuses)
        ? configData.new_game_target_statuses
        : ["actif", "a_relancer"];
      const useCityFilter = configData.new_game_use_city_filter === true;

      console.log(
        `[notifyNewGameAvailableToAllEligible] config enabled=${newGameEnabled} useCity=${useCityFilter}`
      );

      if (!newGameEnabled) {
        console.log(
          `[notifyNewGameAvailableToAllEligible] disabled in config, skipping`
        );
        return null;
      }

      // Récupérer infos du jeu et du commerce
      const gameData = afterData;
      const gameName = getTrimmedString(gameData.name) || "un nouveau jeu";
      const enseigneRef = toDocRef(gameData.enseigne_id);
      const enseigneName = getTrimmedString(gameData.enseigne_name) || "un commerce";
      let enseigneCity = null;

      if (useCityFilter && enseigneRef) {
        const enseigneSnap = await enseigneRef.get();
        if (enseigneSnap.exists) {
          enseigneCity = getTrimmedString(enseigneSnap.data().city);
        }
      }

      // Requête joueurs éligibles
      let usersQuery = firestore
        .collection("users")
        .where("user_role", "==", "joueur")
        .where("player_status_cached", "in", targetStatuses);

      if (useCityFilter && enseigneCity) {
        usersQuery = usersQuery.where("city", "==", enseigneCity);
      }

      const usersSnap = await usersQuery.get();
      console.log(
        `[notifyNewGameAvailableToAllEligible] found ${usersSnap.size} eligible users (city=${enseigneCity})`
      );

      let sent = 0;
      let skippedDuplicate = 0;
      let skippedNoToken = 0;
      let errors = 0;

      // Traiter chaque joueur
      for (const userDoc of usersSnap.docs) {
        const userData = userDoc.data() || {};
        const uid = userData.uid || userDoc.id;
        const userCity = userData.city || "";

        try {
          // ===== ANTI-DOUBLON AVANT ENVOI =====
          const existingNotifRef = firestore
            .doc(`users/${uid}/notifications`)
            .collection("by_game")
            .doc(gameId);
          const existingSnap = await existingNotifRef.get();

          if (existingSnap.exists) {
            console.log(
              `[notifyNewGameAvailableToAllEligible] uid=${uid} game=${gameId} already notified, skipping`
            );
            skippedDuplicate++;
            continue;
          }

          // Vérifier qu'il a au moins un token FCM
          const tokensSnap = await firestore
            .doc(`users/${uid}`)
            .collection(kFcmTokensCollection)
            .get();

          if (tokensSnap.empty) {
            skippedNoToken++;
            continue;
          }

          // ===== CRÉER NOTIFICATION via FF_PUSH_NOTIFICATIONS =====
          const notificationBody = enseigneCity
            ? `${enseigneName} a publi\u00E9 ${gameName} pr\u00E8s de chez vous.`
            : `${enseigneName} a publi\u00E9 ${gameName}.`;

          const notificationRef = firestore
            .collection("ff_push_notifications")
            .doc(`new_game_${gameId}_${uid}_${Date.now()}`);

          await notificationRef.set(
            buildPushNotificationRequestData({
              title: "Nouveau jeu disponible \u{1F389}",
              body: notificationBody,
              parameterData: "", // Pourrait être JSON avec deeplink au jeu
              userRefs: `users/${uid}`,
              createdBy: "system/new_game_available",
            }),
          );

          // ===== CRÉER LOG ANTI-DOUBLON =====
          await existingNotifRef.set({
            type: "new_game_available",
            game_id: gameId,
            game_name: gameName,
            enseigne_id: gameData.enseigne_id ? gameData.enseigne_id.path : "",
            enseigne_name: enseigneName,
            notification_title: "Nouveau jeu disponible \u{1F389}",
            notification_text: notificationBody,
            player_status: userData.player_status_cached || "unknown",
            city_filtered: useCityFilter,
            user_city: userCity,
            enseigne_city: enseigneCity || "",
            sent_at: admin.firestore.FieldValue.serverTimestamp(),
            viewed: false,
          });

          sent++;
          console.log(
            `[notifyNewGameAvailableToAllEligible] uid=${uid} notified for game=${gameId}`
          );
        } catch (e) {
          errors++;
          console.error(
            `[notifyNewGameAvailableToAllEligible] uid=${uid} error=${e.message || e}`
          );
        }
      }

      console.log(
        `[notifyNewGameAvailableToAllEligible] game=${gameId} sent=${sent} skippedDuplicate=${skippedDuplicate} skippedNoToken=${skippedNoToken} errors=${errors}`
      );

      return null;
    } catch (e) {
      console.error(
        `[notifyNewGameAvailableToAllEligible] critical error=${e.message || e}`
      );
      throw e;
    }
  });

async function sendPushNotifications(snapshot) {
  if (isFunctionsEmulator()) {
    console.log(`[LOCAL_FIREBASE_EMULATORS] FCM suppressed notification=${snapshot.id}`);
    await snapshot.ref.update({
      status: "suppressed_local",
      num_sent: 0,
      error: "FCM disabled in Firebase Functions Emulator",
    });
    return;
  }
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
  let numFailed = 0;
  let invalidTokensDeleted = 0;
  const aggregatedErrorCodeCounts = new Map();
  const aggregatedSampleErrors = [];
  await Promise.all(
    messageBatches.map(async (messages) => {
      const response = await admin.messaging().sendEachForMulticast(messages);
      numSent += response.successCount;
      if (response.failureCount > 0) {
        numFailed += response.failureCount;
        const failureSummary = summarizePushFailures(response.responses);
        Object.entries(failureSummary.errorCodeCounts).forEach(([code, count]) => {
          aggregatedErrorCodeCounts.set(
            code,
            (aggregatedErrorCodeCounts.get(code) || 0) + count,
          );
        });
        failureSummary.sampleErrors.forEach((entry) => {
          if (aggregatedSampleErrors.length < 10) {
            aggregatedSampleErrors.push(entry);
          }
        });
        if (failureSummary.topErrorCodes.length) {
          console.log(
            `Push send errors for ${snapshot.id}: failures=${response.failureCount}, codes=${failureSummary.topErrorCodes.join(", ")}`,
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

  const sortedAggregatedErrorEntries = Array.from(
    aggregatedErrorCodeCounts.entries(),
  ).sort((a, b) => {
    if (b[1] !== a[1]) {
      return b[1] - a[1];
    }
    return a[0].localeCompare(b[0]);
  });
  const hasFailures = numFailed > 0;
  const finalStatus = hasFailures
    ? numSent > 0
      ? "partial_failed"
      : "failed"
    : "succeeded";
  const updatePayload = {
    status: finalStatus,
    num_sent: numSent,
    num_failed: numFailed,
    attempted_tokens: tokensArr.length,
    invalid_tokens_deleted: invalidTokensDeleted,
    error_codes: sortedAggregatedErrorEntries.map(([code]) => code),
    error_code_counts: Object.fromEntries(sortedAggregatedErrorEntries),
    sample_errors: aggregatedSampleErrors,
  };
  if (hasFailures) {
    const topSummary = sortedAggregatedErrorEntries
      .slice(0, 5)
      .map(([code, count]) => `${code} (${count})`)
      .join(", ");
    updatePayload.error = topSummary || "push_delivery_failed";
    console.log(
      `Push send completed with failures for ${snapshot.id}: status=${finalStatus}, sent=${numSent}, failed=${numFailed}, invalidTokensDeleted=${invalidTokensDeleted}, summary=${updatePayload.error}`,
    );
  }

  await snapshot.ref.update({
    ...updatePayload,
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
    let merchantEmailDone = isChannelDone(
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
    const winnerFirstName = repairMojibakeText(winnerName.firstName || "Joueur");
    const winnerLastName = repairMojibakeText(winnerName.lastName || "");
    const winnerFullName = [winnerFirstName, winnerLastName]
      .filter((v) => v)
      .join(" ");
    const winnerCity = repairMojibakeText(
      getTrimmedString(winnerData.city) || "ville inconnue",
    );
    const merchantName = repairMojibakeText(buildMerchantName(ownerData));
    const gameName = repairMojibakeText(
      getTrimmedString(gameData.name) || "Jeu ProxiPlay",
    );
    const prizeName = repairMojibakeText(
      getTrimmedString(prizeData.name) || "Lot gagn\u00E9",
    );
    const claimCode = getTrimmedString(prizeData.claim_code) || "N/A";
    const shopName = repairMojibakeText(
      getTrimmedString(prizeData.enseigne_name) ||
        getTrimmedString(enseigneData.name) ||
        "votre enseigne",
    );
    const shopLink = buildShopLink(enseigneData);

    const merchantEmailSubject = "🎉 Un joueur a gagné dans votre commerce !";
    const merchantEmailBody = [
      `Bonjour ${merchantName},`,
      `${winnerFirstName} de ${winnerCity} a remport\u00E9 ${prizeName} sur ProxiPlay :`,
      `Code \u00E0 v\u00E9rifier : ${claimCode}`,
      "Le gagnant devra pr\u00E9senter ce code en boutique pour validation.",
      "Merci de participer \u00E0 la dynamisation du commerce local !",
      "L\u2019\u00E9quipe ProxiPlay",
    ].join("\n");

    const playerEmailSubject = `Bravo ${winnerFirstName}, vous avez gagn\u00E9 !`;
    const playerEmailBody = [
      `Bonjour ${winnerFirstName},`,
      `F\u00E9licitations, vous avez remport\u00E9 ${prizeName} offert par ${shopName}`,
      `Votre code \u00E0 pr\u00E9senter en boutique : ${claimCode}`,
      `Retrouvez la boutique ici : ${shopLink}`,
      "Continuez \u00E0 jouer chaque jour pour multiplier vos chances !",
      "\u00C0 tr\u00E8s vite sur ProxiPlay",
    ].join("\n");

    const playerPushTitle = "Vous avez gagn\u00E9 !";
    const playerPushBody = `Vous avez gagn\u00E9 ${prizeName} chez ${shopName}\nCode : ${claimCode}`;
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
      logPrizeEmailAudit({
        prizeId,
        gameId: gameRef ? gameRef.id : "",
        winnerRef,
        winnerUserId: getUserUidFromRef(winnerRef),
        resolvedEmail: playerEmail,
        resolvedUserId: getUserUidFromRef(winnerRef),
        sourceFunction: "notifyPrizeWon:resolvePlayerEmail",
      });
      const playerEmailRecipientCheck = await validatePrizeEmailRecipient({
        prizeRef: snapshot.ref,
        prizeId,
        winnerRef,
        resolvedEmail: playerEmail,
        resolvedUserId: getUserUidFromRef(winnerRef),
        sourceFunction: "notifyPrizeWon:playerEmail",
      });
      if (!playerEmail) {
        updates.player_email_skipped = true;
        updates.player_email_skip_reason = "missing_player_email";
      } else if (!playerEmailRecipientCheck.ok) {
        updates.player_email_skipped = true;
        updates.player_email_skip_reason =
          playerEmailRecipientCheck.reason || "recipient_guard_blocked";
      } else if (kPrizeEmailEmergencyDisabled === true) {
        console.log("[PRIZE_EMAIL_CONTENT_CHECK]", {
          prizeId,
          winnerId: winnerRef && winnerRef.id ? winnerRef.id : null,
          claimCode: prizeData.claim_code,
          prizeNameFromDB: prizeData.name,
          emailPrizeNameUsed: prizeName,
          emailGameNameUsed: gameName,
          sourceFunction: "notifyPrizeWon:playerEmail",
        });
        updates.player_email_skipped = true;
        updates.player_email_skip_reason = "emergency_disabled";
        console.log(
          `[notifyPrizeWon] prize=${prizeId} player_email_disabled reason=${kPrizeEmailEmergencyDisabledReason}`,
        );
      } else {
        try {
          console.log("[PRIZE_EMAIL_CONTENT_CHECK]", {
            prizeId,
            winnerId: winnerRef && winnerRef.id ? winnerRef.id : null,
            claimCode: prizeData.claim_code,
            prizeNameFromDB: prizeData.name,
            emailPrizeNameUsed: prizeName,
            emailGameNameUsed: gameName,
            sourceFunction: "notifyPrizeWon:playerEmail",
          });
          await sendEmailNotification(
            getMailer(),
            playerEmail,
            playerEmailSubject,
            playerEmailBody,
          );
          logPrizeEmailAudit({
            prizeId,
            gameId: gameRef ? gameRef.id : "",
            winnerRef,
            winnerUserId: getUserUidFromRef(winnerRef),
            resolvedEmail: playerEmail,
            resolvedUserId: getUserUidFromRef(winnerRef),
            sourceFunction: "notifyPrizeWon:sendPlayerEmail",
          });
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
      const lockResult = await acquireMerchantEmailSendRight(statusRef);
      if (!lockResult.acquired) {
        console.log(
          `[notifyPrizeWon] prize=${prizeId} merchant_email send skipped reason=${lockResult.reason}`,
        );
        updates.merchant_email_skipped = true;
        updates.merchant_email_skip_reason = `skipped_${lockResult.reason}`;
      } else {
        const merchantEmail = await resolveUserEmail(ownerRef, ownerData);
        logPrizeEmailAudit({
          prizeId,
          gameId: gameRef ? gameRef.id : "",
          winnerRef,
          winnerUserId: getUserUidFromRef(winnerRef),
          resolvedEmail: merchantEmail,
          resolvedUserId: getUserUidFromRef(ownerRef),
          sourceFunction: "notifyPrizeWon:resolveMerchantEmail",
        });
        const merchantEmailRecipientCheck = await validatePrizeEmailMerchantRecipient({
          prizeId,
          ownerRef,
          enseigneRef,
          enseigneData,
          gameRef,
          gameData,
          resolvedEmail: merchantEmail,
          resolvedUserId: getUserUidFromRef(ownerRef),
          sourceFunction: "notifyPrizeWon:merchantEmail",
        });
        if (!merchantEmail) {
          updates.merchant_email_skipped = true;
          updates.merchant_email_skip_reason = "missing_merchant_email";
          await markMerchantEmailFailed(statusRef, "missing_merchant_email");
        } else if (!merchantEmailRecipientCheck.ok) {
          updates.merchant_email_skipped = true;
          updates.merchant_email_skip_reason =
            merchantEmailRecipientCheck.reason || "recipient_guard_blocked";
          await markMerchantEmailFailed(
            statusRef,
            updates.merchant_email_skip_reason,
          );
        } else if (kPrizeEmailEmergencyDisabled === true) {
          console.log("[PRIZE_EMAIL_CONTENT_CHECK]", {
            prizeId,
            winnerId: winnerRef && winnerRef.id ? winnerRef.id : null,
            claimCode: prizeData.claim_code,
            prizeNameFromDB: prizeData.name,
            emailPrizeNameUsed: prizeName,
            emailGameNameUsed: gameName,
            sourceFunction: "notifyPrizeWon:merchantEmail",
          });
          updates.merchant_email_skipped = true;
          updates.merchant_email_skip_reason = "emergency_disabled";
          console.log(
            `[notifyPrizeWon] prize=${prizeId} merchant_email_disabled reason=${kPrizeEmailEmergencyDisabledReason}`,
          );
          await markMerchantEmailFailed(statusRef, "emergency_disabled");
        } else {
          try {
            console.log("[PRIZE_EMAIL_CONTENT_CHECK]", {
              prizeId,
              winnerId: winnerRef && winnerRef.id ? winnerRef.id : null,
              claimCode: prizeData.claim_code,
              prizeNameFromDB: prizeData.name,
              emailPrizeNameUsed: prizeName,
              emailGameNameUsed: gameName,
              sourceFunction: "notifyPrizeWon:merchantEmail",
            });
            await sendEmailNotification(
              getMailer(),
              merchantEmail,
              merchantEmailSubject,
              merchantEmailBody,
            );
            await markMerchantEmailSent(statusRef);
            logPrizeEmailAudit({
              prizeId,
              gameId: gameRef ? gameRef.id : "",
              winnerRef,
              winnerUserId: getUserUidFromRef(winnerRef),
              resolvedEmail: merchantEmail,
              resolvedUserId: getUserUidFromRef(ownerRef),
              sourceFunction: "notifyPrizeWon:sendMerchantEmail",
            });
            updates.merchant_email_sent = true;
            updates.merchant_email_skipped = admin.firestore.FieldValue.delete();
            updates.merchant_email_skip_reason = admin.firestore.FieldValue.delete();
          } catch (e) {
            errors.push(`merchant_email: ${e.message || e}`);
            updates.merchant_email_sent = false;
            await markMerchantEmailFailed(statusRef, e);
          }
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

exports._testHelpers = {
  acquireMerchantEmailSendRight,
  markMerchantEmailSent,
  markMerchantEmailFailed,
};

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
    try {
      // Lire config
      const configRef = firestore.collection("app_config").doc("notifications_auto");
      const configSnap = await configRef.get();
      const config = configSnap.exists ? configSnap.data() || {} : {};
      const enabled = config.game_ending_enabled === true;
      const daysBefore = config.game_ending_days_before || 3;

      console.log(
        `[followedGameEndingSoon] start enabled=${enabled} daysBefore=${daysBefore}`
      );

      if (!enabled) {
        console.log(`[followedGameEndingSoon] disabled in config, skipping`);
        return null;
      }

      const now = new Date();
      const { start, end } = getTimeZoneDayBounds(now, kParisTimeZone, daysBefore);
      const startTimestamp = admin.firestore.Timestamp.fromDate(start);
      const endTimestamp = admin.firestore.Timestamp.fromDate(end);

      console.log(
        `[followedGameEndingSoon] windowStart=${start.toISOString()} windowEnd=${end.toISOString()}`
      );

      // Chercher jeux qui finissent dans la fenêtre J+X
      const gamesSnap = await firestore
        .collection("games")
        .where("end_date", ">=", startTimestamp)
        .where("end_date", "<", endTimestamp)
        .get();

      console.log(`[followedGameEndingSoon] found ${gamesSnap.size} games`);

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
          await queueFollowedGameEndingSoonNotifications(gameDoc, config);
        } catch (error) {
          console.error(
            `[followedGameEndingSoon] game=${gameDoc.id} error=${error.message || error}`
          );
        }
      }

      console.log(
        `[followedGameEndingSoon] completed matched=${gamesSnap.size} processed=${processed} skippedUnpublished=${skippedUnpublished}`
      );
      return null;
    } catch (e) {
      console.error(
        `[followedGameEndingSoon] critical error=${e.message || e}`
      );
      throw e;
    }
  });

/**
 * Relance des joueurs inactifs (V1 SIMPLE)
 * - Runs quotidiennement à 10h (Europe/Paris)
 * - Lit config depuis app_config/notifications_auto
 * - Filtre users avec player_status_cached in [a_relancer, dormant, mort_probable]
 * - Anti-spam: max 1 relance par N jours (configurable)
 * - Crée notifications individuelles (hardcodées par status)
 * - Met à jour last_inactive_relaunch_at sur utilisateur
 */
exports.relaunInactivePlayersByStatus = functions
  .runWith(kPushNotificationRuntimeOpts)
  .pubsub.schedule("0 10 * * *")
  .timeZone(kParisTimeZone)
  .onRun(async () => {
    const startTime = Date.now();
    let relaunched = 0;
    let skippedAntiSpam = 0;
    let errors = 0;

    try {
      // Lire configuration
      const configRef = firestore.collection("app_config").doc("notifications_auto");
      const configSnap = await configRef.get();
      const configData = configSnap.exists ? configSnap.data() || {} : {};
      const enabled = configData.inactive_relaunch_enabled === true;
      const frequencyDays = configData.inactive_relaunch_frequency_days || 7;

      console.log(
        `[relaunInactivePlayersByStatus] start enabled=${enabled} frequencyDays=${frequencyDays}`,
      );

      if (!enabled) {
        console.log(`[relaunInactivePlayersByStatus] disabled, skipping`);
        return null;
      }

      // Requête: users avec statuts inactifs
      const usersSnap = await firestore
        .collection("users")
        .where("user_role", "==", "joueur")
        .where("player_status_cached", "in", ["a_relancer", "dormant", "mort_probable"])
        .get();

      console.log(
        `[relaunInactivePlayersByStatus] found ${usersSnap.size} inactive users`,
      );

      // Calculer le cutoff pour anti-spam
      const frequencyMs = frequencyDays * 24 * 60 * 60 * 1000;
      const cutoffTime = new Date(Date.now() - frequencyMs);
      const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffTime);

      // Traiter chaque utilisateur
      for (const userDoc of usersSnap.docs) {
        const userData = userDoc.data() || {};
        const uid = userData.uid || userDoc.id;
        const status = userData.player_status_cached || "statut_inconnu";

        // Vérifier anti-spam
        const lastRelaunchRaw = userData.last_inactive_relaunch_at;
        if (lastRelaunchRaw && lastRelaunchRaw > cutoffTimestamp) {
          skippedAntiSpam += 1;
          continue;
        }

        try {
          // Message hardcodé par status
          let messageTitle = "Revenez jouer !";
          let messageBody = "Nous vous avons beaucoup manqu\u00E9 !";

          if (status === "mort_probable") {
            messageTitle = "Nous vous manquons ?";
            messageBody =
              "Revenez jouer \u00E0 ProxiPlay et tentez de remporter des superbes lots !";
          } else if (status === "dormant") {
            messageTitle = "\u00C7a fait longtemps !";
            messageBody =
              "Retrouvez les jeux ProxiPlay et vos lots r\u00E9compenses. Nouveau jeu disponible !";
          } else if (status === "a_relancer") {
            messageTitle = "Revenez jouer !";
            messageBody = "Continuez \u00E0 jouer pour accumuler vos prochaines victoires !";
          }

          // Créer notification individuelle
          const notificationRef = firestore
            .collection("ff_push_notifications")
            .doc(`relaunch_${uid}_${Date.now()}`);

          await notificationRef.set(
            buildPushNotificationRequestData({
              title: messageTitle,
              body: messageBody,
              userRefs: `users/${uid}`,
              createdBy: "system/relaunch_inactive",
            }),
          );

          // Mettre à jour le user avec dernier relance
          await userDoc.ref.update({
            last_inactive_relaunch_at: admin.firestore.FieldValue.serverTimestamp(),
          });

          relaunched += 1;
          console.log(
            `[relaunInactivePlayersByStatus] relaunched uid=${uid} status=${status}`,
          );
        } catch (e) {
          errors += 1;
          console.error(
            `[relaunInactivePlayersByStatus] uid=${uid} error=${e.message || e}`,
          );
        }
      }

      // Mettre à jour config avec stats
      const elapsedMs = Date.now() - startTime;
      await configRef.set(
        {
          last_run_at: admin.firestore.FieldValue.serverTimestamp(),
          last_sent_count: relaunched,
          last_error_count: errors,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      console.log(
        `[relaunInactivePlayersByStatus] completed relaunched=${relaunched} skippedAntiSpam=${skippedAntiSpam} errors=${errors} elapsed=${elapsedMs}ms`,
      );

      return null;
    } catch (e) {
      console.error(
        `[relaunInactivePlayersByStatus] critical error=${e.message || e}`,
      );
      throw e;
    }
  });

// Automatically select a main prize winner after game end.
// Runs hourly to avoid load; processes completed games and enforces
// "no main prize => no main-prize winner" consistency.
exports.pickMainPrizeWinners = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("Europe/Paris")
  .onRun(async () => {
    const gamesSnap = await firestore
      .collection("games")
      .where("hasWinner", "==", false)
      .where("end_date", "<=", admin.firestore.Timestamp.now())
      .get();

    if (gamesSnap.empty) {
      return null;
    }

    await Promise.all(
      gamesSnap.docs.map(async (gameDoc) => {
        const gameData = gameDoc.data();
        const gameId = gameDoc.id;
        const hasMainPrize = resolveHasMainPrize(gameData);
        const endDateValue = gameData.end_date || gameData.endDate || null;
        const endDateLog =
          endDateValue &&
          typeof endDateValue.toDate === "function" &&
          !Number.isNaN(endDateValue.toDate().getTime())
            ? endDateValue.toDate().toISOString()
            : endDateValue === null
              ? "absent"
              : String(endDateValue);

        console.log(
          `[DRAW] Jeu trouvé : gameId=${gameId}, end_date=${endDateLog}, status=${gameData.status || "absent"}, main_prize=${hasMainPrize ? "present" : "absent"}`,
        );

        if (!hasMainPrize) {
          console.log(
            `[DRAW][SKIP] gameId=${gameId} — raison : main_prize absent ou mal formé`,
          );
          return null;
        }

        if (gameData.main_prize_winner) {
          console.log(
            `[DRAW][SKIP] gameId=${gameId} — raison : winner_uid déjà présent`,
          );
          return null;
        }

        const participantsSnap = await gameDoc.ref
          .collection("participants")
          .get();

        if (participantsSnap.empty) {
          console.log(
            `[DRAW][SKIP] gameId=${gameId} — raison : aucun participant`,
          );
          return null;
        }

        const participants = participantsSnap.docs.filter((participantDoc) => {
          const participantData = participantDoc.data() || {};
          const participantUserRef = participantData.user_id;
          if (participantUserRef) {
            return true;
          }

          const participantUid =
            participantData.uid ||
            participantData.user_uid ||
            participantData.userId ||
            participantData.user_id_string ||
            "absent";
          console.log(
            `[DRAW][SKIP] gameId=${gameId} — raison : participant sans user_id (uid=${participantUid})`,
          );
          return false;
        });

        if (participants.length === 0) {
          console.log(
            `[DRAW][SKIP] gameId=${gameId} — raison : aucun participant`,
          );
          return null;
        }

        const winnerDoc =
          participants[Math.floor(Math.random() * participants.length)];
        const winnerRef = winnerDoc.data().user_id;
        const winnerUid =
          winnerRef && typeof winnerRef.path === "string"
            ? winnerRef.path.split("/").pop()
            : "absent";

        const prizeRef = firestore.collection("prizes").doc();
        const claimCode = generateClaimCode();
        const ownerRef = gameData.create_by
          ? firestore.doc(gameData.create_by.path)
          : null;
        const enseigneRef = gameData.enseigne_id
          ? firestore.doc(gameData.enseigne_id.path)
          : null;

        await firestore.runTransaction(async (transaction) => {
          const freshGameDoc = await transaction.get(gameDoc.ref);
          // Lu ici (avant toute ecriture, comme l'exige une transaction
          // Firestore) pour denormaliser prenom/ville sur games et prizes :
          // l'app n'a alors plus jamais besoin de lire le profil d'un autre
          // utilisateur pour afficher "Gagne par <prenom> - <ville>".
          const winnerUserDoc = await transaction.get(winnerRef);
          if (!freshGameDoc.exists) {
            console.log(
              `[DRAW][SKIP] gameId=${gameId} — raison : document introuvable pendant la transaction`,
            );
            return;
          }
          const freshGameData = freshGameDoc.data();

          if (freshGameData.hasWinner || freshGameData.main_prize_winner) {
            console.log(
              `[DRAW][SKIP] gameId=${gameId} — raison : winner_uid déjà présent`,
            );
            return;
          }

          logHasWinnerWrite({
            gameId,
            previousValue: freshGameData.hasWinner === true,
            newValue: true,
            sourceFunction: "pickMainPrizeWinners",
            winnerType: "gagnant-principal",
            hasMainPrize: resolveHasMainPrize(freshGameData),
            endDate:
              freshGameData.end_date?.toDate?.()?.toISOString?.() ||
              freshGameData.end_date ||
              null,
          });

          const winnerUserData = winnerUserDoc.exists
            ? winnerUserDoc.data() || {}
            : {};
          const winnerFirstNameValue = getTrimmedString(
            winnerUserData.first_name || winnerUserData.firstName,
          ).split(/\s+/)[0] || "";
          const winnerCityValue = getTrimmedString(winnerUserData.city);
          const denormalizedWinnerFields = {
            ...(winnerFirstNameValue
              ? {
                  winnerFirstName: winnerFirstNameValue,
                  winner_first_name: winnerFirstNameValue,
                }
              : {}),
            ...(winnerCityValue
              ? { winnerCity: winnerCityValue, winner_city: winnerCityValue }
              : {}),
          };

          transaction.update(gameDoc.ref, {
            hasWinner: true,
            main_prize_winner: winnerRef,
            ...denormalizedWinnerFields,
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
            claim_code: normalizeClaimCode(claimCode),
            claimed: false,
            win_date: admin.firestore.FieldValue.serverTimestamp(),
            ...(gameData.prize_usage_deadline
              ? { usage_deadline: gameData.prize_usage_deadline }
              : {}),
            ...denormalizedWinnerFields,
          });

          const userLotRef = winnerRef
            .collection("my_lots")
            .doc(prizeRef.id);
          transaction.set(userLotRef, {
            prize_id: prizeRef,
          });

          console.log(
            `[DRAW][OK] gameId=${gameId} — gagnant tiré : uid=${winnerUid}`,
          );
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
        logHasWinnerWrite({
          gameId: gameDoc.id,
          previousValue: gameData.hasWinner === true,
          newValue: false,
          sourceFunction: "backfillGamesHasMainPrize",
          winnerType: "correction-coherence",
          hasMainPrize,
          endDate:
            gameData.end_date?.toDate?.()?.toISOString?.() ||
            gameData.end_date ||
            null,
        });
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

try {
  const {
    createSearchGooglePlacesCallable,
  } = require("./google_places_search_callable");
  exports.searchGooglePlaces = createSearchGooglePlacesCallable({
    functions,
    kFunctionsRegion,
    getTrimmedString,
  });
} catch (error) {
  console.log("searchGooglePlaces not loaded yet:", error.message);
}

exports.adminGetNotificationsConfig = adminGetNotificationsConfigCallable;
exports.adminSetNotificationsConfig = adminSetNotificationsConfigCallable;
exports.adminSendPrizeReminderPushTest = adminSendPrizeReminderPushTestCallable;
exports.adminSendPrizeReminderEmailTest = adminSendPrizeReminderEmailTestCallable;
exports.adminRunPrizeReminderDryRun = adminRunPrizeReminderDryRunCallable;
exports.adminRunPrizeReminderForPrizeTest =
  adminRunPrizeReminderForPrizeTestCallable;
exports.adminBackfillWonSecondaryPrizesForGame =
  adminBackfillWonSecondaryPrizesForGameCallable;
exports.runPrizeRemindersDaily = runPrizeRemindersDailyScheduled;
exports.generateInstantWinnersForGame = generateInstantWinnersForGameCallable;
exports.getPrizeWinnerContactForMerchant =
  getPrizeWinnerContactForMerchantCallable;
exports.getMonthlyChallengeState = getMonthlyChallengeStateCallable;
exports.getMonthlyChallengesState = getMonthlyChallengesStateCallable;
exports.adminGetMonthlyChallengeConfig =
  adminGetMonthlyChallengeConfigCallable;
exports.adminUpsertMonthlyChallenge = adminUpsertMonthlyChallengeCallable;
exports.adminGetMonthlyChallengeStats =
  adminGetMonthlyChallengeStatsCallable;
exports.adminRunMonthlyChallengeDraw = adminRunMonthlyChallengeDrawCallable;
exports.drawMonthlyChallengeWinner = drawMonthlyChallengeWinnerScheduled;

try {
  const {
    createRunInactivePlayerAutomationsManual,
  } = require("./lib/notifications/triggers/run_inactive_player_automations_manual");
  exports.runInactivePlayerAutomationsManual =
    createRunInactivePlayerAutomationsManual({
      functions,
      firestore,
      admin,
      assertIsAdmin,
    });
} catch (error) {
  console.log(
    "notifications automation manual trigger not loaded yet:",
    error.message,
  );
}

try {
  const {
    createRunBirthdayAutomationsManual,
  } = require("./lib/notifications/triggers/run_birthday_automations_manual");
  exports.runBirthdayAutomationsManual =
    createRunBirthdayAutomationsManual({
      functions,
      firestore,
      admin,
      assertIsAdmin,
    });
} catch (error) {
  console.log(
    "birthday automation manual trigger not loaded yet:",
    error.message,
  );
}

try {
  const {
    createRunBirthdayAutomationsDaily,
  } = require("./lib/notifications/triggers/run_birthday_automations_daily");
  exports.runBirthdayAutomationsDaily =
    createRunBirthdayAutomationsDaily({
      functions,
      firestore,
      admin,
    });
} catch (error) {
  console.log(
    "birthday automation daily trigger not loaded yet:",
    error.message,
  );
}

try {
  const {
    drawAnimationWinners,
    repairAnimationDraw,
  } = require("./draw_animation_winner");
  exports.drawAnimationWinners = drawAnimationWinners;

  exports.adminRepairAnimationDraw = functions
    .region(kFunctionsRegion)
    .runWith({timeoutSeconds: 120, memory: "512MB"})
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Authentification requise.");
      }
      await assertIsAdmin(context.auth.uid);
      const animationId = getTrimmedString(data && data.animationId);
      if (!animationId || animationId.includes("/")) {
        throw new functions.https.HttpsError("invalid-argument", "animationId invalide.");
      }
      try {
        return await repairAnimationDraw(animationId);
      } catch (error) {
        throw new functions.https.HttpsError("failed-precondition", error.message || "Reparation impossible.");
      }
    });
} catch (error) {
  console.log("drawAnimationWinners not loaded yet:", error.message);
}

try {
  const {
    drawReferralGameWinner,
  } = require("./draw_referral_game_winner");
  exports.drawReferralGameWinner = drawReferralGameWinner;
} catch (error) {
  console.log("drawReferralGameWinner not loaded yet:", error.message);
}

const {drawReferralGame, repairReferralGameDraw} = require("./referral_game_engine");

exports.adminDrawReferralGameWinner = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "512MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentification requise.");
    }
    await assertIsAdmin(context.auth.uid);
    const gameId = getTrimmedString(data && data.gameId);
    if (!gameId || gameId.includes("/")) {
      throw new functions.https.HttpsError("invalid-argument", "gameId invalide.");
    }
    try {
      return await drawReferralGame(gameId, {allowEarly: data && data.allowEarly === true});
    } catch (error) {
      throw new functions.https.HttpsError("failed-precondition", error.message || "Tirage impossible.");
    }
  });

exports.adminRepairReferralGameDraw = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "512MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentification requise.");
    }
    await assertIsAdmin(context.auth.uid);
    const gameId = getTrimmedString(data && data.gameId);
    if (!gameId || gameId.includes("/")) {
      throw new functions.https.HttpsError("invalid-argument", "gameId invalide.");
    }
    try {
      return await repairReferralGameDraw(gameId);
    } catch (error) {
      throw new functions.https.HttpsError("failed-precondition", error.message || "Reparation impossible.");
    }
  });

/**
 * Demarre et termine automatiquement les jeux de parrainage, sans action
 * admin :
 * - un brouillon dont `start_date` est atteinte devient actif (le plus
 *   ancien `start_date` d'abord si plusieurs sont eligibles), sauf si un
 *   autre jeu est deja actif — meme regle que l'activation manuelle
 *   (PATCH /api/admin/referral-games/[id]) : jamais deux jeux actifs a la
 *   fois.
 * - un jeu actif dont `end_date` est atteinte est tire au sort via le
 *   meme moteur que le bouton admin "Tirer le gagnant"
 *   (`referral_game_engine.drawReferralGame`).
 *
 * NOTE: Requires deployment. Toutes les 15 minutes (precision suffisante
 * pour des dates de debut/fin au jour pres).
 */
exports.autoManageReferralGames = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .pubsub.schedule("every 15 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const draftsSnap = await firestore
      .collection("referral_games")
      .where("status", "==", "draft")
      .where("start_date", "<=", now)
      .get();
    if (!draftsSnap.empty) {
      const activeSnap = await firestore
        .collection("referral_games")
        .where("status", "==", "active")
        .limit(1)
        .get();
      if (activeSnap.empty) {
        const sortedDrafts = draftsSnap.docs.sort(
          (a, b) => a.data().start_date.toMillis() - b.data().start_date.toMillis(),
        );
        const toActivate = sortedDrafts[0];
        await toActivate.ref.update({
          status: "active",
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[autoManageReferralGames] activated ${toActivate.id}`);
      }
    }

    const endedSnap = await firestore
      .collection("referral_games")
      .where("status", "==", "active")
      .where("end_date", "<=", now)
      .get();
    for (const doc of endedSnap.docs) {
      try {
        await drawReferralGame(doc.id, {now});
        console.log(`[autoManageReferralGames] drew ${doc.id}`);
      } catch (error) {
        console.error(`[autoManageReferralGames] draw failed for ${doc.id}: ${error.message || error}`);
      }
    }
  });

// Migrees depuis l'ancien codebase firebase/custom_cloud_functions
// (consolidation Firebase : un seul firebase.json, un seul codebase
// Functions). Noms d'export et comportement strictement inchanges.
const {deleteEnseigneAndGames} = require("./delete_enseigne_and_games");
exports.deleteEnseigneAndGames = deleteEnseigneAndGames;

const {deleteCommercantAccount} = require("./delete_commercant_account");
exports.deleteCommercantAccount = deleteCommercantAccount;


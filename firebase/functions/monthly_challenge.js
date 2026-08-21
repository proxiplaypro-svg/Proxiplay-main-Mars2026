const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const {getNowTimestamp} = require("./lib/emulator_runtime");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const kTimeZone = "Europe/Paris";
const kFunctionsRegion = "us-central1";
const kMonthlyChallengeConfigPath = "app_config/monthly_challenge";
const kMonthlyChallengesCollection = "monthly_challenges";
const kPushNotificationsCollection = "ff_push_notifications";
const kDefaultTargetDays = 15;
const kAttendanceChallengeType = "attendance";
const kRestaurantChallengeType = "restaurant";

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeBoolean(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "1", "yes", "on"].includes(normalized)) {
      return true;
    }
    if (["false", "0", "no", "off"].includes(normalized)) {
      return false;
    }
  }
  return fallback;
}

function normalizeNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

function toTimestamp(value) {
  if (!value) {
    return null;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value;
  }
  if (
    typeof value === "object" &&
    value !== null &&
    typeof value.seconds === "number"
  ) {
    return new admin.firestore.Timestamp(
      value.seconds,
      value.nanoseconds || 0,
    );
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return admin.firestore.Timestamp.fromMillis(value);
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) {
      return admin.firestore.Timestamp.fromMillis(parsed);
    }
  }
  if (value instanceof Date) {
    return admin.firestore.Timestamp.fromDate(value);
  }
  return null;
}

function getParisDateParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: kTimeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = parts.find((part) => part.type === "year")?.value || "1970";
  const month = parts.find((part) => part.type === "month")?.value || "01";
  const day = parts.find((part) => part.type === "day")?.value || "01";
  return {year, month, day};
}

function getParisMonthKey(date = new Date()) {
  const {year, month} = getParisDateParts(date);
  return `${year}-${month}`;
}

function getParisDayKey(date = new Date()) {
  const {year, month, day} = getParisDateParts(date);
  return `${year}-${month}-${day}`;
}

function isMonthKey(value) {
  return /^\d{4}-\d{2}$/.test(getTrimmedString(value));
}

function parseMonthKey(monthKey) {
  const match = /^(\d{4})-(\d{2})$/.exec(getTrimmedString(monthKey));
  if (!match) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  if (month < 1 || month > 12) {
    return null;
  }
  return {year, month};
}

function getDaysInMonth(monthKey) {
  const parsed = parseMonthKey(monthKey);
  if (!parsed) {
    return 0;
  }
  return new Date(Date.UTC(parsed.year, parsed.month, 0)).getUTCDate();
}

function getChallengePeriodEnd(monthKey) {
  const parsed = parseMonthKey(monthKey);
  if (!parsed) {
    return null;
  }
  return new Date(Date.UTC(parsed.year, parsed.month, 0, 23, 59, 59, 999));
}

function getMonthLabel(monthKey) {
  const parsed = parseMonthKey(monthKey);
  if (!parsed) {
    return "";
  }
  const date = new Date(Date.UTC(parsed.year, parsed.month - 1, 1));
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: kTimeZone,
    month: "long",
    year: "numeric",
  }).format(date);
}

function getParisDayKeyFromTimestamp(value) {
  const timestamp = toTimestamp(value);
  return timestamp ? getParisDayKey(timestamp.toDate()) : "";
}

function normalizeMonthlyChallengeConfig(raw) {
  const month = getTrimmedString(raw?.month);
  const type = raw?.type === kRestaurantChallengeType ?
    kRestaurantChallengeType :
    kAttendanceChallengeType;
  const challengeId = getTrimmedString(raw?.challenge_id) ||
    getChallengeId(type, month);
  const targetDays = Math.max(
    1,
    normalizeNumber(raw?.target_days ?? raw?.targetDays, kDefaultTargetDays),
  );
  const rawRestaurantRef = raw?.restaurant_ref ?? raw?.restaurantRef;
  const restaurantRef = typeof rawRestaurantRef === "string" &&
    rawRestaurantRef.trim().startsWith("enseignes/") ?
    db.doc(rawRestaurantRef.trim()) :
    rawRestaurantRef || null;
  return {
    challenge_id: challengeId,
    type,
    enabled: normalizeBoolean(raw?.enabled, false),
    month,
    title: getTrimmedString(raw?.title),
    description: getTrimmedString(raw?.description),
    target_days: targetDays,
    prize_title: getTrimmedString(raw?.prize_title ?? raw?.prizeTitle),
    prize_description: getTrimmedString(
      raw?.prize_description ?? raw?.prizeDescription,
    ),
    prize_value: normalizeNumber(raw?.prize_value ?? raw?.prizeValue, 0),
    image_url: getTrimmedString(raw?.image_url ?? raw?.imageUrl),
    restaurant_ref: restaurantRef,
    restaurant_name: getTrimmedString(raw?.restaurant_name ?? raw?.restaurantName),
    restaurant_image_url: getTrimmedString(
      raw?.restaurant_image_url ?? raw?.restaurantImageUrl,
    ),
    draw_date: toTimestamp(raw?.draw_date ?? raw?.drawDate),
    updated_at: raw?.updated_at || null,
  };
}

function getChallengeId(type, monthKey) {
  const month = getTrimmedString(monthKey);
  return type === kRestaurantChallengeType ? `restaurant_${month}` : month;
}

function getMonthlyChallengeConfigRef() {
  return db.doc(kMonthlyChallengeConfigPath);
}

function getMonthlyChallengeConfigDocRef(challengeId) {
  return db.collection(kMonthlyChallengesCollection).doc(challengeId);
}

async function getChallengeConfigForType(type, monthKey) {
  const challengeId = getChallengeId(type, monthKey);
  const configSnap = await getMonthlyChallengeConfigDocRef(challengeId).get();
  if (configSnap.exists) {
    return normalizeMonthlyChallengeConfig(configSnap.data() || {});
  }
  if (type === kAttendanceChallengeType) {
    const legacySnap = await getMonthlyChallengeConfigRef().get();
    const legacy = normalizeMonthlyChallengeConfig(
      legacySnap.exists ? legacySnap.data() || {} : {},
    );
    if (legacy.month === monthKey) {
      return {...legacy, challenge_id: challengeId, type};
    }
  }
  return normalizeMonthlyChallengeConfig({type, month: monthKey});
}

async function getActiveMonthlyChallengeConfigs(monthKey) {
  const [configsSnap, legacySnap] = await Promise.all([
    db.collection(kMonthlyChallengesCollection).where("month", "==", monthKey).get(),
    getMonthlyChallengeConfigRef().get(),
  ]);
  const configs = configsSnap.docs
    .map((snap) => normalizeMonthlyChallengeConfig(snap.data() || {}))
    .filter((config) => config.enabled && config.month === monthKey);
  const hasAttendance = configs.some(
    (config) => config.type === kAttendanceChallengeType,
  );
  const legacy = normalizeMonthlyChallengeConfig(
    legacySnap.exists ? legacySnap.data() || {} : {},
  );
  if (legacy.enabled && legacy.month === monthKey && !hasAttendance) {
    configs.push({...legacy, challenge_id: monthKey, type: kAttendanceChallengeType});
  }
  return configs;
}

function getMonthlyChallengeUserStateRef(userRef, challengeId) {
  return userRef.collection("monthly_challenges").doc(challengeId);
}

function getMonthlyChallengeEntryRef(challengeId, uid) {
  return db.collection("monthly_challenge_entries").doc(`${challengeId}_${uid}`);
}

// Firestore transactions require every transaction.get() to happen before
// any transaction.set()/update() in the whole transaction, not just within
// this function. Callers that already issued writes earlier in the same
// transaction (e.g. participateInGameTransaction) must call this up front,
// before their first write, and pass the result to
// trackMonthlyChallengeParticipation() as `prefetched`.
async function prefetchMonthlyChallengeParticipationState({
  uid,
  userRef,
  now,
  transaction,
  configRef = getMonthlyChallengeConfigRef(),
  challengeId = "",
}) {
  const monthKey = getParisMonthKey(now.toDate());
  const resolvedChallengeId = challengeId || monthKey;
  const stateRef = getMonthlyChallengeUserStateRef(userRef, resolvedChallengeId);
  const entryRef = getMonthlyChallengeEntryRef(resolvedChallengeId, uid);
  const [configSnap, stateSnap, entrySnap] = await Promise.all([
    transaction.get(configRef),
    transaction.get(stateRef),
    transaction.get(entryRef),
  ]);
  return {
    monthKey,
    challengeId: resolvedChallengeId,
    configRef,
    stateRef,
    entryRef,
    configSnap,
    stateSnap,
    entrySnap,
  };
}

function getMonthlyChallengeDrawRef(challengeId) {
  return db.collection("monthly_challenge_draws").doc(challengeId);
}

async function prefetchActiveMonthlyChallenges({uid, userRef, now, transaction}) {
  const monthKey = getParisMonthKey(now.toDate());
  const [challengeConfigsSnap, legacyConfigSnap] = await Promise.all([
    transaction.get(
      db.collection(kMonthlyChallengesCollection).where("month", "==", monthKey),
    ),
    transaction.get(getMonthlyChallengeConfigRef()),
  ]);
  const configs = challengeConfigsSnap.docs
    .map((snap) => ({config: normalizeMonthlyChallengeConfig(snap.data() || {}), ref: snap.ref}))
    .filter(({config}) => config.enabled && config.month === monthKey);
  const hasAttendance = configs.some(
    ({config}) => config.type === kAttendanceChallengeType,
  );
  const legacyConfig = normalizeMonthlyChallengeConfig(
    legacyConfigSnap.exists ? legacyConfigSnap.data() || {} : {},
  );
  if (legacyConfig.enabled && legacyConfig.month === monthKey && !hasAttendance) {
    configs.push({
      config: {...legacyConfig, challenge_id: monthKey, type: kAttendanceChallengeType},
      ref: getMonthlyChallengeConfigRef(),
    });
  }

  return Promise.all(configs.map(({config, ref}) =>
    prefetchMonthlyChallengeParticipationState({
      uid,
      userRef,
      now,
      transaction,
      configRef: ref,
      challengeId: config.challenge_id,
    }),
  ));
}

function sanitizeStringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return [...new Set(value.map((item) => getTrimmedString(item)).filter(Boolean))]
    .sort();
}

function getFrozenTargetDays(userState, config) {
  return Math.max(
    1,
    normalizeNumber(
      userState?.target_days,
      config?.target_days || kDefaultTargetDays,
    ),
  );
}

function normalizeActiveDaysCount(userState, fallbackTargetDays = kDefaultTargetDays) {
  const activeDatesCount = sanitizeStringArray(userState?.active_dates).length;
  const explicitCount = normalizeNumber(userState?.active_days_count, activeDatesCount);
  return Math.max(0, Math.min(Math.max(explicitCount, activeDatesCount), Math.max(fallbackTargetDays, explicitCount, activeDatesCount)));
}

function roundToSingleDecimal(value) {
  return Number(value.toFixed(1));
}

function buildDistributionLabel(min, max, isOpenEnded = false) {
  if (isOpenEnded) {
    return `${min}+`;
  }
  if (min === max) {
    return `${min}`;
  }
  return `${min}-${max}`;
}

function buildProgressDistributionRanges(targetDays) {
  const safeTargetDays = Math.max(1, normalizeNumber(targetDays, kDefaultTargetDays));
  const belowQualifiedDays = Math.max(0, safeTargetDays - 1);
  const ranges = [];

  if (belowQualifiedDays > 0) {
    const bucketCount = Math.min(5, belowQualifiedDays);
    const baseSize = Math.floor(belowQualifiedDays / bucketCount);
    let remainder = belowQualifiedDays % bucketCount;
    let cursor = 1;

    for (let index = 0; index < bucketCount; index += 1) {
      const size = baseSize + (remainder > 0 ? 1 : 0);
      remainder = Math.max(0, remainder - 1);
      const min = cursor;
      const max = cursor + size - 1;
      ranges.push({
        label: buildDistributionLabel(min, max),
        min,
        max,
        count: 0,
      });
      cursor = max + 1;
    }
  }

  ranges.push({
    label: buildDistributionLabel(safeTargetDays, null, true),
    min: safeTargetDays,
    max: null,
    count: 0,
  });

  return ranges;
}

function deriveQualifiedDayKey(userState, targetDays) {
  const qualifiedDay = getParisDayKeyFromTimestamp(userState?.qualified_at);
  if (qualifiedDay) {
    return qualifiedDay;
  }

  if (userState?.qualified !== true) {
    return "";
  }

  const activeDates = sanitizeStringArray(userState?.active_dates);
  if (activeDates.length >= targetDays) {
    return activeDates[targetDays - 1] || "";
  }
  return activeDates[activeDates.length - 1] || "";
}

function buildMonthlyChallengeTimeline(monthKey, participantDayKeys, qualifiedDayKeys) {
  const daysInMonth = getDaysInMonth(monthKey);
  if (daysInMonth <= 0) {
    return [];
  }

  const participantsByDay = new Map();
  const qualifiedByDay = new Map();
  for (const dayKey of participantDayKeys.filter(Boolean)) {
    participantsByDay.set(dayKey, (participantsByDay.get(dayKey) || 0) + 1);
  }
  for (const dayKey of qualifiedDayKeys.filter(Boolean)) {
    qualifiedByDay.set(dayKey, (qualifiedByDay.get(dayKey) || 0) + 1);
  }

  const timeline = [];
  let cumulativeParticipants = 0;
  let cumulativeQualified = 0;
  for (let day = 1; day <= daysInMonth; day += 1) {
    const dayKey = `${monthKey}-${String(day).padStart(2, "0")}`;
    cumulativeParticipants += participantsByDay.get(dayKey) || 0;
    cumulativeQualified += qualifiedByDay.get(dayKey) || 0;
    timeline.push({
      day,
      dateKey: dayKey,
      participants: cumulativeParticipants,
      qualified: cumulativeQualified,
    });
  }
  return timeline;
}

function computeMonthlyChallengeStats(config, monthlyStates, drawData = {}) {
  const monthKey = getTrimmedString(config?.month);
  const ranges = buildProgressDistributionRanges(config?.target_days || kDefaultTargetDays);
  const activeDayValues = [];
  const participantDayKeys = [];
  const qualifiedDayKeys = [];
  let qualifiedCount = 0;

  for (const rawState of monthlyStates) {
    const state = rawState || {};
    const targetDays = getFrozenTargetDays(state, config);
    const activeDaysCount = normalizeActiveDaysCount(state, targetDays);
    activeDayValues.push(activeDaysCount);

    const participantDayKey = sanitizeStringArray(state.active_dates)[0] || "";
    if (participantDayKey) {
      participantDayKeys.push(participantDayKey);
    }

    const qualified =
      state.qualified === true || activeDaysCount >= targetDays;
    if (qualified) {
      qualifiedCount += 1;
      const qualifiedDayKey = deriveQualifiedDayKey(state, targetDays);
      if (qualifiedDayKey) {
        qualifiedDayKeys.push(qualifiedDayKey);
      }
    }

    const matchingRange = ranges.find((range) =>
      range.max == null ? activeDaysCount >= range.min :
      activeDaysCount >= range.min && activeDaysCount <= range.max,
    );
    if (matchingRange) {
      matchingRange.count += 1;
    }
  }

  const startedCount = activeDayValues.length;
  const totalActiveDays = activeDayValues.reduce((sum, value) => sum + value, 0);
  const sortedActiveDays = [...activeDayValues].sort((left, right) => left - right);
  const averageActiveDays = startedCount > 0 ?
    roundToSingleDecimal(totalActiveDays / startedCount) :
    0;
  let medianActiveDays = 0;
  if (sortedActiveDays.length > 0) {
    const middleIndex = Math.floor(sortedActiveDays.length / 2);
    medianActiveDays = sortedActiveDays.length % 2 === 1 ?
      sortedActiveDays[middleIndex] :
      roundToSingleDecimal(
        (sortedActiveDays[middleIndex - 1] + sortedActiveDays[middleIndex]) / 2,
      );
  }

  return {
    month: monthKey,
    startedCount,
    qualifiedCount,
    qualificationRate:
      startedCount > 0 ? roundToSingleDecimal((qualifiedCount / startedCount) * 100) : 0,
    averageActiveDays,
    medianActiveDays,
    progressAverageLabel:
      `${averageActiveDays.toFixed(1)} / ${Math.max(1, normalizeNumber(config?.target_days, kDefaultTargetDays))}`,
    distribution: ranges,
    timeline: buildMonthlyChallengeTimeline(monthKey, participantDayKeys, qualifiedDayKeys),
    drawStatus: getTrimmedString(drawData.status),
    eligibleCount: normalizeNumber(drawData.eligible_count, 0),
    winnerUid: getTrimmedString(drawData.winner_uid),
    drawnAt: drawData.drawn_at || null,
  };
}

function getProgressNotificationKey(remainingDays) {
  if (remainingDays === 3) {
    return "remaining_3";
  }
  if (remainingDays === 1) {
    return "remaining_1";
  }
  return "";
}

function buildPushNotificationRequestData({
  title,
  body,
  userRefOrPath,
  createdBy,
  initialPageName = "",
  parameterData = "",
  targetAudience = "All",
  targetUserGroup = "All",
}) {
  const userRefPath =
    typeof userRefOrPath === "string" ?
      userRefOrPath.trim() :
      getTrimmedString(userRefOrPath?.path);
  if (!userRefPath) {
    throw new Error("Missing target user ref path for push notification request.");
  }
  return {
    notification_title: title || "",
    notification_text: body || "",
    notification_image_url: "",
    notification_sound: "",
    parameter_data: parameterData,
    initial_page_name: initialPageName,
    target_audience: targetAudience,
    target_user_group: targetUserGroup,
    user_refs: userRefPath,
    status: "started",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    created_by: createdBy || "system/custom_cloud_function",
  };
}

async function createPushNotificationRequestIfAbsent(docId, payload) {
  const ref = db.collection(kPushNotificationsCollection).doc(docId);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (snap.exists) {
      return;
    }
    transaction.set(ref, buildPushNotificationRequestData(payload));
  });
}

function isFinalDrawStatus(status) {
  return ["completed", "no_eligible_users"].includes(getTrimmedString(status));
}

function validateMonthlyChallengeConfig(
  config,
  {requireCompleteWhenEnabled = false} = {},
) {
  if (!config || typeof config !== "object") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Configuration de defi mensuel invalide.",
    );
  }

  if (!isMonthKey(config.month) || !parseMonthKey(config.month)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Le mois doit etre un YYYY-MM valide.",
    );
  }

  const daysInMonth = getDaysInMonth(config.month);
  if (config.target_days < 1 || config.target_days > daysInMonth) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `target_days doit etre compris entre 1 et ${daysInMonth}.`,
    );
  }

  if (!config.draw_date) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "La date de tirage est obligatoire.",
    );
  }

  const periodEnd = getChallengePeriodEnd(config.month);
  if (!periodEnd || config.draw_date.toDate().getTime() <= periodEnd.getTime()) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "La date de tirage doit etre posterieure a la fin du mois du defi.",
    );
  }

  if (requireCompleteWhenEnabled) {
    if (!config.title || !config.prize_title) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Titre et lot sont obligatoires lorsque le defi est active.",
      );
    }
  }
}

function validateDrawExecutionOrThrow(config, now) {
  if (!config.enabled) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Le defi mensuel est desactive.",
    );
  }
  validateMonthlyChallengeConfig(config, {requireCompleteWhenEnabled: true});
  if (config.draw_date.toMillis() > now.toMillis()) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Le tirage ne peut pas etre execute avant la draw_date configuree.",
    );
  }
}

function isUserExcludedFromDraw(userData) {
  if (!userData || typeof userData !== "object") {
    return "excluded_missing_user";
  }
  if (userData.auto_deleted === true || userData.deleted === true) {
    return "excluded_deleted_account";
  }
  const accountStatus = getTrimmedString(userData.account_status).toLowerCase();
  if (accountStatus === "rejected" || accountStatus === "suspended") {
    return "excluded_account_status";
  }
  const playerStatus = getTrimmedString(userData.player_status_cached).toLowerCase();
  if (playerStatus === "suspended" || playerStatus === "suspendu") {
    return "excluded_player_status";
  }
  return "";
}

function buildChallengeStateResponse(config, userState) {
  const activeDaysCount = Math.max(
    normalizeNumber(userState?.active_days_count, 0),
    sanitizeStringArray(userState?.active_dates).length,
  );
  const targetDays = getFrozenTargetDays(userState, config);
  const effectiveQualified =
    userState?.qualified === true || activeDaysCount >= targetDays;
  return {
    challengeId: config.challenge_id,
    type: config.type,
    challengeId: config.challenge_id,
    type: config.type,
    showCard: config.enabled && isMonthKey(config.month),
    enabled: config.enabled,
    month: config.month,
    monthLabel: getMonthLabel(config.month),
    title: config.title,
    description: config.description,
    targetDays,
    prizeTitle: config.prize_title,
    prizeDescription: config.prize_description,
    prizeValue: config.prize_value,
    imageUrl: config.image_url,
    restaurantName: config.restaurant_name,
    restaurantImageUrl: config.restaurant_image_url,
    restaurantName: config.restaurant_name,
    restaurantImageUrl: config.restaurant_image_url,
    drawDate: config.draw_date,
    activeDaysCount,
    activeDates: sanitizeStringArray(userState?.active_dates),
    remainingDays: Math.max(0, targetDays - activeDaysCount),
    qualified: effectiveQualified,
    qualifiedAt: userState?.qualified_at || null,
    drawEntryCreated: userState?.draw_entry_created === true,
    winner: userState?.winner === true,
    wonAt: userState?.won_at || null,
  };
}

function buildChallengePrizeDescription(config) {
  const title = getTrimmedString(config.prize_title);
  const description = getTrimmedString(config.prize_description);
  if (title && description) {
    return `${title} - ${description}`;
  }
  return title || description || "Defi mensuel Proxiplay";
}

function generateClaimCode() {
  const timePart = Date.now().toString(36).toUpperCase();
  const randomPart = crypto.randomBytes(2).toString("hex").toUpperCase();
  return `${timePart}${randomPart}`;
}

async function assertIsAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentification requise.",
    );
  }
  const userSnap = await db.collection("users").doc(context.auth.uid).get();
  const role = getTrimmedString(userSnap.data()?.user_role || userSnap.data()?.userRole);
  if (context.auth.token.admin === true || role === "admin") {
    return userSnap;
  }
  throw new functions.https.HttpsError(
    "permission-denied",
    "Acces administrateur requis.",
  );
}

async function ensureChallengeQualificationForUser({
  uid,
  userRef,
  monthKey,
  config,
  now,
}) {
  const stateRef = getMonthlyChallengeUserStateRef(userRef, monthKey);
  const entryRef = getMonthlyChallengeEntryRef(monthKey, uid);
  return db.runTransaction(async (transaction) => {
    const [stateSnap, entrySnap] = await Promise.all([
      transaction.get(stateRef),
      transaction.get(entryRef),
    ]);
    if (!stateSnap.exists) {
      return false;
    }
    const state = stateSnap.data() || {};
    const targetDays = getFrozenTargetDays(state, config);
    const activeDaysCount = Math.max(
      normalizeNumber(state.active_days_count, 0),
      sanitizeStringArray(state.active_dates).length,
    );
    if (activeDaysCount < targetDays) {
      return false;
    }
    const patch = {
      target_days: targetDays,
      qualified: true,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!state.qualified_at) {
      patch.qualified_at = now;
    }
    if (!entrySnap.exists) {
      transaction.set(entryRef, {
        uid,
        month: monthKey,
        user_ref: userRef,
        status: "qualified",
        qualified_at: patch.qualified_at || now,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      patch.draw_entry_created = true;
      patch.draw_entry_id = entryRef.id;
    }
    transaction.set(stateRef, patch, {merge: true});
    return true;
  });
}

async function reconcileMonthlyChallengeEligibility(config, now) {
  const monthKey = config.month;
  const challengeId = config.challenge_id || getChallengeId(config.type, monthKey);
  if (!isMonthKey(monthKey)) {
    return {reconciledUsers: 0, reconciledEntries: 0};
  }

  const snaps = await db
    .collectionGroup("monthly_challenges")
    .where("month", "==", monthKey)
    .get();

  let reconciledUsers = 0;
  let reconciledEntries = 0;
  let batch = db.batch();
  let writes = 0;

  async function flushBatch() {
    if (writes === 0) {
      return;
    }
    await batch.commit();
    batch = db.batch();
    writes = 0;
  }

  for (const doc of snaps.docs) {
    const state = doc.data() || {};
    if (getTrimmedString(state.challenge_id || doc.id) !== challengeId) {
      continue;
    }
    const targetDays = getFrozenTargetDays(state, config);
    const activeDaysCount = Math.max(
      normalizeNumber(state.active_days_count, 0),
      sanitizeStringArray(state.active_dates).length,
    );
    if (activeDaysCount < targetDays) {
      continue;
    }
    const userRef = doc.ref.parent.parent;
    const uid = userRef?.id || "";
    if (!uid || !userRef) {
      continue;
    }
    const entryRef = getMonthlyChallengeEntryRef(challengeId, uid);
    const entrySnap = await entryRef.get();

    const patch = {
      target_days: targetDays,
      qualified: true,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!state.qualified_at) {
      patch.qualified_at = now;
    }
    if (!entrySnap.exists) {
      batch.set(entryRef, {
        uid,
        month: monthKey,
        challenge_id: challengeId,
        type: config.type,
        user_ref: userRef,
        status: "qualified",
        qualified_at: patch.qualified_at || now,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      patch.draw_entry_created = true;
      patch.draw_entry_id = entryRef.id;
      reconciledEntries += 1;
      writes += 1;
    }
    batch.set(doc.ref, patch, {merge: true});
    reconciledUsers += 1;
    writes += 1;
    if (writes >= 350) {
      await flushBatch();
    }
  }

  await flushBatch();
  return {reconciledUsers, reconciledEntries};
}

async function trackMonthlyChallengeParticipation({
  uid,
  userRef,
  now,
  transaction,
  prefetched = null,
}) {
  const fetched =
    prefetched ||
    (await prefetchMonthlyChallengeParticipationState({
      uid,
      userRef,
      now,
      transaction,
    }));
  const {
    monthKey,
    challengeId,
    stateRef,
    entryRef,
    configSnap,
    stateSnap,
    entrySnap,
  } = fetched;
  const config = normalizeMonthlyChallengeConfig(
    configSnap.exists ? configSnap.data() : {},
  );
  const dayKey = getParisDayKey(now.toDate());

  if (!config.enabled || !isMonthKey(config.month) || config.month !== monthKey) {
    return {
      tracked: false,
      challengeId,
      config,
      notifications: [],
    };
  }

  const state = stateSnap.exists ? stateSnap.data() || {} : {};
  const activeDates = sanitizeStringArray(state.active_dates);
  const alreadyActiveToday = activeDates.includes(dayKey);
  const activeDaysCountBefore = Math.max(
    normalizeNumber(state.active_days_count, 0),
    activeDates.length,
  );
  const targetDays = getFrozenTargetDays(state, config);
  const effectiveQualifiedBefore =
    state.qualified === true || activeDaysCountBefore >= targetDays;

  if (alreadyActiveToday) {
    return {
      tracked: true,
      config,
      monthKey,
      challengeId,
      dayKey,
      activeDaysCount: activeDaysCountBefore,
      qualified: effectiveQualifiedBefore,
      notifications: [],
    };
  }

  const nextActiveDates = [...activeDates, dayKey].sort();
  const nextActiveDaysCount = nextActiveDates.length;
  const effectiveQualifiedAfter =
    effectiveQualifiedBefore || nextActiveDaysCount >= targetDays;
  const remainingDays = Math.max(0, targetDays - nextActiveDaysCount);

  const patch = {
    challenge_id: challengeId,
    type: config.type,
    month: monthKey,
    active_days_count: nextActiveDaysCount,
    active_dates: nextActiveDates,
    target_days: targetDays,
    qualified: effectiveQualifiedAfter,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    last_active_day: dayKey,
  };

  if (!stateSnap.exists) {
    patch.created_at = admin.firestore.FieldValue.serverTimestamp();
  }

  const notifications = [];
  let createdEntry = false;

  if (effectiveQualifiedAfter && !state.qualified_at) {
    patch.qualified_at = now;
  }

  if (effectiveQualifiedAfter && !entrySnap.exists) {
    transaction.set(entryRef, {
      uid,
      month: monthKey,
      challenge_id: challengeId,
      type: config.type,
      user_ref: userRef,
      status: "qualified",
      qualified_at: patch.qualified_at || state.qualified_at || now,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    patch.draw_entry_created = true;
    patch.draw_entry_id = entryRef.id;
    createdEntry = true;
  }

  transaction.set(stateRef, patch, {merge: true});

  if (!effectiveQualifiedBefore && effectiveQualifiedAfter) {
    transaction.set(
      stateRef,
      {
        qualification_notification_sent_at:
          admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    notifications.push({
      key: "qualified",
      title: "Tu es qualifie !",
      body: config.type === kRestaurantChallengeType ?
        `Tu participes au tirage du Resto du mois${config.restaurant_name ? ` chez ${config.restaurant_name}` : ""}.` :
        "Tu participes maintenant au tirage Proxiplay du Defi du mois.",
    });
  } else {
    const reminderKey = getProgressNotificationKey(remainingDays);
    const sentReminderKeys = sanitizeStringArray(state.progress_notification_keys);
    if (reminderKey && !sentReminderKeys.includes(reminderKey)) {
      transaction.set(
        stateRef,
        {
          progress_notification_keys: [...sentReminderKeys, reminderKey].sort(),
          last_reminder_remaining: remainingDays,
          last_reminder_sent_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      notifications.push({
        key: reminderKey,
        title: remainingDays === 1 ? "Plus qu'un jour !" : "Plus que 3 jours",
        body: config.type === kRestaurantChallengeType ?
          (remainingDays === 1 ?
            `Reviens jouer encore un jour pour tenter de gagner ton repas pour 2${config.restaurant_name ? ` chez ${config.restaurant_name}` : ""}.` :
            "Encore 3 jours actifs pour participer au tirage du Resto du mois.") :
          (remainingDays === 1 ?
            "Plus qu'un jour pour participer au tirage du Defi Proxiplay." :
            "Encore 3 jours actifs ce mois-ci pour participer au tirage Proxiplay."),
      });
    }
  }

  return {
    tracked: true,
    config,
    monthKey,
    challengeId,
    dayKey,
    activeDaysCount: nextActiveDaysCount,
    qualified: effectiveQualifiedAfter,
    qualifiedNow: !effectiveQualifiedBefore && effectiveQualifiedAfter,
    drawEntryCreatedNow: createdEntry,
    notifications,
  };
}

async function trackMonthlyChallengesParticipation({
  uid,
  userRef,
  now,
  transaction,
  prefetched = null,
}) {
  const challengeStates = prefetched || await prefetchActiveMonthlyChallenges({
    uid,
    userRef,
    now,
    transaction,
  });
  const results = [];
  for (const fetched of challengeStates) {
    results.push(await trackMonthlyChallengeParticipation({
      uid,
      userRef,
      now,
      transaction,
      prefetched: fetched,
    }));
  }
  return {
    tracked: results.some((result) => result.tracked),
    results,
    notifications: results.flatMap((result) => result.notifications || []).map(
      (notification, index) => ({
        ...notification,
        challengeId: results.find((result) =>
          (result.notifications || []).includes(notification),
        )?.challengeId || String(index),
      }),
    ),
  };
}

async function queueMonthlyChallengeNotifications(uid, notifications, monthKey) {
  if (!Array.isArray(notifications) || notifications.length === 0) {
    return;
  }
  for (const notification of notifications) {
    const notificationKey = getTrimmedString(notification.key) || "generic";
    await createPushNotificationRequestIfAbsent(
      `monthly_challenge_${notification.challengeId || monthKey || "unknown"}_${uid}_${notificationKey}`,
      {
        title: notification.title,
        body: notification.body,
        userRefOrPath: `users/${uid}`,
        createdBy: `system/monthly_challenge/${notification.challengeId || monthKey || "unknown"}`,
      },
    );
  }
}

async function drawWinnerForMonthlyChallenge(config, triggerSource) {
  config = normalizeMonthlyChallengeConfig(config || {});
  const monthKey = config.month;
  const challengeId = config.challenge_id || getChallengeId(config.type, monthKey);
  const now = getNowTimestamp(admin);
  validateDrawExecutionOrThrow(config, now);
  await reconcileMonthlyChallengeEligibility(config, now);

  const drawRef = getMonthlyChallengeDrawRef(challengeId);
  const entriesQuery = db
    .collection("monthly_challenge_entries")
    .where("month", "==", monthKey)
    .where("status", "==", "qualified");

  return db.runTransaction(async (transaction) => {
    const [drawSnap, entriesSnap] = await Promise.all([
      transaction.get(drawRef),
      transaction.get(entriesQuery),
    ]);

    if (drawSnap.exists && isFinalDrawStatus(drawSnap.data()?.status)) {
      const drawData = drawSnap.data() || {};
      return {
        status: getTrimmedString(drawData.status) === "completed" ?
          "already_completed" :
          "already_finalized",
        month: monthKey,
        challengeId,
        eligibleCount: normalizeNumber(drawData.eligible_count, 0),
        winnerUid: getTrimmedString(drawData.winner_uid),
      };
    }

    const evaluatedEntries = [];
    for (const entryDoc of entriesSnap.docs) {
      const entryData = entryDoc.data() || {};
      if (getTrimmedString(entryData.challenge_id || entryData.month) !== challengeId) {
        continue;
      }
      const userRef = entryData.user_ref;
      if (!userRef || typeof userRef.get !== "function") {
        evaluatedEntries.push({
          entryDoc,
          exclusionStatus: "excluded_invalid_user_ref",
        });
        continue;
      }
      const userSnap = await transaction.get(userRef);
      if (!userSnap.exists) {
        evaluatedEntries.push({
          entryDoc,
          userRef,
          exclusionStatus: "excluded_missing_user",
        });
        continue;
      }
      const userData = userSnap.data() || {};
      const exclusionStatus = isUserExcludedFromDraw(userData);
      if (exclusionStatus) {
        evaluatedEntries.push({
          entryDoc,
          userRef,
          userData,
          exclusionStatus,
        });
        continue;
      }
      evaluatedEntries.push({entryDoc, userRef, userData});
    }

    const eligibleDocs = evaluatedEntries.filter(
      (entry) => !entry.exclusionStatus,
    );
    for (const entry of evaluatedEntries) {
      if (!entry.exclusionStatus) {
        continue;
      }
      transaction.update(entry.entryDoc.ref, {
        status: entry.exclusionStatus,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (eligibleDocs.length === 0) {
      transaction.set(drawRef, {
        month: monthKey,
        challenge_id: challengeId,
        type: config.type,
        status: "no_eligible_users",
        eligible_count: 0,
        drawn_at: now,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return {
        status: "no_eligible_users",
        month: monthKey,
        eligibleCount: 0,
      };
    }

    const selected = eligibleDocs[crypto.randomInt(0, eligibleDocs.length)];
    const winnerUid = selected.userRef.id;
    const winnerStateRef = getMonthlyChallengeUserStateRef(selected.userRef, challengeId);
    const claimCode = generateClaimCode();
    const prizeRef = db.collection("prizes").doc(`monthly_challenge_${challengeId}`);
    const winnerFirstName = getTrimmedString(
      selected.userData.first_name || selected.userData.firstName,
    ).split(/\s+/)[0] || "";
    const winnerCity = getTrimmedString(selected.userData.city);
    const denormalizedWinnerFields = {
      ...(winnerFirstName ?
        {
          winnerFirstName,
          winner_first_name: winnerFirstName,
        } :
        {}),
      ...(winnerCity ?
        {
          winnerCity,
          winner_city: winnerCity,
        } :
        {}),
    };

    transaction.set(drawRef, {
      month: monthKey,
      challenge_id: challengeId,
      type: config.type,
      status: "completed",
      winner_uid: winnerUid,
      winner_ref: selected.userRef,
      eligible_count: eligibleDocs.length,
      drawn_at: now,
      prize_ref: prizeRef,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    transaction.update(selected.entryDoc.ref, {
      status: "won",
      drawn_at: now,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    transaction.set(winnerStateRef, {
      winner: true,
      won_at: now,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    transaction.set(prizeRef, {
      prize_type: "monthly_challenge",
      name: config.prize_title || "Defi mensuel Proxiplay",
      description: buildChallengePrizeDescription(config),
      winner_id: selected.userRef,
      claim_code: claimCode,
      claimed: false,
      win_date: now,
      monthly_challenge_month: monthKey,
      monthly_challenge_id: challengeId,
      monthly_challenge_type: config.type,
      monthly_challenge_draw_ref: drawRef,
      prize_value: config.prize_value,
      ...denormalizedWinnerFields,
    });

    transaction.set(selected.userRef.collection("my_lots").doc(prizeRef.id), {
      prize_id: prizeRef,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      status: "completed",
      month: monthKey,
      challengeId,
      eligibleCount: eligibleDocs.length,
      winnerUid,
      prizeId: prizeRef.id,
      triggerSource,
    };
  }).then(async (result) => {
    if (result.status === "completed" && result.winnerUid) {
      await createPushNotificationRequestIfAbsent(
        `monthly_challenge_draw_${challengeId}_${result.winnerUid}`,
        {
          title: "Felicitations !",
          body: config.type === kRestaurantChallengeType ?
            `Tu as remporte le Resto du mois${config.restaurant_name ? ` chez ${config.restaurant_name}` : ""} !` :
            "Tu as remporte le Defi Proxiplay du mois.",
          userRefOrPath: `users/${result.winnerUid}`,
          createdBy: `system/monthly_challenge_draw/${challengeId}`,
        },
      );
    }
    return result;
  });
}

const getMonthlyChallengeStateCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentification requise.",
      );
    }
    const userRef = db.collection("users").doc(context.auth.uid);
    const configSnap = await getMonthlyChallengeConfigRef().get();
    const config = normalizeMonthlyChallengeConfig(
      configSnap.exists ? configSnap.data() : {},
    );
    const monthKey = isMonthKey(config.month) ? config.month : getParisMonthKey();
    const stateSnap = await getMonthlyChallengeUserStateRef(userRef, monthKey).get();
    const userState = stateSnap.exists ? stateSnap.data() || {} : {};
    const state = buildChallengeStateResponse(config, userState);

    if (
      state.showCard &&
      state.qualified &&
      (userState.qualified !== true || userState.draw_entry_created !== true)
    ) {
      await ensureChallengeQualificationForUser({
        uid: context.auth.uid,
        userRef,
        monthKey,
        config,
        now: getNowTimestamp(admin),
      });
      const refreshedSnap = await getMonthlyChallengeUserStateRef(userRef, monthKey).get();
      return buildChallengeStateResponse(
        config,
        refreshedSnap.exists ? refreshedSnap.data() || {} : {},
      );
    }

    return state;
  });

const getMonthlyChallengesStateCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentification requise.",
      );
    }
    const userRef = db.collection("users").doc(context.auth.uid);
    const configs = await getActiveMonthlyChallengeConfigs(getParisMonthKey());
    const challenges = await Promise.all(configs.map(async (config) => {
      const stateSnap = await getMonthlyChallengeUserStateRef(
        userRef,
        config.challenge_id,
      ).get();
      return buildChallengeStateResponse(
        config,
        stateSnap.exists ? stateSnap.data() || {} : {},
      );
    }));
    return {challenges};
  });

const adminGetMonthlyChallengeConfigCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data, context) => {
    await assertIsAdmin(context);
    const type = data?.type === kRestaurantChallengeType ?
      kRestaurantChallengeType : kAttendanceChallengeType;
    const month = getTrimmedString(data?.month) || getParisMonthKey();
    return getChallengeConfigForType(type, month);
  });

const adminUpsertMonthlyChallengeCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (data, context) => {
    await assertIsAdmin(context);
    const payload = normalizeMonthlyChallengeConfig(data || {});
    if (payload.enabled) {
      validateMonthlyChallengeConfig(payload, {requireCompleteWhenEnabled: true});
    } else if (payload.month || payload.draw_date) {
      validateMonthlyChallengeConfig(payload);
    }

    const configRef = getMonthlyChallengeConfigDocRef(payload.challenge_id);
    const existingSnap = await configRef.get();
    const existingConfig = normalizeMonthlyChallengeConfig(
      existingSnap.exists ? existingSnap.data() : {},
    );
    const structuralFieldsChanged =
      existingConfig.month !== payload.month ||
      existingConfig.target_days !== payload.target_days ||
      (existingConfig.draw_date?.toMillis() || 0) !==
        (payload.draw_date?.toMillis() || 0);
    const monthsToCheck = [...new Set(
      [existingConfig.month, payload.month].filter((month) => isMonthKey(month)),
    )];
    if (structuralFieldsChanged && monthsToCheck.length > 0) {
      const startedChecks = await Promise.all(
        monthsToCheck.map((month) =>
          db
            .collectionGroup("monthly_challenges")
            .where("month", "==", month)
            .limit(1)
            .get(),
        ),
      );
      if (startedChecks.some((snap) => snap.docs.some((doc) =>
        getTrimmedString(doc.data()?.challenge_id || doc.id) === payload.challenge_id,
      ))) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Le defi a deja commence. Le mois, target_days et draw_date sont figes.",
        );
      }
    }

    await configRef.set({
      ...payload,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_by: context.auth.uid,
    }, {merge: true});
    return {
      ok: true,
      config: payload,
    };
  });

const adminGetMonthlyChallengeStatsCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 120, memory: "512MB"})
  .https.onCall(async (data, context) => {
    await assertIsAdmin(context);
    const type = data?.type === kRestaurantChallengeType ?
      kRestaurantChallengeType : kAttendanceChallengeType;
    const config = await getChallengeConfigForType(
      type,
      getTrimmedString(data?.month) || getParisMonthKey(),
    );
    const monthKey = config.month;
    const challengeId = config.challenge_id;
    let monthlyStates = [];
    if (isMonthKey(monthKey)) {
      const statesSnap = await db
        .collectionGroup("monthly_challenges")
        .where("month", "==", monthKey)
        .get();
      monthlyStates = statesSnap.docs
        .filter((doc) => getTrimmedString(doc.data()?.challenge_id || doc.id) === challengeId)
        .map((doc) => doc.data() || {});
    }
    const drawSnap = isMonthKey(monthKey) ?
      await getMonthlyChallengeDrawRef(challengeId).get() :
      null;
    const drawData = drawSnap && drawSnap.exists ? drawSnap.data() || {} : {};
    const computedStats = computeMonthlyChallengeStats(config, monthlyStates, drawData);
    return {
      config,
      stats: {
        ...computedStats,
      },
    };
  });

const adminRunMonthlyChallengeDrawCallable = functions
  .region(kFunctionsRegion)
  .runWith({timeoutSeconds: 180, memory: "512MB"})
  .https.onCall(async (data, context) => {
    await assertIsAdmin(context);
    const type = data?.type === kRestaurantChallengeType ?
      kRestaurantChallengeType : kAttendanceChallengeType;
    const config = await getChallengeConfigForType(
      type,
      getTrimmedString(data?.month) || getParisMonthKey(),
    );
    validateDrawExecutionOrThrow(config, getNowTimestamp(admin));
    return drawWinnerForMonthlyChallenge(config, "admin");
  });

const drawMonthlyChallengeWinnerScheduled = functions.pubsub
  .schedule("0 1 * * *")
  .timeZone(kTimeZone)
  .onRun(async () => {
    const now = getNowTimestamp(admin);
    const [configsSnap, legacySnap] = await Promise.all([
      db.collection(kMonthlyChallengesCollection).where("enabled", "==", true).get(),
      getMonthlyChallengeConfigRef().get(),
    ]);
    const configs = configsSnap.docs.map((snap) =>
      normalizeMonthlyChallengeConfig(snap.data() || {}),
    );
    const legacy = normalizeMonthlyChallengeConfig(
      legacySnap.exists ? legacySnap.data() || {} : {},
    );
    if (legacy.enabled && !configs.some((config) =>
      config.type === kAttendanceChallengeType && config.month === legacy.month,
    )) {
      configs.push({...legacy, challenge_id: legacy.month, type: kAttendanceChallengeType});
    }
    await Promise.all(configs.map(async (config) => {
      try {
        validateDrawExecutionOrThrow(config, now);
        await drawWinnerForMonthlyChallenge(config, "scheduled");
      } catch (_error) {
        // A draw is only eligible after its configured date.
      }
    }));
    return null;
  });

module.exports = {
  normalizeMonthlyChallengeConfig,
  buildChallengeStateResponse,
  trackMonthlyChallengeParticipation,
  trackMonthlyChallengesParticipation,
  prefetchMonthlyChallengeParticipationState,
  prefetchActiveMonthlyChallenges,
  queueMonthlyChallengeNotifications,
  ensureChallengeQualificationForUser,
  reconcileMonthlyChallengeEligibility,
  drawWinnerForMonthlyChallenge,
  getMonthlyChallengeStateCallable,
  getMonthlyChallengesStateCallable,
  adminGetMonthlyChallengeConfigCallable,
  adminUpsertMonthlyChallengeCallable,
  adminGetMonthlyChallengeStatsCallable,
  adminRunMonthlyChallengeDrawCallable,
  drawMonthlyChallengeWinnerScheduled,
  buildProgressDistributionRanges,
  buildMonthlyChallengeTimeline,
  computeMonthlyChallengeStats,
  getParisMonthKey,
  getParisDayKey,
};

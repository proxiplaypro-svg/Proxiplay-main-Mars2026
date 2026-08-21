const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const nodemailer = require("nodemailer");
const {
  pickDueInstantWinner,
  toMillis,
} = require("./lib/instant_winners_core");

const {
  queuePushNotificationRequest,
} = require("./push_notification_request.js");
const {
  trackMonthlyChallengesParticipation,
  prefetchActiveMonthlyChallenges,
  queueMonthlyChallengeNotifications,
} = require("./monthly_challenge.js");

const db = admin.firestore();

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

function getTrimmedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeRemainingPartValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const trimmed = getTrimmedString(value);
  if (!trimmed) {
    return null;
  }
  const parsed = Number.parseInt(trimmed, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function describeRemainingPartState(value) {
  if (value === null || typeof value === "undefined") {
    return "absent";
  }
  return normalizeRemainingPartValue(value) === null ? "invalid" : "valid";
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

function toBoolean(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "1", "yes", "y", "on"].includes(normalized)) {
      return true;
    }
    if (["false", "0", "no", "n", "off"].includes(normalized)) {
      return false;
    }
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  return fallback;
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
  return {
    transporter: nodemailer.createTransport({
      host: settings.host,
      port: settings.port,
      secure: settings.secure,
      auth: {
        user: settings.user,
        pass: settings.pass,
      },
    }),
    from: `${settings.fromName} <${settings.fromEmail}>`,
    replyTo: settings.replyTo,
  };
}

async function sendEmailNotification(mailer, to, subject, text, html = "") {
  await mailer.transporter.sendMail({
    from: mailer.from,
    to,
    subject,
    text,
    ...(html ? { html } : {}),
    ...(mailer.replyTo ? { replyTo: mailer.replyTo } : {}),
  });
}

function getParisDayKey(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = parts.find((p) => p.type === "year")?.value || "";
  const month = parts.find((p) => p.type === "month")?.value || "";
  const day = parts.find((p) => p.type === "day")?.value || "";
  return `${year}${month}${day}`;
}

// Reads back the outcome of the player's most recent play of this game
// (win/lose message, bonus, prize) from participants_details/{uid}.last_result,
// written right after a successful participation (see below). Used so that a
// player who retries after already having played today gets their real
// result back instead of a dead-end "you already played" message — notably
// covers the case where the first participation committed server-side but
// the game screen never rendered (crash, closed app, lost navigation).
// Returns null for docs written before this field existed, or if the shape
// looks off, so the caller can fall back to the previous generic message.
function resolveCachedLastResult(detailData) {
  const cached = detailData && detailData.last_result;
  if (!cached || typeof cached !== "object") {
    return null;
  }
  const message = getTrimmedString(cached.message);
  if (!message) {
    return null;
  }
  return {
    message,
    messageBonus: getTrimmedString(cached.messageBonus),
    isWin: cached.isWin === true,
    prize_id:
      typeof cached.prize_id === "string" && cached.prize_id
        ? cached.prize_id
        : null,
  };
}

function sanitizeDisplayText(value) {
  if (typeof value !== "string") return "";
  let output = value;

  const replacements = {
    "\u00C3\u00A9": "\u00E9",
    "\u00C3\u00A8": "\u00E8",
    "\u00C3\u00A0": "\u00E0",
    "\u00C3\u00A2": "\u00E2",
    "\u00C3\u00AA": "\u00EA",
    "\u00C3\u00AE": "\u00EE",
    "\u00C3\u00B4": "\u00F4",
    "\u00C3\u00BB": "\u00FB",
    "\u00C3\u00A7": "\u00E7",
    "\u00E2\u20AC\u2122": "'",
    "\u00E2\u20AC\u02DC": "'",
    "\u00E2\u20AC\u0153": "\"",
    "\u00E2\u20AC\u009D": "\"",
    "\u00E2\u20AC\u00A6": "...",
    "\u00E2\u20AC\u0093": "-",
    "\u00E2\u20AC\u0094": "-",
    "\u00E2\u20AC\u00AC": "\u20AC",
    "\u00C2\u00A0": " ",
  };

  Object.entries(replacements).forEach(([source, target]) => {
    output = output.split(source).join(target);
  });

  output = output.replace(/\u00F0[\u0080-\u00BF]{2,4}/g, "");
  output = output.replace(/\u00C3[\u0080-\u00BF]/g, "");
  output = output.replace(/\u00E2[\u0080-\u00BF]{1,2}/g, "");
  output = output.replace(/ð[\wÀ-ÿ]*/g, "");
  output = output.replace(/Ã[\wÀ-ÿ]*/g, "");
  output = output.replace(/[^\t\n\r\x20-\x7E\u00A0-\u00FF]/g, "");
  output = output.replace(/\s+/g, " ").trim();
  output = output.replace(/^[^A-Za-zÀ-ÖØ-öø-ÿ0-9]+/, "");
  return output;
}

function hasUnlimitedAccess(userData, now) {
  const accessUntil = userData && userData.allGamesAccessUntil;
  if (!accessUntil || typeof accessUntil.toMillis !== "function") {
    return false;
  }
  return accessUntil.toMillis() > now.toMillis();
}

function getParisDateParts(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  return {
    year: Number(parts.find((part) => part.type === "year")?.value || 0),
    month: Number(parts.find((part) => part.type === "month")?.value || 0),
    day: Number(parts.find((part) => part.type === "day")?.value || 0),
  };
}

function readBirthdayDate(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value.toDate === "function") {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
  }
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function isAdultFromBirthday(birthdayValue, now = new Date()) {
  const birthday = readBirthdayDate(birthdayValue);
  if (!birthday) {
    return false;
  }
  const todayParts = getParisDateParts(now);
  const birthdayParts = getParisDateParts(birthday);
  let age = todayParts.year - birthdayParts.year;
  if (
    todayParts.month < birthdayParts.month ||
    (todayParts.month === birthdayParts.month &&
      todayParts.day < birthdayParts.day)
  ) {
    age -= 1;
  }
  return age >= 18;
}

/**
 * Calcule le statut du joueur basé sur son activité réelle.
 * 
 * Règles :
 * - actif: dernière activité <= 7 jours OU (dernier <= 14 jours ET games_played >= 3)
 * - a_relancer: dernier 8-30 jours OU (compte > 7 jours ET games_played <= 2)
 * - dormant: dernier 31-90 jours OU (compte > 30 jours ET games_played <= 1)
 * - mort_probable: dernier > 90 jours OU (compte > 60 jours ET 0 participation)
 * - statut_inconnu: données manquantes ou incohérentes
 * 
 * @param userData - Document utilisateur avec created_time, last_real_activity_at, games_played_count
 * @param now - Timestamp serveur actuel
 * @returns {string} - Un des statuts ci-dessus
 */
function calculatePlayerStatus(userData, now) {
  // Vérifier les données requises
  if (!userData || !userData.created_time) {
    return 'statut_inconnu';
  }

  const createdTime = userData.created_time;
  const lastActivityAt = userData.last_real_activity_at;
  const gamesPlayed = userData.games_played_count || 0;

  // Convertir les timestamps Firestore en millisecondes
  const nowMs = now.toMillis ? now.toMillis() : now;
  const createdMs = createdTime.toMillis ? createdTime.toMillis() : createdTime;
  const lastActivityMs = lastActivityAt
    ? (lastActivityAt.toMillis ? lastActivityAt.toMillis() : lastActivityAt)
    : null;

  // Calculer les délais en jours
  const accountAgeDays = Math.floor((nowMs - createdMs) / (1000 * 60 * 60 * 24));
  const daysSinceActivity = lastActivityMs
    ? Math.floor((nowMs - lastActivityMs) / (1000 * 60 * 60 * 24))
    : null;

  // Règle 1 : ACTIF
  if (lastActivityMs !== null) {
    if (daysSinceActivity <= 7) {
      return 'actif';
    }
    if (daysSinceActivity <= 14 && gamesPlayed >= 3) {
      return 'actif';
    }
  }

  // Règle 2 : À RELANCER
  if (lastActivityMs !== null && daysSinceActivity >= 8 && daysSinceActivity <= 30) {
    return 'a_relancer';
  }
  if (accountAgeDays > 7 && gamesPlayed <= 2) {
    return 'a_relancer';
  }

  // Règle 3 : DORMANT
  if (lastActivityMs !== null && daysSinceActivity >= 31 && daysSinceActivity <= 90) {
    return 'dormant';
  }
  if (accountAgeDays > 30 && gamesPlayed <= 1) {
    return 'dormant';
  }

  // Règle 4 : MORT PROBABLE
  if (accountAgeDays > 60 && gamesPlayed === 0) {
    return 'mort_probable';
  }
  if (lastActivityMs !== null && daysSinceActivity > 90) {
    return 'mort_probable';
  }

  // Par défaut
  return 'statut_inconnu';
}

function formatParisTimestamp(date = new Date()) {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date).replace(" ", "T");
}

function traceSerializable(value) {
  if (value === null || typeof value === "undefined") {
    return value;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (value && typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  if (value && typeof value.path === "string") {
    return value.path;
  }
  if (Array.isArray(value)) {
    return value.map((item) => traceSerializable(item));
  }
  if (typeof value === "object") {
    const output = {};
    for (const [key, entry] of Object.entries(value)) {
      output[key] = traceSerializable(entry);
    }
    return output;
  }
  return value;
}

function logParticipationTrace(attemptId, stage, payload = {}) {
  return;
}

exports.participateInGameTransaction = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Vous devez être connecté pour participer."
      );
    }

    let gameRefPath = data.gameRef;
    const fromQr = data.from_qr === true;
    const attemptId =
      typeof data.attemptId === "string" && data.attemptId.trim().length > 0
        ? data.attemptId.trim()
        : `missing_attempt_${Date.now()}`;
    logParticipationTrace(attemptId, "cloud_function_enter", {
      uid: context.auth.uid,
      gameRefPath,
      fromQr,
      payload: data,
    });
    console.log("gameRefPath reçu:", gameRefPath);

    if (!gameRefPath || typeof gameRefPath !== "string" || gameRefPath === "") {
      console.error("gameRefPath est invalide:", gameRefPath);
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Référence du jeu invalide."
      );
    }

    const gameRef = db.collection("games").doc(gameRefPath);
    console.log("gameRef Firestore path:", gameRef.path);

    let responseData = {};
    let transactionDecision = "unknown";
    let finalLastPlayIso = null;
    let finalRemainingPartValue = null;
    const modifiedDocs = [];
    let uid = "";
    let userEmail = "";
    let enseigneName = "";
    let lotDetails = "";
    let claim_code = "";
    let enseigneRef = null;
    let ownerRef = null;
    let userRef = null;
    let lotGagne = false;
    let gameName = "";
    let monthlyChallengeResult = null;

    try {
      await db.runTransaction(async (transaction) => {
        const now = admin.firestore.Timestamp.now();
        uid = context.auth.uid;
        const dayKey = getParisDayKey(new Date());
        const participantDocId = `${dayKey}_${uid}`;

        const participantsRef = gameRef.collection("participants");
        userRef = db.collection("users").doc(uid);
        const participantTodayRef = participantsRef.doc(participantDocId);
        const uniquePlayerRef = gameRef
          .collection("unique_players")
          .doc(uid);

        const participantDetailRef = gameRef
          .collection("participants_details")
          .doc(uid);
        const recordWrite = (op, ref, payload) => {
          const entry = {
            op,
            path: ref.path,
            fields: Object.keys(payload || {}),
          };
          modifiedDocs.push(entry);
          logParticipationTrace(attemptId, "firestore_write_queued", entry);
        };

        console.log("UserRef Firestore path:", userRef.path);

        const [
          gameDoc,
          userDoc,
          participantTodayDoc,
          participantDetailDoc,
          uniquePlayerDoc,
        ] =
          await Promise.all([
            transaction.get(gameRef),
            transaction.get(userRef),
            transaction.get(participantTodayRef),
            transaction.get(participantDetailRef),
            transaction.get(uniquePlayerRef),
          ]);

        // Must happen before any transaction.set()/update() below --
        // Firestore requires every read in a transaction to complete before
        // its first write, and trackMonthlyChallengeParticipation() (called
        // further down, after the "already played" / "no remaining part"
        // guards) does its own reads unless handed this prefetch.
        const monthlyChallengePrefetch = await prefetchActiveMonthlyChallenges({
          uid,
          userRef,
          now,
          transaction,
        });

        // 1. Référence à la sous-collection
        const instantWinnersRef = gameRef.collection("instant_winners");

        // 2. Query tous les instants gagnants echus et encore ouverts.
        // Si plusieurs creneaux sont deja depasses, on ne garde comme
        // gagnant eligible que le plus recent. Les plus anciens sont
        // expires pour eviter une cascade de gains a chaque participation.
        const instantWinnersQuery = instantWinnersRef
          .where("hasWinner", "==", false)
          .where("date", "<=", now)
          .orderBy("date", "asc");

        // 3. Exécuter la query dans la transaction
        const instantWinnerSnap = await transaction.get(instantWinnersQuery);
        let eligibleInstantWinnerDoc = null;
        let remainingDueInstantWinnerDocs = [];
        if (!instantWinnerSnap.empty) {
          const dueInstantWinnerDocs = instantWinnerSnap.docs;
          const selection = pickDueInstantWinner(dueInstantWinnerDocs);
          eligibleInstantWinnerDoc = selection.selected;
          remainingDueInstantWinnerDocs = selection.remaining;

          if (remainingDueInstantWinnerDocs.length > 0) {
            console.log(
              `participateInGameTransaction: gameId=${gameRef.id} dueInstantWinners=${dueInstantWinnerDocs.length} selectedInstantWinnerId=${eligibleInstantWinnerDoc.id}`
            );
          }
        }

        if (!gameDoc.exists) {
          throw new functions.https.HttpsError("not-found", "Le jeu n'existe pas.");
        }
        if (!userDoc.exists) {
          throw new functions.https.HttpsError("not-found", "Utilisateur introuvable.");
        }

        const gameData = gameDoc.data();
        if (gameData.access_mode === "qr_only" && fromQr !== true) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Ce jeu nécessite un scan QR code en boutique."
          );
        }
        const userData = userDoc.data();
        if (gameData.prohibited_for_minors === true) {
          if (!readBirthdayDate(userData.birthday)) {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "Ce jeu est reserve aux personnes majeures. Merci de renseigner votre date de naissance."
            );
          }
          if (!isAdultFromBirthday(userData.birthday, now.toDate())) {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "Ce jeu est reserve aux personnes majeures."
            );
          }
        }
        const gameStartDateMs = toMillis(gameData.start_date);
        const gameEndDateMs = toMillis(gameData.end_date);
        const nowMs = now.toMillis();
        if (
          !Number.isFinite(gameStartDateMs) ||
          !Number.isFinite(gameEndDateMs) ||
          gameStartDateMs > gameEndDateMs
        ) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Les dates du jeu sont invalides."
          );
        }
        if (nowMs < gameStartDateMs || nowMs > gameEndDateMs) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Ce jeu n'est pas disponible actuellement."
          );
        }
        userEmail = getTrimmedString(userData.email);
        ownerRef = gameData.create_by?.path
          ? db.doc(gameData.create_by.path)
          : null;
        const enseigneRefField = gameData.enseigne_id || gameData.enseigne_ref;
        enseigneRef = enseigneRefField?.path
          ? db.doc(enseigneRefField.path)
          : null;
        gameName = getTrimmedString(gameData.name);

        if (!enseigneRef) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "L'enseigne associée au jeu est introuvable."
          );
        }

        // Récupérer l'enseigne avant toute écriture transactionnelle
        const enseigneDoc = await transaction.get(enseigneRef);
        if (!enseigneDoc.exists) {
          throw new functions.https.HttpsError(
            "not-found",
            "L'enseigne associée au jeu n'existe pas."
          );
        }
        const enseigneData = enseigneDoc.data();
        if (!ownerRef && enseigneData?.owner?.path) {
          ownerRef = db.doc(enseigneData.owner.path);
        }
        enseigneName = getTrimmedString(enseigneData.name);

        const currentParticipation = gameData.participations || 0;
        const newPosition = currentParticipation + 1;
        const remainingPartState = describeRemainingPartState(
          userData.remaining_part
        );
        const normalizedRemainingPart = normalizeRemainingPartValue(
          userData.remaining_part
        );
        const remainingPart =
          normalizedRemainingPart === null ? 3 : normalizedRemainingPart;
        const alreadyParticipatedToday = participantTodayDoc.exists;
        const unlimitedAccessActive = hasUnlimitedAccess(userData, now);
        let uniquePlayerNew = false;
        const participantDetailData = participantDetailDoc.exists
          ? participantDetailDoc.data()
          : null;
        const participantDetailLastPlay =
          participantDetailData?.last_play?.toDate?.() || null;

        logParticipationTrace(attemptId, "transaction_state_loaded", {
          uid,
          gameId: gameRef.id,
          dayKey,
          remainingPart,
          unlimitedAccessActive,
          alreadyParticipatedToday,
          participantTodayExists: participantTodayDoc.exists,
          participantDetailExists: participantDetailDoc.exists,
          participantDetailLastPlay,
          fromQr,
        });

        console.log(
          `[participateInGameTransaction] uid=${uid} gameId=${gameRef.id} remaining_part_state=${remainingPartState} remaining_part_value=${remainingPart} unlimitedAccess=${unlimitedAccessActive}`
        );

        // Détection lot principal (sert uniquement à la cohérence des champs, pas au message de perte)
        const hasMainPrizeField = Object.prototype.hasOwnProperty.call(
          gameData || {},
          "hasMainPrize"
        );
        const hasMainPrize = hasMainPrizeField
          ? gameData.hasMainPrize === true
          : (
              (typeof gameData.name === "string" && gameData.name.trim().length > 0) ||
              (typeof gameData.description === "string" && gameData.description.trim().length > 0) ||
              (gameData.prize_value !== null && typeof gameData.prize_value !== "undefined")
            );

        // Patch cohérence: si pas de lot principal -> pas de winner / tirage au sort
        const gameConsistencyPatch = {};
        if (!hasMainPrizeField) {
          gameConsistencyPatch.hasMainPrize = hasMainPrize;
        }
        if (
          !hasMainPrize &&
          (gameData.hasWinner === true || !!gameData.main_prize_winner)
        ) {
          logHasWinnerWrite({
            gameId: gameRef.id,
            previousValue: gameData.hasWinner === true,
            newValue: false,
            sourceFunction: "participateInGameTransaction",
            winnerType: "correction-coherence",
            hasMainPrize,
            endDate:
              gameData.end_date?.toDate?.()?.toISOString?.() ||
              gameData.end_date ||
              null,
          });
          gameConsistencyPatch.hasWinner = false;
          gameConsistencyPatch.main_prize_winner = null;
        }
        let animationEntryRef = null;
        let animationEntryDoc = null;
        let visitedMerchantIds = [];
        let thresholdReached = false;
        let shouldUpdateAnimationEntry = false;

        try {
          const animationId =
            typeof gameData.animation_id === "string"
              ? gameData.animation_id.trim()
              : "";

          if (animationId) {
            const animationRef = db.collection("animations").doc(animationId);
            const animationDoc = await transaction.get(animationRef);

            if (animationDoc.exists) {
              const animationData = animationDoc.data() || {};
              const status = animationData.status;
              const startDate = animationData.start_date;
              const endDate = animationData.end_date;
              const nowMillis = now.toMillis();
              const startMillis =
                startDate && typeof startDate.toMillis === "function"
                  ? startDate.toMillis()
                  : null;
              const endMillis =
                endDate && typeof endDate.toMillis === "function"
                  ? endDate.toMillis()
                  : null;
              const isActiveAnimation =
                status === "active" &&
                startMillis !== null &&
                endMillis !== null &&
                nowMillis >= startMillis &&
                nowMillis <= endMillis;

              if (isActiveAnimation) {
                animationEntryRef = animationRef
                  .collection("entries")
                  .doc(uid);
                animationEntryDoc = await transaction.get(animationEntryRef);
                const animationEntryData = animationEntryDoc.exists
                  ? animationEntryDoc.data() || {}
                  : {};
                const rawVisitedMerchantIds =
                  animationEntryData.visited_merchant_ids;
                visitedMerchantIds = Array.isArray(rawVisitedMerchantIds)
                  ? rawVisitedMerchantIds.map((merchantId) => merchantId.toString())
                  : [];
                const merchantId = enseigneRef.id;

                if (merchantId && !visitedMerchantIds.includes(merchantId)) {
                  visitedMerchantIds.push(merchantId);

                  const threshold = Number.isInteger(animationData.threshold)
                    ? animationData.threshold
                    : parseInt(animationData.threshold, 10) || 0;
                  const visitedCount = visitedMerchantIds.length;
                  thresholdReached = visitedCount >= threshold;
                  shouldUpdateAnimationEntry = true;
                }
              }
            }
          }
        } catch (animationError) {
          console.error(
            `participateInGameTransaction: animation tracking skipped for gameId=${gameRef.id} uid=${uid}`,
            animationError
          );
        }

        if (!uniquePlayerDoc.exists) {
          uniquePlayerNew = true;
        }

        if (alreadyParticipatedToday) {
          transactionDecision = "already_played_participant_today";
          finalLastPlayIso = traceSerializable(participantDetailLastPlay);
          finalRemainingPartValue = remainingPart;
          console.log(
            `participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=true uniquePlayerNew=${uniquePlayerNew}`
          );
          const cachedResult = resolveCachedLastResult(
            participantDetailDoc.exists ? participantDetailDoc.data() : null
          );
          responseData = {
            ...(cachedResult || {
              message: "Vous avez déjà participé aujourd'hui.",
              messageBonus: "",
              isWin: false,
              prize_id: null,
            }),
            alreadyParticipatedToday: true,
          };
          logParticipationTrace(attemptId, "transaction_decision", {
            uid,
            gameId: gameRef.id,
            decision: transactionDecision,
            responseData,
            finalLastPlayIso,
            finalRemainingPartValue,
          });
          return;
        }

        // Bonus/jour
        if (participantDetailDoc.exists) {
          const detailData = participantDetailDoc.data();
          const lastPlay = detailData.last_play?.toDate?.();
          const hasPlayedToday =
            !!lastPlay && getParisDayKey(lastPlay) === dayKey;
          const bonus = detailData.game_bonus || 0;

          if (hasPlayedToday && bonus <= 0) {
            transactionDecision = "already_played_last_play_no_bonus";
            finalLastPlayIso = traceSerializable(lastPlay);
            finalRemainingPartValue = remainingPart;
            console.log(
              `participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=true(unique-last-play) uniquePlayerNew=${uniquePlayerNew}`
            );
            const cachedResult = resolveCachedLastResult(detailData);
            responseData = {
              ...(cachedResult || {
                message: "Vous avez déjà participé aujourd'hui.",
                messageBonus: "",
                isWin: false,
                prize_id: null,
              }),
              alreadyParticipatedToday: true,
            };
            logParticipationTrace(attemptId, "transaction_decision", {
              uid,
              gameId: gameRef.id,
              decision: transactionDecision,
              responseData,
              finalLastPlayIso,
              finalRemainingPartValue,
            });
            return;
          }

          if (hasPlayedToday && bonus > 0) {
            transactionDecision = "already_played_last_play_bonus";
            finalLastPlayIso = traceSerializable(lastPlay);
            finalRemainingPartValue = remainingPart;
            console.log(
              `participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=true(bonus) uniquePlayerNew=${uniquePlayerNew}`
            );
            const cachedResult = resolveCachedLastResult(detailData);
            responseData = {
              ...(cachedResult || {
                message: "Vous avez déjà participé aujourd'hui.",
                messageBonus: "",
                isWin: false,
                prize_id: null,
              }),
              alreadyParticipatedToday: true,
            };
            logParticipationTrace(attemptId, "transaction_decision", {
              uid,
              gameId: gameRef.id,
              decision: transactionDecision,
              responseData,
              finalLastPlayIso,
              finalRemainingPartValue,
            });
            return;
          } else {
            recordWrite("set", participantDetailRef, {
              last_play: now,
              game_bonus: bonus,
              user_id: userRef,
            });
            transaction.set(
              participantDetailRef,
              {
                last_play: now,
                game_bonus: bonus,
                user_id: userRef,
              },
              { merge: true }
            );
          }
        } else {
          recordWrite("set", participantDetailRef, {
            last_play: now,
            game_bonus: 0,
            user_id: userRef,
          });
          transaction.set(participantDetailRef, {
            last_play: now,
            game_bonus: 0,
            user_id: userRef,
          });
        }

        // Verifie APRES les trois retours anticipes "deja joue" ci-dessus :
        // un joueur qui relit son resultat d'une partie deja jouee
        // (remaining_part deja decremente sur cette meme partie) ne doit
        // jamais tomber sur ce message a la place de son vrai resultat en
        // cache. Ne s'applique qu'a une VRAIE nouvelle participation.
        if (remainingPart <= 0 && !unlimitedAccessActive) {
          transactionDecision = "no_remaining_part";
          finalLastPlayIso = traceSerializable(participantDetailLastPlay);
          finalRemainingPartValue = remainingPart;
          logParticipationTrace(attemptId, "transaction_decision", {
            uid,
            gameId: gameRef.id,
            decision: transactionDecision,
            finalLastPlayIso,
            finalRemainingPartValue,
          });
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Vous n'avez plus de parties disponibles."
          );
        }

        monthlyChallengeResult = await trackMonthlyChallengesParticipation({
          uid,
          userRef,
          now,
          transaction,
          prefetched: monthlyChallengePrefetch,
        });

        // Enregistrer participation
        if (Object.keys(gameConsistencyPatch).length > 0) {
          recordWrite("update", gameRef, gameConsistencyPatch);
          transaction.update(gameRef, gameConsistencyPatch);
        }

        if (uniquePlayerNew) {
          recordWrite("set", uniquePlayerRef, {
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          transaction.set(uniquePlayerRef, {
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          recordWrite("update", gameRef, {
            unique_players_count: admin.firestore.FieldValue.increment(1),
          });
          transaction.update(gameRef, {
            unique_players_count: admin.firestore.FieldValue.increment(1),
          });
        }

        recordWrite("set", participantTodayRef, {
          user_id: userRef,
          participation_date: now,
        });
        transaction.set(participantTodayRef, {
          user_id: userRef,
          participation_date: now,
        });

        if (shouldUpdateAnimationEntry && animationEntryRef) {
          recordWrite("set", animationEntryRef, {
            uid,
            visited_merchant_ids: visitedMerchantIds,
            visited_count: visitedMerchantIds.length,
            threshold_reached: thresholdReached,
            last_updated: now,
          });
          transaction.set(
            animationEntryRef,
            {
              uid,
              visited_merchant_ids: visitedMerchantIds,
              visited_count: visitedMerchantIds.length,
              threshold_reached: thresholdReached,
              last_updated: now,
            },
            { merge: true }
          );
        }

        recordWrite("update", gameRef, {
          participations: admin.firestore.FieldValue.increment(1),
        });
        transaction.update(gameRef, {
          participations: admin.firestore.FieldValue.increment(1),
        });

        let messageBonus = "";
        let remainingPartDelta = 0;
        if (!unlimitedAccessActive) {
          remainingPartDelta -= 1;
        }

        // Bonus toutes les 10 participations
        if (newPosition % 10 === 0) {
          remainingPartDelta += 3;
          messageBonus = "Vous avez gagné 3 parties supplémentaires !";
        }

        // Mettre à jour l'activité réelle du joueur et les statistiques
        const userUpdateData = {
          last_real_activity_at: now,
          games_played_count: admin.firestore.FieldValue.increment(1),
        };

        if (remainingPartDelta !== 0 || normalizedRemainingPart === null) {
          userUpdateData.remaining_part = remainingPart + remainingPartDelta;
          if (!userData.part_last_update) {
            userUpdateData.part_last_update = admin.firestore.FieldValue.serverTimestamp();
          }
        }

        // Calculer le nouveau statut du joueur basé sur son activité
        // Remarque : games_played_count est déjà incrémenté ci-dessus,
        // mais la transaction n'a pas encore committée. On doit passer la valeur future.
        const projectedGamesPlayedCount = (userData.games_played_count || 0) + 1;
        const projectedUserData = {
          ...userData,
          last_real_activity_at: now,
          games_played_count: projectedGamesPlayedCount,
        };
        userUpdateData.player_status_cached = calculatePlayerStatus(projectedUserData, now);

        recordWrite("update", userRef, userUpdateData);
        transaction.update(userRef, userUpdateData);

        // Lots (gains immédiats uniquement)
        let transactionLotGagne = false;
        let transactionLotDetails = null;
        let prizeRef = null;

        if (eligibleInstantWinnerDoc) {
          const instantWinnerData = eligibleInstantWinnerDoc.data() || {};

          const generatedClaimCode = generateClaimCode();
          const selectedSecondaryPrizeName =
            typeof instantWinnerData.secondary_prize_name === "string" &&
            instantWinnerData.secondary_prize_name.trim().length > 0
              ? instantWinnerData.secondary_prize_name.trim()
              : "Lot secondaire";
          const selectedSecondaryPrizePresentation =
            typeof instantWinnerData.secondary_prize_presentation === "string"
              ? instantWinnerData.secondary_prize_presentation.trim()
              : "";

          logHasWinnerWrite({
            gameId: gameRef.id,
            previousValue: instantWinnerData.hasWinner === true,
            newValue: true,
            sourceFunction: "participateInGameTransaction",
            winnerType: "gain-instantane",
            hasMainPrize,
            endDate:
              gameData.end_date?.toDate?.()?.toISOString?.() ||
              gameData.end_date ||
              null,
          });
          transaction.update(eligibleInstantWinnerDoc.ref, {
            hasWinner: true,
            player_id: userRef,
          });
          recordWrite("update", eligibleInstantWinnerDoc.ref, {
            hasWinner: true,
            player_id: userRef,
          });

          prizeRef = db.collection("prizes").doc();

          // userData est deja en memoire (charge plus haut dans la meme
          // transaction) : denormaliser prenom/ville ici evite a l'app
          // d'avoir a relire le profil du gagnant pour l'afficher ailleurs.
          const secondaryWinnerFirstName = getTrimmedString(
            userData.first_name || userData.firstName,
          ).split(/\s+/)[0] || "";
          const secondaryWinnerCity = getTrimmedString(userData.city);
          const secondaryDenormalizedWinnerFields = {
            ...(secondaryWinnerFirstName
              ? {
                  winnerFirstName: secondaryWinnerFirstName,
                  winner_first_name: secondaryWinnerFirstName,
                }
              : {}),
            ...(secondaryWinnerCity
              ? {
                  winnerCity: secondaryWinnerCity,
                  winner_city: secondaryWinnerCity,
                }
              : {}),
          };

          recordWrite("set", prizeRef, {
            prize_type: "secondaire",
            name: selectedSecondaryPrizeName,
            description: selectedSecondaryPrizePresentation,
            winner_id: userRef,
            game_id: gameRef,
            enseigne_id: enseigneRef,
            enseigne_name: enseigneName,
            owner_id: ownerRef,
            claim_code: normalizeClaimCode(generatedClaimCode),
            claimed: false,
            win_date: now,
          });
          transaction.set(prizeRef, {
            prize_type: "secondaire",
            name: selectedSecondaryPrizeName,
            description: selectedSecondaryPrizePresentation,
            winner_id: userRef,
            game_id: gameRef,
            enseigne_id: enseigneRef,
            enseigne_name: enseigneName,
            owner_id: ownerRef,
            claim_code: normalizeClaimCode(generatedClaimCode),
            claimed: false,
            win_date: now,
            ...(gameData.prize_usage_deadline
              ? { usage_deadline: gameData.prize_usage_deadline }
              : {}),
            ...secondaryDenormalizedWinnerFields,
          });

          const userLotRef = userRef.collection("my_lots").doc(prizeRef.id);
          recordWrite("set", userLotRef, {
            prize_id: prizeRef,
          });
          transaction.set(userLotRef, {
            prize_id: prizeRef,
          });

          transactionLotGagne = true;
          transactionLotDetails = selectedSecondaryPrizeName;
          lotGagne = true;
          lotDetails = selectedSecondaryPrizeName;
          claim_code = normalizeClaimCode(generatedClaimCode);
        }

        // Messages aleatoires a afficher en cas de perte
        const loseMessages = [
          "Retente ta chance demain !",
          "A demain pour une nouvelle partie.",
          "Reviens demain pour une nouvelle tentative !",
        ];

        // Message principal renvoye a l'app :
        // - Si gain immédiat => lotDetails
        // - Si perte => message aléatoire (même si pas de lot principal)
        const message = transactionLotGagne
          ? transactionLotDetails
          : loseMessages[Math.floor(Math.random() * loseMessages.length)];

        responseData = {
          message,
          messageBonus,
          isWin: transactionLotGagne,
          prize_id: prizeRef ? prizeRef.path : null,
          alreadyParticipatedToday: false,
          // Optionnel: garde l'info côté app si besoin un jour
          // hasMainPrize,
        };

        // Cache this outcome on participants_details/{uid} so a later retry
        // that lands on an "already played" branch above can hand the real
        // result back instead of a dead-end message (see
        // resolveCachedLastResult). Purely additive: does not affect
        // remaining_part or any existing field.
        recordWrite("set", participantDetailRef, {
          last_result: {
            message,
            messageBonus,
            isWin: transactionLotGagne,
            prize_id: prizeRef ? prizeRef.path : null,
            recorded_at: now,
          },
        });
        transaction.set(
          participantDetailRef,
          {
            last_result: {
              message,
              messageBonus,
              isWin: transactionLotGagne,
              prize_id: prizeRef ? prizeRef.path : null,
              recorded_at: now,
            },
          },
          { merge: true }
        );

        transactionDecision = "accepted";
        finalLastPlayIso = now.toDate().toISOString();
        finalRemainingPartValue =
          remainingPartDelta !== 0 || normalizedRemainingPart === null
            ? remainingPart + remainingPartDelta
            : remainingPart;
        logParticipationTrace(attemptId, "transaction_decision", {
          uid,
          gameId: gameRef.id,
          decision: transactionDecision,
          responseData,
          finalLastPlayIso,
          finalRemainingPartValue,
          modifiedDocs,
        });

        console.log(`participateInGameTransaction: uid=${uid} gameId=${gameRef.id} dayKey=${dayKey} alreadyParticipatedToday=false uniquePlayerNew=${uniquePlayerNew}`);
      });

      console.log("Retour des données FINAL :", responseData);
      responseData = {
        ...responseData,
        message: sanitizeDisplayText(responseData.message || ""),
        messageBonus: sanitizeDisplayText(responseData.messageBonus || ""),
      };
      logParticipationTrace(attemptId, "cloud_function_return_success", {
        uid,
        gameRefPath,
        decision: transactionDecision,
        responseData,
        modifiedDocs,
        finalLastPlayIso,
        finalRemainingPartValue,
      });

      if (lotGagne === true) {
        try {
          const mailer = createSmtpMailer();

          if (userEmail) {
            const playerMailSubject = `🎉 Vous avez gagné chez ${enseigneName} !`;
            const playerMailHtml = `
              <p>Félicitations ! Vous avez gagné : ${lotDetails}</p>
              <p>Rendez-vous chez ${enseigneName} pour récupérer votre lot.</p>
              <p>Code de retrait : ${claim_code}</p>
            `;
            const playerMailText = [
              `Félicitations ! Vous avez gagné : ${lotDetails}`,
              `Rendez-vous chez ${enseigneName} pour récupérer votre lot.`,
              `Code de retrait : ${claim_code}`,
            ].join("\n");

            await sendEmailNotification(
              mailer,
              userEmail,
              playerMailSubject,
              playerMailText,
              playerMailHtml
            );
          }

          let merchantOwnerRef = null;
          if (enseigneRef) {
            const enseigneSnapshot = await enseigneRef.get();
            if (enseigneSnapshot.exists) {
              const enseigneData = enseigneSnapshot.data() || {};
              if (enseigneData.owner) {
                merchantOwnerRef = enseigneData.owner;
                // Warning si owner et create_by divergent
                if (ownerRef && enseigneData.owner.path !== ownerRef.path) {
                  console.warn(
                    `participateInGameTransaction: owner mismatch for gameId=${gameRef.id} — create_by=${ownerRef.path} vs enseigne.owner=${enseigneData.owner.path} — using enseigne.owner`
                  );
                }
              } else {
                // Fallback sur create_by si owner absent
                console.warn(
                  `participateInGameTransaction: enseigne.owner absent for enseigneId=${enseigneRef.id}, falling back to create_by`
                );
                merchantOwnerRef = ownerRef;
              }
            }
          }

          let merchantEmail = "";
          if (merchantOwnerRef) {
            const merchantUserSnap = await merchantOwnerRef.get();
            if (merchantUserSnap.exists) {
              const merchantUserData = merchantUserSnap.data() || {};
              merchantEmail = getTrimmedString(merchantUserData.email);
            }
          }

          if (merchantOwnerRef) {
            await queuePushNotificationRequest(db, {
              title: "🎉 Un joueur a gagné !",
              body: `Un joueur vient de gagner : ${lotDetails}. Code : ${claim_code}. Jeu : ${gameName}`,
              userRefOrPath: merchantOwnerRef,
              createdBy: `system/participate_in_game_transaction/${gameRef.id}`,
            });
          }
        } catch (postTransactionNotificationError) {
          console.error(
            `participateInGameTransaction: post-transaction notifications failed for gameId=${gameRef.id} uid=${uid}`,
            postTransactionNotificationError
          );
        }
      }

      if (monthlyChallengeResult?.tracked === true) {
        try {
          await queueMonthlyChallengeNotifications(
            uid,
            monthlyChallengeResult.notifications,
            ""
          );
        } catch (monthlyChallengeNotificationError) {
          console.error(
            `participateInGameTransaction: monthly challenge notifications failed for gameId=${gameRef.id} uid=${uid}`,
            monthlyChallengeNotificationError
          );
        }
      }

      return responseData;
    } catch (error) {
      logParticipationTrace(attemptId, "cloud_function_return_error", {
        uid: uid || context.auth.uid,
        gameRefPath,
        decision: transactionDecision,
        modifiedDocs,
        finalLastPlayIso,
        finalRemainingPartValue,
        errorCode: error?.code || "internal",
        errorMessage: error?.message || String(error),
      });
      console.error("Erreur lors de la participation au jeu :", error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        "internal",
        error.message || "Une erreur est survenue."
      );
    }
  }
);

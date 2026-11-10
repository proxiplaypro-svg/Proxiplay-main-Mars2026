"use strict";

// Correction de la date de naissance d'un joueur par un administrateur
// (1.1.4). Depuis le verrouillage des regles Firestore, c'est la seule voie
// de modification d'une date deja enregistree.
//
// Minimisation (RGPD) : le journal users/{uid}/birthday_corrections ne
// conserve ni l'ancienne ni la nouvelle date, seulement les tranches d'age
// avant/apres (ce qui explique l'effet de la correction sur les droits du
// joueur), l'administrateur, la date et le motif. Il est supprime avec le
// compte (onUserDeleted). La nouvelle date vit uniquement dans users/{uid}.
//
// Effets immediats : les jeux reserves aux majeurs, les publicites adultes
// et le consentement marketing relisent users/{uid}.birthday a chaque
// appel ; un consentement marketing devenu inadmissible (moins de 15 ans)
// est retire dans la meme transaction, avec un evenement trace. Aucun lot
// deja gagne n'est annule.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {isTrustedAdmin} = require("./admin_identity");

const kMinimumMarketingAge = 15;
const kAdultAge = 18;
const kReasonMinLength = 5;
const kReasonMaxLength = 200;
const kMarketingEventRetentionMs = 3 * 365 * 24 * 60 * 60 * 1000;
const kParisTimeZone = "Europe/Paris";

function getParisDateParts(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: kParisTimeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const read = (type) => Number(parts.find((part) => part.type === type)?.value || 0);
  return {year: read("year"), month: read("month"), day: read("day"),
    hour: read("hour"), minute: read("minute")};
}

// "AAAA-MM-JJ" strict, date calendaire reelle.
function parseIsoDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(typeof value === "string" ? value.trim() : "");
  if (!match) return null;
  const [year, month, day] = match.slice(1).map(Number);
  const probe = new Date(Date.UTC(year, month - 1, day));
  if (probe.getUTCFullYear() !== year || probe.getUTCMonth() !== month - 1 ||
      probe.getUTCDate() !== day) {
    return null;
  }
  return {year, month, day};
}

// Minuit a Paris pour ce jour : meme convention que l'app (date choisie a
// minuit, heure locale) et que les controles d'age serveur (date de Paris).
function parisMidnightMillis({year, month, day}) {
  for (const offsetHours of [1, 2, 0]) {
    const candidate = Date.UTC(year, month - 1, day) - offsetHours * 3600000;
    const parts = getParisDateParts(new Date(candidate));
    if (parts.year === year && parts.month === month && parts.day === day &&
        parts.hour === 0 && parts.minute === 0) {
      return candidate;
    }
  }
  return null;
}

function readBirthdayDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function ageOnParisDate(birthday, now) {
  const today = getParisDateParts(now);
  const born = getParisDateParts(birthday);
  let age = today.year - born.year;
  if (today.month < born.month || (today.month === born.month && today.day < born.day)) {
    age -= 1;
  }
  return age;
}

function ageBand(birthdayValue, now) {
  const birthday = readBirthdayDate(birthdayValue);
  if (!birthday) return "unknown";
  const age = ageOnParisDate(birthday, now);
  if (age < kMinimumMarketingAge) return "under_15";
  if (age < kAdultAge) return "15_17";
  return "18_plus";
}

function isPlayer(userData) {
  return userData.user_role === "joueur" || userData.userRole === "joueur";
}

function sameParisDay(left, right) {
  if (!left || !right) return false;
  const a = getParisDateParts(left);
  const b = getParisDateParts(right);
  return a.year === b.year && a.month === b.month && a.day === b.day;
}

async function adminCorrectPlayerBirthdayHandler(data, context = {}) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
  }
  const db = admin.firestore();
  const callerSnap = await db.collection("users").doc(context.auth.uid).get();
  if (!isTrustedAdmin(context.auth, callerSnap.data() || {})) {
    throw new functions.https.HttpsError("permission-denied", "Reserve a l'administration.");
  }

  const userId = typeof data?.userId === "string" ? data.userId.trim() : "";
  const reason = typeof data?.reason === "string" ? data.reason.trim().replace(/\s+/g, " ") : "";
  const parsed = parseIsoDate(data?.birthday);
  if (!userId || userId.includes("/") || userId.length > 128) {
    throw new functions.https.HttpsError("invalid-argument", "Joueur invalide.");
  }
  if (reason.length < kReasonMinLength || reason.length > kReasonMaxLength) {
    throw new functions.https.HttpsError("invalid-argument",
      `Le motif est obligatoire (${kReasonMinLength} a ${kReasonMaxLength} caracteres).`);
  }
  const nowDate = new Date();
  const birthdayMs = parsed ? parisMidnightMillis(parsed) : null;
  const todayParis = getParisDateParts(nowDate);
  const isFuture = parsed && (parsed.year * 10000 + parsed.month * 100 + parsed.day) >
    (todayParis.year * 10000 + todayParis.month * 100 + todayParis.day);
  if (!parsed || birthdayMs === null || parsed.year < 1900 || isFuture) {
    throw new functions.https.HttpsError("invalid-argument",
      "Date de naissance invalide (AAAA-MM-JJ, entre 1900 et aujourd'hui).");
  }

  const userRef = db.collection("users").doc(userId);
  const correctionRef = userRef.collection("birthday_corrections").doc();
  return db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Joueur introuvable.");
    }
    const userData = userSnap.data() || {};
    if (!isPlayer(userData)) {
      throw new functions.https.HttpsError("failed-precondition",
        "Seule la date de naissance d'un joueur peut etre corrigee.");
    }

    const newBirthday = admin.firestore.Timestamp.fromMillis(birthdayMs);
    const previousBirthday = readBirthdayDate(userData.birthday);
    if (sameParisDay(previousBirthday, newBirthday.toDate())) {
      return {changed: false, marketingConsentWithdrawn: false,
        previousAgeBand: ageBand(userData.birthday, nowDate),
        newAgeBand: ageBand(userData.birthday, nowDate)};
    }

    const previousAgeBand = ageBand(userData.birthday, nowDate);
    const newAgeBand = ageBand(newBirthday, nowDate);
    const consent = userData.marketing_consent;
    const withdrawMarketing = newAgeBand === "under_15" && consent?.enabled === true;
    const serverNow = admin.firestore.FieldValue.serverTimestamp();

    const userPatch = {birthday: newBirthday};
    if (withdrawMarketing) {
      const withdrawn = {
        enabled: false,
        updated_at: serverNow,
        text_version: consent.text_version || "marketing-player-v1",
        source: "admin-birthday-correction",
        newsletter_eligibility: "age_ineligible",
      };
      userPatch.marketing_consent = withdrawn;
      transaction.create(userRef.collection("marketing_consent_events").doc(), {
        ...withdrawn,
        event_type: "withdrawn",
        withdrawal_reason: "birthday_correction_under_15",
        retention_until: admin.firestore.Timestamp.fromMillis(Date.now() + kMarketingEventRetentionMs),
      });
    }
    transaction.update(userRef, userPatch);
    transaction.create(correctionRef, {
      corrected_at: serverNow,
      corrected_by: context.auth.uid,
      reason,
      previous_age_band: previousAgeBand,
      new_age_band: newAgeBand,
      had_birthday: previousBirthday !== null,
      marketing_consent_withdrawn: withdrawMarketing,
    });
    return {changed: true, correctionId: correctionRef.id, previousAgeBand, newAgeBand,
      marketingConsentWithdrawn: withdrawMarketing};
  });
}

exports.adminCorrectPlayerBirthday = functions
  .region("us-central1")
  .https.onCall(adminCorrectPlayerBirthdayHandler);

exports._test = {
  adminCorrectPlayerBirthdayHandler,
  ageBand,
  parisMidnightMillis,
  parseIsoDate,
};

// Calendrier de Paris (Europe/Paris), sans dependance : dates civiles,
// fin de journee, et (lot 1.3) jours ouvres francais. Les delais des CGV
// sont exprimes en jours civils ou ouvres a Paris, jamais en heures UTC.

const kZone = "Europe/Paris";
const partsFormatter = new Intl.DateTimeFormat("en-GB", {
  timeZone: kZone, hourCycle: "h23",
  year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
});

function parisParts(ms) {
  const parts = Object.fromEntries(partsFormatter.formatToParts(new Date(ms))
    .filter((p) => p.type !== "literal").map((p) => [p.type, Number(p.value)]));
  return {y: parts.year, m: parts.month, d: parts.day, h: parts.hour, mi: parts.minute, s: parts.second,
    ms: ((ms % 1000) + 1000) % 1000};
}

function offsetMs(ms) {
  const p = parisParts(ms);
  return Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s, p.ms) - ms;
}

/** Heure locale de Paris -> instant UTC (en ms). */
function parisLocalToUtc(y, m, d, h = 0, mi = 0, s = 0, msPart = 0) {
  const local = Date.UTC(y, m - 1, d, h, mi, s, msPart);
  const first = local - offsetMs(local);
  return local - offsetMs(first);
}

function parisDate(ms) {
  const p = parisParts(ms);
  return {y: p.y, m: p.m, d: p.d};
}

function addDays(ymd, days) {
  const date = new Date(Date.UTC(ymd.y, ymd.m - 1, ymd.d + days));
  return {y: date.getUTCFullYear(), m: date.getUTCMonth() + 1, d: date.getUTCDate()};
}

function endOfParisDay(ymd) {
  return parisLocalToUtc(ymd.y, ymd.m, ymd.d, 23, 59, 59, 999);
}

/**
 * Art. 4.2 : signalement d'une visite « dans les quatorze (14) jours suivant
 * la conclusion du contrat ». Le jour de la conclusion ne compte pas (meme
 * computation que l'art. 7.2) : fin de journee, a Paris, du 14e jour suivant.
 */
function visitReportDeadline(conclusionMs) {
  return endOfParisDay(addDays(parisDate(conclusionMs), 14));
}

// ---- lot 1.3 : jours ouvres (lundi a vendredi, hors jours feries francais)

/** Dimanche de Paques (calendrier gregorien, algorithme anonyme). */
function easterSunday(year) {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return {y: year, m: month, d: day};
}

function ymdKey(ymd) {
  return `${ymd.y}-${String(ymd.m).padStart(2, "0")}-${String(ymd.d).padStart(2, "0")}`;
}

const holidayCache = new Map();
/** Les 11 jours feries de France metropolitaine (hors Alsace-Moselle). */
function frenchHolidays(year) {
  if (!holidayCache.has(year)) {
    const easter = easterSunday(year);
    const fixed = ["01-01", "05-01", "05-08", "07-14", "08-15", "11-01", "11-11", "12-25"].map((md) => `${year}-${md}`);
    const moving = [1, 39, 50].map((offset) => ymdKey(addDays(easter, offset))); // lundi de Paques, Ascension, lundi de Pentecote
    holidayCache.set(year, new Set([...fixed, ...moving]));
  }
  return holidayCache.get(year);
}

function isBusinessDay(ymd) {
  const weekday = new Date(Date.UTC(ymd.y, ymd.m - 1, ymd.d)).getUTCDay();
  return weekday >= 1 && weekday <= 5 && !frenchHolidays(ymd.y).has(ymdKey(ymd));
}

/**
 * Ajoute n jours ouvres a un instant, en gardant l'heure de Paris. Une
 * demande recue un jour non ouvre compte a partir du debut du jour ouvre
 * suivant.
 */
function addBusinessDays(ms, n) {
  const p = parisParts(ms);
  let ymd = {y: p.y, m: p.m, d: p.d};
  let time = [p.h, p.mi, p.s, p.ms];
  if (!isBusinessDay(ymd)) {
    do ymd = addDays(ymd, 1); while (!isBusinessDay(ymd));
    time = [0, 0, 0, 0];
  }
  for (let count = 0; count < n; count++) {
    do ymd = addDays(ymd, 1); while (!isBusinessDay(ymd));
  }
  return parisLocalToUtc(ymd.y, ymd.m, ymd.d, ...time);
}

module.exports = {
  easterSunday,
  frenchHolidays,
  isBusinessDay,
  addBusinessDays,
  kZone,
  parisParts,
  parisLocalToUtc,
  parisDate,
  addDays,
  endOfParisDay,
  visitReportDeadline,
};

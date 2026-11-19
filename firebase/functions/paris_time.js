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

module.exports = {
  kZone,
  parisParts,
  parisLocalToUtc,
  parisDate,
  addDays,
  endOfParisDay,
  visitReportDeadline,
};

"use strict";

// Solde de parties d'un joueur (1.1.4).
//
//  - remaining_part : parties quotidiennes, remises a 3 chaque nuit a minuit
//    (heure de Paris) par resetDailyRemainingParts.
//  - bonus_part : reserve de parties bonus (anniversaire, 10e participation
//    a un jeu, recompense « parties » de parrainage). Jamais touchee par le
//    reset, cumulable, sans plafond ni expiration.
//
// Une partie qui consomme un credit utilise d'abord les parties du jour,
// puis la reserve bonus. Une partie au QR du commerce et l'acces « tous les
// jeux jusqu'a minuit » (allGamesAccessUntil) ne consomment rien. Les deux
// champs ne sont ecrits que par le serveur, dans des transactions.

const kDailyPlays = 3;
const kParticipationBonusPlays = 3;
const kParticipationBonusEvery = 10;

function normalizeBonusPart(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.trunc(number) : 0;
}

/**
 * @return {{allowed: boolean, source: "daily"|"bonus"|"free"|"unlimited"|"none",
 *   dailyDelta: number, bonusDelta: number}}
 */
function planPlayConsumption({dailyRemaining, bonusRemaining, consumesPlay, unlimited}) {
  if (!consumesPlay) {
    return {allowed: true, source: "free", dailyDelta: 0, bonusDelta: 0};
  }
  if (unlimited) {
    return {allowed: true, source: "unlimited", dailyDelta: 0, bonusDelta: 0};
  }
  if (dailyRemaining > 0) {
    return {allowed: true, source: "daily", dailyDelta: -1, bonusDelta: 0};
  }
  if (normalizeBonusPart(bonusRemaining) > 0) {
    return {allowed: true, source: "bonus", dailyDelta: 0, bonusDelta: -1};
  }
  return {allowed: false, source: "none", dailyDelta: 0, bonusDelta: 0};
}

function isParticipationBonusPosition(position) {
  return Number.isInteger(position) && position > 0 &&
    position % kParticipationBonusEvery === 0;
}

const kParticipationBonusMessage =
  `Vous avez gagné ${kParticipationBonusPlays} parties bonus ! ` +
  "Elles sont conservées jusqu'à ce que vous les jouiez.";

module.exports = {
  kDailyPlays,
  kParticipationBonusMessage,
  kParticipationBonusPlays,
  isParticipationBonusPosition,
  normalizeBonusPart,
  planPlayConsumption,
};

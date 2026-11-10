/// Solde de parties du joueur (1.1.4), meme regle que le serveur
/// (firebase/functions/play_balance.js) :
///  - `remaining_part` : 3 parties du jour, remises a 3 a minuit ;
///  - `bonus_part` : reserve de parties bonus, conservee sans limite de
///    duree ni plafond, utilisee quand les parties du jour sont epuisees.
/// Le serveur reste seul juge ; l'app n'ecrit jamais ces champs.
library;

int normalizeBonusPart(int? value) => value == null || value < 0 ? 0 : value;

/// Parties jouables maintenant : celles du jour plus la reserve bonus.
int playablePartsCount({required int dailyRemaining, required int bonusPart}) =>
    (dailyRemaining < 0 ? 0 : dailyRemaining) + normalizeBonusPart(bonusPart);

/// Aucune partie jouable (ni du jour, ni bonus) et pas d'acces illimite.
bool hasNoPlayableParts({
  required int dailyRemaining,
  required int bonusPart,
  required bool unlimitedAccess,
}) =>
    !unlimitedAccess &&
    playablePartsCount(dailyRemaining: dailyRemaining, bonusPart: bonusPart) <=
        0;

/// Libelle court de la barre du haut, vide sans bonus.
String bonusBadgeLabel(int bonusPart) {
  final bonus = normalizeBonusPart(bonusPart);
  return bonus <= 0 ? '' : '+$bonus bonus';
}

String bonusBalanceTitle(int bonusPart) {
  final bonus = normalizeBonusPart(bonusPart);
  return bonus <= 1 ? '$bonus partie bonus' : '$bonus parties bonus';
}

const String kBonusBalanceExplanation =
    'Vos parties bonus sont conservées jusqu’à ce que vous les jouiez. '
    'Elles sont utilisées une fois vos 3 parties du jour épuisées.';

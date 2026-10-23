/// Status shown when a finished game has no announced main-prize winner.
String? mainPrizeDrawStatusMessage({
  required bool ended,
  required bool hasMainPrize,
  required bool hasWinner,
  required Object? drawStatus,
}) {
  if (!ended || !hasMainPrize || hasWinner || drawStatus == 'no_main_prize') {
    return null;
  }
  if (drawStatus == 'no_eligible_entries') {
    return 'Tirage effectué sans gagnant.';
  }
  if (drawStatus == 'completed') return 'Résultat du tirage indisponible.';
  return 'Tirage au sort en attente';
}

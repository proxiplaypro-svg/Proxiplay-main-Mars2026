$homeTarget = '.codex_tmp_home_target.dart'
$homeContent = Get-Content $homeTarget -Raw

$homeOriginalVisibility = @'
  bool _isGameVisibleForPlayer(GamesRecord game) {
    final now = getCurrentTimestamp;
    final endDate = game.endDate;
    if (endDate == null || !endDate.isAfter(now)) {
      return false;
    }
    final startDate = game.startDate;
    if (startDate != null && now.isBefore(startDate)) {
      return false;
    }
    return true;
  }
'@
$homeReplacementVisibility = @'
  bool _isGameVisibleForPlayer(GamesRecord game) {
    final now = getCurrentTimestamp;
    final endDate = game.endDate;
    if (endDate == null || !endDate.isAfter(now)) {
      return false;
    }
    final startDate = game.startDate;
    if (startDate != null && now.isBefore(startDate)) {
      return false;
    }
    return true;
  }

  bool _hasVisibleMainPrizeForPlayer(GamesRecord game) {
    return game.hasMainPrize == true && game.prizeValue > 0;
  }
'@
$homeContent = $homeContent.Replace($homeOriginalVisibility, $homeReplacementVisibility)

$homeOriginalSignature = @'
    required Future<void> Function() onTap,
    String? winnerText,
    int winnerMaxLines = 1,
'@
$homeReplacementSignature = @'
    required Future<void> Function() onTap,
    String? winnerText,
    String? badgeText,
    String finishedInfoText = 'Jeu terminé',
    int winnerMaxLines = 1,
'@
$homeContent = $homeContent.Replace($homeOriginalSignature, $homeReplacementSignature)

$homeOriginalCardArgs = @'
        prizeText: prizeText,
        endDateText: endDateText,
        winnerText: winnerText,
        winnerMaxLines: winnerMaxLines,
'@
$homeReplacementCardArgs = @'
        prizeText: prizeText,
        endDateText: endDateText,
        badgeText: badgeText,
        winnerText: winnerText,
        finishedInfoText: finishedInfoText,
        winnerMaxLines: winnerMaxLines,
'@
$homeContent = $homeContent.Replace($homeOriginalCardArgs, $homeReplacementCardArgs)

$homeOriginalEndedFilter = @'
                                                                if (!(g.hasWinner ||
                                                                    g.mainPrizeWinner !=
                                                                        null ||
                                                                    g.hasMainPrize ==
                                                                        false)) {
'@
$homeReplacementEndedFilter = @'
                                                                final hasVisibleMainPrize =
                                                                    _hasVisibleMainPrizeForPlayer(
                                                                        g);
                                                                if (!(g.hasWinner ||
                                                                    g.mainPrizeWinner !=
                                                                        null ||
                                                                    !hasVisibleMainPrize)) {
'@
$homeContent = $homeContent.Replace($homeOriginalEndedFilter, $homeReplacementEndedFilter)

$homeOriginalFinishedBlock = @'
                                                                          final enseigne = enseigneSnapshot.data;
                                                                          final finishedInfoText =
                                                                              game.hasMainPrize ==
                                                                                      false
                                                                                  ? 'Lots secondaires attribués'
                                                                                  : 'Jeu terminé';
'@
$homeReplacementFinishedBlock = @'
                                                                          final enseigne = enseigneSnapshot.data;
                                                                          final hasVisibleMainPrize =
                                                                              _hasVisibleMainPrizeForPlayer(
                                                                                  game);
                                                                          final finishedBadgeText =
                                                                              !hasVisibleMainPrize
                                                                                  ? 'Lots attribués'
                                                                                  : null;
                                                                          final finishedInfoText =
                                                                              !hasVisibleMainPrize
                                                                                  ? 'Lots secondaires attribués'
                                                                                  : 'Jeu terminé';
'@
$homeContent = $homeContent.Replace($homeOriginalFinishedBlock, $homeReplacementFinishedBlock)

$homeOriginalNoWinnerCard = @'
                                                                            endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                            isFinished: true,
'@
$homeReplacementNoWinnerCard = @'
                                                                            endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                            badgeText: finishedBadgeText,
                                                                            isFinished: true,
'@
$homeContent = $homeContent.Replace($homeOriginalNoWinnerCard, $homeReplacementNoWinnerCard)

$homeOriginalWinnerCard = @'
                                                                              endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                              winnerText: winnerLabel,
'@
$homeReplacementWinnerCard = @'
                                                                              endDateText: game.endDate != null ? "Jusqu'au : ${dateTimeFormat('d/M/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}" : "Jusqu'au : -",
                                                                              badgeText: finishedBadgeText,
                                                                              winnerText: winnerLabel,
'@
$homeContent = $homeContent.Replace($homeOriginalWinnerCard, $homeReplacementWinnerCard)
Set-Content $homeTarget $homeContent -Encoding utf8

$favorisTarget = '.codex_tmp_favoris_target.dart'
$favorisContent = Get-Content $favorisTarget -Raw

$favorisOriginalVisibility = @'
  bool _isGameVisibleForPlayer(GamesRecord game) {
    final now = getCurrentTimestamp;
    final endDate = game.endDate;
    if (endDate == null || !endDate.isAfter(now)) {
      return false;
    }
    final startDate = game.startDate;
    if (startDate != null && now.isBefore(startDate)) {
      return false;
    }
    return true;
  }
'@
$favorisReplacementVisibility = @'
  bool _isGameVisibleForPlayer(GamesRecord game) {
    final now = getCurrentTimestamp;
    final endDate = game.endDate;
    if (endDate == null) {
      return false;
    }
    if (!endDate.isAfter(now)) {
      return _shouldKeepFinishedGameVisibleForPlayer(game);
    }
    final startDate = game.startDate;
    if (startDate != null && now.isBefore(startDate)) {
      return false;
    }
    return true;
  }

  bool _hasVisibleMainPrizeForPlayer(GamesRecord game) {
    return game.hasMainPrize == true && game.prizeValue > 0;
  }

  bool _shouldKeepFinishedGameVisibleForPlayer(GamesRecord game) {
    if (!_isGameFinished(game)) {
      return false;
    }
    return !_hasVisibleMainPrizeForPlayer(game);
  }
'@
$favorisContent = $favorisContent.Replace($favorisOriginalVisibility, $favorisReplacementVisibility)

$favorisOriginalBuildCard = @'
                                                    Widget buildCard(
                                                        {String? winnerText}) {
                                                      return GameCardWidget(
'@
$favorisReplacementBuildCard = @'
                                                    Widget buildCard(
                                                        {String? winnerText}) {
                                                      final hasVisibleMainPrize =
                                                          _hasVisibleMainPrizeForPlayer(
                                                              containerGamesRecord);
                                                      final finishedBadgeText =
                                                          isFinished &&
                                                                  !hasVisibleMainPrize
                                                              ? 'Lots attribués'
                                                              : null;
                                                      final finishedInfoText =
                                                          !hasVisibleMainPrize
                                                              ? 'Lots attribués'
                                                              : 'Jeu terminé';
                                                      return GameCardWidget(
'@
$favorisContent = $favorisContent.Replace($favorisOriginalBuildCard, $favorisReplacementBuildCard)

$favorisOriginalCardArgs = @'
                                                        endDateText: containerGamesRecord
                                                                    .endDate !=
                                                                null
                                                            ? 'Valable jusqu\'au : ${dateTimeFormat("d/M/y", containerGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}'
                                                            : 'Valable jusqu\'au : -',
                                                        winnerText: winnerText,
                                                        winnerMaxLines: 1,
                                                        isFinished: isFinished,
'@
$favorisReplacementCardArgs = @'
                                                        endDateText: containerGamesRecord
                                                                    .endDate !=
                                                                null
                                                            ? 'Valable jusqu\'au : ${dateTimeFormat("d/M/y", containerGamesRecord.endDate, locale: FFLocalizations.of(context).languageCode)}'
                                                            : 'Valable jusqu\'au : -',
                                                        badgeText:
                                                            finishedBadgeText,
                                                        winnerText: winnerText,
                                                        winnerMaxLines: 1,
                                                        isFinished: isFinished,
                                                        finishedInfoText:
                                                            finishedInfoText,
'@
$favorisContent = $favorisContent.Replace($favorisOriginalCardArgs, $favorisReplacementCardArgs)
Set-Content $favorisTarget $favorisContent -Encoding utf8

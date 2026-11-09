import '/utils/player_game_visibility.dart';

export '/utils/player_game_visibility.dart'
    show isGameHiddenFromPlayer, gamePublicationState, GamePublicationState;

bool isPlayerHomeGameVisible({
  required DateTime now,
  required String animationId,
  required DateTime? startDate,
  required DateTime? endDate,
}) {
  if (animationId.trim().isNotEmpty) {
    return false;
  }
  if (endDate == null || !endDate.isAfter(now)) {
    return false;
  }
  if (startDate != null && now.isBefore(startDate)) {
    return false;
  }
  return true;
}

/// "JEUX TERMINÉS": a game ended less than 30 days ago, and only if players
/// were allowed to see it (player_game_visibility.dart). A cancelled, draft or
/// re-hidden game must never be presented as finished with prizes awarded.
bool isRecentlyEndedGameVisibleForPlayer({
  required Map<String, dynamic> data,
  required DateTime? endDate,
  required DateTime now,
}) {
  if (endDate == null) return false;
  if (isGameHiddenFromPlayer(data)) return false;
  return now.isAfter(endDate) &&
      now.isBefore(endDate.add(const Duration(days: 30)));
}

const String kFinishedGameLabel = 'Jeu termin\u00E9';
const String kPrizesAwardedLabel = 'Lots attribu\u00E9s';

/// A finished game shows "Lots attribués" only when an attribution is
/// confirmed on the game itself: the main prize draw recorded a winner
/// (hasWinner / main_prize_winner, written by the server). Instant wins are
/// not summarised on the game, so an instant-win game, a draw still pending
/// or a draw without eligible entries all read "Jeu terminé".
bool isFinishedGameAwardConfirmed(Map<String, dynamic> data) =>
    data['hasWinner'] == true || data['main_prize_winner'] != null;

String finishedGameStatusText(Map<String, dynamic> data) =>
    isFinishedGameAwardConfirmed(data) ? kPrizesAwardedLabel : kFinishedGameLabel;

/// Date line of a game card: "Terminé le …" once the game is finished,
/// otherwise the existing [ongoingPrefix] ("Jusqu'au : …") is kept.
String gameCardEndDateText({
  required DateTime? endDate,
  required bool finished,
  required String Function(DateTime) format,
  String ongoingPrefix = "Jusqu'au : ",
}) {
  if (finished) {
    return endDate == null ? kFinishedGameLabel : 'Termin\u00E9 le ${format(endDate)}';
  }
  return endDate == null ? '$ongoingPrefix-' : '$ongoingPrefix${format(endDate)}';
}

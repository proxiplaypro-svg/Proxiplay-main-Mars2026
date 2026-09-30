/// Whether a player's participation may be presented as an entry in the
/// main-prize draw.  `null` is deliberately treated as false: legacy games
/// are backfilled by the backend, but the UI must never infer a draw from a
/// prize value or from instant-win data.
bool shouldShowMainPrizeTicket({required bool? hasMainPrize}) {
  return hasMainPrize == true;
}

/// The ticket information shown after a valid participation in a main-prize
/// game. The caller is responsible for only using it when [ticketCount] > 0.
String mainPrizeTicketLabel(int ticketCount) {
  return '🎫 $ticketCount ${ticketCount > 1 ? 'tickets validés' : 'ticket validé'}';
}

/// Whether the primary action on a player's game-detail page can launch a
/// participation. A participation already recorded for today is a displayed
/// status, not an action: keeping the callback null also removes the button's
/// press feedback and prevents a second backend call.
bool isGameDetailPrimaryActionEnabled({
  required bool gameEnded,
  required bool noRemainingParts,
  required bool hasPlayedToday,
  required bool isLaunchingGame,
}) {
  return !gameEnded &&
      !(noRemainingParts && !hasPlayedToday) &&
      !hasPlayedToday &&
      !isLaunchingGame;
}

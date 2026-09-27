/// Whether a player's participation may be presented as an entry in the
/// main-prize draw.  `null` is deliberately treated as false: legacy games
/// are backfilled by the backend, but the UI must never infer a draw from a
/// prize value or from instant-win data.
bool shouldShowMainPrizeTicket({required bool? hasMainPrize}) {
  return hasMainPrize == true;
}

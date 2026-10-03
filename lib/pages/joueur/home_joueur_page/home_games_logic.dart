/// A game still in draft (visible_public:false, set by the client at
/// creation and flipped to true only by the server once the instant
/// winners calendar is confirmed complete) must never appear in player
/// carousels. A legacy game that never had this field stays visible --
/// same "absent = public" convention as the admin console
/// (lib/firebase/*Queries.ts: `visible_public !== false`), so only an
/// explicit `false` hides the game.
bool isGameDraftHiddenFromPlayer({
  required bool hasVisiblePublicField,
  required bool visiblePublic,
}) =>
    hasVisiblePublicField && !visiblePublic;

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

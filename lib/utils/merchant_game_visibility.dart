import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';

bool isMerchantActiveGame(GamesRecord game) {
  final now = getCurrentTimestamp;
  final end = game.endDate;
  if (end == null) return false;
  if (game.snapshotData['hidden_from_merchant_stats'] == true) return false;
  return !end.isBefore(now);
}

/// A non-active game is not necessarily finished (missing dates or hidden).
/// Management actions require a known elapsed end, and must exclude future games.
bool canManageFinishedMerchantGame(GamesRecord game) {
  if (isMerchantActiveGame(game)) return false;
  final now = getCurrentTimestamp;
  return game.endDate != null &&
      game.endDate!.isBefore(now) &&
      (game.startDate == null || !game.startDate!.isAfter(now));
}

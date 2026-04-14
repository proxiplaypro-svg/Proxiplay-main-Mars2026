import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';

bool isMerchantActiveGame(GamesRecord game) {
  final now = getCurrentTimestamp;
  final end = game.endDate;
  if (end == null) return false;
  if (game.snapshotData['hidden_from_merchant_stats'] == true) return false;
  return !end.isBefore(now);
}

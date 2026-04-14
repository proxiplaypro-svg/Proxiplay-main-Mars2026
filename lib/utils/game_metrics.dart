import '/backend/schema/games_record.dart';

bool hasBrokenViewsTracking(GamesRecord game) {
  return game.views == 0 && game.participations > 0;
}

String gameViewsDisplayValue(GamesRecord game) {
  if (hasBrokenViewsTracking(game)) {
    return 'non remontees';
  }
  return game.views.toString();
}

String totalViewsDisplayValue(Iterable<GamesRecord> games) {
  if (games.any(hasBrokenViewsTracking)) {
    return 'non remontees';
  }
  final totalViews = games.fold<int>(0, (sum, game) => sum + game.views);
  return totalViews.toString();
}

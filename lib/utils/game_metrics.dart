import '/backend/schema/games_record.dart';

int effectiveGameViews(GamesRecord game) {
  if (game.views > 0) {
    return game.views;
  }
  if (game.participations > 0) {
    return game.participations;
  }
  return 0;
}

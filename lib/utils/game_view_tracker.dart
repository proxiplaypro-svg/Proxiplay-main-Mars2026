import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/foundation.dart';

Future<void> trackGamePresentationView(
  GamesRecord? game,
  String screenName, {
  String? source,
}) async {
  final gameRef = game?.reference;
  if (gameRef == null) {
    debugPrint(
      '[GAME_VIEW_PROD_CHECK] skipped_missing_game_ref screen=$screenName',
    );
    return;
  }

  final gameId = gameRef.id;
  final sourceLabel = (source == null || source.isEmpty) ? 'unknown' : source;
  debugPrint(
    '[GAME_VIEW_PROD_CHECK] page_open gameId=$gameId screen=$screenName source=$sourceLabel',
  );

  try {
    debugPrint(
      '[GAME_VIEW_PROD_CHECK] increment_start gameId=$gameId screen=$screenName source=$sourceLabel',
    );
    await gameRef.update(
      mapToFirestore(
        {
          'views': FieldValue.increment(1),
        },
      ),
    );
    debugPrint(
      '[GAME_VIEW_PROD_CHECK] increment_success gameId=$gameId screen=$screenName source=$sourceLabel',
    );
  } catch (error) {
    debugPrint(
      '[GAME_VIEW_PROD_CHECK] increment_error gameId=$gameId screen=$screenName source=$sourceLabel error=$error',
    );
  }
}

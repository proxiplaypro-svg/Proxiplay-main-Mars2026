import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/player_game_visibility.dart';

void main() {
  group('isGameDraftHiddenFromPlayer', () {
    test('hides only an explicit draft marker', () {
      expect(
        isGameDraftHiddenFromPlayer(
          hasVisiblePublicField: true,
          visiblePublic: false,
        ),
        isTrue,
      );
      expect(
        isGameDraftHiddenFromPlayer(
          hasVisiblePublicField: true,
          visiblePublic: true,
        ),
        isFalse,
      );
    });

    test('keeps legacy games without a visibility field public', () {
      expect(
        isGameDraftHiddenFromPlayer(
          hasVisiblePublicField: false,
          visiblePublic: false,
        ),
        isFalse,
      );
    });
  });

  test('all player game lists use the shared draft predicate', () {
    const playerListFiles = [
      'lib/pages/joueur/enseigne_detail_joueur_page/'
          'enseigne_detail_joueur_page_widget.dart',
      'lib/pages/joueur/favoris_joueur_page/'
          'favoris_joueur_page_widget.dart',
      'lib/pages/joueur/animation_detail_page/'
          'animation_detail_page_widget.dart',
    ];

    for (final path in playerListFiles) {
      final source = File(path).readAsStringSync();
      expect(source, contains('isGameDraftHiddenFromPlayer('), reason: path);
      expect(
        source,
        contains('hasVisiblePublicField: game.hasVisiblePublic()'),
        reason: path,
      );
      expect(
        source,
        contains('visiblePublic: game.visiblePublic'),
        reason: path,
      );
    }
  });
}

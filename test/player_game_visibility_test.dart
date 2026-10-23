import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/player_game_visibility.dart';

const _stateNames = {
  'disabled': GamePublicationState.disabled,
  'hidden': GamePublicationState.hidden,
  'published': GamePublicationState.published,
  'published_inconsistent': GamePublicationState.publishedInconsistent,
  'draft': GamePublicationState.draft,
};

void main() {
  test('matches the shared case table used by Cloud Functions and the Admin', () {
    final cases = jsonDecode(
            File('test/fixtures/game_publication_cases.json').readAsStringSync())
        as List<dynamic>;
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      expect(gamePublicationState(Map<String, dynamic>.from(c['game'] as Map)),
          _stateNames[c['state']],
          reason: c['name'] as String);
    }
  });

  group('gamePublicationState', () {
    test('published game, explicit or legacy without the field, is visible', () {
      expect(gamePublicationState({'visible_public': true, 'status': 'actif'}),
          GamePublicationState.published);
      expect(gamePublicationState({'name': 'legacy'}),
          GamePublicationState.published);
      expect(isGameHiddenFromPlayer({'name': 'legacy'}), isFalse);
    });

    test('a real draft never launched is hidden', () {
      final draft = {'visible_public': false, 'status': 'brouillon', 'participations': 0};
      expect(gamePublicationState(draft), GamePublicationState.draft);
      expect(isGameHiddenFromPlayer(draft), isTrue);
      expect(isGameHiddenFromPlayer({'visible_public': true, 'status': 'brouillon'}), isTrue);
    });

    test('a few test plays do not publish a draft', () {
      expect(
          isGameHiddenFromPlayer({'visible_public': false, 'unique_players_count': 3, 'participations': 9}),
          isTrue);
      expect(isGameHiddenFromPlayer({'visible_public': false, 'participations': 19}), isTrue);
    });

    test('a launched game with stale draft flags stays visible', () {
      // Same shape as "Des croquettes à gagner !" in production.
      final launched = {
        'visible_public': false,
        'status': 'brouillon',
        'unique_players_count': 262,
        'participations': 1198,
      };
      expect(gamePublicationState(launched), GamePublicationState.publishedInconsistent);
      expect(isGameHiddenFromPlayer(launched), isFalse);
      // Older games without the unique-player counter rely on participations.
      expect(isGameHiddenFromPlayer({'visible_public': false, 'participations': 20}), isFalse);
    });

    test('cancelled, deactivated or admin-hidden games stay hidden whatever their activity', () {
      for (final status in ['cancelled', 'canceled', 'disabled', 'desactive', 'annulé']) {
        expect(
            gamePublicationState({'visible_public': true, 'status': status, 'unique_players_count': 500}),
            GamePublicationState.disabled,
            reason: status);
      }
      expect(gamePublicationState({'deleted': true}), GamePublicationState.disabled);
      expect(
          gamePublicationState({
            'visible_public': false,
            'visible_public_auto_published': true,
            'unique_players_count': 500,
          }),
          GamePublicationState.hidden);
    });
  });
}

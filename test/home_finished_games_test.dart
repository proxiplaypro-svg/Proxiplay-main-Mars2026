import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/home_joueur_page/home_games_logic.dart';

void main() {
  final now = DateTime(2026, 11, 8, 12);
  final ended = now.subtract(const Duration(days: 3));

  test('jeux terminés : fenêtre de 30 jours conservée', () {
    bool visible(DateTime? end) => isRecentlyEndedGameVisibleForPlayer(
        data: const {}, endDate: end, now: now);
    expect(visible(ended), isTrue);
    expect(visible(null), isFalse);
    expect(visible(now.add(const Duration(hours: 1))), isFalse,
        reason: 'pas encore terminé');
    expect(visible(now.subtract(const Duration(days: 31))), isFalse,
        reason: 'terminé depuis plus de 30 jours');
  });

  test('annulé, brouillon ou masqué : jamais dans « JEUX TERMINÉS »', () {
    for (final data in <Map<String, dynamic>>[
      {'status': 'cancelled'},
      {'status': 'annulé'},
      {'deleted': true},
      {'visible_public': false, 'participations': 0},
      {'visible_public': false, 'visible_public_auto_published': true},
    ]) {
      expect(
          isRecentlyEndedGameVisibleForPlayer(
              data: data, endDate: ended, now: now),
          isFalse,
          reason: '$data');
    }
  });

  test('table partagée : visible terminé = visible pour le joueur', () {
    final cases = jsonDecode(File('test/fixtures/game_publication_cases.json')
        .readAsStringSync()) as List<dynamic>;
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(c['game'] as Map);
      expect(
          isRecentlyEndedGameVisibleForPlayer(
              data: data, endDate: ended, now: now),
          !isGameHiddenFromPlayer(data),
          reason: c['name'] as String);
    }
  });

  group('libellés d’un jeu terminé', () {
    test('« Lots attribués » seulement si l’attribution est confirmée', () {
      expect(isFinishedGameAwardConfirmed(const {}), isFalse);
      expect(isFinishedGameAwardConfirmed(const {'hasWinner': false}), isFalse);
      expect(
          isFinishedGameAwardConfirmed(
              const {'draw_status': 'no_eligible_entries'}),
          isFalse);
      expect(isFinishedGameAwardConfirmed(const {'draw_status': 'no_main_prize'}),
          isFalse);
      expect(isFinishedGameAwardConfirmed(const {'hasWinner': true}), isTrue);
      expect(isFinishedGameAwardConfirmed(const {'main_prize_winner': 'users/u1'}),
          isTrue);
      expect(finishedGameStatusText(const {'prize_value': 0}), 'Jeu terminé',
          reason: 'gains instantanés : aucune attribution confirmée sur le jeu');
      expect(finishedGameStatusText(const {'hasWinner': true}), 'Lots attribués');
    });

    test('« Terminé le » pour un jeu terminé, « Jusqu’au » inchangé sinon', () {
      String fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
      final end = DateTime(2026, 11, 5);
      expect(gameCardEndDateText(endDate: end, finished: true, format: fmt),
          'Terminé le 5/11/2026');
      expect(gameCardEndDateText(endDate: null, finished: true, format: fmt),
          'Jeu terminé');
      expect(gameCardEndDateText(endDate: end, finished: false, format: fmt),
          "Jusqu'au : 5/11/2026");
      expect(gameCardEndDateText(endDate: null, finished: false, format: fmt),
          "Jusqu'au : -");
      expect(
          gameCardEndDateText(
              endDate: end,
              finished: false,
              format: fmt,
              ongoingPrefix: "Valable jusqu'au : "),
          "Valable jusqu'au : 5/11/2026");
    });

    test('accueil et favoris : plus de « Lots attribués » codé en dur', () {
      final home = File(
              'lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart')
          .readAsStringSync();
      final favoris = File(
              'lib/pages/joueur/favoris_joueur_page/favoris_joueur_page_widget.dart')
          .readAsStringSync();
      for (final src in [home, favoris]) {
        expect(src.contains('finishedGameStatusText('), isTrue);
        expect(src.contains("'Lots attribu"), isFalse);
        expect(src.contains('Lots secondaires attribu'), isFalse);
      }
      expect(home.contains('endDateText: finishedEndDateText'), isTrue);
      expect(favoris.contains('finished: isFinished'), isTrue);
      // Les cartes des jeux en cours gardent « Jusqu'au ».
      expect(home.contains("\"Jusqu'au : \${dateTimeFormat("), isTrue);
    });
  });
}

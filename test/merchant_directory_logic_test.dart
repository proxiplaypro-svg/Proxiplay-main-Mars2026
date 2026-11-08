import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/enseigne_joueur_page/merchant_directory_logic.dart';

const known = ['Alimentation', 'Restaurants & bars', 'Beauté & bien-être'];

DirectoryGame game(
  String? path, {
  Map<String, dynamic> data = const {},
  DateTime? start,
  DateTime? end,
}) =>
    (merchantPath: path, data: data, startDate: start, endDate: end);

void main() {
  final now = DateTime(2026, 11, 8, 12);

  test('la recherche ignore la casse, les accents et les espaces superflus',
      () {
    expect(normalizeDirectoryText('  Café   Crème ÉPICERIE '),
        'cafe creme epicerie');
    const merchant = DirectoryMerchant(
      id: 'a',
      name: 'La Taverne du Jean Bart',
      city: 'Strasbourg',
      categories: ['Restaurants & bars'],
    );
    expect(merchantMatchesQuery(merchant, 'taverne'), isTrue);
    expect(merchantMatchesQuery(merchant, 'STRASBOURG'), isTrue);
    expect(merchantMatchesQuery(merchant, 'restaurants'), isTrue);
    expect(merchantMatchesQuery(merchant, 'jean strasbourg'), isTrue);
    expect(merchantMatchesQuery(merchant, 'boulangerie'), isFalse);
    expect(merchantMatchesQuery(merchant, ''), isTrue);
    const beauty = DirectoryMerchant(
        id: 'b', name: 'Institut', categories: ['Beauté & bien-être']);
    expect(merchantMatchesQuery(beauty, 'beaute'), isTrue);
    expect(merchantMatchesQuery(beauty, 'BIEN-ETRE'), isTrue);
  });

  test('catégories proposées : seulement celles présentes, ordre habituel', () {
    final categories = availableDirectoryCategories(const [
      DirectoryMerchant(id: '1', categories: ['Beauté & bien-être']),
      DirectoryMerchant(id: '2', categories: ['Alimentation', 'Zoo']),
      DirectoryMerchant(id: '3', categories: ['Alimentation', ' ']),
    ], known);
    expect(categories, ['Alimentation', 'Beauté & bien-être', 'Zoo']);
    expect(
        availableDirectoryCategories(const [DirectoryMerchant(id: 'x')], known),
        isEmpty,
        reason: 'un commerce sans catégorie ne crée aucun filtre');
  });

  group('badge « Jeu en cours » : table partagée de player_game_visibility',
      () {
    final ongoingDates = (
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    final cases = jsonDecode(File('test/fixtures/game_publication_cases.json')
        .readAsStringSync()) as List<dynamic>;
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      test(c['name'] as String, () {
        final data = Map<String, dynamic>.from(c['game'] as Map);
        final visible =
            const {'published', 'published_inconsistent'}.contains(c['state']);
        expect(
            isDirectoryGameOngoing(
                game('enseignes/x',
                    data: data,
                    start: ongoingDates.start,
                    end: ongoingDates.end),
                now),
            visible,
            reason: 'badge = jeu visible sur la fiche');
      });
    }
  });

  test('badge : cas réels QR seul, annulé, masqué, futur, terminé', () {
    final end = now.add(const Duration(days: 3));
    bool ongoing(Map<String, dynamic> data, {DateTime? start, DateTime? e}) =>
        isDirectoryGameOngoing(
            game('enseignes/x', data: data, start: start, end: e ?? end), now);
    // QR seul : listé dans « Jeux en cours » de la fiche, jouable en boutique.
    expect(ongoing({'access_mode': 'qr_only', 'visible_public': true}), isTrue);
    expect(ongoing({'status': 'cancelled'}), isFalse);
    expect(ongoing({'status': 'annulé'}), isFalse);
    expect(ongoing({'status': 'desactive'}), isFalse);
    expect(
        ongoing(
            {'visible_public': false, 'visible_public_auto_published': true}),
        isFalse,
        reason: 'masqué à nouveau par un admin');
    expect(ongoing({'visible_public': false, 'participations': 0}), isFalse,
        reason: 'brouillon jamais lancé');
    expect(ongoing({}, start: now.add(const Duration(minutes: 1))), isFalse,
        reason: 'futur');
    expect(ongoing({}, e: now), isFalse, reason: 'terminé à l’instant');
    expect(ongoing({}, start: now), isTrue, reason: 'commence maintenant');
  });

  test('« Jeu en cours » suit exactement la règle de la fiche commerçant', () {
    final ongoing = game('enseignes/ok',
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(days: 1)));
    expect(isDirectoryGameOngoing(ongoing, now), isTrue);
    // Sans date de début : en cours dès la publication, comme la fiche.
    expect(
        isDirectoryGameOngoing(
            game('enseignes/ok', end: now.add(const Duration(hours: 1))), now),
        isTrue);
    expect(
        isDirectoryGameOngoing(
            game('enseignes/x',
                start: now.add(const Duration(hours: 1)),
                end: now.add(const Duration(days: 1))),
            now),
        isFalse,
        reason: 'pas encore commencé');
    expect(isDirectoryGameOngoing(game('enseignes/x', end: now), now), isFalse,
        reason: 'terminé');
    expect(isDirectoryGameOngoing(game('enseignes/x'), now), isFalse,
        reason: 'sans date de fin');
    expect(
        isDirectoryGameOngoing(
            game('enseignes/x',
                data: {'status': 'brouillon'},
                end: now.add(const Duration(days: 1))),
            now),
        isFalse,
        reason: 'brouillon masqué par player_game_visibility');
    expect(
        isDirectoryGameOngoing(
            game('enseignes/x',
                data: {'deleted': true}, end: now.add(const Duration(days: 1))),
            now),
        isFalse);
  });

  test('les identifiants de commerce viennent uniquement de enseignes/{id}',
      () {
    final end = now.add(const Duration(days: 2));
    final ids = activeMerchantIdsFromGames([
      game('enseignes/a', end: end),
      game('/enseignes/b', end: end),
      game('merchants/c', end: end),
      game('enseignes/d/images/e', end: end),
      game(null, end: end),
      game('enseignes/f', end: now.subtract(const Duration(days: 1))),
    ], now);
    expect(ids, {'a', 'b'});
  });

  test('note Google : affichée seulement si elle est valide', () {
    expect(const DirectoryMerchant(id: 'a', googleRating: 4.56).ratingLabel,
        '4,6');
    expect(
        const DirectoryMerchant(id: 'a', googleRating: 6).ratingLabel, isNull);
    expect(
        const DirectoryMerchant(id: 'a', googleRating: double.nan).ratingLabel,
        isNull);
    expect(const DirectoryMerchant(id: 'a').ratingLabel, isNull);
    expect(
        const DirectoryMerchant(id: 'a', name: '  ').displayName, 'Commerçant');
  });
}

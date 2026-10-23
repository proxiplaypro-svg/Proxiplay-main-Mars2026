import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/backend/schema/games_record.dart';
import 'package:proxi_play/utils/main_prize_presentation.dart';

// The record only stores this reference; it never calls Firestore in these tests.
// ignore: subtype_of_sealed_class
class _DocumentReferenceStub
    implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  MainPrizePresentation presentation(Map<String, dynamic> data) {
    final game =
        GamesRecord.getDocumentFromData(data, _DocumentReferenceStub());
    return mainPrizeFromGameData(
      data: game.snapshotData,
      hasMainPrize: game.hasMainPrize,
      prizeValue: game.prizeValue,
    );
  }

  for (final accessMode in ['public', 'qr_only']) {
    group('Firestore main prize ($accessMode)', () {
      MainPrizePresentation resolve({String? title, String? description}) =>
          presentation({
            'access_mode': accessMode,
            'hasMainPrize': true,
            'prize_value': 112,
            'description': 'Description générale du jeu',
            if (title != null) 'main_prize_title': title,
            if (description != null) 'main_prize_description': description,
          });

      test('title only', () {
        final prize = resolve(title: 'Lot');
        expect(prize.title, 'Lot');
        expect(prize.hasDistinctDescription, isFalse);
      });

      test('description only', () {
        final prize = resolve(description: 'Détails du lot');
        expect(prize.title, isEmpty);
        expect(prize.description, 'Détails du lot');
        expect(prize.hasDistinctDescription, isTrue);
      });

      test('title and description', () {
        final prize = resolve(title: 'Lot', description: 'Détails du lot');
        expect(prize.title, 'Lot');
        expect(prize.description, 'Détails du lot');
        expect(prize.hasDistinctDescription, isTrue);
      });

      test('explicit empty dedicated fields do not reuse the game description',
          () {
        expect(resolve(title: '', description: '').hasContent, isFalse);
      });

      test('historical shape restores the old prize description', () {
        expect(resolve().description, 'Description générale du jeu');
      });
    });
  }

  test('CycloBart historical data shows its description as in 1.1.1', () {
    final prize = presentation({
      'name': '1h30 de CycloBart pour 4 pers',
      'description':
          "Montez à bord du Beer Bike jusqu'à 14 personnes et profitez d'une expérience conviviale et originale ! Pédalez ensemble, partagez un bon moment et profitez d'une ambiance festive entre amis, collègues ou pour un événement spécial.\n4 places offertes pour un minimum de 8 personnes \nValable jusqu'au 28 Août",
      'hasMainPrize': true,
      'prize_value': 112,
      'access_mode': 'public',
    });
    expect(prize.title, isEmpty);
    expect(prize.description, startsWith('Montez à bord du Beer Bike'));
    expect(prize.description, contains('4 places offertes'));
    expect(prize.hasDistinctDescription, isTrue);
  });

  test('a null dedicated field prevents the historical fallback', () {
    final prize = presentation({
      'hasMainPrize': true,
      'prize_value': 112,
      'main_prize_description': null,
      'description': 'Description générale',
    });
    expect(prize.hasContent, isFalse);
  });

  test('historical fallback retains the positive prize value requirement', () {
    for (final value in [0, -1]) {
      final prize = presentation({
        'hasMainPrize': true,
        'prize_value': value,
        'description': 'Description générale',
      });
      expect(prize.hasContent, isFalse);
    }
  });

  test('no main prize prevents the historical fallback', () {
    final prize = presentation({
      'hasMainPrize': false,
      'prize_value': 112,
      'description': 'Description générale',
    });
    expect(prize.hasContent, isFalse);
  });

  test('legacy duplicate dedicated fields are shown once', () {
    final prize = presentation({
      'hasMainPrize': true,
      'main_prize_title': 'Lot historique',
      'main_prize_description': 'Lot historique',
    });
    expect(prize.title, 'Lot historique');
    expect(prize.hasDistinctDescription, isFalse);
  });
}

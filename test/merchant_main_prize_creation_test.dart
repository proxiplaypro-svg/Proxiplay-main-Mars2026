import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/backend/schema/games_record.dart';

void main() {
  test(
      'merchant creation passes the two dedicated fields only for a main prize',
      () {
    final source = File(
      'lib/pages/commercant/add_game_commercant_page/add_game_commercant_page_widget.dart',
    ).readAsStringSync();
    expect(
        source,
        contains(
            'mainPrizeTitle: shouldPersistMainPrize ? mainPrizeName : null'));
    expect(source,
        contains('shouldPersistMainPrize ? mainPrizeDescription : null'));
    expect(source,
        contains('mainPrizeName.isNotEmpty || mainPrizeDescription.isNotEmpty'));
    expect(source, contains('!hasMainPrizeText || (mainPrizeValue ?? 0) <= 0'));
  });

  test(
      'Firestore serialization preserves title and an explicitly empty description',
      () {
    final data = createGamesRecordData(
      name: 'Jeu',
      description: 'Description du jeu',
      hasMainPrize: true,
      mainPrizeTitle: 'Lot',
      mainPrizeDescription: '',
    );
    expect(data['name'], 'Jeu');
    expect(data['description'], 'Description du jeu');
    expect(data['main_prize_title'], 'Lot');
    expect(data['main_prize_description'], '');
  });

  test('Firestore serialization preserves an explicitly empty title', () {
    final data = createGamesRecordData(
      hasMainPrize: true,
      mainPrizeTitle: '',
      mainPrizeDescription: 'Description du lot',
    );
    expect(data['main_prize_title'], '');
    expect(data['main_prize_description'], 'Description du lot');
  });

  test('a game without a main prize omits both dedicated fields', () {
    final data = createGamesRecordData(hasMainPrize: false);
    expect(data.containsKey('main_prize_title'), isFalse);
    expect(data.containsKey('main_prize_description'), isFalse);
  });
}

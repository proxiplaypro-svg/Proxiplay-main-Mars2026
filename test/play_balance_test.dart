import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/components/play_balance_card.dart';
import 'package:proxi_play/utils/play_balance.dart';

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('play balance', () {
    test('playable = daily + kept bonus, never negative', () {
      expect(playablePartsCount(dailyRemaining: 3, bonusPart: 0), 3);
      expect(playablePartsCount(dailyRemaining: 0, bonusPart: 5), 5);
      expect(playablePartsCount(dailyRemaining: 2, bonusPart: 4), 6);
      expect(playablePartsCount(dailyRemaining: -1, bonusPart: -3), 0);
    });

    test('blocked only without daily plays, bonus plays and unlimited access',
        () {
      expect(
          hasNoPlayableParts(
              dailyRemaining: 0, bonusPart: 0, unlimitedAccess: false),
          isTrue);
      expect(
          hasNoPlayableParts(
              dailyRemaining: 0, bonusPart: 1, unlimitedAccess: false),
          isFalse);
      expect(
          hasNoPlayableParts(
              dailyRemaining: 0, bonusPart: 0, unlimitedAccess: true),
          isFalse);
      expect(
          hasNoPlayableParts(
              dailyRemaining: 1, bonusPart: 0, unlimitedAccess: false),
          isFalse);
    });

    test('labels', () {
      expect(bonusBadgeLabel(0), '');
      expect(bonusBadgeLabel(7), '+7 bonus');
      expect(bonusBalanceTitle(1), '1 partie bonus');
      expect(bonusBalanceTitle(12), '12 parties bonus');
      expect(kBonusBalanceExplanation, contains('conservées'));
    });
  });

  testWidgets('the balance card shows daily and kept bonus plays',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlayBalanceCard(dailyRemaining: 2, bonusPart: 5)),
    ));
    expect(find.text('Mes parties'), findsOneWidget);
    expect(find.text('2 parties du jour · 5 parties bonus'), findsOneWidget);
    expect(find.textContaining('conservées'), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            RegExp(r'^Mes parties : 2 parties du jour, 5 parties bonus\. ')),
        findsOneWidget);
  });

  testWidgets('the balance card fits a 320 px wide screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlayBalanceCard(dailyRemaining: 3, bonusPart: 1234)),
    ));
    expect(tester.takeException(), isNull);
  });

  test('the app uses the kept bonus wherever it decides a player can play', () {
    final detail = _source(
        'lib/pages/joueur/jeu_detail_joueur_page/jeu_detail_joueur_page_widget.dart');
    final home = _source(
        'lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart');
    final appBar = _source('lib/components/app_bar_joueur_widget.dart');
    final profile = _source(
        'lib/pages/joueur/profil_joueur_page/profil_joueur_page_widget.dart');
    final record = _source('lib/backend/schema/users_record.dart');
    expect(detail, contains('return hasNoPlayableParts('));
    expect(detail, contains('bonusPart: user?.bonusPart ?? 0'));
    expect(home, contains('final remainingPart = playablePartsCount('));
    expect(appBar, contains('bonusBadgeLabel(bonusPart)'));
    expect(profile, contains('child: PlayBalanceCard('));
    expect(record, contains("_readFlexibleInt(snapshotData['bonus_part'])"));
    // The client never writes the reserve.
    expect(record, isNot(contains("'bonus_part': ")));
  });
}

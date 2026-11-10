import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/parrainage_commercant_page/merchant_referral_conditions.dart';
import 'package:proxi_play/utils/merchant_referral_conditions.dart';

Map<String, dynamic> published({
  Object? version = 3,
  Object? format = 'plain_v1',
  Object? title = 'Conditions du programme de parrainage commerçant',
  Object? text = 'Intro.\n\n- A\n- B\n\nFin.',
  bool enabled = false,
}) =>
    {
      'enabled': enabled,
      'conditions': {
        'version': version,
        'format': format,
        'title': title,
        'text': text,
        'effective_at': Timestamp.fromDate(DateTime(2026, 12, 1, 12)),
        'updated_at': Timestamp.fromDate(DateTime(2026, 12, 1, 12)),
      },
    };

Future<void> pumpDialog(WidgetTester tester,
    MerchantReferralConditionsLoader loader) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MerchantReferralConditionsDialog(loader: loader))));
}

void main() {
  test('paragraphes et listes, comme cote serveur', () {
    final blocks = parseMerchantReferralConditionsText(
        'Ligne 1\nsuite\n\n- un\n- deux\nAprès liste\r\n\r\n\n   \nFin.  ');
    expect(blocks, hasLength(4));
    expect((blocks[0] as ConditionsParagraph).text, 'Ligne 1 suite');
    expect((blocks[1] as ConditionsList).items, ['un', 'deux']);
    expect((blocks[2] as ConditionsParagraph).text, 'Après liste');
    expect((blocks[3] as ConditionsParagraph).text, 'Fin.');
  });

  test('la version publiee est lue avec son numero et sa date', () {
    final result =
        resolveMerchantReferralConditions(config: published(), fromCache: false);
    expect(result.source, MerchantReferralConditionsSource.online);
    expect(result.notice, isNull);
    expect(result.conditions.version, 3);
    expect(conditionsVersionLabel(result.conditions),
        'Version 3 · en vigueur depuis le 01/12/2026');
    expect(result.conditions.blocks, hasLength(3));
  });

  test('copie du cache de l appareil : signalee comme telle', () {
    final result =
        resolveMerchantReferralConditions(config: published(), fromCache: true);
    expect(result.source, MerchantReferralConditionsSource.deviceCache);
    expect(result.notice, kConditionsCacheNotice);
    expect(result.conditions.version, 3);
  });

  test('document absent ou conditions invalides : copie integree signalee', () {
    for (final config in <Map<String, dynamic>?>[
      null,
      {'enabled': true},
      published(version: 0),
      published(version: '3'),
      published(format: 'html'),
      published(title: ' '),
      published(text: 42),
      published(text: '\n\n'),
    ]) {
      final result =
          resolveMerchantReferralConditions(config: config, fromCache: false);
      expect(result.source, MerchantReferralConditionsSource.embedded,
          reason: '$config');
      expect(result.notice, kConditionsEmbeddedNotice);
      expect(result.conditions.version, isNull);
      expect(conditionsVersionLabel(result.conditions), '');
    }
  });

  test('la copie integree est exactement la version 1 du serveur', () {
    final serverText =
        File('firebase/functions/merchant_referral_conditions_v1.txt')
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .trim();
    expect(kEmbeddedMerchantReferralConditionsText, serverText);
    final server = File('firebase/functions/merchant_referral_conditions.js')
        .readAsStringSync();
    expect(server, contains(kEmbeddedMerchantReferralConditionsTitle));
  });

  test('la copie integree reprend les conditions validees, sans ajout', () {
    const text = kEmbeddedMerchantReferralConditionsText;
    for (final expected in [
      'ouvert aux joueurs et aux commerçants',
      '50 € en bons cadeaux',
      'nouveau client ProxiPlay',
      'lors de la création de son compte',
      'intégralement réglé son premier abonnement',
      "ne pas avoir fait l'objet d'une annulation ou d'un remboursement",
      "parrainé qu'une seule fois",
      'ne peut pas se parrainer lui-même',
      'vérification et validation du parrainage par ProxiPlay',
      'ni échangeables contre des espèces ni remboursables',
      'frauduleux, fictif',
      'conditions applicables lors de leur enregistrement',
    ]) {
      expect(text, contains(expected));
    }
    // Points non decides : jamais inventes.
    for (final forbidden in ['validité', 'délai', 'jours', 'mois', 'fraction']) {
      expect(text.toLowerCase(), isNot(contains(forbidden)), reason: forbidden);
    }
  });

  testWidgets('indicateur de chargement, puis conditions en ligne',
      (tester) async {
    final completer = Completer<MerchantReferralConditionsResult>();
    await pumpDialog(tester, () => completer.future);
    expect(find.byKey(const ValueKey('merchant-referral-conditions-loading')),
        findsOneWidget);
    completer.complete(
        resolveMerchantReferralConditions(config: published(), fromCache: false));
    await tester.pumpAndSettle();
    expect(find.text('Conditions du programme de parrainage commerçant'),
        findsOneWidget);
    expect(find.text('Intro.'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('Fin.'), findsOneWidget);
    expect(find.byKey(const ValueKey('merchant-referral-conditions-notice')),
        findsNothing);
  });

  testWidgets('hors connexion avec cache : avertissement visible',
      (tester) async {
    await pumpDialog(
        tester,
        () async => resolveMerchantReferralConditions(
            config: published(), fromCache: true));
    await tester.pumpAndSettle();
    expect(find.text(kConditionsCacheNotice), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('petit ecran et grand texte : la copie integree defile sans erreur',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 568), textScaler: TextScaler.linear(1.6)),
      child: MaterialApp(
        home: Scaffold(
          body: MerchantReferralConditionsDialog(
            loader: () async => resolveMerchantReferralConditions(
                config: null, fromCache: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(kConditionsEmbeddedNotice), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}

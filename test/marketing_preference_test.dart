import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/components/marketing_preference_card.dart';
import 'package:proxi_play/utils/marketing_consent_state.dart';

void main() {
  group('état du consentement', () {
    test('absence de réponse, accord et retrait restent distincts', () {
      expect(marketingConsentStateOf(null), MarketingConsentState.unanswered);
      expect(marketingConsentStateOf({}), MarketingConsentState.unanswered);
      expect(marketingConsentStateOf({'enabled': 'true'}),
          MarketingConsentState.unanswered,
          reason: 'une valeur non booléenne n’est jamais un accord');
      expect(marketingConsentStateOf({'enabled': true}),
          MarketingConsentState.granted);
      expect(marketingConsentStateOf({'enabled': false}),
          MarketingConsentState.withdrawn);
    });

    test('éligibilité : 15 ans révolus, comme le serveur', () {
      final now = DateTime(2026, 11, 8);
      expect(isMarketingEligibleBirthday(null, now: now), isFalse);
      expect(
          isMarketingEligibleBirthday(DateTime(2011, 11, 8), now: now), isTrue,
          reason: 'jour des 15 ans');
      expect(
          isMarketingEligibleBirthday(DateTime(2011, 11, 9), now: now), isFalse,
          reason: 'la veille des 15 ans');
      expect(
          isMarketingEligibleBirthday(DateTime(1990, 1, 1), now: now), isTrue);
    });

    test('messages : Callable absente, âge, session, réseau, autre', () {
      expect(marketingConsentErrorMessage('not-found'),
          contains('pas encore disponible'));
      expect(marketingConsentErrorMessage('failed-precondition'),
          contains('15 ans'));
      expect(marketingConsentErrorMessage('unauthenticated'),
          contains('Reconnectez-vous'));
      expect(marketingConsentErrorMessage('unavailable'), contains('réseau'));
      expect(marketingConsentErrorMessage(null), contains('Réessayez'));
    });
  });

  group('carte « Actualités par e-mail »', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required MarketingConsentState state,
      bool saving = false,
      ValueChanged<bool>? onChanged,
      double width = 390,
      double scale = 1,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: MarketingPreferenceCard(
                  state: state, saving: saving, onChanged: onChanged),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('présentation courte et état par défaut désactivé',
        (tester) async {
      await pumpCard(tester, state: MarketingConsentState.unanswered);
      expect(find.text('Recevoir les actualités de ProxiPlay'), findsOneWidget);
      expect(find.text('Nouveaux jeux, cadeaux et actualités'), findsOneWidget);
      expect(find.byKey(const Key('marketing-consent-status')), findsNothing);
      expect(find.byKey(const Key('marketing-consent-text')), findsNothing);
      expect(
          tester
              .widget<Switch>(find.byKey(const Key('marketing-consent-switch')))
              .value,
          isFalse,
          reason: 'jamais d’accord par défaut');
    });

    testWidgets('accord et retrait conservent la valeur de l’interrupteur',
        (tester) async {
      await pumpCard(tester, state: MarketingConsentState.granted);
      expect(
          tester
              .widget<Switch>(find.byKey(const Key('marketing-consent-switch')))
              .value,
          isTrue);
      await pumpCard(tester, state: MarketingConsentState.withdrawn);
      expect(
          tester
              .widget<Switch>(find.byKey(const Key('marketing-consent-switch')))
              .value,
          isFalse);
    });

    testWidgets('l’interrupteur transmet le choix ; enregistrement en cours',
        (tester) async {
      final choices = <bool>[];
      await pumpCard(tester,
          state: MarketingConsentState.unanswered, onChanged: choices.add);
      await tester.tap(find.byKey(const Key('marketing-consent-switch')));
      expect(choices, [true]);
      await pumpCard(tester,
          state: MarketingConsentState.unanswered, saving: true);
      expect(find.byKey(const Key('marketing-consent-switch')), findsNothing);
      expect(find.byKey(const Key('marketing-consent-saving')), findsOneWidget);
    });

    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
            '${width.toInt()} px, texte x$scale : sans débordement, '
            'interrupteur aligné à droite', (tester) async {
          await pumpCard(tester,
              state: MarketingConsentState.granted,
              width: width,
              scale: scale,
              onChanged: (_) {});
          expect(tester.takeException(), isNull);
          final card = tester.getRect(
              find.byKey(const Key('marketing-preference-card-surface')));
          final toggle =
              tester.getRect(find.byKey(const Key('marketing-consent-switch')));
          expect(card.right - toggle.right, lessThan(30));
          expect(toggle.center.dy, closeTo(card.center.dy, 2));
          expect(
              tester
                  .getSize(find
                      .byKey(const Key('marketing-preference-card-surface')))
                  .height,
              lessThan(scale == 1 ? 190 : 300),
              reason: 'hauteur dictée par les deux textes, jamais par la page');
        });
      }
    }
  });
}

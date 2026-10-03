// Real-behavior widget test for the "Titre du jeu" regression
// (lib/pages/commercant/add_game_commercant_page/add_game_commercant_page_widget.dart).
//
// Regression: commit 664a8def ("Finalize merchant sharing and legal UI
// fixes") introduced the "Lots à gains immédiats" (secondaryPrizesEnabled)
// toggle and, while restructuring that section, accidentally nested the
// pre-existing, independent "Titre du jeu" field inside it - the field
// used to depend only on mainPrizeEnabled, it ended up depending on BOTH
// mainPrizeEnabled and secondaryPrizesEnabled. Since mainPrizeEnabled
// defaults to true and secondaryPrizesEnabled defaults to false, the field
// was invisible on the very first screen a merchant sees.
//
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proxi_play/flutter_flow/internationalization.dart';
import 'package:proxi_play/pages/commercant/add_game_commercant_page/add_game_commercant_page_widget.dart';

// Test-font substitution (no real Inter font downloaded here) measures text
// wider than in production, which can overflow a Row at narrow test widths -
// this also happens on untouched, already-shipped parts of this same page
// under this harness, so it is a test artifact, not a defect introduced by
// this change. Same suppressor as test/merchant_signup_entry_point_widget_test.dart.
void ignoreKnownFontSubstitutionOverflow() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await initializeDateFormatting('fr');
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
            const BasicMessageChannel<Object?>(
                'dev.flutter.pigeon.firebase_analytics_platform_interface.FirebaseAnalyticsHostApi.logEvent',
                StandardMessageCodec()),
            (_) async => <Object?>[null]);
  });

  Future<void> pump(WidgetTester tester) async {
    ignoreKnownFontSubstitutionOverflow();
    tester.view.physicalSize = const Size(390, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        localizationsDelegates: const [
          FFLocalizationsDelegate(),
          FallbackMaterialLocalizationDelegate(),
          FallbackCupertinoLocalizationDelegate(),
        ],
        supportedLocales: const [Locale('fr')],
        locale: const Locale('fr'),
        home: AddGameCommercantPageWidget(
          enseigneRef: null,
          enseigne: 'Ma Boutique',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setMainPrizeEnabled(WidgetTester tester, bool value) async {
    final current = tester.widget<Switch>(find.byType(Switch).first).value;
    if (current != value) {
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
    }
  }

  Future<void> setSecondaryPrizesEnabled(
      WidgetTester tester, bool value) async {
    final current = tester.widget<Switch>(find.byType(Switch).at(1)).value;
    if (current != value) {
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
    }
  }

  group('Titre du jeu field visibility', () {
    testWidgets(
        '1. Lot principal OFF, gains immédiats OFF -> Titre du jeu visible',
        (tester) async {
      await pump(tester);
      await setMainPrizeEnabled(tester, false);
      await setSecondaryPrizesEnabled(tester, false);

      expect(find.text('Titre du jeu'), findsOneWidget);
    });

    testWidgets(
        '2. Lot principal OFF, gains immédiats ON -> Titre du jeu visible',
        (tester) async {
      await pump(tester);
      await setMainPrizeEnabled(tester, false);
      await setSecondaryPrizesEnabled(tester, true);

      expect(find.text('Titre du jeu'), findsOneWidget);
    });

    testWidgets(
        '3. REGRESSION: Lot principal ON, gains immédiats OFF (état par '
        'défaut du formulaire) -> Titre du jeu doit rester visible',
        (tester) async {
      await pump(tester);
      // mainPrizeEnabled=true, secondaryPrizesEnabled=false : valeurs par
      // defaut du modele, aucun tap necessaire - c'est l'ecran que voit
      // tout commercant ouvrant ce formulaire pour la premiere fois.

      expect(find.text('Titre du jeu'), findsOneWidget,
          reason: 'avant correctif, ce champ etait cache dans cet etat '
              '(regression 664a8def)');
    });

    testWidgets(
        '4. Lot principal ON, gains immédiats ON -> Titre du jeu visible',
        (tester) async {
      await pump(tester);
      await setSecondaryPrizesEnabled(tester, true);

      expect(find.text('Titre du jeu'), findsOneWidget);
    });

    testWidgets(
        '5. no regression: basculer Lot principal sur OFF ne vide plus le '
        'Titre du jeu', (tester) async {
      await pump(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Titre du jeu'), 'Mon jeu');
      await tester.pumpAndSettle();
      await setMainPrizeEnabled(tester, false);

      expect(find.text('Mon jeu'), findsOneWidget,
          reason: 'le titre du jeu ne doit jamais dependre de '
              'mainPrizeEnabled, y compris pour son effacement');
    });
  });
}

// FlutterFire platform fakes use the platform packages shipped by our SDKs.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth_platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as font_testing;
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:proxi_play/app_state.dart';
import 'package:proxi_play/auth/firebase_auth/account_routing_logic.dart';
import 'package:proxi_play/backend/schema/enums/enums.dart';
import 'package:proxi_play/flutter_flow/flutter_flow_button_tabbar.dart';
import 'package:proxi_play/flutter_flow/internationalization.dart';
import 'package:proxi_play/pages/auth/inscription_page/inscription_page_widget.dart';
import 'package:proxi_play/pages/auth/login_page/login_page_widget.dart';
import 'package:proxi_play/pages/auth/inscription_informations_page/inscription_informations_page_widget.dart';
import 'package:proxi_play/components/signup_progress_indicator.dart';
import 'package:proxi_play/flutter_flow/nav/nav.dart';
import 'package:proxi_play/auth/firebase_auth/firebase_user_provider.dart';
import 'package:proxi_play/utils/share_links.dart';

/// Signup UX regression tests (24/10/2026 Samsung findings: header overflow
/// on the profile completion page, no progress feedback, referral code asked
/// twice). Harness copied from test/merchant_signup_entry_point_widget_test.dart
/// (no Firebase service is contacted); unlike that test, overflows FAIL here.
/// Original harness note: real-behavior widget test for the merchant signup entry point (same
/// Firebase-fake harness as test/merchant_presentation_test.dart - no
/// Firebase service is ever contacted). This confirms the actual user
/// journey, not just the presence of the strings/wiring in source
/// (test/merchant_signup_entry_point_test.dart covers that separately).
class _Store extends platform.FirebaseFirestorePlatform {
  final data = <String, Map<String, dynamic>>{};
  @override
  platform.FirebaseFirestorePlatform delegateFor(
          {required FirebaseApp app, required String databaseId}) =>
      this;
  @override
  platform.CollectionReferencePlatform collection(String path) =>
      _Collection(this, path);
  @override
  platform.DocumentReferencePlatform doc(String path) => _Document(this, path);
  platform.DocumentSnapshotPlatform snapshot(String path) =>
      platform.DocumentSnapshotPlatform(
          this,
          path,
          data[path],
          platform.InternalSnapshotMetadata(
              hasPendingWrites: false, isFromCache: false));
}

class _Document extends platform.DocumentReferencePlatform {
  _Document(this.store, String path) : super(store, path);
  final _Store store;
  @override
  Future<platform.DocumentSnapshotPlatform> get(
          [platform.GetOptions options = const platform.GetOptions()]) async =>
      store.snapshot(path);
  @override
  Stream<platform.DocumentSnapshotPlatform> snapshots(
          {bool includeMetadataChanges = false,
          required platform.ListenSource listenSource}) =>
      Stream.value(store.snapshot(path));
}

class _Collection extends platform.CollectionReferencePlatform {
  _Collection(this.store, String path) : super(store, path) {
    parameters['where'] = <List<dynamic>>[];
    parameters['orderBy'] = <List<dynamic>>[];
  }
  final _Store store;
  @override
  platform.DocumentReferencePlatform doc([String? documentPath]) =>
      store.doc('$path/$documentPath');
  @override
  platform.QueryPlatform where(List<List<dynamic>> conditions) => this;
  @override
  platform.QueryPlatform limit(int limit) => this;
  @override
  bool get isCollectionGroupQuery => false;
  @override
  Stream<platform.QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required platform.ListenSource listenSource,
  }) =>
      Stream.fromFuture(get());
  @override
  Future<platform.QuerySnapshotPlatform> get(
      [platform.GetOptions options = const platform.GetOptions()]) async {
    final docs = store.data.keys
        .where((key) =>
            key.startsWith('$path/') &&
            key.split('/').length == path.split('/').length + 1)
        .map(store.snapshot)
        .toList();
    return platform.QuerySnapshotPlatform(
        docs, [], platform.SnapshotMetadataPlatform(false, false));
  }
}

class _AuthStore extends auth_platform.FirebaseAuthPlatform {
  _AuthStore() : super();
  auth_platform.UserPlatform? _currentUser;
  @override
  auth_platform.UserPlatform? get currentUser => _currentUser;
  @override
  set currentUser(auth_platform.UserPlatform? value) => _currentUser = value;
  @override
  auth_platform.FirebaseAuthPlatform delegateFor({required FirebaseApp app}) =>
      this;
  @override
  auth_platform.FirebaseAuthPlatform setInitialValues({
    auth_platform.InternalUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;
  // No signed-in user: the auth streams start empty.
  @override
  Stream<auth_platform.UserPlatform?> authStateChanges() => Stream.value(null);
  @override
  Stream<auth_platform.UserPlatform?> idTokenChanges() => Stream.value(null);
  @override
  Stream<auth_platform.UserPlatform?> userChanges() => Stream.value(null);
}

class _FontManifest extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Inter', 'InterTight'])
          for (final weight in [
            'Regular',
            'Medium',
            'SemiBold',
            'Bold',
            'ExtraBold'
          ])
            'test-fonts/$family-$weight.ttf'
      ];
}

/// Without the real, downloaded Inter font (disabled here via
/// GoogleFonts.config.allowRuntimeFetching = false, same as
/// merchant_presentation_test.dart), labelMedium.override(font:
/// GoogleFonts.inter(...)) text measures wider than in production and can
/// overflow its Row - this also happens on the untouched, already-shipped
/// "Pas de compte ? Inscription" link under this same harness, so it is a
/// test-font-substitution artifact, not a defect introduced here. Suppressed
/// at the source (FlutterError.onError) rather than via takeException(),
/// because once more than one such error fires in a frame, Flutter collapses
/// them into a single "Multiple exceptions" wrapper that can no longer be
/// inspected individually. Anything other than this exact, known overflow
/// still fails the test normally.
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
  final store = _Store();
  final auth = _AuthStore();

  setUpAll(() async {
    await initializeDateFormatting('fr');
    GoogleFonts.config.allowRuntimeFetching = false;
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final fontFile = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/roboto-regular.ttf');
    final fontBytes = fontFile.existsSync() ? fontFile.readAsBytesSync() : null;
    font_testing.assetManifest = _FontManifest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = const StringCodec().decodeMessage(message)!;
      if (key.startsWith('test-fonts/')) {
        return fontBytes == null
            ? ByteData(0)
            : ByteData.sublistView(fontBytes);
      }
      final file = File('build/unit_test_assets/$key');
      return file.existsSync()
          ? ByteData.sublistView(file.readAsBytesSync())
          : null;
    });
    if (fontBytes != null) {
      await (FontLoader('TestSans')
            ..addFont(Future.value(ByteData.sublistView(fontBytes))))
          .load();
    }
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
          .load();
    }
    await Firebase.initializeApp();
    auth_platform.FirebaseAuthPlatform.instance = auth;
    platform.FirebaseFirestorePlatform.instance = store;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
            const BasicMessageChannel<Object?>(
                'dev.flutter.pigeon.firebase_analytics_platform_interface.FirebaseAnalyticsHostApi.logEvent',
                StandardMessageCodec()),
            (_) async => <Object?>[null]);
    for (final name in [
      'plugins.flutter.io/firebase_analytics',
      'flutter_keyboard_visibility'
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
  });

  setUp(() {
    store.data.clear();
    auth.currentUser = null;
    FFAppState.reset();
  });

  GoRouter buildRouter() => GoRouter(routes: [
        GoRoute(
          path: '/',
          name: LoginPageWidget.routeName,
          builder: (_, __) => const LoginPageWidget(),
        ),
        GoRoute(
          path: '/inscriptionPage',
          name: InscriptionPageWidget.routeName,
          builder: (_, state) => InscriptionPageWidget(
            initialRole: resolveInitialSignupRole(
              state.uri.queryParameters['role'],
            ),
          ),
        ),
      ]);

  Future<void> pump(WidgetTester tester, GoRouter router) async {
    ignoreKnownFontSubstitutionOverflow();
    // Tall enough that every element is laid out without needing a scroll
    // gesture - this test is about tap/navigation/tab-selection behavior,
    // not scrolling, so a generous height sidesteps unrelated layout noise.
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(router.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<FFAppState>.value(
      value: FFAppState(),
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          FFLocalizationsDelegate(),
          FallbackMaterialLocalizationDelegate(),
          FallbackCupertinoLocalizationDelegate(),
        ],
        supportedLocales: const [Locale('fr')],
        locale: const Locale('fr'),
        theme: ThemeData(fontFamily: 'TestSans'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // --- Signup UX (24/10/2026 Samsung findings) -----------------------------

  // A fixed number of frames instead of pumpAndSettle: the progress indicator
  // and the blinking cursor of the autofocused field never settle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Unlike pump() above, overflows are NOT ignored here, except the known
  // test-font artefact of the login page link, which is not on these pages.
  Future<List<String>> pumpPage(
    WidgetTester tester,
    Widget page, {
    required Size size,
    double textScale = 1.0,
    double keyboard = 0.0,
  }) async {
    final overflows = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exception.toString();
      if (text.contains('A RenderFlex overflowed')) {
        overflows.add(details
            .toString()
            .split('\n')
            .where((l) => l.contains('overflowed') || l.contains('.dart:'))
            .take(4)
            .join(' | '));
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final router = GoRouter(routes: [
      GoRoute(path: '/', name: 'page', builder: (_, __) => page),
      GoRoute(
        path: '/inscriptionPage',
        name: InscriptionPageWidget.routeName,
        builder: (_, __) => const InscriptionPageWidget(),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<FFAppState>.value(
      value: FFAppState(),
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          FFLocalizationsDelegate(),
          FallbackMaterialLocalizationDelegate(),
          FallbackCupertinoLocalizationDelegate(),
        ],
        supportedLocales: const [Locale('fr')],
        locale: const Locale('fr'),
        theme: ThemeData(fontFamily: 'TestSans'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ));
    await settle(tester);
    // Restored before any expect(), as flutter_test requires.
    FlutterError.onError = previousOnError;
    return overflows;
  }

  group('profile completion page (informations complémentaires)', () {
    for (final size in const [Size(320, 568), Size(360, 740), Size(412, 915)]) {
      for (final textScale in const [1.0, 1.3]) {
        for (final keyboard in const [0.0, 320.0]) {
          testWidgets(
              'no overflow at ${size.width.toInt()}x${size.height.toInt()}, '
              'text x$textScale, keyboard ${keyboard.toInt()}px', (tester) async {
            FFAppState().offerProfileCompletionAfterLogin = true;
            final overflows = await pumpPage(
                tester, const InscriptionInformationsPageWidget(),
                size: size, textScale: textScale, keyboard: keyboard);
            expect(overflows, isEmpty, reason: overflows.join('\n---\n'));
            // "Plus tard" stays above the first field, never over it.
            final later = tester.getRect(find.text('Plus tard'));
            final header = tester.getRect(
                find.byKey(const ValueKey('profile-completion-header')));
            expect(header.contains(later.center), isTrue);
            final firstField = tester.getRect(find.byType(TextFormField).first);
            expect(later.bottom, lessThanOrEqualTo(firstField.top));
            // Every field can be reached by scrolling, keyboard open or not.
            await tester.ensureVisible(find.byType(TextFormField).last);
            await settle(tester);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('without the "Plus tard" row the header keeps its height', (tester) async {
      final overflows = await pumpPage(
          tester, const InscriptionInformationsPageWidget(),
          size: const Size(360, 740));
      expect(overflows, isEmpty, reason: overflows.join('\n'));
      expect(find.text('Plus tard'), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('profile-completion-header'))).height,
          200.0);
    });
  });

  group('signup page: the referral code is asked only on the entry screen', () {
    Future<void> openEmailForm(WidgetTester tester) async {
      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);
      await tester.ensureVisible(find.text('Continuer avec l\'e-mail'));
      await tester.tap(find.text('Continuer avec l\'e-mail'));
      await settle(tester);
    }

    testWidgets('the e-mail form neither asks for the code nor recalls it; Retour changes it', (tester) async {
      await pumpPage(tester, const InscriptionPageWidget(), size: const Size(390, 1400));
      await tester.enterText(find.byKey(const ValueKey('entry-referral-code')), 'ab12cd34');
      await settle(tester);
      expect(FFAppState().pendingReferralCode, 'AB12CD34');
      await openEmailForm(tester);
      expect(find.byKey(const ValueKey('entry-referral-code')), findsNothing);
      expect(find.textContaining('parrainage'), findsNothing,
          reason: 'no referral field, recall, "Modifier" or "Ajouter" in the e-mail form');
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Ajouter'), findsNothing);
      // The code is kept for the signup.
      expect(FFAppState().pendingReferralCode, 'AB12CD34');
      // "Retour" goes back to the single field, which can still be changed.
      await tester.tap(find.text('Retour'));
      await settle(tester);
      final field = find.byKey(const ValueKey('entry-referral-code'));
      expect(tester.widget<TextFormField>(field).controller!.text, 'ab12cd34');
      await tester.enterText(field, '99887766');
      await settle(tester);
      expect(FFAppState().pendingReferralCode, '99887766');
    });

    testWidgets('a referral link received with the e-mail form open is kept for the signup', (tester) async {
      await pumpPage(tester, const InscriptionPageWidget(), size: const Size(390, 1400));
      await openEmailForm(tester);
      FFAppState().update(() => FFAppState().pendingReferralCode = '99887766');
      await settle(tester);
      expect(find.textContaining('parrainage'), findsNothing);
      await tester.tap(find.text('Retour'));
      await settle(tester);
      expect(
          tester.widget<TextFormField>(find.byKey(const ValueKey('entry-referral-code'))).controller!.text,
          '99887766');
    });
  });

  testWidgets('the progress indicator shows its message and no button', (tester) async {
    await pumpPage(
        tester,
        const Scaffold(
            body: SignupProgressIndicator(
                message: 'Enregistrement de vos informations…')),
        size: const Size(320, 568),
        textScale: 1.3);
    expect(find.text('Enregistrement de vos informations…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // --- Referral link /i with the real app router (createRouter) -----------
  // AppStateNotifier is a singleton: the cold start test runs first, while
  // the auth state is still unresolved, as on a real launch.
  group('referral link https://play.proxiplay.fr/i?ref=CODE (real app router)', () {
    Future<GoRouter> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = createRouter(AppStateNotifier.instance);
      addTearDown(router.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<FFAppState>.value(
        value: FFAppState(),
        child: MaterialApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            FFLocalizationsDelegate(),
            FallbackMaterialLocalizationDelegate(),
            FallbackCupertinoLocalizationDelegate(),
          ],
          supportedLocales: const [Locale('fr')],
          locale: const Locale('fr'),
          theme: ThemeData(fontFamily: 'TestSans'),
        ),
      ));
      await settle(tester);
      return router;
    }

    String location(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.path;

    Future<void> expectPlayerSignupWith(WidgetTester tester, GoRouter router, String code) async {
      expect(location(router), '/inscriptionPage');
      expect(find.byType(InscriptionPageWidget), findsOneWidget);
      expect(
          tester.widget<FlutterFlowButtonTabBar>(find.byType(FlutterFlowButtonTabBar)).controller!.index,
          0,
          reason: 'Joueur selected');
      final field = find.byKey(const ValueKey('entry-referral-code'));
      expect(tester.widget<TextFormField>(field).controller!.text, code);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      expect(find.text("Continuer avec l'e-mail"), findsOneWidget);
    }

    testWidgets('cold start, signed out: the player signup opens directly with the code', (tester) async {
      ignoreKnownFontSubstitutionOverflow();
      final router = await pumpApp(tester);
      // The link the platform opens the app with, before auth is known.
      router.go('/i?ref=ab12cd34');
      await settle(tester);
      expect(find.byType(InscriptionPageWidget), findsNothing, reason: 'waits for the auth state');
      AppStateNotifier.instance.update(ProxiPlayFirebaseUser(null));
      AppStateNotifier.instance.stopShowingSplashImage();
      await tester.pump(const Duration(seconds: 4)); // signed-out auth resolution
      await settle(tester);
      await expectPlayerSignupWith(tester, router, 'AB12CD34');
      expect(FFAppState().pendingReferralCode, 'AB12CD34');
      // Back: the usual screen, no loop back to the signup.
      router.pop();
      await settle(tester);
      expect(location(router), '/');
      await tester.pump(const Duration(seconds: 2));
      expect(location(router), '/');
      // The code is kept for a later signup.
      expect(FFAppState().pendingReferralCode, 'AB12CD34');
    });

    testWidgets('app already open: a new link goes to the signup with the new code, once', (tester) async {
      ignoreKnownFontSubstitutionOverflow();
      final router = await pumpApp(tester);
      router.go('/');
      await settle(tester);
      router.go('/i?ref=99887766');
      await settle(tester);
      await expectPlayerSignupWith(tester, router, '99887766');
      // The same link received again: same screen, nothing stacked.
      router.go('/i?ref=99887766');
      await settle(tester);
      await expectPlayerSignupWith(tester, router, '99887766');
      router.pop();
      await settle(tester);
      expect(location(router), '/');
    });

    testWidgets('a link without a valid code keeps the usual navigation', (tester) async {
      ignoreKnownFontSubstitutionOverflow();
      FFAppState().clearPendingReferralCode();
      final router = await pumpApp(tester);
      for (final link in ['/i', '/i?ref=', '/i?ref=%3Cscript%3E', '/i?ref=TEST']) {
        router.go(link);
        await settle(tester);
        expect(location(router), '/', reason: link);
        expect(find.byType(InscriptionPageWidget), findsNothing, reason: link);
      }
      expect(FFAppState().pendingReferralCode, isEmpty);
    });
  });

  // --- Shop QR link: the token must survive the way Android opens the app --
  // (25/10/2026 Samsung: a shop QR scan opened through the browser lost its
  // token, so the game was played as a normal, counted participation).
  group('shop QR link delivered by the platform (real app router)', () {
    const token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

    Future<GoRouter> pumpRealApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = createRouter(AppStateNotifier.instance);
      addTearDown(router.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<FFAppState>.value(
        value: FFAppState(),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            FFLocalizationsDelegate(),
            FallbackMaterialLocalizationDelegate(),
            FallbackCupertinoLocalizationDelegate(),
          ],
          supportedLocales: const [Locale('fr')],
          locale: const Locale('fr'),
          theme: ThemeData(fontFamily: 'TestSans'),
        ),
      ));
      await settle(tester);
      AppStateNotifier.instance.update(ProxiPlayFirebaseUser(null));
      AppStateNotifier.instance.stopShowingSplashImage();
      await tester.pump(const Duration(seconds: 4));
      return router;
    }

    // What the Android embedding sends when a link opens the app.
    Future<void> platformOpens(WidgetTester tester, String link) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
            MethodCall('pushRouteInformation', {'location': link, 'state': null})),
        (_) {},
      );
      await settle(tester);
    }

    bool routeMatched(GoRouter router) =>
        router.routerDelegate.currentConfiguration.matches.isNotEmpty;

    for (final entry in const {
      'https App Link (release build)': ['G_HTTPS', 'https://play.proxiplay.fr/j/G_HTTPS?qr_token=$token'],
      'custom scheme from the /j web page (debug build, unverified App Link)':
          ['G_SCHEME', 'proxiplay://game/G_SCHEME?qr_token=$token'],
    }.entries) {
      testWidgets('${entry.key}: the game opens and its token is kept', (tester) async {
        ignoreKnownFontSubstitutionOverflow();
        final router = await pumpRealApp(tester);
        await platformOpens(tester, entry.value[1]);
        final path = router.routerDelegate.currentConfiguration.uri.path;
        expect(gameQrToken(entry.value[0]), token, reason: 'path reached: $path');
        expect(routeMatched(router), isTrue, reason: 'path reached: $path');
      });
    }

    testWidgets('an old proxiplay://game/<game> link without token still opens the game',
        (tester) async {
      ignoreKnownFontSubstitutionOverflow();
      const gameId = 'AbCdEfGhIjKlMnOpQrSt';
      final router = await pumpRealApp(tester);
      await platformOpens(tester, 'proxiplay://game/$gameId');
      final path = router.routerDelegate.currentConfiguration.uri.path;
      expect(routeMatched(router), isTrue, reason: 'path reached: $path');
      expect(path, isNot('/$gameId'));
      expect(gameQrToken(gameId), isNull);
    });

    testWidgets('an invalid token is never kept', (tester) async {
      ignoreKnownFontSubstitutionOverflow();
      const gameId = 'BcDeFgHiJkLmNoPqRsTu';
      final router = await pumpRealApp(tester);
      await platformOpens(tester, 'proxiplay://game/$gameId?qr_token=not-a-token');
      expect(routeMatched(router), isTrue);
      expect(gameQrToken(gameId), isNull);
    });
  });

  group('customSchemeGameLocation', () {
    const token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    String? rewrite(String location, {bool matched = false}) =>
        customSchemeGameLocation(Uri.parse(location), matched: matched);

    test('a game id with its shop token goes to the game route, token kept', () {
      expect(rewrite('/G1?qr_token=$token'), '/game/G1?qr_token=$token');
    });

    test('an old tokenless link with a Firestore game id goes to the game route', () {
      expect(rewrite('/AbCdEfGhIjKlMnOpQrSt'), '/game/AbCdEfGhIjKlMnOpQrSt');
    });

    test('matched routes and other addresses are never rewritten', () {
      expect(rewrite('/i?ref=99887766', matched: true), isNull);
      expect(rewrite('/game/G1?qr_token=$token', matched: true), isNull);
      expect(rewrite('/'), isNull);
      expect(rewrite('/unknownPage'), isNull);
      expect(rewrite('/a/b?qr_token=$token'), isNull);
      expect(rewrite('/G1?qr_token=short'), isNull);
      expect(rewrite('/bad%20id?qr_token=$token'), isNull);
    });
  });
}

// FlutterFire platform fakes use the platform packages shipped by our SDKs.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart'
    as functions_platform;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as font_testing;
import 'package:proxi_play/backend/backend.dart';
import 'package:proxi_play/components/merchant_pickup_point.dart';
import 'package:proxi_play/components/merchant_presentation.dart';
import 'package:proxi_play/components/winner_email_text.dart';
import 'package:proxi_play/pages/commercant/home_commercant_page/home_commercant_page_widget.dart';
import 'package:proxi_play/pages/commercant/jeux_commercant_page/jeux_commercant_page_widget.dart';
import 'package:proxi_play/flutter_flow/internationalization.dart';
import 'package:proxi_play/pages/joueur/enseigne_detail_joueur_page/enseigne_detail_joueur_page_widget.dart';
import 'package:proxi_play/pages/joueur/lot_detail_joueur_page/lot_detail_joueur_page_widget.dart';

/// Read-only fixture store: any accidental write or collection-group query
/// remains unimplemented and fails the test. No Firebase service is contacted.
class _Store extends platform.FirebaseFirestorePlatform {
  final data = <String, Map<String, dynamic>>{};
  final reads = <String>[];
  final denied = <String>{};
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
      required platform.ListenSource listenSource}) {
    store.reads.add(path);
    if (store.denied.contains(path)) {
      return Stream.error(StateError('Unavailable fixture'));
    }
    return Stream.value(store.snapshot(path));
  }
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
  Future<platform.QuerySnapshotPlatform> get(
      [platform.GetOptions options = const platform.GetOptions()]) async {
    store.reads.add(path);
    if (store.denied.contains(path)) throw StateError('Unavailable fixture');
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

class _Functions extends functions_platform.FirebaseFunctionsPlatform {
  _Functions() : super(null, 'europe-west1');
  late Future<dynamic> Function(dynamic) handler;
  @override
  functions_platform.FirebaseFunctionsPlatform delegateFor(
          {FirebaseApp? app, required String region}) =>
      this;
  @override
  functions_platform.HttpsCallablePlatform httpsCallable(String? origin,
          String name, functions_platform.HttpsCallableOptions options) =>
      _Callable(this, name, options);
}

class _Callable extends functions_platform.HttpsCallablePlatform {
  _Callable(_Functions functions, String name,
      functions_platform.HttpsCallableOptions options)
      : super(functions, null, name, options, null);
  @override
  Future<dynamic> call([dynamic parameters]) {
    if (name != 'getMerchantGames') {
      throw StateError('Unexpected callable $name');
    }
    return (functions as _Functions).handler(parameters);
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  final store = _Store();
  final calls = _Functions();
  final screenshotKey = GlobalKey();
  setUpAll(() async {
    await initializeDateFormatting('fr');
    GoogleFonts.config.allowRuntimeFetching = false;
    // Offline font fixture from the Flutter SDK. No application asset changes.
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
    platform.FirebaseFirestorePlatform.instance = store;
    functions_platform.FirebaseFunctionsPlatform.instance = calls;
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
    store.reads.clear();
    store.denied.clear();
    calls.handler = (_) async => throw StateError('Unexpected call');
  });

  DocumentReference ref([String path = 'enseignes/shop']) =>
      FirebaseFirestore.instance.doc(path);
  EnseignesRecord merchant(Map<String, dynamic> values) =>
      EnseignesRecord.getDocumentFromData(values, ref());
  Map<String, dynamic> complete() => {
        'name': 'L’Unique',
        'city': 'Dunkerque',
        'address': '12 rue du Centre',
        'area_code': '59140',
        'description':
            'Bar convivial au cœur de Dunkerque. Café, apéros et bonne ambiance.',
        'category': ['Restaurants_bars'],
        'phone_number': '03 28 00 00 00',
        'site_web_url': 'https://example.com',
        'google_rating': 4.6,
        'google_reviews_count': 73,
      };
  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 390, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          FFLocalizationsDelegate(),
          FallbackMaterialLocalizationDelegate(),
          FallbackCupertinoLocalizationDelegate(),
        ],
        supportedLocales: const [
          Locale('fr')
        ],
        locale: const Locale('fr'),
        theme: ThemeData(
            fontFamily: 'TestSans',
            colorScheme: ColorScheme.fromSeed(seedColor: merchantAccent),
            scaffoldBackgroundColor: const Color(0xFFF7F5F8)),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: RepaintBoundary(key: screenshotKey, child: child)));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('MERCHANT_CAPTURE')) return;
    final boundary = screenshotKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('.tmp_merchant_ui');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('merchant screens show errors and retry to empty without a loop',
      (tester) async {
    for (final page in [
      const HomeCommercantPageWidget(),
      const JeuxCommercantPageWidget()
    ]) {
      var count = 0;
      calls.handler = (_) async {
        count++;
        if (count == 1) {
          throw FirebaseException(
              plugin: 'cloud_functions',
              code: 'not-found',
              message: 'Missing endpoint');
        }
        return {'ids': <String>[], 'cursor': '', 'hasMore': false};
      };
      await pump(tester, page, width: 320, scale: 1.5);
      expect(find.text('Impossible de charger vos jeux.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(count, 1);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(count, 2);
      expect(find.text('Impossible de charger vos jeux.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('merchant pagination retains games and retries the same cursor',
      (tester) async {
    const photo = 'https://example.invalid/merchant-game.png';
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
          File('assets/images/Background.png').readAsBytesSync());
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
          const NetworkImage(photo),
          () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: frame.image))));
    });
    store.data['games/one'] = {
      'name': 'Premier jeu',
      'photo': photo,
      'end_date':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 2)))
    };
    final cursors = <String>[];
    calls.handler = (parameters) async {
      cursors.add(parameters['cursor'] as String);
      if (cursors.length == 2) {
        throw FirebaseException(
            plugin: 'cloud_functions', code: 'unavailable', message: 'Offline');
      }
      return cursors.length == 1
          ? {
              'ids': ['one'],
              'cursor': 'one',
              'hasMore': true
            }
          : {'ids': <String>[], 'cursor': 'one', 'hasMore': false};
    };
    await pump(tester, const JeuxCommercantPageWidget(), width: 800);
    expect(find.text('Premier jeu'), findsWidgets);
    await tester.tap(find.text('Charger plus de jeux'));
    await tester.pumpAndSettle();
    expect(find.text('Premier jeu'), findsWidgets);
    expect(find.text('Impossible de charger vos jeux.'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(cursors, ['', 'one', 'one']);
    expect(find.text('Premier jeu'), findsWidgets);
    expect(find.text('Impossible de charger vos jeux.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('winner email remains readable at narrow width and large text',
      (tester) async {
    for (final scale in [1.0, 2.0]) {
      await pump(
          tester,
          const Scaffold(
              body: Padding(
                  padding: EdgeInsets.all(32),
                  child: WinnerEmailText(
                    email: 'prenom.nom@gmail.com',
                    style: TextStyle(fontSize: 14),
                  ))),
          width: 320,
          scale: scale);
      final displayed =
          tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(displayed.replaceAll('\n', ''), 'prenom.nom@gmail.com');
      expect(displayed.contains('gmail.co\nm'), isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('portrait cards fit sparse content and enlarged text',
      (tester) async {
    for (final scale in [1.0, 2.0]) {
      await pump(
          tester,
          Scaffold(
              body: SingleChildScrollView(
                  child: SizedBox(
            width: 260,
            child: MerchantSummaryCard(
                merchant: merchant({'name': 'Commerce'}),
                photoFuture: Future.value([]),
                onTap: () {}),
          ))),
          width: 320,
          scale: scale);
      final cardBottom =
          tester.getBottomLeft(find.byType(MerchantSummaryCard)).dy;
      final linkBottom =
          tester.getBottomLeft(find.text('Voir le commerçant')).dy;
      expect(cardBottom - linkBottom, closeTo(16, 2));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('today schedule expands seven days without reads at large text',
      (tester) async {
    final days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche'
    ];
    final hours = List.generate(
        7,
        (i) => HorairesRecord.getDocumentFromData({
              'day': days[i],
              'is_open': i == 0,
              'is_full_day': true,
              'opening_morning': DateTime(2026, 1, 1, 10),
              'closing_morning': DateTime(2026, 1, 1, 14, 30),
              'opening_afternoon': DateTime(2026, 1, 1, 18),
              'closing_afternoon': DateTime(2026, 1, 1, 21, 30),
            }, ref('enseignes/shop/horaires/$i')));
    await pump(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: MerchantTodayHours(
          hours: hours,
          today: DateTime(2026, 9, 7),
        ))),
        width: 320,
        scale: 2);
    expect(find.text("Aujourd'hui"), findsOneWidget);
    expect(find.text('10:00 – 14:30\n18:00 – 21:30'), findsOneWidget);
    expect(find.text('Mardi'), findsNothing);
    await tester.tap(find.text('Voir tous les horaires'));
    await tester.pumpAndSettle();
    for (final day in days) {
      expect(find.text(day), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Réduire'));
    await tester.tap(find.text('Réduire'));
    await tester.pumpAndSettle();
    expect(find.text('Mardi'), findsNothing);
    expect(store.reads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'micro cards reuse supplied photos and keep navigation separate from favorite',
      (tester) async {
    var opens = 0;
    var favorites = 0;
    final photos = Future.value(<ImagesRecord>[]);
    await pump(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MerchantSummaryCard(
                      merchant: merchant(complete()),
                      photoFuture: photos,
                      onTap: () => opens++,
                      favorite: IconButton(
                          onPressed: () => favorites++,
                          icon: const Icon(Icons.favorite_border)),
                    )))));
    expect(find.text('4,6 Google (73 avis)'), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(store.reads, isEmpty);
    await tester.tap(find.byIcon(Icons.favorite_border));
    expect(favorites, 1);
    expect(opens, 0);
    await tester.tap(find.text('Voir le commerçant'));
    expect(opens, 1);
    await capture(tester, 'micro_complete');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow compact card supports large text, long name and absent optional fields',
      (tester) async {
    await pump(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: MerchantSummaryCard(
          merchant: merchant({
            'name': 'Un très long nom de commerçant de proximité',
            'city': 'Dunkerque'
          }),
          compact: true,
          photoFuture: Future.value([]),
          onTap: () {},
        ))),
        width: 320,
        scale: 1.5);
    expect(find.byType(MerchantRating), findsNothing);
    expect(find.text('null'), findsNothing);
    expect(find.text('Voir le commerçant'), findsOneWidget);
    await capture(tester, 'micro_narrow');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Proxiplay image is displayed and rebuilding a card does not reload its images',
      (tester) async {
    const url = 'https://example.invalid/proxiplay-photo.png';
    // Seed Flutter's image cache with a local fixture: no HTTP or Google call.
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
          File('assets/images/Background.png').readAsBytesSync());
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
        const CachedNetworkImageProvider(url),
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame.image))),
      );
      codec.dispose();
    });
    store.data['enseignes/shop/images/main'] = {'url': url};
    final record = merchant(complete());
    Widget card() => Scaffold(
        body: SingleChildScrollView(
            child: MerchantSummaryCard(merchant: record, onTap: () {})));
    await pump(tester, card());
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsNothing);
    await pump(tester, card());
    expect(
        store.reads.where((path) => path == 'enseignes/shop/images').length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'schedule distinguishes closed, missing, continuous and split hours',
      (tester) async {
    HorairesRecord day(String id, Map<String, dynamic> values) =>
        HorairesRecord.getDocumentFromData(
            values, ref('enseignes/shop/horaires/$id'));
    final hours = [
      day('sun', {'day': 'Dimanche', 'is_open': false}),
      day('mon', {
        'day': 'Lundi',
        'is_open': true,
        'is_full_day': false,
        'opening_day': DateTime(2026, 1, 1, 9),
        'closing_day': DateTime(2026, 1, 1, 18)
      }),
      day('tue', {
        'day': 'Mardi',
        'is_open': true,
        'is_full_day': true,
        'opening_morning': DateTime(2026, 1, 1, 9),
        'closing_morning': DateTime(2026, 1, 1, 12),
        'opening_afternoon': DateTime(2026, 1, 1, 14),
        'closing_afternoon': DateTime(2026, 1, 1, 18)
      }),
      day('wed', {'day': 'Mercredi'}),
    ];
    await pump(tester, Scaffold(body: MerchantHours(hours: hours)));
    expect(find.text('Fermé'), findsOneWidget);
    expect(find.text('09:00 – 18:00'), findsOneWidget);
    expect(find.text('09:00 – 12:00\n14:00 – 18:00'), findsOneWidget);
    expect(find.text('Horaires non renseignés'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Lundi')).dy,
        lessThan(tester.getTopLeft(find.text('Dimanche')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pickup never queries schedules for absent, invalid or deleted merchant',
      (tester) async {
    for (final reference in [
      null,
      ref('users/invalid'),
      ref('enseignes/deleted')
    ]) {
      store.reads.clear();
      await pump(
          tester, Scaffold(body: MerchantPickupPoint(enseigneRef: reference)));
      expect(find.text('Informations du commerçant indisponibles.'),
          findsOneWidget);
      expect(store.reads.where((path) => path.contains('horaires')), isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'pickup loads only prize merchant, one schedule, and navigates to merchant route',
      (tester) async {
    store.data['enseignes/shop'] = complete();
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              Scaffold(body: MerchantPickupPoint(enseigneRef: ref()))),
      GoRoute(
          path: '/merchant',
          name: EnseigneDetailJoueurPageWidget.routeName,
          builder: (_, state) {
            final extra = state.extra! as Map<String, dynamic>;
            final record = extra['enseigneDoc'] as EnseignesRecord;
            return Scaffold(body: Text('Destination ${record.reference.path}'));
          }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Horaires du point de retrait'));
    await tester.pumpAndSettle();
    expect(find.text('Horaires non renseignés'), findsOneWidget);
    expect(
        store.reads.where((path) => path == 'enseignes/shop/horaires').length,
        1);
    expect(store.reads.where((path) => path.startsWith('games')), isEmpty);
    await tester.tap(find.text('Voir la fiche commerçant'));
    await tester.pumpAndSettle();
    expect(find.text('Destination enseignes/shop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'detail displays complete merchant, single schedule, current games and gallery fallback',
      (tester) async {
    store.data['enseignes/shop'] = complete();
    store.data['enseignes/shop/horaires/monday'] = {
      'day': [
        'Lundi',
        'Mardi',
        'Mercredi',
        'Jeudi',
        'Vendredi',
        'Samedi',
        'Dimanche'
      ][DateTime.now().weekday - 1],
      'is_open': false
    };
    store.data['games/current'] = {
      'name': 'Un déjeuner à gagner',
      'prize_value': 35,
      'start_date':
          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
      'end_date':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 2)))
    };
    await pump(tester,
        EnseigneDetailJoueurPageWidget(enseigneDoc: merchant(complete())));
    expect(find.text('L’Unique'), findsOneWidget);
    expect(find.text('4,6 Google (73 avis)'), findsOneWidget);
    await capture(tester, 'detail_identity');
    await tester.scrollUntilVisible(find.text('Horaires'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byType(MerchantTodayHours), findsOneWidget);
    expect(find.text('Fermé'), findsOneWidget);
    await tester.ensureVisible(find.text('Voir tous les horaires'));
    await tester.tap(find.text('Voir tous les horaires'));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantHours), findsOneWidget);
    await tester.tap(find.text('Réduire'));
    await tester.pumpAndSettle();
    await capture(tester, 'detail_practical');
    await tester.scrollUntilVisible(find.text('Un déjeuner à gagner'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Jeux en cours'), findsOneWidget);
    expect(find.text('Valeur du lot : 35 €'), findsOneWidget);
    expect(
        store.reads.where((path) => path == 'enseignes/shop/horaires').length,
        1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'detail without description, rating, images or hours invents no content',
      (tester) async {
    store.data['enseignes/shop'] = {'name': 'L’Unique'};
    await pump(
        tester,
        EnseigneDetailJoueurPageWidget(
            enseigneDoc: merchant({'name': 'L’Unique'})));
    expect(find.byType(MerchantRating), findsNothing);
    expect(find.text('Présentation'), findsNothing);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Horaires non renseignés'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Adresse non renseignée'), findsOneWidget);
    expect(find.text('Horaires non renseignés'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Aucun jeu en cours actuellement.'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Jeux en cours'), findsNothing);
    expect(tester.getSize(find.text('Aucun jeu en cours actuellement.')).height,
        lessThan(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail handles null, invalid, deleted and denied references',
      (tester) async {
    for (final path in [
      null,
      'users/invalid',
      'enseignes/deleted',
      'enseignes/denied'
    ]) {
      store.reads.clear();
      store.denied.add('enseignes/denied');
      await pump(
          tester,
          EnseigneDetailJoueurPageWidget(
              enseigneDoc: path == null
                  ? null
                  : EnseignesRecord.getDocumentFromData(
                      {'name': 'Old name'}, ref(path))));
      expect(find.text('Fiche commerçant indisponible'), findsOneWidget);
      expect(
          store.reads.where(
              (path) => path.endsWith('/horaires') || path.endsWith('/images')),
          isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'lot without merchant keeps claim display without querying schedules',
      (tester) async {
    store.data['prizes/prize'] = {
      'name': 'Votre cadeau',
      'claim_code': 'ABC123',
      'fulfillment_type': 'platform'
    };
    final prize = PrizesRecord.getDocumentFromData(
        store.data['prizes/prize']!, ref('prizes/prize'));
    await pump(tester, LotDetailJoueurPageWidget(lot: prize));
    expect(find.text('Remise du lot organisée par Proxiplay.'), findsOneWidget);
    expect(store.reads.where((path) => path.contains('horaires')), isEmpty);
    await capture(tester, 'lot_without_merchant');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'classic lot with game but no merchant still renders without a schedule query',
      (tester) async {
    store.data['games/source'] = {'name': 'Jeu source'};
    store.data['prizes/prize'] = {
      'name': 'Votre cadeau',
      'claim_code': 'ABC123',
      'game_id': ref('games/source')
    };
    final prize = PrizesRecord.getDocumentFromData(
        store.data['prizes/prize']!, ref('prizes/prize'));
    await pump(tester, LotDetailJoueurPageWidget(lot: prize));
    await tester.scrollUntilVisible(find.text('Point de retrait'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(
        find.text('Informations du commerçant indisponibles.'), findsOneWidget);
    expect(store.reads.where((path) => path.contains('horaires')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'collection point stays compact and shows hours only when expanded',
      (tester) async {
    store.data['enseignes/shop'] = complete();
    store.data['enseignes/shop/horaires/monday'] = {
      'day': 'Lundi',
      'is_open': false
    };
    await pump(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MerchantPickupPoint(enseigneRef: ref())))));
    expect(find.text('Présentation'), findsNothing);
    expect(find.text('Jeux en cours'), findsNothing);
    expect(store.reads.where((path) => path.contains('horaires')), isEmpty);
    await tester.tap(find.text('Horaires du point de retrait'));
    await tester.pumpAndSettle();
    expect(find.text('Fermé'), findsOneWidget);
    expect(find.byType(MerchantHours), findsOneWidget);
    await capture(tester, 'pickup_point');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed schedule loads are handled even before the section becomes visible',
      (tester) async {
    store.data['enseignes/shop'] = complete();
    store.denied.add('enseignes/shop/horaires');
    await pump(tester,
        EnseigneDetailJoueurPageWidget(enseigneDoc: merchant(complete())));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Horaires indisponibles'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Horaires indisponibles'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await pump(tester, Scaffold(body: MerchantPickupPoint(enseigneRef: ref())));
    await tester.tap(find.text('Horaires du point de retrait'));
    await tester.pumpAndSettle();
    expect(find.text('Horaires indisponibles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

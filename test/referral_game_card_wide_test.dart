import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proxi_play/flutter_flow/internationalization.dart';
import 'package:proxi_play/index.dart';
import 'package:proxi_play/widgets/referral_game_card.dart';

// Wide "LE JEU DU PARRAINAGE" card (27/10/2026): full section width, same look
// as the "JEUX A SCANNER" cards, no text overflow, whole card clickable.

// ignore: subtype_of_sealed_class
class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this._data);
  final Map<String, dynamic> _data;
  @override
  String get id => 'referral-1';
  @override
  Map<String, dynamic> data() => _data;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('fr');
  });

  String? openedGameId;

  Future<void> pump(
    WidgetTester tester, {
    required Map<String, dynamic> data,
    required Size size,
    double textScale = 1.0,
  }) async {
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exception.toString();
      if (text.contains('overflowed')) {
        overflows.add(text.split('\n').first);
        return;
      }
      // Google Fonts cannot load fonts in tests (runtime fetching disabled).
      if (text.contains('GoogleFonts') || text.contains('google_fonts')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    openedGameId = null;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Padding(
            // Same horizontal padding as the Home.
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(children: [
              ReferralGameCard(gameSnapshot: _Doc(data), wide: true),
            ]),
          ),
        ),
      ),
      GoRoute(
        path: '/referral',
        name: ReferralGameDetailJoueurPageWidget.routeName,
        builder: (_, state) {
          openedGameId = state.uri.queryParameters['gameId'];
          return const Scaffold(body: Text('detail'));
        },
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        FFLocalizationsDelegate(),
        FallbackMaterialLocalizationDelegate(),
        FallbackCupertinoLocalizationDelegate(),
      ],
      supportedLocales: const [Locale('fr')],
      locale: const Locale('fr'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ));
    await tester.pump();
    FlutterError.onError = previous;
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  }

  final endDate = Timestamp.fromDate(DateTime(2026, 11, 3));

  testWidgets('wide card spans the section width, shows title, prize and programme',
      (tester) async {
    await pump(tester,
        data: {'title': 'test', 'prize_value': 1, 'end_date': endDate},
        size: const Size(412, 915));
    final card = find.byKey(const ValueKey('referral-game-wide-card'));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).width, 412 - 40);
    expect(tester.getSize(card).height, 160);
    expect(find.text('test'), findsOneWidget);
    expect(find.text('1 €'), findsOneWidget);
    expect(find.textContaining('Programme de parrainage'), findsOneWidget);
    expect(find.textContaining("Jusqu'au 03/11"), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(360, 740), Size(412, 915)]) {
    for (final textScale in const [1.0, 1.3, 1.6]) {
      testWidgets(
          'no overflow at ${size.width.toInt()}px, text x$textScale, long title and prize',
          (tester) async {
        await pump(tester,
            data: {
              'title': 'Grand jeu de parrainage de la Toussaint avec un titre très long',
              'prize_description': 'Un week-end pour deux personnes à la mer, dîner compris',
              'end_date': endDate,
            },
            size: size,
            textScale: textScale);
      });
    }
  }

  testWidgets('the whole card opens the referral game', (tester) async {
    await pump(tester,
        data: {'title': 'test', 'prize_value': 1, 'end_date': endDate},
        size: const Size(390, 844));
    final card = find.byKey(const ValueKey('referral-game-wide-card'));
    // A tap near a corner, away from the texts.
    final rect = tester.getRect(card);
    await tester.tapAt(rect.topRight + const Offset(-12, 12));
    await tester.pumpAndSettle();
    expect(openedGameId, 'referral-1');
  });
}

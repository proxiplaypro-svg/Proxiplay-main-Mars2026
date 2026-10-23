import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/app_state.dart';
import 'package:proxi_play/services/ad_system_service.dart';
import 'package:proxi_play/widgets/open_ad_gate.dart';

// Valid 1x1 PNG: a creative that loads without network.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

class _FakeAds extends AdSystemService {
  _FakeAds(this.load);
  final Future<AdPlacementConfig> Function() load;
  final events = <String>[];
  int loads = 0;
  bool? lastSignedIn;

  @override
  Future<AdPlacementConfig> getDisplayablePlacement(String placement,
      {required bool signedIn}) {
    loads++;
    lastSignedIn = signedIn;
    return load();
  }

  @override
  Future<void> recordImpression(String placement, {String campaignId = ''}) async =>
      events.add('impression:$placement:$campaignId');

  @override
  Future<void> recordClick(String placement, {String campaignId = ''}) async =>
      events.add('click:$placement:$campaignId');
}

AdPlacementConfig _config({
  bool? enabled = true,
  String imageUrl = 'https://ads.example/creative.png',
  String destinationUrl = '',
  int? frequencyCapHours,
  DateTime? endAt,
  String type = 'advertisement',
}) =>
    AdPlacementConfig(
      enabled: enabled,
      imageUrl: imageUrl,
      destinationUrl: destinationUrl,
      startAt: null,
      endAt: endAt,
      frequencyCapHours: frequencyCapHours,
      campaignId: 'c1',
      communicationType: type,
    );

const _homeText = 'Accueil joueur';
const _impression = 'impression:open:c1';
Finder get _overlay => find.byKey(const ValueKey('open-ad-overlay'));
Finder get _closeButton => find.byIcon(Icons.close_rounded);

Widget _home(_FakeAds ads, {bool brokenImage = false, bool signedIn = true}) => OpenAdGate(
      service: ads,
      signedIn: signedIn,
      imageProviderFor: (_) => brokenImage
          ? MemoryImage(Uint8List.fromList(const [1, 2, 3]))
          : MemoryImage(_png),
      child: const Scaffold(body: Center(child: Text(_homeText))),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _pumpHome(WidgetTester tester, _FakeAds ads,
    {bool brokenImage = false, bool signedIn = true}) async {
  await tester.pumpWidget(MaterialApp(home: _home(ads, brokenImage: brokenImage, signedIn: signedIn)));
  await _settle(tester);
}

void main() {
  setUp(() {
    OpenAdGate.resetAttemptForTest();
    FFAppState().adOpenLastShownAt = null;
  });

  testWidgets('a ready ad covers the player Home, is labelled, counted once on screen and closes',
      (tester) async {
    final ads = _FakeAds(() async => _config());
    await _pumpHome(tester, ads);
    expect(_overlay, findsOneWidget);
    expect(find.text('Publicité'), findsOneWidget);
    expect(ads.events, [_impression]);
    expect(ads.lastSignedIn, isTrue);
    expect(FFAppState().adOpenLastShownAt, isNotNull);
    expect(find.text(_homeText, skipOffstage: false), findsOneWidget);
    await tester.tap(_closeButton);
    await tester.pump();
    expect(_overlay, findsNothing);
    expect(ads.events, [_impression], reason: 'closing is not a click');
  });

  testWidgets('Android back closes the ad and nothing else', (tester) async {
    final ads = _FakeAds(() async => _config());
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('Écran précédent')),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => _home(ads)));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_overlay, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_overlay, findsNothing);
    expect(find.text(_homeText), findsOneWidget, reason: 'the Home stays: back did not pop it');
    // Without an ad, back works normally again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Écran précédent'), findsOneWidget);
  });

  testWidgets('not ready within 2 seconds: abandoned for this launch, never shown late',
      (tester) async {
    final completer = Completer<AdPlacementConfig>();
    final ads = _FakeAds(() => completer.future);
    await tester.pumpWidget(MaterialApp(home: _home(ads)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2, milliseconds: 100));
    completer.complete(_config());
    await _settle(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(_overlay, findsNothing);
    expect(ads.events, isEmpty);
    expect(FFAppState().adOpenLastShownAt, isNull);
  });

  testWidgets('never over a screen opened on top of the Home (e.g. a game from a QR code)',
      (tester) async {
    final completer = Completer<AdPlacementConfig>();
    final ads = _FakeAds(() => completer.future);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: _home(ads)));
    await tester.pump();
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Jeu ouvert par QR'))));
    await tester.pump();
    completer.complete(_config());
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Jeu ouvert par QR'), findsOneWidget);
    expect(_overlay, findsNothing);
    expect(ads.events, isEmpty);
  });

  testWidgets('no ad: disabled, expired, without creative or within the frequency cap',
      (tester) async {
    for (final config in [
      _config(enabled: false),
      _config(enabled: null),
      _config(endAt: DateTime.now().subtract(const Duration(hours: 1))),
      _config(imageUrl: ''), // e.g. adults-only campaign refused by the server
    ]) {
      OpenAdGate.resetAttemptForTest();
      final ads = _FakeAds(() async => config);
      await _pumpHome(tester, ads);
      expect(_overlay, findsNothing);
      expect(ads.events, isEmpty);
    }
    OpenAdGate.resetAttemptForTest();
    FFAppState().adOpenLastShownAt = DateTime.now().subtract(const Duration(hours: 1));
    final capped = _FakeAds(() async => _config(frequencyCapHours: 24));
    await _pumpHome(tester, capped);
    expect(_overlay, findsNothing);
  });

  testWidgets('a guest Home asks for ordinary campaigns only', (tester) async {
    final ads = _FakeAds(() async => _config());
    await _pumpHome(tester, ads, signedIn: false);
    expect(ads.lastSignedIn, isFalse);
  });

  testWidgets('a network error or a broken image never blocks the Home', (tester) async {
    await _pumpHome(tester, _FakeAds(() async => throw StateError('offline')));
    expect(_overlay, findsNothing);
    expect(find.text(_homeText), findsOneWidget);
    OpenAdGate.resetAttemptForTest();
    final broken = _FakeAds(() async => _config());
    await _pumpHome(tester, broken, brokenImage: true);
    expect(_overlay, findsNothing);
    expect(broken.events, isEmpty);
  });

  testWidgets('one attempt per cold start: a revisit or a resume shows nothing again',
      (tester) async {
    final ads = _FakeAds(() async => _config());
    await _pumpHome(tester, ads);
    await tester.tap(_closeButton);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpHome(tester, ads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ads.loads, 1);
    expect(_overlay, findsNothing);
    expect(ads.events, [_impression]);
  });

  group('label of the opening interstitial', () {
    for (final entry in const {
      'advertisement': 'Publicité',
      'discovery': 'À découvrir',
      'proxiplay_info': 'Info ProxiPlay',
      '': 'Publicité', // older campaign without the field
      'future_type': 'Publicité', // unknown value
    }.entries) {
      testWidgets('"${entry.key}" is labelled "${entry.value}", top left, closing and counting unchanged',
          (tester) async {
        final ads = _FakeAds(() async => _config(type: entry.key));
        await _pumpHome(tester, ads);
        final label = find.byKey(const ValueKey('open-ad-label'));
        expect(tester.widget<Text>(label).data, entry.value);
        final overlay = tester.getRect(_overlay);
        final labelRect = tester.getRect(label);
        expect(labelRect.left - overlay.left, lessThan(60), reason: 'top left');
        expect(labelRect.top - overlay.top, lessThan(120), reason: 'top left');
        expect(labelRect.width, lessThan(overlay.width / 2), reason: 'small, not covering the visual');
        expect(ads.events, [_impression]);
        await tester.tap(_closeButton);
        await tester.pump();
        expect(_overlay, findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/services/ad_system_service.dart';
import 'package:proxi_play/widgets/ad_banner_zone.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

class _FakeAds extends AdSystemService {
  final events = <String>[];
  @override
  Future<void> recordImpression(String placement, {String campaignId = ''}) async =>
      events.add('impression:$placement:$campaignId');
  @override
  Future<void> recordClick(String placement, {String campaignId = ''}) async =>
      events.add('click:$placement:$campaignId');
}

AdPlacementConfig _ad({
  String campaign = 'c1',
  bool enabled = true,
  String image = 'https://ads/img.png',
  String type = 'advertisement',
  String destination = '',
  String label = '',
}) =>
    AdPlacementConfig(
      enabled: enabled,
      imageUrl: image,
      destinationUrl: destination,
      communicationType: type,
      displayLabel: label,
      startAt: null,
      endAt: null,
      frequencyCapHours: null,
      campaignId: campaign,
    );

const _bannerFinderKey = ValueKey('ad-banner-home_banner');
const _contentBelow = 'Contenu sous le bandeau';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// The Home layout in miniature: content above (variable height), the
/// banner, then content below, in a vertical scroll view.
Widget _home(
  _FakeAds ads,
  Future<AdPlacementConfig?> config, {
  double above = 100,
  bool brokenImage = false,
  ScrollController? controller,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        controller: controller,
        children: [
          SizedBox(height: above),
          AdBannerZone(
            placement: 'home_banner',
            configFuture: config,
            service: ads,
            trailingSpace: 16,
            imageProviderFor: (_) =>
                brokenImage ? MemoryImage(Uint8List.fromList(const [1, 2, 3])) : MemoryImage(_png),
          ),
          const SizedBox(height: 40, child: Text(_contentBelow)),
          const SizedBox(height: 2000),
        ],
      ),
    ),
  );
}

double _bannerZoneHeight(WidgetTester tester) => tester.getSize(find.byType(AdBannerZone)).height;
const _labelKey = ValueKey('ad-banner-label-home_banner');
// 16 top + label + 4 + 90 image + 16 trailing.
double _fullHeight(WidgetTester tester) => 16 + tester.getSize(find.byKey(_labelKey)).height + 4 + 90 + 16;

void main() {
  testWidgets('no ad: no banner, no margin, nothing counted', (tester) async {
    for (final config in <Future<AdPlacementConfig?> Function()>[
      () => Future.value(null),
      () => Future.value(_ad(enabled: false)),
      () => Future.value(_ad(image: '')),
      // A failed load (the Home loaders turn errors into null; a raw error
      // must not break the banner either).
      () {
        final failed = Future<AdPlacementConfig?>.error(StateError('offline'));
        failed.ignore();
        return failed;
      },
    ]) {
      final ads = _FakeAds();
      await tester.pumpWidget(_home(ads, config()));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_bannerZoneHeight(tester), 0);
      expect(find.text('Publicité'), findsNothing);
      expect(ads.events, isEmpty);
    }
  });

  testWidgets('a visible banner is counted once its image shows and it stays 1 s on screen',
      (tester) async {
    final ads = _FakeAds();
    await tester.pumpWidget(_home(ads, Future.value(_ad())));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(_bannerFinderKey), findsOneWidget);
    expect(find.text('Publicité'), findsOneWidget);
    // Reserved space: 16 top + 90 banner + 16 trailing.
    expect(_bannerZoneHeight(tester), _fullHeight(tester));
    await tester.pump(const Duration(milliseconds: 500));
    expect(ads.events, isEmpty, reason: 'not yet one second on screen');
    await tester.pump(const Duration(milliseconds: 600));
    expect(ads.events, ['impression:home_banner:c1']);
    // Staying on screen or being rebuilt does not count again.
    await tester.pump(const Duration(seconds: 5));
    expect(ads.events, ['impression:home_banner:c1']);
  });

  testWidgets('below the fold it is not counted until scrolled into view', (tester) async {
    final ads = _FakeAds();
    final controller = ScrollController();
    await tester.pumpWidget(_home(ads, Future.value(_ad()), above: 1500, controller: controller));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(ads.events, isEmpty);
    // Barely visible (less than half): still not counted.
    const bannerTop = 1500.0 + 16.0;
    final viewport = tester.getSize(find.byType(ListView)).height;
    controller.jumpTo(bannerTop - viewport + 30);
    await tester.pump();
    await _settle(tester); // the banner is built (and its image decoded) when it comes near
    await tester.pump(const Duration(seconds: 2));
    expect(ads.events, isEmpty);
    // Fully in view for one second: counted.
    controller.jumpTo(bannerTop - viewport + 200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));
    expect(ads.events, ['impression:home_banner:c1']);
  });

  testWidgets('scrolled away before one second: not counted', (tester) async {
    final ads = _FakeAds();
    final controller = ScrollController();
    await tester.pumpWidget(_home(ads, Future.value(_ad()), controller: controller));
    await _settle(tester);
    await tester.pumpAndSettle();
    controller.jumpTo(1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(ads.events, isEmpty);
  });

  testWidgets('a refresh with the same campaign is not counted again; a new campaign is',
      (tester) async {
    final ads = _FakeAds();
    await tester.pumpWidget(_home(ads, Future.value(_ad())));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpWidget(_home(ads, Future.value(_ad())));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(ads.events, ['impression:home_banner:c1']);
    await tester.pumpWidget(_home(ads, Future.value(_ad(campaign: 'c2'))));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(ads.events, ['impression:home_banner:c1', 'impression:home_banner:c2']);
  });

  testWidgets('in the background nothing is counted', (tester) async {
    final ads = _FakeAds();
    await tester.pumpWidget(_home(ads, Future.value(_ad())));
    await _settle(tester);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(ads.events, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(ads.events, ['impression:home_banner:c1']);
  });

  testWidgets('a broken image collapses the banner smoothly, without counting', (tester) async {
    final ads = _FakeAds();
    await tester.pumpWidget(_home(ads, Future.value(_ad()), brokenImage: true));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(_bannerZoneHeight(tester), 0);
    expect(ads.events, isEmpty);
    // Content below moves up to where the banner would have been.
    expect(tester.getTopLeft(find.text(_contentBelow)).dy, 100);
  });

  testWidgets('the size changes are animated, not instantaneous', (tester) async {
    final ads = _FakeAds();
    final completer = Completer<AdPlacementConfig?>();
    await tester.pumpWidget(_home(ads, completer.future));
    await tester.pump();
    expect(_bannerZoneHeight(tester), 0);
    completer.complete(_ad());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = _bannerZoneHeight(tester);
    expect(midway, greaterThan(0));
    expect(midway, lessThan(130));
    await tester.pumpAndSettle();
    expect(_bannerZoneHeight(tester), _fullHeight(tester));
  });

  group('communication type label', () {
    for (final entry in const {
      'advertisement': 'Publicité',
      'discovery': 'À découvrir',
      'proxiplay_info': 'Info ProxiPlay',
      '': 'Publicité', // older campaign without the field
      'future_type': 'Publicité', // unknown value: historical behavior
    }.entries) {
      testWidgets('"${entry.key}" shows "${entry.value}" above the image, never over it',
          (tester) async {
        final ads = _FakeAds();
        await tester.pumpWidget(_home(ads, Future.value(_ad(type: entry.key))));
        await _settle(tester);
        await tester.pumpAndSettle();
        final label = find.byKey(_labelKey);
        expect(tester.widget<Text>(label).data, entry.value);
        final image = find.byType(Image);
        expect(tester.getSize(image).height, 90, reason: 'image size unchanged');
        expect(tester.getBottomLeft(label).dy, lessThanOrEqualTo(tester.getTopLeft(image).dy),
            reason: 'label sits above the image');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('a free label set in the Admin replaces the type label', (tester) async {
      final ads = _FakeAds();
      await tester.pumpWidget(_home(ads, Future.value(_ad(type: 'discovery', label: 'Partenaire local'))));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(_labelKey)).data, 'Partenaire local');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the longest label stays on one line on a 320 px screen, no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ads = _FakeAds();
      await tester.pumpWidget(_home(ads, Future.value(_ad(label: 'W' * 30))));
      await _settle(tester);
      await tester.pumpAndSettle();
      final label = tester.widget<Text>(find.byKey(_labelKey));
      expect(label.data, 'W' * 24, reason: 'cut to the Admin limit');
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the banner stays clickable whatever its type', (tester) async {
      final ads = _FakeAds();
      await tester.pumpWidget(_home(ads,
          Future.value(_ad(type: 'discovery', destination: 'https://example.org/evenement'))));
      await _settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image));
      await tester.pump();
      expect(ads.events, contains('click:home_banner:c1'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

}

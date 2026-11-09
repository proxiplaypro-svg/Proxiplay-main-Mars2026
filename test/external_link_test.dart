import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/external_link.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('openMerchantExternalLink', () {
    late List<(Uri, LaunchMode)> calls;

    ExternalLinkOpener opener(Map<LaunchMode, Object> results) =>
        (uri, mode) async {
          calls.add((uri, mode));
          final result = results[mode];
          if (result is Exception) throw result;
          return result as bool? ?? false;
        };

    setUp(() => calls = []);

    test('ouvre d’abord hors de l’application', () async {
      final ok = await openMerchantExternalLink('https://www.instagram.com/x',
          opener: opener({LaunchMode.externalApplication: true}));
      expect(ok, isTrue);
      expect(calls.map((c) => c.$2), [LaunchMode.externalApplication]);
      expect(calls.single.$1.toString(), 'https://www.instagram.com/x');
    });

    test('repli sur le mode par défaut si aucune application externe',
        () async {
      final ok = await openMerchantExternalLink('https://example.com',
          opener: opener({
            LaunchMode.externalApplication: false,
            LaunchMode.platformDefault: true,
          }));
      expect(ok, isTrue);
      expect(calls.map((c) => c.$2),
          [LaunchMode.externalApplication, LaunchMode.platformDefault]);
    });

    test('repli aussi après une exception, sans jamais lever', () async {
      final ok = await openMerchantExternalLink('https://example.com',
          opener: opener({
            LaunchMode.externalApplication: Exception('no handler'),
            LaunchMode.platformDefault: Exception('still no handler'),
          }));
      expect(ok, isFalse);
      expect(calls, hasLength(2));
    });

    test('refuse tout ce qui n’est pas un lien web', () async {
      for (final url in ['tel:0102030405', 'javascript:alert(1)', '', 'x y']) {
        expect(
            await openMerchantExternalLink(url, opener: opener(const {})),
            isFalse,
            reason: url);
      }
      expect(calls, isEmpty);
    });
  });

  test('liens commerciaux externes ; téléphone et pages légales inchangés',
      () {
    final detail = File(
            'lib/pages/joueur/enseigne_detail_joueur_page/enseigne_detail_joueur_page_widget.dart')
        .readAsStringSync();
    final pickup =
        File('lib/components/merchant_pickup_point.dart').readAsStringSync();
    final legal =
        File('lib/legal_page/legal_page_widget.dart').readAsStringSync();
    final util =
        File('lib/flutter_flow/flutter_flow_util.dart').readAsStringSync();

    // Site, Instagram, Facebook, X (one button builder) and directions.
    expect(detail.contains('onPressed: () => openMerchantExternalLink(url)'),
        isTrue);
    for (final src in [detail, pickup]) {
      expect(
          src.contains('openMerchantExternalLink(\n') ||
              src.contains('openMerchantExternalLink(\r\n'),
          isTrue,
          reason: 'itinéraire');
      expect(src.contains("launchURL(\n                      'https://www.google.com/maps"),
          isFalse);
      expect(src.contains("launchURL('tel:"), isTrue, reason: 'appel inchangé');
    }
    expect(RegExp(r'launchURL\(\s*.https://www\.google\.com/maps')
            .hasMatch(detail + pickup),
        isFalse);
    // ProxiPlay legal pages keep the in-app browser view; launchURL untouched.
    expect(legal.contains('LaunchMode.inAppBrowserView'), isTrue);
    expect(util.contains('await launchUrl(uri);'), isTrue);
  });
}

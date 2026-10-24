import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/share_links.dart';

/// Regression guard for the AndroidManifest.xml intent-filter removed by
/// mistake in 664a8de (09/05/2026): the OneLink "app installed" redirect
/// target (proxiplay://proxiplay.com?ref=...) stopped reaching the app,
/// silently breaking the referral-code prefill on Android while
/// createReferral/registerReferralAcceptance kept working normally.
void main() {
  // extractReferralCodeFromUri only ever inspects uri.queryParameters (see
  // lib/utils/share_links.dart) — it is deliberately generic and ignores
  // scheme/host/path entirely. A `ref` param is therefore extracted the
  // same way whether it sits on the restored OneLink target, on the game
  // deep link, or on a /j/* universal link: these cases are asserted
  // explicitly below instead of being assumed, precisely because that
  // genericity is easy to mis-describe as "host X never carries a code".
  group('extractReferralCodeFromUri real behavior per link family', () {
    test('1. proxiplay://proxiplay.com?ref=TESTCODE -> TESTCODE '
        '(restored OneLink target)', () {
      final uri = Uri.parse('proxiplay://proxiplay.com?ref=TESTCODE');
      expect(extractReferralCodeFromUri(uri), 'TESTCODE');
    });

    test('lowercase codes are normalized to uppercase, matching '
        'generateUniqueInviteCode() output', () {
      final uri = Uri.parse('proxiplay://proxiplay.com?ref=testcode');
      expect(extractReferralCodeFromUri(uri), 'TESTCODE');
    });

    test('2. proxiplay://game/123 -> null (no ref param)', () {
      final uri = Uri.parse('proxiplay://game/123');
      expect(extractReferralCodeFromUri(uri), isNull);
    });

    test('3. proxiplay://game/123?ref=TESTCODE -> TESTCODE '
        '(the function is host-agnostic: it would extract a ref param '
        'here too, same as on any other link)', () {
      final uri = Uri.parse('proxiplay://game/123?ref=TESTCODE');
      expect(extractReferralCodeFromUri(uri), 'TESTCODE');
    });

    test('4. https://play.proxiplay.fr/j/123 -> null (no ref param)', () {
      final uri = Uri.parse('https://play.proxiplay.fr/j/123');
      expect(extractReferralCodeFromUri(uri), isNull);
    });

    test('5. https://play.proxiplay.fr/j/123?ref=TESTCODE -> TESTCODE '
        '(same host-agnostic extraction as case 3)', () {
      final uri = Uri.parse('https://play.proxiplay.fr/j/123?ref=TESTCODE');
      expect(extractReferralCodeFromUri(uri), 'TESTCODE');
    });
  });

  group('AndroidManifest.xml declares all four required intent-filters', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('proxiplay://game (game QR / deep links) is present', () {
      expect(manifest, contains('android:scheme="proxiplay" android:host="game"'));
    });

    test('proxiplay://proxiplay.com (historical OneLink redirect target) '
        'is present', () {
      expect(
        manifest,
        contains('android:scheme="proxiplay" android:host="proxiplay.com"'),
      );
    });

    test('https://proxiplay.fr/j/* is present', () {
      expect(manifest, contains('android:host="proxiplay.fr"'));
      expect(manifest, contains('android:pathPrefix="/j/"'));
    });

    test('https://play.proxiplay.fr/j/* is present', () {
      expect(manifest, contains('android:host="play.proxiplay.fr"'));
    });
  });

  // 1.1.2: onelink.to redirects Android straight to the store and drops the
  // ref parameter, so invitations use a ProxiPlay address opened by the app.
  group('player referral link https://play.proxiplay.fr/i?ref=CODE', () {
    String source(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    final manifest = source('android/app/src/main/AndroidManifest.xml')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    final filters = RegExp(r'<intent-filter[\s\S]*?</intent-filter>')
        .allMatches(manifest)
        .map((m) => m.group(0)!)
        .toList();

    test('the shared link carries the normalized code on the ProxiPlay domain', () {
      expect(buildReferralShareLink(' ab12cd34 '),
          'https://play.proxiplay.fr/i?ref=AB12CD34');
      expect(extractReferralCodeFromUri(Uri.parse(buildReferralShareLink('AB12CD34'))),
          'AB12CD34');
      expect(buildAppShareText(referralCode: 'AB12CD34'),
          contains('https://play.proxiplay.fr/i?ref=AB12CD34'));
    });

    test('shares without a code (games, store) keep the store link', () {
      expect(buildReferralShareLink(), shareLinkBase);
      expect(buildReferralShareLink('  '), shareLinkBase);
      expect(buildAppShareText(title: 'Jeu'), endsWith(shareLinkBase));
    });

    test('Android opens exactly /i on play.proxiplay.fr, verified', () {
      final referral = filters.where((f) => f.contains('android:path="/i"')).toList();
      expect(referral, hasLength(1));
      expect(referral.single, contains('android:autoVerify="true"'));
      expect(referral.single, contains('android:scheme="https"'));
      expect(referral.single, contains('android:host="play.proxiplay.fr"'));
      // Never a prefix: /index.html or any other page stays in the browser.
      expect(manifest, isNot(contains('android:pathPrefix="/i')));
    });

    test('game links are unchanged and merchant referral links are never intercepted', () {
      for (final host in ['proxiplay.fr', 'play.proxiplay.fr', 'www.proxiplay.fr']) {
        expect(
            filters.where((f) =>
                f.contains('android:host="$host"') && f.contains('android:pathPrefix="/j/"')),
            hasLength(1),
            reason: host);
      }
      final https = filters.where((f) => f.contains('android:scheme="https"'));
      for (final f in https) {
        expect(f, anyOf(contains('android:pathPrefix="/j/"'), contains('android:path="/i"')));
      }
      expect(manifest, isNot(contains('commercant')));
    });

    test('iOS Universal Links: same exact path, game links kept', () {
      final aasa = source('hosting/.well-known/apple-app-site-association');
      expect(aasa, contains('"9FBNDYD396.com.proxiplay.proxiplay"'));
      expect(aasa, contains('"/j/*"'));
      expect(aasa, contains('"/i"'));
      expect(aasa, isNot(contains('"/i*"')));
      expect(aasa, isNot(contains('"*"')));
      final entitlements = source('ios/Runner/Runner.entitlements');
      expect(entitlements, contains('applinks:play.proxiplay.fr'));
    });

    test('the /i route opens the signup flow with the code of the link', () {
      final nav = source('lib/flutter_flow/nav/nav.dart');
      final route = nav.substring(nav.indexOf('name: ReferralLinkPageWidget.routeName'));
      expect(route.substring(0, 300), contains("params.getParam('ref', ParamType.String)"));
      expect(nav, contains('GameLaunchPageWidget.routePath'));
      final page = source('lib/pages/public/referral_link_page/referral_link_page_widget.dart');
      expect(page, contains('pendingReferralCode = code'));
      expect(page, contains('context.goNamed(InscriptionPageWidget.routeName)'));
      expect(page, contains("resolveAuthenticatedHome(source: 'referral_link')"));
    });

    test('a link received with the signup page open fills the field', () {
      final page = source('lib/pages/auth/inscription_page/inscription_page_widget.dart');
      expect(page, contains('FFAppState().addListener(_syncReferralCodeField)'));
      expect(page, contains('FFAppState().removeListener(_syncReferralCodeField)'));
    });

    test('the web page for visitors without the app shows the code safely', () {
      final html = source('hosting/i/index.html');
      expect(html, contains("textContent = code"));
      expect(html, isNot(contains('innerHTML')));
      expect(html, contains('/^[0-9A-F]{4,32}\$/'));
      expect(html, contains('https://play.google.com/store/apps/details?id=com.proxiplay.proxiplay'));
      expect(html, contains('https://apps.apple.com/app/id6753818573'));
      final hosting = source('firebase.json');
      expect(hosting, contains('"source": "/i",\n        "destination": "/i/index.html"'));
    });
  });
}

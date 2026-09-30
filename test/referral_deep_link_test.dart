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
}

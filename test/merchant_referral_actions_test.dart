import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/services/merchant_referral_actions.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class FakeShare extends SharePlatform {
  String? text;
  Rect? origin;
  @override
  Future<ShareResult> share(String text,
      {String? subject, Rect? sharePositionOrigin}) async {
    this.text = text;
    origin = sharePositionOrigin;
    return ShareResult.unavailable;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('copie le code exact et refuse un code invalide', () async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    expect(await copyMerchantReferralCode('AB3DE7G2'), isTrue);
    expect(copied, 'AB3DE7G2');
    copied = null;
    expect(await copyMerchantReferralCode('invalid'), isFalse);
    expect(copied, isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('partage natif $platform avec le code sans lien inventé', () async {
      final old = SharePlatform.instance;
      final fake = FakeShare();
      SharePlatform.instance = fake;
      debugDefaultTargetPlatformOverride = platform;
      try {
        expect(
            await shareMerchantReferralCode('AB3DE7G2',
                origin: const Rect.fromLTWH(1, 2, 3, 4)),
            isTrue);
        expect(fake.text, contains('AB3DE7G2'));
        expect(fake.text, isNot(contains('https://')));
        expect(fake.origin, const Rect.fromLTWH(1, 2, 3, 4));
        fake.text = null;
        expect(await shareMerchantReferralCode(null), isFalse);
        expect(fake.text, isNull);
      } finally {
        SharePlatform.instance = old;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The merchant signup form no longer carries a referral code: the player
// referral program (share_promo) is for new players only, and the merchant
// referral program (50 EUR in gift cards for the referring player) has its own
// code entry. The player signup flows are unchanged.
void main() {
  final page = File('lib/pages/auth/inscription_page/inscription_page_widget.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final model = File('lib/pages/auth/inscription_page/inscription_page_model.dart')
      .readAsStringSync();

  test('no referral code field in the merchant form', () {
    expect(page, isNot(contains('referralCodeCommercant')));
    expect(model, isNot(contains('referralCodeCommercant')));
  });

  test('the merchant signup never calls the player referral program', () {
    final start = page.indexOf("source:\n                                                                      'email_signup_merchant'");
    expect(start, greaterThan(0));
    final merchantFlow = page.substring(start, page.indexOf('goNamedAuth(', start));
    expect(merchantFlow, isNot(contains('_applyPendingReferralCodeIfNeeded')));
    expect(merchantFlow, isNot(contains('registerReferralAcceptance')));
  });

  test('the player signups still apply the player referral code', () {
    expect(page, contains('createReferralEmailAccount('));
    expect(page, contains('createReferralGoogleAccount('));
    expect(page, contains("labelText: 'Code de parrainage (facultatif)'"));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The merchant signup form carries one optional code for the MERCHANT
// referral program only (ambassador code, later partner codes), checked by the
// server (createMerchantAccountWithReferral). It never feeds the player
// referral program (share_promo). The player signup flows are unchanged.
void main() {
  final page = File('lib/pages/auth/inscription_page/inscription_page_widget.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final model = File('lib/pages/auth/inscription_page/inscription_page_model.dart')
      .readAsStringSync();
  final merchantStart = page.indexOf('final merchantEmail = _model');
  final merchantFlow = page.substring(merchantStart, page.indexOf('goNamedAuth(', merchantStart));

  test('the old ambiguous field is gone, the merchant field is its own', () {
    expect(page, isNot(contains('referralCodeCommercant')));
    expect(model, isNot(contains('referralCodeCommercant')));
    expect(page, contains("'Code de parrainage ou partenaire (facultatif)'"));
    // Never prefilled with a player referral code from a deep link.
    expect(page, contains('_model.merchantSignupCodeTextController ??= TextEditingController();'));
  });

  test('with a code the merchant signup goes to the merchant program, never the player one', () {
    expect(merchantStart, greaterThan(0));
    expect(merchantFlow, contains('createMerchantAccountWithReferral('));
    expect(merchantFlow, contains('merchantSignupCodeToSubmit('));
    expect(merchantFlow, isNot(contains('_applyPendingReferralCodeIfNeeded')));
    expect(merchantFlow, isNot(contains('registerReferralAcceptance')));
    expect(merchantFlow, isNot(contains('pendingReferralCode')));
    expect(merchantFlow, isNot(contains('createReferralEmailAccount')));
  });

  test('a refused code stops before any account; the same request id is reused on retry', () {
    final refused = merchantFlow.indexOf('on FirebaseFunctionsException catch (error)');
    expect(refused, greaterThan(0));
    expect(merchantFlow.substring(refused, merchantFlow.indexOf('return;', refused)),
        contains('merchantSignupCodeErrorMessage('));
    expect(merchantFlow, contains('merchantPrefs.getString(merchantOpKey) ?? const Uuid().v4()'));
    // The stored request id is only cleared once signed in.
    expect(merchantFlow.indexOf('merchantPrefs!.remove(merchantOpKey!)'),
        greaterThan(merchantFlow.indexOf('signInWithEmail(')));
  });

  test('without a code the merchant signup is unchanged', () {
    expect(merchantFlow, contains('merchantCode.isEmpty\n                                                                  ? await authManager.createAccountWithEmail('));
  });

  test('the code field is hidden unless the merchant program is enabled', () {
    final compact = page.replaceAll(RegExp(r'\s+'), '');
    final field = compact.indexOf('.merchantSignupCodeTextController,');
    final guard = compact.lastIndexOf('if(shouldShowMerchantSignupCodeField(_merchantReferralEnabled))Padding(', field);
    expect(guard, greaterThan(0));
    expect(compact.substring(guard, field), isNot(contains('TextFormField(controller:_model.passwordConfirm')),
        reason: 'the guard wraps the code field itself');
    // Read once from app_config/merchant_referral, null on error (hidden).
    expect(compact, contains("bool?_merchantReferralEnabled;"));
    expect(compact, contains(".doc('app_config/merchant_referral')"));
    expect(compact, contains('}catch(_){enabled=null;}'));
    // A code typed before the field was hidden is never sent.
    expect(merchantFlow.replaceAll(RegExp(r'\s+'), ''),
        contains('merchantSignupCodeToSubmit(_model.merchantSignupCodeTextController?.text,'
            'fieldVisible:shouldShowMerchantSignupCodeField(_merchantReferralEnabled));'));
  });

  test('an unavailable referral service cannot block a signup without code', () {
    // The service is only called inside the "with a code" branch; without a
    // code the account is created by the app as before.
    final withCode = merchantFlow.indexOf('if (merchantCode.isNotEmpty) {');
    final call = merchantFlow.indexOf('createMerchantAccountWithReferral(');
    final branchEnd = merchantFlow.indexOf('if (!context.mounted) return;', call);
    expect(withCode, greaterThan(0));
    expect(call, greaterThan(withCode));
    expect(branchEnd, greaterThan(call));
    expect('createMerchantAccountWithReferral('.allMatches(merchantFlow).length, 1);
    expect(merchantFlow.indexOf('authManager.createAccountWithEmail('), greaterThan(branchEnd));
  });

  test('the player signups still apply the player referral code', () {
    expect(page, contains('createReferralEmailAccount('));
    expect(page, contains('createReferralGoogleAccount('));
    expect(page, contains("labelText: 'Code de parrainage (facultatif)'"));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/services/referral_signup_error.dart';

void main() {
  test('explains that a created account can be used without referral', () {
    final result = describeReferralSignupError('already-exists', {
      'reason': 'referral_unavailable', 'accountCreated': true,
    });
    expect(result.accountCreated, isTrue);
    expect(result.message, contains('compte'));
    expect(result.message, contains('connecter'));
    expect(result.message, contains('sans parrainage'));
  });
  test('invalid code, used code, existing email and network are distinct', () {
    expect(describeReferralSignupError('not-found', null).message, contains('invalide'));
    expect(describeReferralSignupError('failed-precondition', {'reason': 'referral_unavailable'}).message, contains('utilis\u00e9'));
    expect(describeReferralSignupError('already-exists', {'reason': 'email_exists'}).message, contains('e-mail'));
    expect(describeReferralSignupError('unavailable', null).message, contains('R\u00e9essayez'));
  });
  test('a deleted then recreated address is told it cannot be referred', () {
    expect(describeReferralSignupError('failed-precondition', {'reason': 'email_not_eligible'}).message,
        contains('ne peut plus'));
  });
  test('Google signup with a code: notice after sign-in, error before it', () {
    expect(googleReferralNotice('accepted'), isNull);
    expect(googleReferralNotice('existing_account'), contains('nouveaux comptes'));
    expect(googleReferralNotice('not_eligible'), contains('sans parrainage'));
    expect(googleReferralNotice('refused'), contains('compte est créé'));
    expect(googleReferralErrorMessage('not-found', null), contains('invalide'));
    expect(googleReferralErrorMessage('failed-precondition', {'reason': 'referral_unavailable'}), contains('utilisé'));
    expect(googleReferralErrorMessage('resource-exhausted', null), contains('Trop de tentatives'));
    expect(googleReferralErrorMessage('unavailable', null), contains('Réessayez'));
  });
}

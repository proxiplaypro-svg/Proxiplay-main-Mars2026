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
}

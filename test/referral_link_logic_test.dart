import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/referral_link_logic.dart';

void main() {
  group('resolveReferralLinkTarget (/i route)', () {
    test('waits until the auth state is known', () {
      expect(resolveReferralLinkTarget(authResolved: false, authenticated: false),
          ReferralLinkTarget.wait);
      expect(resolveReferralLinkTarget(authResolved: false, authenticated: true),
          ReferralLinkTarget.wait);
    });

    test('a visitor goes to the signup page, a signed-in account to its home', () {
      expect(resolveReferralLinkTarget(authResolved: true, authenticated: false),
          ReferralLinkTarget.signup);
      expect(resolveReferralLinkTarget(authResolved: true, authenticated: true),
          ReferralLinkTarget.home);
    });
  });

  group('referralFieldSyncText (link received with the signup page open)', () {
    test('an empty field receives the code of the link', () {
      expect(referralFieldSyncText(fieldText: '', pendingCode: 'AB12CD34'), 'AB12CD34');
    });

    test('a new link replaces the code of a previous link', () {
      expect(referralFieldSyncText(fieldText: 'AB12CD34', pendingCode: '99887766'), '99887766');
    });

    test('what the player is typing is never rewritten (stored as typed, upper case)', () {
      expect(referralFieldSyncText(fieldText: 'ab12', pendingCode: 'AB12'), isNull);
      expect(referralFieldSyncText(fieldText: ' AB12CD34 ', pendingCode: 'AB12CD34'), isNull);
      expect(referralFieldSyncText(fieldText: '', pendingCode: ''), isNull);
    });

    test('a cleared code (after signup) empties the field', () {
      expect(referralFieldSyncText(fieldText: 'AB12CD34', pendingCode: ''), '');
    });
  });
}

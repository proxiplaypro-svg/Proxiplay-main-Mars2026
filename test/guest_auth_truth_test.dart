import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/auth/firebase_auth/auth_util.dart';

void main() {
  test('Sylvie: real Firebase user overrides stale local guest preference', () {
    expect(
      isGuestOrAnonymousFromAuth(
        hasFirebaseUser: true,
        isAnonymous: false,
        localGuest: true,
      ),
      isFalse,
    );
  });

  test('public mode is retained only without a Firebase session', () {
    expect(
      isGuestOrAnonymousFromAuth(
        hasFirebaseUser: false,
        isAnonymous: false,
        localGuest: true,
      ),
      isTrue,
    );
  });

  test('anonymous Firebase users remain guests', () {
    expect(
      isGuestOrAnonymousFromAuth(
        hasFirebaseUser: true,
        isAnonymous: true,
        localGuest: false,
      ),
      isTrue,
    );
  });
}

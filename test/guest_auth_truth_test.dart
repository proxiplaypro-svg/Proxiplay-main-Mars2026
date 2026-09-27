import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/auth/firebase_auth/auth_util.dart';

void main() {
  test('Sylvie: real Firebase user overrides stale local guest preference', () {
    expect(
        isGuestOrAnonymousFromAuth(
            hasFirebaseUser: true, isAnonymous: false, localGuest: true),
        isFalse);
  });

  test('public mode is retained only without a Firebase session', () {
    expect(
        isGuestOrAnonymousFromAuth(
            hasFirebaseUser: false, isAnonymous: false, localGuest: true),
        isTrue);
  });

  test('anonymous Firebase users remain guests', () {
    expect(
        isGuestOrAnonymousFromAuth(
            hasFirebaseUser: true, isAnonymous: true, localGuest: false),
        isTrue);
  });

  test('real Firebase user keeps its reference before provider repair', () {
    const uid = 'TEST_UID';
    expect(
      currentUserReferenceUidFromAuth(
        firebaseUid: uid,
        isAnonymous: false,
        localGuest: true,
      ),
      uid,
    );
  });

  test('anonymous or absent Firebase users never get a user reference', () {
    expect(
      currentUserReferenceUidFromAuth(
        firebaseUid: 'ANONYMOUS_UID',
        isAnonymous: true,
        localGuest: false,
      ),
      isNull,
    );
    expect(
      currentUserReferenceUidFromAuth(
        firebaseUid: null,
        isAnonymous: false,
        localGuest: true,
      ),
      isNull,
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for finding #1 (mini-audit): an unauthenticated guest
/// (FFAppState().isGuest, no Firebase session at all) could reach
/// HomeJoueurPageWidget - requireAuth only checks appStateNotifier.loggedIn,
/// which is also true for a local guest flag - and the referral_games
/// StreamBuilder ran its query unconditionally, hitting Firestore with
/// request.auth == null (referral_games requires request.auth != null).
/// Reproduced with a rules-emulator test during the mini-audit: the read was
/// denied (no data leak), but it fired a permission-denied error on a live
/// listener for nothing.
///
/// Same convention as test/play_joueur_ticket_gate_source_test.dart: this
/// FlutterFlow widget depends on Firebase/GamesRecord/FirebaseAuth not
/// available in this environment, so the call-site wiring is guarded
/// directly from the source text instead of a full widget test.
void main() {
  final source = File(
    'lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart',
  ).readAsStringSync();

  final guardStart = source.indexOf('if (!showReferralGameCard ||');
  const queryCall = "collection('referral_games')";
  final guardEnd = guardStart >= 0 ? source.indexOf(queryCall, guardStart) : -1;

  setUpAll(() {
    expect(guardStart, greaterThan(-1),
        reason: 'the referral_games guard clause was not found - has this '
            'call site moved or been rewritten?');
    expect(guardEnd, greaterThan(guardStart));
  });

  group('home_joueur_page referral_games guest gate (regression)', () {
    test('the guard ahead of the referral_games query rejects a guest '
        'before it fires', () {
      final block = source.substring(guardStart, guardEnd);
      expect(block, contains('isGuestOrAnonymous'));
      expect(block, contains('currentUserUid.isEmpty'));
    });

    test('the guard short-circuits to a referral-less carousel instead of '
        'building the StreamBuilder', () {
      final block = source.substring(guardStart, guardEnd);
      expect(block, contains('buildCarousel(hasActiveReferralGame: false)'));
    });
  });
}

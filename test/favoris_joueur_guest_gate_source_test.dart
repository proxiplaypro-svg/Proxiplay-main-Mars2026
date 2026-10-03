import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for finding #2 (mini-audit): FavorisJoueurPageWidget is
/// reachable by a guest the same way HomeJoueurPageWidget is (requireAuth
/// only checks appStateNotifier.loggedIn, also true for FFAppState().isGuest
/// with no Firebase session at all). _loadSortedFavoriteGames() called
/// queryFavoriteGamesRecordOnce(parent: currentUserReference) unconditionally;
/// for a guest currentUserReference is null, and
/// FavoriteGamesRecord.collection(null) falls back to a GLOBAL
/// collectionGroup('favorite_games') query across every user. Firestore
/// rules (`allow read: if request.auth.uid == parent`) deny every document
/// to an unauthenticated reader, so there is no data leak, but the call
/// should never be attempted in the first place.
///
/// Same convention as test/play_joueur_ticket_gate_source_test.dart: this
/// FlutterFlow widget depends on Firebase/GamesRecord not available in this
/// environment, so the call-site wiring is guarded directly from the source
/// text instead of a full widget test.
void main() {
  final source = File(
    'lib/pages/joueur/favoris_joueur_page/favoris_joueur_page_widget.dart',
  ).readAsStringSync();

  final methodStart = source.indexOf(
    'Future<List<_FavoriteGameListItem>> _loadSortedFavoriteGames()',
  );
  const queryCall = 'queryFavoriteGamesRecordOnce(';
  final queryIndex =
      methodStart >= 0 ? source.indexOf(queryCall, methodStart) : -1;
  const callArgsEndMarker = ');';
  final callArgsEnd = queryIndex >= 0
      ? source.indexOf(callArgsEndMarker, queryIndex)
      : -1;

  setUpAll(() {
    expect(methodStart, greaterThan(-1),
        reason: '_loadSortedFavoriteGames not found - has this call site '
            'moved or been rewritten?');
    expect(queryIndex, greaterThan(methodStart));
    expect(callArgsEnd, greaterThan(queryIndex));
  });

  group('favoris_joueur_page guest gate (regression)', () {
    test('a null currentUserReference is checked before '
        'queryFavoriteGamesRecordOnce can run', () {
      final block = source.substring(methodStart, queryIndex);
      expect(block, contains('== null'));
      expect(block, contains('return const []'));
    });

    test('queryFavoriteGamesRecordOnce is never called with a possibly-null '
        'parent (the guarded local variable is passed, not '
        'currentUserReference directly)', () {
      final callSite = source.substring(
        queryIndex,
        callArgsEnd + callArgsEndMarker.length,
      );
      expect(callSite, isNot(contains('parent: currentUserReference')));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard (Samsung, 27/10/2026): "Jeux terminés" stayed on
/// "Chargement..." because the Home's stored _activeAnimationsStream fed two
/// StreamBuilders. A Firestore snapshots() stream is a broadcast stream that
/// does not replay its last snapshot, so the StreamBuilder subscribing second
/// never received data while no animation changed.
///
/// Same convention as test/home_joueur_referral_guest_gate_source_test.dart:
/// the widget depends on Firebase, so the wiring is checked from the source.
void main() {
  final source = File(
    'lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart',
  ).readAsStringSync();
  // Whitespace-insensitive: the file is formatted with deep indentation.
  final compact = source.replaceAll(RegExp(r'\s+'), '');

  final storedStreams = RegExp(r'late(?:final)?Stream<[^;]*?>(_\w+Stream);')
      .allMatches(compact)
      .map((match) => match.group(1)!)
      .toSet();

  test('the Home stores its Firestore streams in fields', () {
    expect(
      storedStreams,
      containsAll(<String>[
        '_recentlyEndedGamesStream',
        '_activeAnimationsStream',
        '_finishedAnimationsStream',
        '_qrOnlyGamesStream',
        '_activeReferralGamesStream',
      ]),
    );
  });

  test('each stored stream feeds exactly one StreamBuilder', () {
    for (final name in storedStreams) {
      final uses = RegExp('stream:${RegExp.escape(name)}[,)]')
          .allMatches(compact)
          .length;
      expect(uses, 1, reason: '$name is passed to $uses StreamBuilders');
    }
  });

  test('"Jeux terminés" listens to its own animations stream', () {
    final section = compact.indexOf("'JEUXTERMIN\\u00C9S'");
    expect(section, greaterThan(0));
    final next = compact.indexOf('stream:', compact.indexOf('stream:', section) + 1);
    expect(compact.substring(next, next + 'stream:_finishedAnimationsStream'.length),
        'stream:_finishedAnimationsStream');
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "LE JEU DU PARRAINAGE" (27/10/2026): the referral game left "Jeux à la une"
/// for its own section, in this strict order on the displayed Home:
/// À la une, ad, Le jeu du parrainage, Nouveautés, Bientôt finis, Jeux terminés,
/// ad. Same convention as home_joueur_referral_guest_gate_source_test.dart:
/// the page depends on Firebase, so its wiring is checked from the source.
void main() {
  final source = File(
    'lib/pages/joueur/home_joueur_page/home_joueur_page_widget.dart',
  ).readAsStringSync();
  final compact = source.replaceAll(RegExp(r'\s+'), '');

  String methodBody(String signature) {
    final start = compact.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature not found');
    // Ends at the next method or at the doc comment that precedes it.
    final ends = [
      compact.indexOf('Widget_build', start + signature.length),
      compact.indexOf('///', start + signature.length),
    ].where((index) => index > start);
    return compact.substring(
        start, ends.isEmpty ? compact.length : ends.reduce((a, b) => a < b ? a : b));
  }

  test('"Jeux à la une" no longer shows the referral game', () {
    final carousel = methodBody('Widget_buildFeaturedGamesCarousel(');
    expect(carousel, isNot(contains('ReferralGameCard')));
    expect(carousel, isNot(contains('_activeReferralGamesStream')));
    expect(compact, isNot(contains('showReferralGameCard')));
  });

  test('the referral card is built in one place only: its section', () {
    expect('ReferralGameCard('.allMatches(compact).length, 1);
    final zone = methodBody('Widget_buildReferralGamesZone(BuildContextcontext)');
    expect(zone, contains('ReferralGameCard('));
    expect(zone, contains("'LEJEUDUPARRAINAGE'"));
    expect(zone, contains('ReferralGameCard(gameSnapshot:docs.first,wide:true,)'));
  });

  test('the explanation promises a chance, never a win', () {
    final zone = methodBody('Widget_buildReferralGamesZone(BuildContextcontext)');
    expect(source, contains(
        "'Parrainez vos amis, obtenez des tickets et tentez votre chance\\u00A0!'"));
    expect(zone.toLowerCase(), isNot(contains('gagnez')));
  });

  test('the section is hidden without an active game and for a guest', () {
    final zone = methodBody('Widget_buildReferralGamesZone(BuildContextcontext)');
    final guard = zone.indexOf('if(isGuestOrAnonymous||currentUserUid.isEmpty){returnconstSizedBox.shrink();}');
    final stream = zone.indexOf('stream:_activeReferralGamesStream');
    expect(guard, greaterThan(-1));
    expect(stream, greaterThan(guard), reason: 'no query before the guest guard');
    expect(zone, contains('if(docs.isEmpty){returnconstSizedBox.shrink();}'));
  });

  test('displayed Home order: une, ad, parrainage, nouveautés, bientôt finis, terminés, ad', () {
    final start = compact.indexOf('if(_showsFullGameCatalog){');
    final end = compact.indexOf("branchName:'minor_filtered'", start);
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    final branch = compact.substring(start, end);
    final markers = <String>[
      "'JEUX\\u00C0LAUNE'",
      '_buildAdHomeBannerZone(context)',
      '_buildReferralGamesZone(context)',
      "'NOUVEAUT\\u00C9S'",
      "'BIENT\\u00D4TFINIS'",
      "'JEUXTERMIN\\u00C9S'",
      '_buildAdHomeReferralBannerZone(context)',
    ];
    var previous = -1;
    for (final marker in markers) {
      expect(marker.allMatches(branch).length, 1, reason: '$marker once');
      final position = branch.indexOf(marker);
      expect(position, greaterThan(previous), reason: '$marker out of order');
      previous = position;
    }
  });
}

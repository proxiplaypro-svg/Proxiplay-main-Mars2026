import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A game opened from its shop QR must stay playable at zero chances: the
// "no remaining parts" gate is lifted as soon as the scan token is known,
// for public and QR-only games alike. The server stays the authority.
void main() {
  final source = File(
          'lib/pages/joueur/jeu_detail_joueur_page/jeu_detail_joueur_page_widget.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  String gateBody() {
    final start = source.indexOf('bool _hasNoRemainingParts(');
    expect(start, isNot(-1), reason: 'gate not found');
    final end = source.indexOf('\n  }\n', start);
    return source.substring(start, end);
  }

  test('the free shop play lifts the balance and "already played" gates', () {
    // The balance gate is the balance only; both public buttons lift it, and
    // the "already played" gate, while the shop play is offered.
    expect(gateBody().contains('gameQrToken('), isFalse);
    final compact = source.replaceAll(RegExp(r'\s+'), '');
    expect(RegExp(r'noRemainingParts:noRemainingParts(Live)?&&!daily\.shopPlay').allMatches(compact).length, 2);
    expect(RegExp(r'hasPlayedToday:daily\.classicPlayedToday&&!daily\.shopPlay').allMatches(compact).length, 2);
  });

  test('every participation call forwards the scan token to the server', () {
    final compact = source.replaceAll(RegExp(r'\s+'), '');
    final calls = RegExp(r'"from_qr":').allMatches(compact).length;
    // QR-only buttons always send the token; public buttons send it with the
    // shop play only (dailyPlayPayloadFields).
    final tokens = RegExp(r'"qr_token":gameQrToken\(').allMatches(compact).length +
        RegExp(r'\.\.\.dailyPlayPayloadFields\(').allMatches(compact).length;
    expect(calls, greaterThan(0));
    expect(tokens, calls);
  });

  test('the share page forwards the scan token to the server too', () {
    final share = File(
            'lib/pages/joueur/share_jeu_page/share_jeu_page_widget.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), '');
    final calls = RegExp(r'"gameRef":').allMatches(share).length;
    final tokens = RegExp(r'\.\.\.dailyPlayPayloadFields\(').allMatches(share).length;
    expect(calls, greaterThan(0));
    expect(tokens, calls);
  });
}

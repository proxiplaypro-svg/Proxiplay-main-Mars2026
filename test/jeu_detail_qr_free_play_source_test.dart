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

  test('a scanned game (token kept) is never blocked for lack of chances', () {
    final body = gateBody();
    final tokenCheck = body.indexOf('gameQrToken(');
    final balanceCheck = body.indexOf('getSafeRemainingPart(');
    expect(tokenCheck, isNot(-1));
    expect(tokenCheck < balanceCheck, isTrue,
        reason: 'the token check must run before the balance check');
    expect(body.contains('accessMode'), isFalse,
        reason: 'the rule applies to public and QR-only games alike');
  });

  test('every participation call forwards the scan token to the server', () {
    final calls = RegExp(r'"from_qr":').allMatches(source).length;
    final tokens = RegExp(r'"qr_token": gameQrToken\(').allMatches(source).length;
    expect(calls, greaterThan(0));
    expect(tokens, calls);
  });

  test('the share page forwards the scan token to the server too', () {
    final share = File(
            'lib/pages/joueur/share_jeu_page/share_jeu_page_widget.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), '');
    final calls = RegExp(r'"gameRef":').allMatches(share).length;
    final tokens = RegExp(r'"qr_token":gameQrToken\(').allMatches(share).length;
    expect(calls, greaterThan(0));
    expect(tokens, calls);
  });
}

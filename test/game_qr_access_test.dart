import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/share_links.dart';

void main() {
  test('QR capability survives web, custom scheme and Android intent links',
      () {
    final token = List.filled(64, 'a').join();
    final qr = Uri.parse(buildGameQrLink('secure-game', token: token));
    expect(qr.path, '/j/secure-game');
    rememberGameQrToken('secure-game', qr);
    expect(gameQrToken('secure-game'), token);
    expect(
        Uri.parse(buildGameDeepLink('secure-game')).queryParameters['qr_token'],
        token);
    expect(buildGameAndroidIntentUrl('secure-game'),
        contains('?qr_token=$token#Intent;'));
    expect(gameQrToken('other-game'), isNull);
  });
  test('boolean, malformed tokens and plain old links confer no capability',
      () {
    for (final value in ['true', 'forged', '']) {
      rememberGameQrToken(
          'invalid-game',
          Uri.parse(
              'https://play.proxiplay.fr/j/invalid-game?from_qr=true&qr_token=$value'));
      expect(gameQrToken('invalid-game'), isNull);
    }
    expect(buildGameQrLink('public-game'),
        'https://play.proxiplay.fr/j/public-game');
    expect(buildGameDeepLink('public-game'), 'proxiplay://game/public-game');
  });
  test('historic game domains become canonical without losing parameters', () {
    final token = List.filled(64, 'b').join();
    for (final host in [
      'proxiplay.fr',
      'www.proxiplay.fr',
      'play.proxiplay.fr'
    ]) {
      final link = canonicalizeGameLink(
          'https://$host/j/game?qr_token=$token&merchant_id=m&x=1&x=2');
      final uri = Uri.parse(link);
      expect(uri.host, 'play.proxiplay.fr');
      expect(uri.queryParameters['qr_token'], token);
      expect(uri.queryParameters['merchant_id'], 'm');
      expect(uri.queryParametersAll['x'], ['1', '2']);
    }
    expect(canonicalizeGameLink('https://other.example/j/game'),
        'https://other.example/j/game');
  });
  test('login keeps QR proof in memory but a new process requires a scan',
      () async {
    final token = List.filled(64, 'c').join();
    rememberGameQrToken('login-game',
        Uri.parse('https://play.proxiplay.fr/j/login-game?qr_token=$token'));
    // Login resumes the same game in the same process.
    expect(gameQrToken('login-game'), token);
    // An isolate has a fresh memory store, like a restarted process.
    expect(await Isolate.run(() => gameQrToken('login-game')), isNull);
  });
}

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
}

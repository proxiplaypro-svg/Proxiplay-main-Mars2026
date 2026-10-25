import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/game_daily_play.dart';
import 'package:proxi_play/utils/share_links.dart';

// Shop QR rule (1.1.2): one classic play plus one free shop play per game
// and day, in either order. These helpers decide what the buttons offer
// and send; the server stays the authority.
void main() {
  const token =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
  final now = DateTime(2026, 10, 26, 15);
  const none = DailyPlayState(classicPlayedToday: false, shopPlayedToday: false);
  var gameSeq = 0;
  String scannedGame() {
    final id = 'G${++gameSeq}';
    rememberGameQrToken(id, Uri.parse('https://play.proxiplay.fr/j/$id?qr_token=$token'));
    return id;
  }

  group('dailyPlayState', () {
    test('reads today\'s classic and shop tickets apart', () {
      final state = dailyPlayState(
        ticketIds: ['2026-10-26_uid_qr', '2026-10-25_uid'],
        lastPlay: now,
        now: now,
      );
      expect(state.shopPlayedToday, isTrue);
      expect(state.classicPlayedToday, isFalse);
      final both = dailyPlayState(
          ticketIds: ['2026-10-26_uid', '2026-10-26_uid_qr'], lastPlay: now, now: now);
      expect(both.classicPlayedToday && both.shopPlayedToday, isTrue);
    });

    test('a play today without any ticket yet counts as the classic one', () {
      final state = dailyPlayState(ticketIds: const [], lastPlay: now, now: now);
      expect(state.classicPlayedToday, isTrue);
      expect(state.shopPlayedToday, isFalse);
    });

    test('yesterday\'s plays leave both available', () {
      final state = dailyPlayState(
        ticketIds: ['2026-10-25_uid', '2026-10-25_uid_qr'],
        lastPlay: DateTime(2026, 10, 25, 20),
        now: now,
      );
      expect(state.classicPlayedToday || state.shopPlayedToday, isFalse);
    });
  });

  group('offersShopPlay', () {
    test('only with a scan token, and only until the shop play is used', () {
      expect(offersShopPlay(gameId: 'never_scanned', state: none, now: now), isFalse);
      final id = scannedGame();
      expect(offersShopPlay(gameId: id, state: none, now: now), isTrue);
      const classicDone = DailyPlayState(classicPlayedToday: true, shopPlayedToday: false);
      expect(offersShopPlay(gameId: id, state: classicDone, now: now), isTrue,
          reason: 'also after the classic play');
      const shopDone = DailyPlayState(classicPlayedToday: false, shopPlayedToday: true);
      expect(offersShopPlay(gameId: id, state: shopDone, now: now), isFalse);
    });

    test('a shop play accepted by the server is not offered again today', () {
      final id = scannedGame();
      shopPlayAttemptId(id, () => 'a1');
      settleShopPlayAttempt(id, succeeded: true, now: now, shopPlayDone: true);
      expect(offersShopPlay(gameId: id, state: none, now: now), isFalse);
      expect(offersShopPlay(gameId: id, state: none, now: now.add(const Duration(days: 1))), isTrue);
    });
  });

  group('lost answers', () {
    test('a shop play without answer keeps its attempt for the next tap', () {
      final id = scannedGame();
      expect(shopPlayAttemptId(id, () => 'first'), 'first');
      for (final code in ['unavailable', 'deadline-exceeded', 'internal', 'timeout-client', null]) {
        settleShopPlayAttempt(id, succeeded: false, errorCode: code, now: now);
        expect(shopPlayAttemptId(id, () => 'second'), 'first', reason: '$code');
      }
      // Still offered as the shop play even if the tickets already show it,
      // so the retry replays it instead of starting a paid play.
      const shopDone = DailyPlayState(classicPlayedToday: false, shopPlayedToday: true);
      expect(offersShopPlay(gameId: id, state: shopDone, now: now), isTrue);
    });

    test('a server answer closes the attempt', () {
      final id = scannedGame();
      shopPlayAttemptId(id, () => 'first');
      settleShopPlayAttempt(id, succeeded: false, errorCode: 'failed-precondition', now: now);
      expect(pendingShopPlayAttempt(id), isNull);
      expect(shopPlayAttemptId(id, () => 'second'), 'second');
    });
  });

  test('a token refused by the server is dropped', () {
    final id = scannedGame();
    forgetRefusedShopQr(id, {'reason': 'other'});
    expect(gameQrToken(id), token);
    forgetRefusedShopQr(id, {'reason': 'invalid_shop_qr'});
    expect(gameQrToken(id), isNull);
    expect(offersShopPlay(gameId: id, state: none, now: now), isFalse);
  });

  test('the token goes only with the shop play', () {
    final id = scannedGame();
    expect(dailyPlayPayloadFields(id, shopPlay: true),
        {'participation_mode': 'qr', 'qr_token': token});
    expect(dailyPlayPayloadFields(id, shopPlay: false),
        {'participation_mode': 'classic', 'qr_token': null});
  });
}

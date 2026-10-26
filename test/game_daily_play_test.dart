import 'dart:io';

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

  // Real Firestore ticket ids (participate_in_game_transaction.js):
  // `yyyyMMdd_<uid>` (classic) and `yyyyMMdd_<uid>_qr` (shop QR).
  group('dailyPlayState', () {
    test('the day key is the server one (yyyyMMdd)', () {
      expect(localDayKey(DateTime(2026, 10, 26, 23, 59)), '20261026');
      expect(localDayKey(DateTime(2026, 1, 5)), '20260105');
    });

    test('reads today\'s classic and shop tickets apart', () {
      final state = dailyPlayState(
        ticketIds: ['20261026_uid_qr', '20261025_uid'],
        lastPlay: now,
        now: now,
      );
      expect(state.shopPlayedToday, isTrue);
      expect(state.classicPlayedToday, isFalse);
      final both = dailyPlayState(
          ticketIds: ['20261026_uid', '20261026_uid_qr'], lastPlay: now, now: now);
      expect(both.classicPlayedToday && both.shopPlayedToday, isTrue);
    });

    test('bug 26/10: after the QR play only, the classic play stays available', () {
      // Firestore: only `20261026_uid_qr`; participants_details.last_play is
      // the QR play time, last_classic_play is empty.
      final state = dailyPlayState(
        ticketIds: ['20261026_uid_qr'],
        lastPlay: DateTime(2026, 10, 26, 12, 20),
        now: now,
      );
      expect(state.classicPlayedToday, isFalse);
      expect(state.shopPlayedToday, isTrue);
      final id = scannedGame();
      expect(offersShopPlay(gameId: id, state: state, now: now), isFalse,
          reason: 'the button offers the classic play, not a second free one');
    });

    test('both orders: classic then QR, QR then classic', () {
      final id = scannedGame();
      // Classic first: the free QR play is still offered.
      final afterClassic = dailyPlayState(ticketIds: ['20261026_uid'], lastPlay: now, now: now);
      expect(afterClassic.classicPlayedToday, isTrue);
      expect(offersShopPlay(gameId: id, state: afterClassic, now: now), isTrue);
      // QR first: the classic play is still available, no second free play.
      final afterShop = dailyPlayState(ticketIds: ['20261026_uid_qr'], lastPlay: now, now: now);
      expect(afterShop.classicPlayedToday, isFalse);
      expect(offersShopPlay(gameId: id, state: afterShop, now: now), isFalse);
      // Both done: nothing left today.
      final done = dailyPlayState(ticketIds: ['20261026_uid_qr', '20261026_uid'], lastPlay: now, now: now);
      expect(done.classicPlayedToday && done.shopPlayedToday, isTrue);
      expect(offersShopPlay(gameId: id, state: done, now: now), isFalse);
    });

    test('a second scan after an app restart does not offer a new free play', () {
      // The in-memory "used" mark is gone after a restart; the ticket list
      // alone must tell the QR play of the day is used.
      final id = scannedGame(); // scanned again, token kept
      final state = dailyPlayState(ticketIds: ['20261026_uid_qr'], lastPlay: now, now: now);
      expect(shopPlayUsedToday(id, now), isFalse);
      expect(offersShopPlay(gameId: id, state: state, now: now), isFalse);
    });

    test('a play today without any ticket yet counts as the classic one', () {
      final state = dailyPlayState(ticketIds: const [], lastPlay: now, now: now);
      expect(state.classicPlayedToday, isTrue);
      expect(state.shopPlayedToday, isFalse);
    });

    test('yesterday\'s plays leave both available', () {
      final state = dailyPlayState(
        ticketIds: ['20261025_uid', '20261025_uid_qr'],
        lastPlay: DateTime(2026, 10, 25, 20),
        now: now,
      );
      expect(state.classicPlayedToday || state.shopPlayedToday, isFalse);
    });
  });

  test('contract: Flutter reads the ticket ids the server writes', () {
    final server = File('firebase/functions/participate_in_game_transaction.js')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), '');
    // Day key yyyyMMdd, classic id `<day>_<uid>`, shop id `<classic id>_qr`.
    expect(server, contains(r'return`${year}${month}${day}`;'));
    expect(server, contains(r'constparticipantDocId=`${dayKey}_${uid}`;'));
    expect(server, contains(r'participantsRef.doc(`${participantDocId}_qr`)'));
    expect(server, contains('constdayKey=getParisDayKey('));
    // The app builds the same day key: year, 2-digit month and day, joined.
    final day = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    expect(localDayKey(now), day);
    // The same ids, built as the server does, are read correctly.
    final state = dailyPlayState(
        ticketIds: ['${day}_uid', '${day}_uid$shopQrTicketSuffix'], lastPlay: now, now: now);
    expect(state.classicPlayedToday && state.shopPlayedToday, isTrue);
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

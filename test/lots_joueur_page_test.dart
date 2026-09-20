import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/backend/schema/my_lots_record.dart';
import 'package:proxi_play/backend/schema/prizes_record.dart';
import 'package:proxi_play/pages/joueur/lots_joueur_page/lots_joueur_page_widget.dart';

// Regression coverage for the "Mes gains" ("Impossible de charger vos lots
// pour le moment.") bug: a single unreadable/malformed prize used to throw
// out of _loadLotItems and blank the player's entire list. resolveMyLotItem
// / resolveMyLotItems (extracted, @visibleForTesting, from
// lots_joueur_page_widget.dart) now treat every my_lots entry independently
// -- see the doc comments on those functions for the contract.

// Only path/firestore access is needed for these logic-level tests, same
// pattern as test/rollout_prize_compatibility_test.dart.
// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.path);
  @override
  final String path;
  @override
  FirebaseFirestore get firestore => _Firestore();
  @override
  bool operator ==(Object other) => other is _Reference && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

// ignore: subtype_of_sealed_class
class _Firestore extends Fake implements FirebaseFirestore {
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      _Reference(path);
}

// ignore: subtype_of_sealed_class
class _FakeSnapshot extends Fake implements DocumentSnapshot<Object?> {
  _FakeSnapshot({required this.exists, Map<String, dynamic>? data})
      : _data = data,
        reference = _Reference('prizes/fake');
  @override
  final bool exists;
  @override
  final DocumentReference<Object?> reference;
  final Map<String, dynamic>? _data;
  @override
  Map<String, dynamic>? data() => _data;
}

void main() {
  MyLotsRecord myLot(String id, Map<String, dynamic> data) =>
      MyLotsRecord.getDocumentFromData(
          data, _Reference('users/u1/my_lots/$id'));

  Map<String, dynamic> prizeData({
    String name = 'Lot test',
    bool claimed = false,
    DateTime? usageDeadline,
  }) =>
      <String, dynamic>{
        'name': name,
        'claimed': claimed,
        if (usageDeadline != null) 'usage_deadline': usageDeadline,
      };

  group('resolveMyLotItem (single lot)', () {
    test('uses the cached prize_snapshot without any fetch', () async {
      final record = myLot('l1', {
        'prize_id': _Reference('prizes/p1'),
        'prize_snapshot': prizeData(name: 'Cadeau'),
      });
      final item = await resolveMyLotItem(
        record,
        getPrizeSnapshot: (_) async =>
            throw StateError('should not fetch when snapshot is cached'),
      );
      expect(item, isNotNull);
      expect(item!.prize.name, 'Cadeau');
    });

    test('falls back to a live prizes read when no snapshot is cached',
        () async {
      final record = myLot('l1', {'prize_id': _Reference('prizes/p1')});
      final item = await resolveMyLotItem(
        record,
        getPrizeSnapshot: (ref) async {
          expect(ref.path, 'prizes/p1');
          return _FakeSnapshot(
              exists: true, data: prizeData(name: 'Depuis prizes'));
        },
      );
      expect(item!.prize.name, 'Depuis prizes');
    });

    test('returns null when the prize doc no longer exists', () async {
      final record = myLot('l1', {'prize_id': _Reference('prizes/p1')});
      final item = await resolveMyLotItem(
        record,
        getPrizeSnapshot: (_) async => _FakeSnapshot(exists: false),
      );
      expect(item, isNull);
    });

    test('returns null when the prize was explicitly marked deleted',
        () async {
      final record = myLot('l1', {
        'prize_id': _Reference('prizes/p1'),
        'prize_deleted': true,
      });
      final item = await resolveMyLotItem(
        record,
        getPrizeSnapshot: (_) async =>
            throw StateError('should not fetch a deleted prize'),
      );
      expect(item, isNull);
    });

    test('returns null when the my_lots entry has no prize_id', () async {
      final record = myLot('l1', {});
      final item = await resolveMyLotItem(record);
      expect(item, isNull);
    });

    test('throws when the prize read is denied (permission-denied)',
        () async {
      final record = myLot('l1', {'prize_id': _Reference('prizes/p1')});
      await expectLater(
        resolveMyLotItem(
          record,
          getPrizeSnapshot: (_) async => throw FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied'),
        ),
        throwsA(isA<FirebaseException>()),
      );
    });

    test(
        'throws when the prize doc has a malformed field (legacy winner_id string)',
        () async {
      final record = myLot('l1', {'prize_id': _Reference('prizes/p1')});
      await expectLater(
        resolveMyLotItem(
          record,
          getPrizeSnapshot: (_) async => _FakeSnapshot(
            exists: true,
            data: {...prizeData(), 'winner_id': 'not-a-reference'},
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('a repaired_at field on my_lots does not affect resolution',
        () async {
      final record = myLot('l1', {
        'prize_id': _Reference('prizes/p1'),
        'repaired_at': DateTime(2026, 9, 1),
      });
      final item = await resolveMyLotItem(
        record,
        getPrizeSnapshot: (_) async =>
            _FakeSnapshot(exists: true, data: prizeData()),
      );
      expect(item, isNotNull);
    });
  });

  group('resolveMyLotItems (per-lot isolation across the whole list)', () {
    test('two valid lots -> both resolved', () async {
      final records = [
        myLot('l1', {
          'prize_id': _Reference('prizes/p1'),
          'prize_snapshot': prizeData(name: 'A'),
        }),
        myLot('l2', {
          'prize_id': _Reference('prizes/p2'),
          'prize_snapshot': prizeData(name: 'B'),
        }),
      ];
      final items = await resolveMyLotItems(records);
      expect(items.length, 2);
    });

    test('one valid lot + one missing prize -> the valid lot is still shown',
        () async {
      final records = [
        myLot('l1', {
          'prize_id': _Reference('prizes/p1'),
          'prize_snapshot': prizeData(name: 'A'),
        }),
        myLot('l2', {'prize_id': _Reference('prizes/p2')}),
      ];
      final items = await resolveMyLotItems(
        records,
        getPrizeSnapshot: (_) async => _FakeSnapshot(exists: false),
      );
      expect(items.length, 1);
      expect(items.single.prize.name, 'A');
    });

    test(
        'one valid lot + one historical lot with a malformed field -> the valid lot is still shown',
        () async {
      final records = [
        myLot('l1', {
          'prize_id': _Reference('prizes/p1'),
          'prize_snapshot': prizeData(name: 'A'),
        }),
        myLot('l2', {'prize_id': _Reference('prizes/p2')}),
      ];
      final items = await resolveMyLotItems(
        records,
        getPrizeSnapshot: (ref) async => ref.path == 'prizes/p2'
            ? _FakeSnapshot(
                exists: true,
                data: {...prizeData(), 'winner_id': 'legacy-string'})
            : _FakeSnapshot(exists: true, data: prizeData(name: 'A')),
      );
      expect(items.length, 1);
      expect(items.single.prize.name, 'A');
    });

    test('a permission-denied on one lot never blanks the others', () async {
      final records = [
        myLot('l1', {
          'prize_id': _Reference('prizes/p1'),
          'prize_snapshot': prizeData(name: 'A'),
        }),
        myLot('l2', {'prize_id': _Reference('prizes/p2')}),
      ];
      final items = await resolveMyLotItems(
        records,
        getPrizeSnapshot: (ref) async => ref.path == 'prizes/p2'
            ? throw FirebaseException(
                plugin: 'cloud_firestore', code: 'permission-denied')
            : _FakeSnapshot(exists: true, data: prizeData(name: 'A')),
      );
      expect(items.length, 1);
      expect(items.single.prize.name, 'A');
    });

    test('a repaired lot (repaired_at present) resolves alongside a normal one',
        () async {
      final records = [
        myLot('l1', {
          'prize_id': _Reference('prizes/p1'),
          'prize_snapshot': prizeData(name: 'A'),
        }),
        myLot('l2', {
          'prize_id': _Reference('prizes/p2'),
          'repaired_at': DateTime(2026, 9, 1),
        }),
      ];
      final items = await resolveMyLotItems(
        records,
        getPrizeSnapshot: (_) async =>
            _FakeSnapshot(exists: true, data: prizeData(name: 'B')),
      );
      expect(items.length, 2);
    });

    test('no lots -> empty list, not an error', () async {
      final items = await resolveMyLotItems(const []);
      expect(items, isEmpty);
    });
  });

  group('prize classification (À récupérer vs Historique)', () {
    PrizesRecord prize(Map<String, dynamic> data) =>
        PrizesRecord.getDocumentFromData(data, _Reference('prizes/p1'));

    test('an unclaimed, non-expired prize is available ("À récupérer")', () {
      expect(prize(prizeData()).isAvailable, true);
    });

    test('a claimed (retiré) prize is history, not available', () {
      final p = prize(prizeData(claimed: true));
      expect(p.isAvailable, false);
      expect(p.claimed, true);
    });

    test('an expired prize is history, not available', () {
      final p = prize(prizeData(usageDeadline: DateTime(2000)));
      expect(p.isAvailable, false);
      expect(p.isExpired, true);
    });

    test('a prize with no game_id/enseigne_id still parses and classifies',
        () {
      // "game manquant" / "enseigne manquante": these fields are only ever
      // read as denormalized references, never dereferenced live when
      // building the list -- a missing/dangling one must not break parsing.
      final p = prize(prizeData());
      expect(p.gameId, isNull);
      expect(p.enseigneId, isNull);
      expect(p.isAvailable, true);
    });
  });

  group('winner_id -- current format, absent, and legacy fallback', () {
    test('a well-formed winner_id (DocumentReference, current format) parses fine',
        () async {
      final record = myLot('l1', {'prize_id': _Reference('prizes/p1')});
      final item = await resolveMyLotItem(
        record,
        getPrizeSnapshot: (_) async => _FakeSnapshot(
          exists: true,
          data: {...prizeData(), 'winner_id': _Reference('users/u1')},
        ),
      );
      expect(item, isNotNull);
      expect(item!.prize.winnerId?.path, 'users/u1');
    });

    test('a prize with no winner_id at all still resolves without crashing',
        () async {
      // A my_lots link pointing at a prize that (inconsistently) has no
      // winner_id yet must not throw -- winner_id itself is nullable on
      // PrizesRecord, only the Firestore *rule* requires it for reads by
      // a non-owner; parsing it must stay safe either way.
      final record = myLot('l1', {'prize_id': _Reference('prizes/p1')});
      final item = await resolveMyLotItem(
        record,
        getPrizeSnapshot: (_) async =>
            _FakeSnapshot(exists: true, data: prizeData()),
      );
      expect(item, isNotNull);
      expect(item!.prize.winnerId, isNull);
    });

    test(
        'legacy winner_id format (string) on one lot: no compatibility shim -- '
        'documented fallback is "skip this lot", proven by resolveMyLotItems above',
        () async {
      // This repo's own write paths (participate_in_game_transaction.js,
      // main_prize_draw.js, draw_animation_winner.js, referral_game_engine.js,
      // monthly_challenge.js) have never written winner_id as anything but a
      // DocumentReference (verified this session against production data and
      // full git history) -- so there is intentionally no format-migration
      // logic here. A string winner_id throws while parsing this ONE prize
      // (see "throws when the prize doc has a malformed field" above) and
      // resolveMyLotItems already proves that failure is isolated, not fatal
      // to the rest of the list.
      final record = myLot('l1', {'prize_id': _Reference('prizes/p1')});
      await expectLater(
        resolveMyLotItem(
          record,
          getPrizeSnapshot: (_) async => _FakeSnapshot(
            exists: true,
            data: {...prizeData(), 'winner_id': 'users/u1'},
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('code de retrait (claim_code) surfaces correctly', () {
    PrizesRecord prize(Map<String, dynamic> data) =>
        PrizesRecord.getDocumentFromData(data, _Reference('prizes/p1'));

    test('claimCode round-trips through PrizesRecord for an available lot',
        () {
      final p = prize({...prizeData(), 'claim_code': 'ABC123'});
      expect(p.claimCode, 'ABC123');
      expect(p.isAvailable, true);
    });

    test('missing claim_code yields an empty string, not a crash', () {
      final p = prize(prizeData());
      expect(p.claimCode, '');
    });
  });
}

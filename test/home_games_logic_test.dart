import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/joueur/home_joueur_page/home_games_logic.dart';
import 'package:proxi_play/utils/paged_stream_merge.dart';

void main() {
  group('isPlayerHomeGameVisible', () {
    final now = DateTime.utc(2026, 7, 21, 12);

    test('returns true for active public window', () {
      expect(
        isPlayerHomeGameVisible(
          now: now,
          animationId: '',
          startDate: now.subtract(const Duration(hours: 1)),
          endDate: now.add(const Duration(hours: 1)),
        ),
        isTrue,
      );
    });

    test('returns false for future game', () {
      expect(
        isPlayerHomeGameVisible(
          now: now,
          animationId: '',
          startDate: now.add(const Duration(hours: 1)),
          endDate: now.add(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('returns false for ended game', () {
      expect(
        isPlayerHomeGameVisible(
          now: now,
          animationId: '',
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now,
        ),
        isFalse,
      );
    });

    test('returns false when end date is missing', () {
      expect(
        isPlayerHomeGameVisible(
          now: now,
          animationId: '',
          startDate: now.subtract(const Duration(days: 1)),
          endDate: null,
        ),
        isFalse,
      );
    });

    test('returns false for animation-linked game', () {
      expect(
        isPlayerHomeGameVisible(
          now: now,
          animationId: 'anim-42',
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now.add(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('is timezone-stable with equivalent UTC instants', () {
      final parisEquivalent = DateTime.parse('2026-07-21T14:00:00+02:00').toUtc();
      expect(parisEquivalent, now);
      expect(
        isPlayerHomeGameVisible(
          now: parisEquivalent,
          animationId: '',
          startDate: DateTime.parse('2026-07-21T13:00:00+02:00').toUtc(),
          endDate: DateTime.parse('2026-07-21T15:00:00+02:00').toUtc(),
        ),
        isTrue,
      );
    });
  });

  group('mergePagedStreamItems', () {
    test('fills an initially empty cached page when server items arrive later', () {
      final merged = mergePagedStreamItems<_FakeItem>(
        currentItems: const [],
        incomingItems: const [
          _FakeItem('a', 'first'),
          _FakeItem('b', 'second'),
        ],
        getId: (item) => item.id,
      );

      expect(merged.map((item) => item.id).toList(), ['a', 'b']);
    });

    test('keeps stable order when cache has 2 games and server expands to 5', () {
      final merged = mergePagedStreamItems<_FakeItem>(
        currentItems: const [
          _FakeItem('a', 'cached-a'),
          _FakeItem('b', 'cached-b'),
        ],
        incomingItems: const [
          _FakeItem('a', 'server-a'),
          _FakeItem('b', 'server-b'),
          _FakeItem('c', 'server-c'),
          _FakeItem('d', 'server-d'),
          _FakeItem('e', 'server-e'),
        ],
        getId: (item) => item.id,
      );

      expect(
        merged.map((item) => '${item.id}:${item.label}').toList(),
        ['a:server-a', 'b:server-b', 'c:server-c', 'd:server-d', 'e:server-e'],
      );
    });

    test('updates existing items without duplicating ids', () {
      final merged = mergePagedStreamItems<_FakeItem>(
        currentItems: const [
          _FakeItem('a', 'old'),
          _FakeItem('b', 'keep'),
        ],
        incomingItems: const [
          _FakeItem('a', 'new'),
          _FakeItem('c', 'append'),
        ],
        getId: (item) => item.id,
      );

      expect(
        merged.map((item) => '${item.id}:${item.label}').toList(),
        ['a:new', 'b:keep', 'c:append'],
      );
    });

    test('preserves existing items when incoming snapshot is empty', () {
      final merged = mergePagedStreamItems<_FakeItem>(
        currentItems: const [
          _FakeItem('a', 'first'),
          _FakeItem('b', 'second'),
        ],
        incomingItems: const [],
        getId: (item) => item.id,
      );

      expect(
        merged.map((item) => '${item.id}:${item.label}').toList(),
        ['a:first', 'b:second'],
      );
    });

    test('accepts incoming documents in a different order without duplicates', () {
      final merged = mergePagedStreamItems<_FakeItem>(
        currentItems: const [
          _FakeItem('a', 'old-a'),
          _FakeItem('b', 'old-b'),
        ],
        incomingItems: const [
          _FakeItem('b', 'new-b'),
          _FakeItem('a', 'new-a'),
          _FakeItem('c', 'new-c'),
        ],
        getId: (item) => item.id,
      );

      expect(
        merged.map((item) => '${item.id}:${item.label}').toList(),
        ['a:new-a', 'b:new-b', 'c:new-c'],
      );
    });

    test('supports several successive live updates', () {
      var state = mergePagedStreamItems<_FakeItem>(
        currentItems: const [],
        incomingItems: const [
          _FakeItem('a', 'v1'),
          _FakeItem('b', 'v1'),
          _FakeItem('c', 'v1'),
        ],
        getId: (item) => item.id,
      );

      state = mergePagedStreamItems<_FakeItem>(
        currentItems: state,
        incomingItems: const [
          _FakeItem('a', 'v2'),
          _FakeItem('c', 'v2'),
          _FakeItem('d', 'v1'),
        ],
        getId: (item) => item.id,
      );

      state = mergePagedStreamItems<_FakeItem>(
        currentItems: state,
        incomingItems: const [
          _FakeItem('d', 'v2'),
          _FakeItem('e', 'v1'),
        ],
        getId: (item) => item.id,
      );

      expect(
        state.map((item) => '${item.id}:${item.label}').toList(),
        ['a:v2', 'b:v1', 'c:v2', 'd:v2', 'e:v1'],
      );
    });
  });
}

class _FakeItem {
  const _FakeItem(this.id, this.label);

  final String id;
  final String label;
}

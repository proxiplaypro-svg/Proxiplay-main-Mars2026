import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/ad_system_utils.dart';

void main() {
  final now = DateTime(2026, 6, 15, 12, 0, 0);

  group('isAdPlacementEnabled (fail-closed on activation, by design)', () {
    test('1. enabled=true, no schedule bounds -> eligible', () {
      expect(
        isAdPlacementEnabled(enabled: true, startAt: null, endAt: null, now: now),
        isTrue,
      );
    });

    test('2. enabled=false -> never eligible', () {
      expect(
        isAdPlacementEnabled(enabled: false, startAt: null, endAt: null, now: now),
        isFalse,
      );
    });

    test('3. enabled=null (not configured) -> never eligible', () {
      expect(
        isAdPlacementEnabled(enabled: null, startAt: null, endAt: null, now: now),
        isFalse,
      );
    });

    test('4. before start_at -> not yet eligible', () {
      expect(
        isAdPlacementEnabled(
          enabled: true,
          startAt: now.add(const Duration(days: 1)),
          endAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('5. after end_at -> no longer eligible', () {
      expect(
        isAdPlacementEnabled(
          enabled: true,
          startAt: null,
          endAt: now.subtract(const Duration(days: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('6. within [start_at, end_at] -> eligible', () {
      expect(
        isAdPlacementEnabled(
          enabled: true,
          startAt: now.subtract(const Duration(days: 1)),
          endAt: now.add(const Duration(days: 1)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('isOpenAdFrequencyElapsed (fail-open)', () {
    test('7. never shown before -> allowed', () {
      expect(
        isOpenAdFrequencyElapsed(lastShownAt: null, frequencyCapHours: 24, now: now),
        isTrue,
      );
    });

    test('8. no frequency cap configured -> always allowed', () {
      expect(
        isOpenAdFrequencyElapsed(
          lastShownAt: now.subtract(const Duration(minutes: 1)),
          frequencyCapHours: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('9. cap=0 -> allowed at every cold launch', () {
      expect(
        isOpenAdFrequencyElapsed(
          lastShownAt: now.subtract(const Duration(minutes: 1)),
          frequencyCapHours: 0,
          now: now,
        ),
        isTrue,
      );
    });

    test('10. negative cap -> fail-open, allowed', () {
      expect(
        isOpenAdFrequencyElapsed(
          lastShownAt: now.subtract(const Duration(minutes: 1)),
          frequencyCapHours: -1,
          now: now,
        ),
        isTrue,
      );
    });

    test('11. shown 1 hour ago, cap=24h -> not yet elapsed, blocked', () {
      expect(
        isOpenAdFrequencyElapsed(
          lastShownAt: now.subtract(const Duration(hours: 1)),
          frequencyCapHours: 24,
          now: now,
        ),
        isFalse,
      );
    });

    test('12. shown exactly 24 hours ago, cap=24h -> elapsed, allowed', () {
      expect(
        isOpenAdFrequencyElapsed(
          lastShownAt: now.subtract(const Duration(hours: 24)),
          frequencyCapHours: 24,
          now: now,
        ),
        isTrue,
      );
    });

    test('13. shown 25 hours ago, cap=24h -> elapsed, allowed', () {
      expect(
        isOpenAdFrequencyElapsed(
          lastShownAt: now.subtract(const Duration(hours: 25)),
          frequencyCapHours: 24,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('shouldShowOpenAd (combines activation + schedule + frequency)', () {
    test('14. all conditions satisfied -> show', () {
      expect(
        shouldShowOpenAd(
          enabled: true,
          startAt: null,
          endAt: null,
          lastShownAt: null,
          frequencyCapHours: 24,
          now: now,
        ),
        isTrue,
      );
    });

    test('15. disabled, even with frequency elapsed -> never show', () {
      expect(
        shouldShowOpenAd(
          enabled: false,
          startAt: null,
          endAt: null,
          lastShownAt: null,
          frequencyCapHours: 24,
          now: now,
        ),
        isFalse,
      );
    });

    test('16. enabled but frequency not elapsed -> do not show again yet', () {
      expect(
        shouldShowOpenAd(
          enabled: true,
          startAt: null,
          endAt: null,
          lastShownAt: now.subtract(const Duration(minutes: 5)),
          frequencyCapHours: 24,
          now: now,
        ),
        isFalse,
      );
    });

    test('17. enabled, frequency elapsed, but outside schedule window -> do not show', () {
      expect(
        shouldShowOpenAd(
          enabled: true,
          startAt: now.add(const Duration(days: 2)),
          endAt: null,
          lastShownAt: now.subtract(const Duration(days: 10)),
          frequencyCapHours: 24,
          now: now,
        ),
        isFalse,
      );
    });
  });
}

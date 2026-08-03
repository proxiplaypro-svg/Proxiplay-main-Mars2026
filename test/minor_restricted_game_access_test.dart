import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/minor_restricted_game_access.dart';

void main() {
  group('resolveMinorRestrictedGameAccess', () {
    test('public game is always allowed without birthday', () {
      expect(
        resolveMinorRestrictedGameAccess(
          prohibitedForMinors: false,
          birthday: null,
          today: DateTime(2026, 8, 3),
        ),
        MinorRestrictedGameAccessStatus.allowed,
      );
    });

    test('minor restricted game requires birthday when missing', () {
      expect(
        resolveMinorRestrictedGameAccess(
          prohibitedForMinors: true,
          birthday: null,
          today: DateTime(2026, 8, 3),
        ),
        MinorRestrictedGameAccessStatus.birthdayRequired,
      );
    });

    test('adult can play minor restricted game', () {
      expect(
        canPlayMinorRestrictedGame(
          prohibitedForMinors: true,
          birthday: DateTime(1990, 7, 14),
          today: DateTime(2026, 8, 3),
        ),
        isTrue,
      );
    });

    test('minor cannot play minor restricted game', () {
      expect(
        resolveMinorRestrictedGameAccess(
          prohibitedForMinors: true,
          birthday: DateTime(2010, 9, 1),
          today: DateTime(2026, 8, 3),
        ),
        MinorRestrictedGameAccessStatus.underage,
      );
    });

    test('18th birthday is allowed on the same day', () {
      expect(
        isAdult(
          DateTime(2008, 8, 3),
          today: DateTime(2026, 8, 3),
        ),
        isTrue,
      );
    });
  });
}

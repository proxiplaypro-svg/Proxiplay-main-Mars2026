import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/auth/user_profile/user_profile_completion.dart';
import 'package:proxi_play/backend/schema/enums/enums.dart';

void main() {
  group('isUserProfileCompleteFromData', () {
    test('player profile is complete when required fields are present', () {
      final isComplete = isUserProfileCompleteFromData(
        <String, dynamic>{
          'first_name': 'Julie',
          'last_name': 'Deblieck',
          'phone_number': '06 00 00 00 00',
          'city': 'Lille',
          'birthday': DateTime(1995, 1, 1),
        },
        role: Roles.joueur,
      );

      expect(isComplete, isTrue);
    });

    test('player profile stays incomplete with blank names', () {
      final isComplete = isUserProfileCompleteFromData(
        <String, dynamic>{
          'first_name': '  ',
          'last_name': '',
          'phone_number': '06 00 00 00 00',
          'city': 'Lille',
          'birthday': DateTime(1995, 1, 1),
        },
        role: Roles.joueur,
      );

      expect(isComplete, isFalse);
    });

    test('merchant profile does not require birthday', () {
      final isComplete = isUserProfileCompleteFromData(
        <String, dynamic>{
          'first_name': 'Meh',
          'last_name': 'Ben',
          'phone_number': '06 00 00 00 00',
          'city': 'Roubaix',
        },
        role: Roles.commercant,
      );

      expect(isComplete, isTrue);
    });

    test('admin profile is always considered complete', () {
      final isComplete = isUserProfileCompleteFromData(
        const <String, dynamic>{},
        role: Roles.admin,
      );

      expect(isComplete, isTrue);
    });
  });

  group('shouldRequireUserProfileCompletionFromData', () {
    test('new schema player with profile_completed false is blocked', () {
      final requiresCompletion = shouldRequireUserProfileCompletionFromData(
        <String, dynamic>{
          'profile_schema_version': 1,
          'profile_completed': false,
          'first_name': '',
          'last_name': '',
          'phone_number': '',
          'city': '',
        },
        role: Roles.joueur,
      );

      expect(requiresCompletion, isTrue);
    });

    test('new schema player with complete profile is not blocked', () {
      final requiresCompletion = shouldRequireUserProfileCompletionFromData(
        <String, dynamic>{
          'profile_schema_version': 1,
          'profile_completed': true,
          'first_name': 'Julie',
          'last_name': 'Deblieck',
          'phone_number': '06 00 00 00 00',
          'city': 'Lille',
          'birthday': DateTime(1995, 1, 1),
        },
        role: Roles.joueur,
      );

      expect(requiresCompletion, isFalse);
    });

    test('legacy incomplete player without schema version is not blocked', () {
      final requiresCompletion = shouldRequireUserProfileCompletionFromData(
        <String, dynamic>{
          'display_name': 'Julie Deblieck',
        },
        role: Roles.joueur,
      );

      expect(requiresCompletion, isFalse);
    });

    test('legacy account explicitly marked incomplete can be blocked later', () {
      final requiresCompletion = shouldRequireUserProfileCompletionFromData(
        <String, dynamic>{
          'profile_completed': false,
        },
        role: Roles.joueur,
      );

      expect(requiresCompletion, isTrue);
    });
  });

  group('profile display name helpers', () {
    test('display name is rebuilt from validated first and last name', () {
      expect(
        buildDisplayNameFromProfileNames(
          firstName: 'Julie',
          lastName: 'Deblieck',
        ),
        'Julie Deblieck',
      );
    });

    test('temporary Google display name prefill stays ephemeral', () {
      final prefill =
          buildTemporaryNamePrefillFromDisplayName('Melanie Gaillard');

      expect(prefill, isNotNull);
      expect(prefill?.firstName, 'Melanie');
      expect(prefill?.lastName, 'Gaillard');
    });
  });
}

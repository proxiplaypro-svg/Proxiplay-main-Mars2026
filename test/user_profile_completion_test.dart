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

    test('incomplete profile prompt is offered only until dismissed', () {
      expect(
        shouldOfferUserProfileCompletionPrompt(
          isProfileComplete: false,
          hasDismissedPrompt: false,
        ),
        isTrue,
      );
      expect(
        shouldOfferUserProfileCompletionPrompt(
          isProfileComplete: false,
          hasDismissedPrompt: true,
        ),
        isFalse,
      );
      expect(
        shouldOfferUserProfileCompletionPrompt(
          isProfileComplete: true,
          hasDismissedPrompt: false,
        ),
        isFalse,
      );
    });
  });
}

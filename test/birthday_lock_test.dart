import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/birthday_lock.dart';

void main() {
  final stored = DateTime(1990, 5, 18);
  final picked = DateTime(1991, 6, 1);

  group('birthday lock', () {
    test('a recorded birthday locks the field', () {
      expect(isBirthdayLocked(null), isFalse);
      expect(isBirthdayLocked(stored), isTrue);
    });

    test('a recorded birthday is never sent again', () {
      expect(
          birthdayToSubmit(
              isMerchant: false,
              storedBirthday: stored,
              pickedBirthday: picked),
          isNull);
      expect(
          birthdayToSubmit(
              isMerchant: false, storedBirthday: null, pickedBirthday: picked),
          picked);
      expect(
          birthdayToSubmit(
              isMerchant: true, storedBirthday: null, pickedBirthday: picked),
          isNull);
    });

    test('confirmation only for the first entry of a player', () {
      expect(
          shouldConfirmBirthdayBeforeSave(
              isMerchant: false, storedBirthday: null, pickedBirthday: picked),
          isTrue);
      expect(
          shouldConfirmBirthdayBeforeSave(
              isMerchant: false,
              storedBirthday: stored,
              pickedBirthday: stored),
          isFalse);
      expect(
          shouldConfirmBirthdayBeforeSave(
              isMerchant: true, storedBirthday: null, pickedBirthday: picked),
          isFalse);
      expect(
          shouldConfirmBirthdayBeforeSave(
              isMerchant: false, storedBirthday: null, pickedBirthday: null),
          isFalse);
    });

    test('the confirmation says the date can no longer be changed', () {
      final message = birthdayConfirmMessage('18/5/1990');
      expect(message, contains('18/5/1990'));
      expect(message, contains('ne pourra plus être modifiée'));
      expect(kBirthdayLockedHelpText, contains('support'));
    });
  });

  // The page depends on Firebase: its wiring is guarded from the source text
  // (same convention as enseigne_joueur_page_directory_source_test.dart).
  test('the signup information page applies the lock', () {
    final page = File(
            'lib/pages/auth/inscription_informations_page/inscription_informations_page_widget.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
        page,
        contains(
            'final birthdayLocked = isBirthdayLocked(currentUserDocument?.birthday);'));
    expect(page, contains('onTap: birthdayLocked\n'));
    expect(page, contains('if (!isMerchant && birthdayLocked)'));
    expect(page, contains('kBirthdayLockedHelpText'));
    expect(page, contains('shouldConfirmBirthdayBeforeSave('));
    expect(page, contains('birthday: birthdayToSubmit('));
    // The only birthday written with the profile goes through the lock.
    expect(RegExp(r'birthday: isMerchant').hasMatch(page), isFalse);
  });
}

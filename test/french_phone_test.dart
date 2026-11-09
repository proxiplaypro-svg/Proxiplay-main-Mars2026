import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/pages/commercant/update_enseigne_commercant_page/merchant_update_result.dart';
import 'package:proxi_play/utils/french_phone.dart';

void main() {
  group('normalizeFrenchPhone', () {
    test('formats français usuels, avec ou sans séparateurs', () {
      const expected = '06 46 30 79 86';
      for (final input in [
        '06 46 30 79 86', // capture du test Android
        '0646307986',
        '06.46.30.79.86',
        '06-46-30-79-86',
        ' 06 46 30 79 86 ',
        '06 46 30 79 86',
        '+33646307986',
        '+33 6 46 30 79 86',
        '+33 (0)6 46 30 79 86',
        '0033 6 46 30 79 86',
      ]) {
        expect(normalizeFrenchPhone(input), expected, reason: input);
        expect(validateFrenchPhone(input), isNull, reason: input);
      }
      expect(normalizeFrenchPhone('03 28 00 00 00'), '03 28 00 00 00');
      expect(normalizeFrenchPhone('09 70 00 00 00'), '09 70 00 00 00');
    });

    test('refuse les chaînes arbitraires', () {
      for (final input in [
        'abc',
        '06 46 30 79 8', // 9 chiffres
        '06 46 30 79 866', // 11 chiffres
        '00 46 30 79 86', // préfixe 00
        '6 46 30 79 86', // sans 0
        '+32 6 46 30 79 86', // autre pays
        '+33 0 46 30 79 86',
        '06 46 30 79 8a',
        '06/46/30/79/86',
        '+',
      ]) {
        expect(normalizeFrenchPhone(input), isNull, reason: input);
        expect(validateFrenchPhone(input), kPhoneInvalidMessage,
            reason: input);
      }
    });

    test('message requis en français', () {
      expect(validateFrenchPhone(null), kPhoneRequiredMessage);
      expect(validateFrenchPhone('   '), kPhoneRequiredMessage);
      expect(kPhoneInvalidMessage, contains('06 12 34 56 78'));
    });
  });

  test('messages d’échec explicites en français', () {
    expect(merchantUpdateErrorMessage(TimeoutException('x')),
        contains('ne sont pas confirmées'));
    expect(
        merchantUpdateErrorMessage(
            FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
        contains('autorisation'));
    expect(
        merchantUpdateErrorMessage(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')),
        contains('Vérifiez votre connexion'));
    expect(merchantUpdateErrorMessage(StateError('?')),
        kMerchantUpdateGenericError);
  });
}

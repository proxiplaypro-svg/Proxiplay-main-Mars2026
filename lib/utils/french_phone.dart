import 'package:flutter/services.dart';

const String kPhoneRequiredMessage = 'Numéro de téléphone requis.';
const String kPhoneInvalidMessage =
    'Numéro invalide. Saisissez un numéro français à 10 chiffres, '
    'par exemple 06 12 34 56 78.';

/// Separators players commonly type or paste: spaces (including the
/// non-breaking ones), dots, dashes and parentheses.
final RegExp _separators = RegExp(r'[\s.\-()  ]');

/// Normalises a French phone number to its national display form
/// "0X XX XX XX XX". Accepted, with or without separators:
/// - 0X XX XX XX XX (X from 1 to 9),
/// - +33 X XX XX XX XX, +33 (0)X XX XX XX XX and 0033 X XX XX XX XX.
/// Anything else (letters, wrong length, 00 prefix, other country) is
/// rejected with null: no arbitrary string is accepted.
String? normalizeFrenchPhone(String? input) {
  if (input == null) return null;
  var compact = input.trim().replaceAll(_separators, '');
  if (compact.startsWith('+33')) {
    compact = compact.substring(3);
  } else if (compact.startsWith('0033')) {
    compact = compact.substring(4);
  } else if (compact.startsWith('0')) {
    compact = compact.substring(1);
  } else {
    return null;
  }
  // "+33 (0)6…" written with the trunk zero.
  if (compact.length == 10 && compact.startsWith('0')) {
    compact = compact.substring(1);
  }
  if (!RegExp(r'^[1-9]\d{8}$').hasMatch(compact)) return null;
  final digits = '0$compact';
  return [
    for (var i = 0; i < 10; i += 2) digits.substring(i, i + 2),
  ].join(' ');
}

/// French form validator message, or null when the number is valid.
String? validateFrenchPhone(String? value) {
  if (value == null || value.trim().isEmpty) return kPhoneRequiredMessage;
  return normalizeFrenchPhone(value) == null ? kPhoneInvalidMessage : null;
}

/// Input restriction of the phone field: digits, "+", spaces, dots, dashes
/// and parentheses only, so "+33 6 …" and "06.46…" can be typed or pasted
/// while letters cannot. The text is shown as typed and normalised on save.
final List<TextInputFormatter> kFrenchPhoneInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s.\-()]')),
  LengthLimitingTextInputFormatter(20),
];

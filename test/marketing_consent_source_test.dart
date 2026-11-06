import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final signup = File(
    'lib/pages/auth/inscription_informations_page/'
    'inscription_informations_page_widget.dart',
  ).readAsStringSync();
  final profile = File(
    'lib/pages/joueur/profil_joueur_page/'
    'profil_joueur_page_widget.dart',
  ).readAsStringSync();
  final model = File(
    'lib/pages/auth/inscription_informations_page/'
    'inscription_informations_page_model.dart',
  ).readAsStringSync();

  test(
      'the shared player completion form offers an optional, unchecked consent',
      () {
    expect(model, contains('bool marketingConsent = false;'));
    expect(signup, contains('if (!isMerchant)'));
    expect(signup, contains('CheckboxListTile('));
    expect(signup, contains('kMarketingPlayerConsentText'));
    expect(signup, contains("'source': 'signup'"));
  });

  test('an unchecked signup choice remains unknown and cannot enable email',
      () {
    expect(signup, contains('if (!isMerchant &&'));
    expect(signup, contains('_model.marketingConsent)'));
    expect(signup, contains('A box left unchecked means no response'));
  });

  test(
      'existing players get a non-blocking profile preference and can withdraw',
      () {
    expect(
        profile, contains('Vous n’avez pas encore indiqué votre préférence.'));
    expect(profile, contains("'source': 'player-profile'"));
    expect(profile, contains("'enabled': value"));
    expect(profile, contains('setMarketingConsent'));
  });
}

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
    expect(signup, contains('if (!isMerchant &&'));
    expect(signup, contains('CheckboxListTile('));
    expect(signup, contains('kMarketingPlayerConsentText'));
    expect(signup, contains("'source': 'signup'"));
  });

  test('an unchecked signup choice remains unknown and cannot enable email',
      () {
    expect(signup, contains('checked: _model.marketingConsent,'));
    expect(signup, contains('A box left unchecked means no response'));
    expect(signup, isNot(contains("'enabled': false")),
        reason: 'signup never records a refusal for an unchecked box');
  });

  test('the consent call can never make the signup fail', () {
    final consentCall = signup.indexOf("'setMarketingConsent'");
    expect(consentCall, greaterThan(0));
    // The profile is saved before the optional call...
    expect(signup.indexOf('await currentUserReference!.set('),
        lessThan(consentCall));
    // ...and every failure of the call is caught locally, before navigation.
    final afterCall = signup.substring(consentCall);
    expect(afterCall.indexOf('} catch (_) {'), greaterThan(0));
    expect(afterCall.indexOf('} catch (_) {'),
        lessThan(afterCall.indexOf('if (_isOptionalProfileCompletionFlow)')));
    // Eligibility (age, no recorded preference) is checked before the call.
    expect(signup.indexOf('shouldSendSignupMarketingConsent('),
        lessThan(consentCall));
  });

  test(
      'existing players get a non-blocking profile preference and can withdraw',
      () {
    expect(profile, contains('MarketingPreferenceCard('));
    expect(profile, contains('marketingConsentStateOf('));
    expect(profile, contains("'source': 'player-profile'"));
    expect(profile, contains("'enabled': value"));
    expect(profile, contains('setMarketingConsent'));
    expect(profile, contains('marketingConsentErrorMessage(error.code)'));
    expect(profile, contains('} catch (_) {'));
  });

  test('the client never writes marketing_consent itself', () {
    for (final source in [signup, profile]) {
      expect(source, isNot(contains("'marketing_consent':")));
      expect(source, isNot(contains('marketingConsent:')));
    }
  });
}

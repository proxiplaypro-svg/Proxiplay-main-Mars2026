import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the merchant signup entry point. Bug: a new
/// merchant opening the app only ever saw the login form (LoginPage is the
/// app's sole "/" entry point) with no clearly labeled way to create a
/// merchant account - the only path to the existing, functional
/// "Professionnel" signup tab was a generic "Pas de compte ? Inscription"
/// link that always defaulted to the "Joueur" tab.
///
/// These are static source-content checks (same convention as
/// test/referral_deep_link_test.dart's AndroidManifest guard): this
/// FlutterFlow-generated widget tree depends on Firebase/Rive/camera
/// plugins not available in this environment, so pure logic
/// (resolveInitialSignupRole, see account_routing_test.dart) is tested
/// directly and the surrounding wiring is guarded here.
void main() {
  final loginPage = File(
    'lib/pages/auth/login_page/login_page_widget.dart',
  ).readAsStringSync();
  final inscriptionPage = File(
    'lib/pages/auth/inscription_page/inscription_page_widget.dart',
  ).readAsStringSync();

  group('login screen offers both paths (point 3: existing accounts keep '
      'using login as-is)', () {
    test('the original player "Pas de compte ? Inscription" link is still '
        'present and unconditional', () {
      expect(loginPage, contains("'Pas de compte ? '"));
      expect(loginPage, contains("' Inscription'"));
    });

    test('1. a new, clearly labeled "Créer un compte" entry point for '
        'merchants exists for a logged-out visitor', () {
      expect(loginPage, contains("'Commerçant ? '"));
      expect(loginPage, contains("'Créer un compte'"));
      expect(loginPage, contains("queryParameters: {'role': 'commercant'}"));
    });

    test('the login form itself (email/password submit) is untouched - '
        'an existing merchant or player keeps logging in normally', () {
      expect(loginPage, contains('_routeAfterAuthenticatedLogin'));
    });
  });

  group('4. no inscription <-> login loop', () {
    test('both signup tabs (Joueur and Professionnel) keep their own way '
        'back to login', () {
      final returnLinks = 'Déjà un compte ? '.allMatches(inscriptionPage).length;
      expect(returnLinks, 2,
          reason: 'one "Déjà un compte ?" link per tab (Joueur, '
              'Professionnel) - losing one would trap that tab\'s users');
    });

    test('the role tabs are still named Joueur and Professionnel', () {
      expect(inscriptionPage, contains("text: 'Joueur'"));
      expect(inscriptionPage, contains("text: 'Professionnel'"));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source contract of the sign-in after a server-side signup with a code
// (24/10/2026 finding: the profile was created without a role, 0 chances).
// The server creates the profile with its role; the app sign-in passes the
// same role, which only applies when the profile does not exist yet. The
// server behaviour is covered by
// firebase/functions/test/referral_signup_profile.test.js.
String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final page = _source('lib/pages/auth/inscription_page/inscription_page_widget.dart');
  final manager = _source('lib/auth/firebase_auth/firebase_auth_manager.dart');
  final backend = _source('lib/backend/backend.dart');

  test('the player sign-in after a signup with a code passes the player role', () {
    expect(page, contains(
        ': await authManager.signInWithEmail(context, email, password, roleHint: Roles.joueur);'));
  });

  test('the merchant sign-in after a signup with a code passes the merchant role', () {
    expect(page, contains(
        ': await authManager.signInWithEmail(\n'
        '                                                                      context, merchantEmail, merchantPassword,\n'
        '                                                                      roleHint: Roles.commercant);'));
  });

  test('signInWithEmail forwards the role to the profile creation', () {
    final start = manager.indexOf('Future<BaseAuthUser?> signInWithEmail(');
    final body = manager.substring(start, manager.indexOf('@override', start));
    expect(body, contains('Roles? roleHint,'));
    expect(body, contains('roleHint: roleHint,'));
  });

  test('a role is only written when the profile has none (never changed by the app)', () {
    expect(backend, contains("if (existingRole == null && roleHint != null) {\n"
        "      patch['user_role'] = roleHint.serialize();"));
  });

  test('signups without a code are unchanged', () {
    expect(page, contains('? await authManager.createAccountWithEmail(context, email, password, roleHint: _model.userType)'));
  });
}

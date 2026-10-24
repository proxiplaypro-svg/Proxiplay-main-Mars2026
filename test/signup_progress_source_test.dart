import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source contract of the signup progress feedback (24/10/2026 Samsung
// finding: nothing showed that the app was working). Each signup action shows
// SignupProgressIndicator in place of its button while it runs, cannot run
// twice, and gets its button back after a failure. Rendering is covered by
// test/signup_ux_widget_test.dart.
String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final signup = _source('lib/pages/auth/inscription_page/inscription_page_widget.dart');
  final profile = _source(
      'lib/pages/auth/inscription_informations_page/inscription_informations_page_widget.dart');
  String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  test('player and merchant e-mail signups show "Création de votre compte…"', () {
    final s = squash(signup);
    for (final flag in ['_isSubmittingPlayerSignup', '_isSubmittingMerchantSignup']) {
      expect(s, contains("child: $flag ? const SignupProgressIndicator( message: 'Création de votre compte…') : FFButtonWidget("),
          reason: flag);
      expect(s, contains('if ($flag) { return; }'), reason: '$flag: never twice');
    }
  });

  test('Google: one sign-in at a time, with "Connexion avec Google…"', () {
    final s = squash(signup);
    expect(s, contains("if (_isGoogleSignupInProgress) const SignupProgressIndicator(message: 'Connexion avec Google…') else FFButtonWidget("));
    final handler = s.substring(s.indexOf('Future<void> _handleGooglePlayerSignup() async {'));
    expect(handler, startsWith('Future<void> _handleGooglePlayerSignup() async { if (_isGoogleSignupInProgress) { return; } '
        'safeSetState(() => _isGoogleSignupInProgress = true); try { await _runGooglePlayerSignup(); } finally { '
        'if (mounted) { safeSetState(() => _isGoogleSignupInProgress = false); } } }'));
    // The e-mail form cannot be opened during a Google sign-in.
    expect(s, contains('void _openPlayerEmailForm() { if (_isGoogleSignupInProgress) { return; }'));
  });

  test('profile completion shows "Enregistrement de vos informations…" until it navigates', () {
    final s = squash(profile);
    expect(s, contains("child: _isSubmitting || _hasNavigatedAway ? const SignupProgressIndicator( message: 'Enregistrement de vos informations…') : FFButtonWidget("));
    // Navigation only after the write is confirmed; the button comes back after a failure.
    final write = s.indexOf('await currentUserReference!.set(');
    expect(write, greaterThan(0));
    expect(s.indexOf('_navigateOnce(router, destination);', write), greaterThan(write));
    expect(s, contains("'Une erreur est survenue pendant la finalisation de votre inscription.'"));
    expect(s, contains('} finally { if (mounted && !_hasNavigatedAway) { safeSetState(() { _isSubmitting = false; }); } }'));
  });

  test('the e-mail form has no second referral field', () {
    expect(signup, isNot(contains('.referralCodeJoueurTextControllerValidator')));
    expect(RegExp(r"'Code de parrainage \(facultatif\)'").allMatches(signup), hasLength(1));
    expect(signup, contains('_buildEmailFormReferralRecap(),'));
  });
}

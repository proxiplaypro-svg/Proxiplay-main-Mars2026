import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source contract of the Google signup with a referral code: the server
// (createReferralGoogleAccount) is called with the Google ID token BEFORE the
// Firebase sign-in, a refusal stops before any sign-in, and the sign-in
// without a code is unchanged. The server behaviour itself is covered by
// firebase/functions/test/referral_google_signup.test.js.
String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final googleAuth = _source('lib/auth/firebase_auth/google_auth.dart');
  final page = _source('lib/pages/auth/inscription_page/inscription_page_widget.dart');
  final flowStart = page.indexOf('Future<void> _handleGooglePlayerSignup()');
  final googleFlow = page.substring(flowStart, page.indexOf('resolveAuthenticatedHome', flowStart));

  test('the server step runs with the ID token before the Firebase sign-in', () {
    final hook = googleAuth.indexOf('await beforeFirebaseSignIn(idToken)');
    final signIn = googleAuth.indexOf('FirebaseAuth.instance.signInWithCredential(credential)');
    expect(hook, greaterThan(0));
    expect(signIn, greaterThan(hook));
    // A failed server step is rethrown, never swallowed into a sign-in.
    expect(googleAuth, contains('throw GoogleSignInInterrupted(e)'));
    expect(googleAuth, contains('on GoogleSignInInterrupted {\n    rethrow;'));
  });

  test('with a code the Google flow uses createReferralGoogleAccount, never the 1.1.1 endpoint', () {
    expect(googleFlow, contains('createReferralGoogleAccount('));
    expect(googleFlow, isNot(contains('registerReferralAcceptance')));
    expect(googleFlow, isNot(contains('_applyPendingReferralCodeIfNeeded')));
    // Interrupted: nothing signed in, the code is kept for a retry.
    final interrupted = googleFlow.indexOf('on GoogleSignInInterrupted');
    expect(interrupted, greaterThan(0));
    expect(googleFlow.substring(interrupted, googleFlow.indexOf('return;', interrupted)),
        isNot(contains('clearPendingReferralCode')));
  });

  test('an existing account is signed in normally, then told the code does not apply', () {
    // Any server answer (accepted, existing_account, refused) lets the sign-in
    // continue; the notice is shown once the account is open.
    final hook = googleFlow.indexOf('beforeFirebaseSignIn:');
    final hookBody = googleFlow.substring(hook, googleFlow.indexOf('on GoogleSignInInterrupted'));
    expect(hookBody, contains('referralNotice = googleReferralNotice(status)'));
    expect(hookBody, contains('clearPendingReferralCode()'));
    expect(hookBody, isNot(contains('throw')));
    final after = page.indexOf('_showReferralErrorMessage(referralNotice!)');
    expect(after, greaterThan(page.indexOf('_ensureGooglePlayerProfileBootstrap()', flowStart)));
  });

  test('without a code the Google sign-in is unchanged (no server step)', () {
    expect(googleFlow, contains('beforeFirebaseSignIn: referralCode.isEmpty\n            ? null'));
    expect(googleAuth, contains('if (beforeFirebaseSignIn != null) {'));
  });
}

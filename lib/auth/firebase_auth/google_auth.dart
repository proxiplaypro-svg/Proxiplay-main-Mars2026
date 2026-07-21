import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

final _googleSignIn = GoogleSignIn(scopes: ['profile', 'email']);

Map<String, String> splitGoogleDisplayName(String displayName) {
  final clean = displayName.trim();

  if (clean.isEmpty) {
    return {'prenom': '', 'nom': ''};
  }

  final parts = clean.split(RegExp(r'\s+'));

  if (parts.length == 1) {
    return {'prenom': parts.first, 'nom': ''};
  }

  return {
    'prenom': parts.first,
    'nom': parts.sublist(1).join(' '),
  };
}

Future<UserCredential?> googleSignInFunc() async {
  try {
    if (kIsWeb) {
      return await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    }

    await signOutWithGoogle().catchError((_, __) => null);
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      if (kDebugMode) {
        debugPrint('GOOGLE FIREBASE AUTH: user cancelled Google sign-in');
      }
      return null;
    }

    final googleAuth = await googleUser.authentication;

    if (googleAuth.accessToken == null && googleAuth.idToken == null) {
      debugPrint('GOOGLE FIREBASE AUTH ERROR: missing Google tokens');
      return null;
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return await FirebaseAuth.instance.signInWithCredential(credential);
  } catch (e, stack) {
    debugPrint('GOOGLE FIREBASE AUTH ERROR: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stack);
    }
    return null;
  }
}

Future signOutWithGoogle() => _googleSignIn.signOut();

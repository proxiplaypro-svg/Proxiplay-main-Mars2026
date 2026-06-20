import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

const _googleScopes = <String>['profile', 'email'];
final _googleSignIn = GoogleSignIn.instance;
Future<void>? _googleSignInInitialization;

Future<void> _ensureGoogleSignInInitialized() {
  return _googleSignInInitialization ??= _googleSignIn.initialize();
}

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

Future<void> _ensureFirestoreUserDoc(UserCredential userCredential) async {
  final firebaseUser = userCredential.user;
  if (firebaseUser == null) {
    if (kDebugMode) {
      debugPrint('GOOGLE AUTH OK BUT FIREBASE USER NULL');
    }
    return;
  }

  final uid = firebaseUser.uid;
  final email = firebaseUser.email;
  final displayName = firebaseUser.displayName ?? '';
  final photoURL = firebaseUser.photoURL ?? '';
  final splitName = splitGoogleDisplayName(displayName);
  final prenom = splitName['prenom'] ?? '';
  final nom = splitName['nom'] ?? '';
  final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);

  try {
    final userDocSnapshot = await userDocRef.get();
    final existingData = userDocSnapshot.data();
    final existingFirstName = (existingData?['first_name'] as String?) ?? '';
    final existingLastName = (existingData?['last_name'] as String?) ?? '';
    final existingDisplayName = (existingData?['display_name'] as String?) ?? '';
    final existingEmail = (existingData?['email'] as String?) ?? '';
    final existingPhotoUrl = (existingData?['photo_url'] as String?) ?? '';
    final baseData = <String, dynamic>{
      'uid': uid,
      'user_role': 'joueur',
      'account_status': 'active',
      'last_login_time': FieldValue.serverTimestamp(),
    };
    if (existingEmail.trim().isEmpty && (email ?? '').trim().isNotEmpty) {
      baseData['email'] = email;
    }
    if (existingDisplayName.trim().isEmpty && displayName.trim().isNotEmpty) {
      baseData['display_name'] = displayName;
    }
    if (existingPhotoUrl.trim().isEmpty && photoURL.trim().isNotEmpty) {
      baseData['photo_url'] = photoURL;
    }
    if (existingFirstName.trim().isEmpty && prenom.trim().isNotEmpty) {
      baseData['first_name'] = prenom;
    }
    if (existingLastName.trim().isEmpty && nom.trim().isNotEmpty) {
      baseData['last_name'] = nom;
    }

    if (userDocSnapshot.exists) {
      await userDocRef.set(baseData, SetOptions(merge: true));
    } else {
      await userDocRef.set(
        <String, dynamic>{
          ...baseData,
          'created_time': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  } on FirebaseException catch (e) {
    debugPrint('FIRESTORE USER DOC WRITE ERROR: code=${e.code}');
  } catch (e, stack) {
    debugPrint('FIRESTORE USER DOC ERROR: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stack);
    }
  }
}

Future<UserCredential?> googleSignInFunc() async {
  try {
    if (kIsWeb) {
      final userCredential =
          await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      await _ensureFirestoreUserDoc(userCredential);
      return userCredential;
    }

    await _ensureGoogleSignInInitialized();
    await signOutWithGoogle().catchError((_, __) => null);
    final googleUser = await _googleSignIn.authenticate(
      scopeHint: _googleScopes,
    );

    final googleAuth = googleUser.authentication;

    if (googleAuth.idToken == null) {
      debugPrint('GOOGLE FIREBASE AUTH ERROR: missing Google tokens');
      return null;
    }

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    await _ensureFirestoreUserDoc(userCredential);
    return userCredential;
  } on GoogleSignInException catch (e, stack) {
    if (e.code == GoogleSignInExceptionCode.canceled ||
        e.code == GoogleSignInExceptionCode.interrupted) {
      if (kDebugMode) {
        debugPrint('GOOGLE FIREBASE AUTH: user cancelled Google sign-in');
      }
      return null;
    }
    debugPrint('GOOGLE FIREBASE AUTH ERROR: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stack);
    }
    return null;
  } catch (e, stack) {
    debugPrint('GOOGLE FIREBASE AUTH ERROR: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stack);
    }
    return null;
  }
}

Future signOutWithGoogle() async {
  await _ensureGoogleSignInInitialized();
  return _googleSignIn.signOut();
}

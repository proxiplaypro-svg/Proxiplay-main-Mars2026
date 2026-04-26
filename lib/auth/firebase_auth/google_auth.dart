import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

Future<void> _ensureFirestoreUserDoc(UserCredential userCredential) async {
  print('_ensureFirestoreUserDoc STARTED');
  final firebaseUser = userCredential.user;
  if (firebaseUser == null) {
    print('GOOGLE AUTH OK BUT FIREBASE USER NULL');
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

  print('GOOGLE displayName: $displayName');
  print('PREFILL prenom: $prenom');
  print('PREFILL nom: $nom');
  print('GOOGLE FIREBASE USER UID: $uid');
  print('CHECKING FIRESTORE USER DOC');

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
      print('MERGING FIRESTORE USER DOC');
      print('WRITING FIRESTORE USER DOC path=users/$uid');
      await userDocRef.set(baseData, SetOptions(merge: true));
      print('FIRESTORE WRITE SUCCESS path=users/$uid');
    } else {
      print('CREATING FIRESTORE USER DOC');
      print('WRITING FIRESTORE USER DOC path=users/$uid');
      await userDocRef.set(
        <String, dynamic>{
          ...baseData,
          'created_time': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      print('FIRESTORE WRITE SUCCESS path=users/$uid');
    }

    print('FIRESTORE USER DOC READY');
  } on FirebaseException catch (e) {
    print('FIRESTORE USER DOC WRITE ERROR');
    print('code=${e.code}');
    print('message=${e.message}');
    print('path=users/$uid');
    print('authUid=${FirebaseAuth.instance.currentUser?.uid}');
    print('FIRESTORE USER DOC ERROR: $e');
  } catch (e, stack) {
    print('FIRESTORE USER DOC ERROR: $e');
    print(stack);
  }
}

Future<UserCredential?> googleSignInFunc() async {
  try {
    final firebaseOptions = Firebase.app().options;
    print(
      'GOOGLE FIREBASE AUTH projectId=${firebaseOptions.projectId} '
      'appId=${firebaseOptions.appId}',
    );

    if (kIsWeb) {
      print('GOOGLE FIREBASE AUTH STEP 1: open Google');
      print(
        'GOOGLE FIREBASE AUTH STEP 4: calling FirebaseAuth.signInWithCredential '
        '(via signInWithPopup on web)',
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      print('AFTER SIGN IN WITH CREDENTIAL');
      print('USER CREDENTIAL UID: ${userCredential.user?.uid}');
      print(
        'GOOGLE FIREBASE AUTH STEP 5: Firebase result '
        'currentUserUid=${FirebaseAuth.instance.currentUser?.uid} '
        'currentUserEmail=${FirebaseAuth.instance.currentUser?.email} '
        'userCredentialUid=${userCredential.user?.uid} '
        'userCredentialEmail=${userCredential.user?.email}',
      );
      print('CALLING _ensureFirestoreUserDoc');
      await _ensureFirestoreUserDoc(userCredential);
      print('_ensureFirestoreUserDoc FINISHED');
      return userCredential;
    }

    await signOutWithGoogle().catchError((_, __) => null);
    print('GOOGLE FIREBASE AUTH STEP 1: open Google');
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      print('GOOGLE FIREBASE AUTH: user cancelled Google sign-in');
      return null;
    }

    print(
      'GOOGLE FIREBASE AUTH STEP 2: selected Google account='
      '${googleUser.email}',
    );

    final googleAuth = await googleUser.authentication;
    print(
      'GOOGLE FIREBASE AUTH STEP 3: tokens received '
      'accessTokenPresent=${googleAuth.accessToken != null} '
      'idTokenPresent=${googleAuth.idToken != null}',
    );

    if (googleAuth.accessToken == null && googleAuth.idToken == null) {
      print('GOOGLE FIREBASE AUTH ERROR: missing Google tokens');
      return null;
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    print('GOOGLE FIREBASE AUTH STEP 4: credential created');

    print('GOOGLE FIREBASE AUTH STEP 5: calling FirebaseAuth.signInWithCredential');
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    print('AFTER SIGN IN WITH CREDENTIAL');
    print('USER CREDENTIAL UID: ${userCredential.user?.uid}');
    print(
      'GOOGLE FIREBASE AUTH STEP 6: Firebase result '
      'currentUserUid=${FirebaseAuth.instance.currentUser?.uid} '
      'currentUserEmail=${FirebaseAuth.instance.currentUser?.email} '
      'userCredentialUid=${userCredential.user?.uid} '
      'userCredentialEmail=${userCredential.user?.email}',
    );
    print('CALLING _ensureFirestoreUserDoc');
    await _ensureFirestoreUserDoc(userCredential);
    print('_ensureFirestoreUserDoc FINISHED');
    return userCredential;
  } catch (e, stack) {
    print('GOOGLE FIREBASE AUTH ERROR: $e');
    print(stack);
    return null;
  }
}

Future signOutWithGoogle() => _googleSignIn.signOut();

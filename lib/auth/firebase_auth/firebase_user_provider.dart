import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

import '../base_auth_user_provider.dart';
import '../../app_state.dart';

export '../base_auth_user_provider.dart';

class ProxiPlayFirebaseUser extends BaseAuthUser {
  ProxiPlayFirebaseUser(this.user);
  User? user;
  @override
  bool get loggedIn => user != null;

  @override
  AuthUserInfo get authUserInfo => AuthUserInfo(
        uid: user?.uid,
        email: user?.email,
        displayName: user?.displayName,
        photoUrl: user?.photoURL,
        phoneNumber: user?.phoneNumber,
      );

  @override
  Future? delete() => user?.delete();

  @override
  Future? updateEmail(String email) async {
    await user?.verifyBeforeUpdateEmail(email);
  }

  @override
  Future? updatePassword(String newPassword) async {
    await user?.updatePassword(newPassword);
  }

  @override
  Future? sendEmailVerification() => user?.sendEmailVerification();

  @override
  bool get emailVerified {
    // Reloads the user when checking in order to get the most up to date
    // email verified status.
    if (loggedIn && !user!.emailVerified) {
      refreshUser();
    }
    return user?.emailVerified ?? false;
  }

  @override
  Future refreshUser() async {
    await FirebaseAuth.instance.currentUser
        ?.reload()
        .then((_) => user = FirebaseAuth.instance.currentUser);
  }

  static BaseAuthUser fromUserCredential(UserCredential userCredential) =>
      fromFirebaseUser(userCredential.user);
  static BaseAuthUser fromFirebaseUser(User? user) =>
      ProxiPlayFirebaseUser(user);
}

Stream<BaseAuthUser> proxiPlayFirebaseUserStream() => FirebaseAuth.instance
        .authStateChanges()
        // Always debounce null user events a bit to prevent transient auth flicker
        // (which can cause GoRouter to redirect to /loginPage and bounce back).
        .debounce((user) => user == null
            ? TimerStream(true, const Duration(seconds: 1))
            : Stream.value(user))
        .map<BaseAuthUser>(
      (user) {
        currentUser = user == null && FFAppState().isGuest
            ? GuestAuthUser()
            : ProxiPlayFirebaseUser(user);
        return currentUser!;
      },
    );

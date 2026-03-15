class AuthUserInfo {
  const AuthUserInfo({
    this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
  });

  final String? uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? phoneNumber;
}

abstract class BaseAuthUser {
  bool get loggedIn;
  bool get emailVerified;

  AuthUserInfo get authUserInfo;

  Future? delete();
  Future? updateEmail(String email);
  Future? updatePassword(String newPassword);
  Future? sendEmailVerification();
  Future refreshUser() async {}

  String? get uid => authUserInfo.uid;
  String? get email => authUserInfo.email;
  String? get displayName => authUserInfo.displayName;
  String? get photoUrl => authUserInfo.photoUrl;
  String? get phoneNumber => authUserInfo.phoneNumber;
}

class GuestAuthUser extends BaseAuthUser {
  GuestAuthUser();

  @override
  bool get loggedIn => true;

  @override
  bool get emailVerified => false;

  @override
  AuthUserInfo get authUserInfo => const AuthUserInfo();

  @override
  Future delete() =>
      Future.error(UnimplementedError('Guest user cannot be deleted'));

  @override
  Future sendEmailVerification() => Future.error(
      UnimplementedError('Guest user cannot send email verification'));

  @override
  Future updateEmail(String email) =>
      Future.error(UnimplementedError('Guest user cannot update email'));

  @override
  Future updatePassword(String newPassword) =>
      Future.error(UnimplementedError('Guest user cannot update password'));
}

BaseAuthUser? currentUser;
bool get loggedIn => currentUser?.loggedIn ?? false;

// Detaching this device from an account that signs out (24/10/2026 Samsung
// finding: after a sign-out the device token stayed attached to the previous
// account, so a push meant for that account - a referral reward for the
// inviter - showed up during the signup of another account on the same
// phone). Pure logic with injected dependencies, tested in
// test/fcm_device_detach_test.dart; wired in FirebaseAuthManager.signOut().
import 'dart:async';
import 'dart:convert';

/// Pending detach kept on the device when a sign-out could not finish it
/// (offline, timeout): retried at the next app start, before any token is
/// registered again.
const String kPendingFcmDetachKey = 'ff_pendingFcmDetach';

/// True while a sign-out detaches this device: no token may be registered
/// meanwhile (a token refresh would otherwise re-attach it to the account
/// that is signing out).
bool fcmRegistrationSuspended = false;

/// Whether a token may be registered for [userPath] now: only for the account
/// currently signed in, and never during a sign-out.
bool shouldRegisterFcmToken({
  required String userPath,
  required String? currentUid,
  required bool suspended,
}) {
  if (suspended || currentUid == null || currentUid.isEmpty) {
    return false;
  }
  return userPath == 'users/$currentUid';
}

class FcmDetachDeps {
  const FcmDetachDeps({
    required this.readToken,
    required this.deleteTokenDoc,
    required this.invalidateToken,
    required this.savePending,
    required this.clearPending,
  });

  /// The device token (FirebaseMessaging.getToken()).
  final Future<String?> Function() readToken;

  /// Deletes users/{uid}/fcm_tokens/{token} (allowed to the owner only).
  final Future<void> Function(String userPath, String token) deleteTokenDoc;

  /// FirebaseMessaging.deleteToken(): the token stops receiving messages.
  final Future<void> Function() invalidateToken;
  final Future<void> Function(String value) savePending;
  final Future<void> Function() clearPending;
}

class FcmDetachResult {
  const FcmDetachResult({required this.docDeleted, required this.invalidated});
  final bool docDeleted;
  final bool invalidated;
  bool get complete => invalidated;
}

Future<bool> _attempt(Future<void> Function() step, Duration timeout) async {
  try {
    await step().timeout(timeout);
    return true;
  } catch (_) {
    return false;
  }
}

/// Detaches this device from the account [userPath] before it signs out:
/// only this device's token document is deleted (other devices of the account
/// keep theirs), then the local token is invalidated. Never throws and never
/// waits more than a few seconds per step: the sign-out always proceeds. If
/// the token could not be invalidated, the detach is kept pending on the
/// device and retried by [retryPendingFcmDetach] at the next start.
Future<FcmDetachResult> detachDeviceFromAccount({
  required String? userPath,
  required FcmDetachDeps deps,
  Duration timeout = const Duration(seconds: 4),
}) async {
  String? token;
  try {
    token = await deps.readToken().timeout(timeout);
  } catch (_) {
    token = null;
  }
  final hasToken = token != null && token.isNotEmpty;
  if (hasToken && userPath != null && userPath.isNotEmpty) {
    await _attempt(
        () => deps.savePending(jsonEncode({'path': userPath, 'token': token})),
        timeout);
  }
  final docDeleted = hasToken && userPath != null && userPath.isNotEmpty
      ? await _attempt(() => deps.deleteTokenDoc(userPath, token!), timeout)
      : false;
  final invalidated = await _attempt(deps.invalidateToken, timeout);
  if (invalidated) {
    await _attempt(deps.clearPending, timeout);
  }
  return FcmDetachResult(docDeleted: docDeleted, invalidated: invalidated);
}

/// At app start, before any token registration: finishes a detach that a
/// previous sign-out left incomplete. The token is invalidated (that alone
/// stops the previous account's messages; the server then discards the dead
/// token), and its document is deleted only if that account is the one
/// signed in again. Never throws.
Future<bool> retryPendingFcmDetach({
  required String? pending,
  required String? currentUid,
  required FcmDetachDeps deps,
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (pending == null || pending.isEmpty) {
    return false;
  }
  String? path;
  String? token;
  try {
    final data = jsonDecode(pending) as Map<String, dynamic>;
    path = data['path'] as String?;
    token = data['token'] as String?;
  } catch (_) {
    await _attempt(deps.clearPending, timeout);
    return false;
  }
  if (path != null && token != null && currentUid != null && path == 'users/$currentUid') {
    await _attempt(() => deps.deleteTokenDoc(path!, token!), timeout);
  }
  String? current;
  try {
    current = await deps.readToken().timeout(timeout);
  } catch (_) {
    current = null;
  }
  // The pending token was already replaced: nothing left to invalidate.
  final invalidated = current != token || await _attempt(deps.invalidateToken, timeout);
  if (invalidated) {
    await _attempt(deps.clearPending, timeout);
  }
  return invalidated;
}

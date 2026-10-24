import 'dart:io' show Platform;

import '../../auth/firebase_auth/auth_util.dart';
import '../cloud_functions/cloud_functions.dart';

import 'package:flutter/foundation.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/config/firebase_environment.dart';
import 'fcm_device_detach.dart';

export 'push_notifications_handler.dart';
export 'serialization_util.dart';

class UserTokenInfo {
  const UserTokenInfo(this.userPath, this.fcmToken);
  final String userPath;
  final String fcmToken;
}

bool _isPushAuthorizationGranted(AuthorizationStatus status) {
  return status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional ||
      status.name == 'ephemeral';
}

Future<String?> _getFcmTokenAfterPermission() async {
  final settings = await FirebaseMessaging.instance.requestPermission();
  if (!_isPushAuthorizationGranted(settings.authorizationStatus)) {
    return null;
  }

  if (!kIsWeb && Platform.isIOS) {
    for (var attempt = 0; attempt < 6; attempt++) {
      final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  return FirebaseMessaging.instance.getToken();
}

Stream<UserTokenInfo> getFcmTokenStream(String userPath) =>
    Stream.value(!kIsWeb && (Platform.isIOS || Platform.isAndroid))
        .where((shouldGetToken) => shouldGetToken)
        .asyncMap<String?>((_) => _getFcmTokenAfterPermission())
        .switchMap((fcmToken) =>
            Stream.value(fcmToken).merge(FirebaseMessaging.instance.onTokenRefresh))
        .where((fcmToken) => fcmToken != null && fcmToken.isNotEmpty)
        .map((token) => UserTokenInfo(userPath, token!));

/// Push notifications are handled on Android and iOS only, outside the local
/// emulators.
bool isFcmEnabledOnThisDevice() =>
    !kIsWeb &&
    (Platform.isIOS || Platform.isAndroid) &&
    !FirebaseEnvironment.isLocalEmulatorMode;

FcmDetachDeps defaultFcmDetachDeps() => FcmDetachDeps(
      readToken: () => FirebaseMessaging.instance.getToken(),
      deleteTokenDoc: (userPath, token) => FirebaseFirestore.instance
          .doc(userPath)
          .collection('fcm_tokens')
          .doc(token)
          .delete(),
      invalidateToken: () => FirebaseMessaging.instance.deleteToken(),
      savePending: (value) async =>
          (await SharedPreferences.getInstance())
              .setString(kPendingFcmDetachKey, value),
      clearPending: () async =>
          (await SharedPreferences.getInstance()).remove(kPendingFcmDetachKey),
    );

/// Finishes, at app start, a device detach that a sign-out left incomplete.
Future<void> retryPendingFcmDetachOnStart() async {
  if (!isFcmEnabledOnThisDevice()) {
    return;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await retryPendingFcmDetach(
      pending: prefs.getString(kPendingFcmDetachKey),
      currentUid: FirebaseAuth.instance.currentUser?.uid,
      deps: defaultFcmDetachDeps(),
    );
  } catch (_) {}
}

// The token of this device is registered for the signed-in account only:
// a sign-out ends the subscription (token refreshes included), and a
// registration is skipped during a sign-out or for another account.
final fcmTokenUserStream = authenticatedUserStream
    .map((user) => user?.reference.path)
    .distinct()
    .switchMap((userPath) => userPath == null
        ? Stream<UserTokenInfo>.empty()
        : getFcmTokenStream(userPath))
    .where((userTokenInfo) => shouldRegisterFcmToken(
          userPath: userTokenInfo.userPath,
          currentUid: FirebaseAuth.instance.currentUser?.uid,
          suspended: fcmRegistrationSuspended,
        ))
    .asyncMap(
      (userTokenInfo) async {
        final res = await makeCloudCall(
          'addFcmToken',
          {
            'userDocPath': userTokenInfo.userPath,
            'fcmToken': userTokenInfo.fcmToken,
            'deviceType': Platform.isIOS ? 'iOS' : 'Android',
          },
        );
        return res;
      },
    );

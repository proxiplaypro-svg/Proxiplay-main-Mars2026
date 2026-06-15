import 'dart:io' show Platform;

import '../../auth/firebase_auth/auth_util.dart';
import '../cloud_functions/cloud_functions.dart';

import 'package:flutter/foundation.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

final fcmTokenUserStream = authenticatedUserStream
    .where((user) => user != null)
    .map((user) => user!.reference.path)
    .distinct()
    .switchMap(getFcmTokenStream)
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

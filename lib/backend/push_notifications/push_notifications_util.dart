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

Stream<UserTokenInfo> getFcmTokenStream(String userPath) =>
    Stream.value(!kIsWeb && (Platform.isIOS || Platform.isAndroid))
        .where((shouldGetToken) {
          print('FCM: shouldGetToken = $shouldGetToken');
          return shouldGetToken;
        })
        .asyncMap<String?>(
            (_) => FirebaseMessaging.instance.requestPermission().then(
                  (settings) {
                    print('FCM: notification permission status = ${settings.authorizationStatus}');
                    return settings.authorizationStatus ==
                            AuthorizationStatus.authorized
                        ? FirebaseMessaging.instance.getToken()
                        : null;
                  },
                ))
        .switchMap((fcmToken) {
          print('FCM: got token = ${fcmToken?.substring(0, 20) ?? "null"}...');
          return Stream.value(fcmToken)
              .merge(FirebaseMessaging.instance.onTokenRefresh);
        })
        .where((fcmToken) => fcmToken != null && fcmToken.isNotEmpty)
        .map((token) => UserTokenInfo(userPath, token!));

final fcmTokenUserStream = authenticatedUserStream
    .where((user) => user != null)
    .map((user) {
      print('FCM: user authenticated, path = ${user!.reference.path}');
      return user.reference.path;
    })
    .distinct()
    .switchMap(getFcmTokenStream)
    .asyncMap(
      (userTokenInfo) async {
        print('FCM: saving token for ${userTokenInfo.userPath}');
        final res = await makeCloudCall(
          'addFcmToken',
          {
            'userDocPath': userTokenInfo.userPath,
            'fcmToken': userTokenInfo.fcmToken,
            'deviceType': Platform.isIOS ? 'iOS' : 'Android',
          },
        );
        print('FCM: addFcmToken result = $res');
        return res;
      },
    );

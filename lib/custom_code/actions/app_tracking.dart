// Automatic FlutterFlow imports
// Imports other custom actions
// Imports custom functions
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

Future appTracking() async {
  // Add your function code here!
  if (kIsWeb) {
    debugPrint('Skipping app tracking in web environment.');
    return;
  }

  if (Platform.isIOS) {
    final TrackingStatus status =
        await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await Future.delayed(const Duration(milliseconds: 200));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
    await AppTrackingTransparency.getAdvertisingIdentifier();
  }
}

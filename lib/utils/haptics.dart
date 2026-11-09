import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<void> triggerLightHaptic() async {
  await HapticFeedback.lightImpact();
}

/// One short, clearly perceptible confirmation when an instant prize or a
/// server-confirmed bonus is revealed. Flutter maps this to Android's
/// `CONFIRM` feedback on API 30+ and to iOS's native success notification.
/// No permission is required; the phone's own haptic setting still applies.
Future<void> triggerWinHaptic() async {
  try {
    if (kDebugMode) {
      debugPrint('[WIN_HAPTIC_TRACE] event=success_notification_requested');
    }
    await HapticFeedback.successNotification();
    if (kDebugMode) {
      debugPrint('[WIN_HAPTIC_TRACE] event=success_notification_completed');
    }
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
          '[WIN_HAPTIC_TRACE] event=pulse_failed errorType=${error.runtimeType}');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<void> triggerLightHaptic() async {
  await HapticFeedback.lightImpact();
}

/// Gap between the two pulses of [triggerWinHaptic].
const Duration kWinHapticGap = Duration(milliseconds: 120);

/// Two short pulses when a won instant prize is revealed. Native haptics: no
/// permission, the phone's own setting applies (silent when disabled or not
/// supported). Never throws, and uses no BuildContext: leaving the screen
/// during the pulses is harmless.
Future<void> triggerWinHaptic({Duration gap = kWinHapticGap}) async {
  try {
    if (kDebugMode) {
      debugPrint('[WIN_HAPTIC_TRACE] event=first_pulse_requested');
    }
    await HapticFeedback.mediumImpact();
    if (kDebugMode) {
      debugPrint('[WIN_HAPTIC_TRACE] event=first_pulse_completed');
    }
    await Future<void>.delayed(gap);
    if (kDebugMode) {
      debugPrint(
          '[WIN_HAPTIC_TRACE] event=second_pulse_requested gapMs=${gap.inMilliseconds}');
    }
    await HapticFeedback.mediumImpact();
    if (kDebugMode) {
      debugPrint('[WIN_HAPTIC_TRACE] event=second_pulse_completed');
    }
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
          '[WIN_HAPTIC_TRACE] event=pulse_failed errorType=${error.runtimeType}');
    }
  }
}

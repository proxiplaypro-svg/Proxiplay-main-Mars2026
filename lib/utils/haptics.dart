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
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(gap);
    await HapticFeedback.mediumImpact();
  } catch (_) {}
}

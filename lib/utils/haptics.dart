import 'package:flutter/services.dart';

Future<void> triggerLightHaptic() async {
  await HapticFeedback.lightImpact();
}

import 'package:flutter/foundation.dart';

class PerfTrace {
  PerfTrace._();

  static final Stopwatch _sw = Stopwatch()..start();

  static void log(
    String label, {
    int? itemCount,
  }) {
    if (!kDebugMode) return;

    final deltaMs = _sw.elapsedMilliseconds;
    final itemPart = itemCount != null ? ' | items=$itemCount' : '';

    debugPrint('[PERF] $label | +${deltaMs}ms$itemPart');
  }
}

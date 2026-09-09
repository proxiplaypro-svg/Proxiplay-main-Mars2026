/// Read-only view of the authoritative participation response.
class AnimationProgress {
  const AnimationProgress(this.id, this.visitedCount, this.threshold,
      this.thresholdReached, this.newlyQualified);
  final String id;
  final int visitedCount;
  final int threshold;
  final bool thresholdReached;
  final bool newlyQualified;

  static AnimationProgress? fromResponse(dynamic response,
      {bool replay = false}) {
    final data = response is Map ? response['animation'] : null;
    if (data is! Map || data['id'] is! String) return null;
    return AnimationProgress(
      data['id'] as String,
      (data['visitedCount'] as num?)?.toInt() ?? 0,
      (data['threshold'] as num?)?.toInt() ?? 0,
      data['thresholdReached'] == true,
      !replay && data['newlyQualified'] == true,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/backend/animation_progress.dart';

void main() {
  test('server qualification is read without client calculation', () {
    final response = {'animation': {'id': 'a', 'visitedCount': 3,
      'threshold': 3, 'thresholdReached': true, 'newlyQualified': true}};
    final progress = AnimationProgress.fromResponse(response)!;
    expect(progress.id, 'a');
    expect(progress.visitedCount, 3);
    expect(progress.newlyQualified, true);
    expect(AnimationProgress.fromResponse(response, replay: true)!.newlyQualified, false);
    expect(AnimationProgress.fromResponse({}), isNull);
  });
}

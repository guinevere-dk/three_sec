import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/utils/trim_timeline_interaction_policy.dart';

void main() {
  group('trim timeline interaction policy', () {
    test('playhead pointer is disabled over the end trim handle', () {
      expect(
        shouldTrimPlayheadReceivePointer(
          startPercent: 0.0,
          endPercent: 1.0,
          currentPercent: 1.0,
          timelineWidth: 280.0,
        ),
        isFalse,
      );
    });

    test('playhead pointer remains enabled away from trim handles', () {
      expect(
        shouldTrimPlayheadReceivePointer(
          startPercent: 0.0,
          endPercent: 1.0,
          currentPercent: 0.5,
          timelineWidth: 280.0,
        ),
        isTrue,
      );
    });
  });
}

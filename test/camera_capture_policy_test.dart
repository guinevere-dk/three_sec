import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:three_s/utils/camera_capture_policy.dart';

void main() {
  group('camera capture focus policy', () {
    test('normalizes tap points into the camera API coordinate range', () {
      expect(
        normalizeCameraFocusPoint(const Offset(-0.4, 1.4)),
        const Offset(0, 1),
      );
      expect(
        normalizeCameraFocusPoint(const Offset(0.25, 0.75)),
        const Offset(0.25, 0.75),
      );
      expect(kCameraFocusDefaultPoint, const Offset(0.5, 0.5));
    });

    test('throttles rapid nearby focus updates', () {
      final first = DateTime(2026, 6, 6, 12);

      expect(
        shouldApplyCameraFocusUpdate(
          now: first,
          lastAppliedAt: null,
          lastAppliedPoint: null,
          requestedPoint: const Offset(0.5, 0.5),
        ),
        isTrue,
      );

      expect(
        shouldApplyCameraFocusUpdate(
          now: first.add(const Duration(milliseconds: 150)),
          lastAppliedAt: first,
          lastAppliedPoint: const Offset(0.5, 0.5),
          requestedPoint: const Offset(0.53, 0.54),
        ),
        isFalse,
      );
    });

    test('allows deliberate distant or delayed focus updates', () {
      final first = DateTime(2026, 6, 6, 12);

      expect(
        shouldApplyCameraFocusUpdate(
          now: first.add(const Duration(milliseconds: 150)),
          lastAppliedAt: first,
          lastAppliedPoint: const Offset(0.2, 0.2),
          requestedPoint: const Offset(0.8, 0.8),
        ),
        isTrue,
      );

      expect(
        shouldApplyCameraFocusUpdate(
          now: first.add(
            kCameraFocusMinInterval + const Duration(milliseconds: 1),
          ),
          lastAppliedAt: first,
          lastAppliedPoint: const Offset(0.5, 0.5),
          requestedPoint: const Offset(0.52, 0.5),
        ),
        isTrue,
      );
    });

    test(
      'skips focus updates while a previous camera request is in flight',
      () {
        final now = DateTime(2026, 6, 6, 12);

        expect(
          shouldSkipCameraFocusUpdate(
            isFocusUpdateInFlight: true,
            now: now,
            lastAppliedAt: now.subtract(const Duration(seconds: 10)),
            lastAppliedPoint: const Offset(0.2, 0.2),
            requestedPoint: const Offset(0.8, 0.8),
          ),
          isTrue,
        );
        expect(
          shouldSkipCameraFocusUpdate(
            isFocusUpdateInFlight: false,
            now: now,
            lastAppliedAt: now.subtract(const Duration(seconds: 10)),
            lastAppliedPoint: const Offset(0.2, 0.2),
            requestedPoint: const Offset(0.8, 0.8),
          ),
          isFalse,
        );
      },
    );

    test('chooses the strongest supported video stabilization mode', () {
      expect(
        preferredVideoStabilizationMode(const {
          VideoStabilizationMode.off,
          VideoStabilizationMode.level1,
          VideoStabilizationMode.level3,
        }),
        VideoStabilizationMode.level3,
      );
      expect(
        preferredVideoStabilizationMode(const {
          VideoStabilizationMode.off,
          VideoStabilizationMode.level2,
        }),
        VideoStabilizationMode.level2,
      );
      expect(
        preferredVideoStabilizationMode(const {VideoStabilizationMode.off}),
        VideoStabilizationMode.off,
      );
    });
  });
}

import 'package:flutter/widgets.dart';

import 'package:camera/camera.dart';

const Offset kCameraFocusDefaultPoint = Offset(0.5, 0.5);
const Duration kCameraFocusMinInterval = Duration(milliseconds: 800);
const double kCameraFocusMinDistance = 0.12;

Offset normalizeCameraFocusPoint(Offset raw) {
  return Offset(
    raw.dx.clamp(0.0, 1.0).toDouble(),
    raw.dy.clamp(0.0, 1.0).toDouble(),
  );
}

bool shouldApplyCameraFocusUpdate({
  required DateTime now,
  required DateTime? lastAppliedAt,
  required Offset? lastAppliedPoint,
  required Offset requestedPoint,
}) {
  if (lastAppliedAt == null || lastAppliedPoint == null) return true;

  final elapsed = now.difference(lastAppliedAt);
  if (elapsed >= kCameraFocusMinInterval) return true;

  final normalizedRequested = normalizeCameraFocusPoint(requestedPoint);
  final normalizedLast = normalizeCameraFocusPoint(lastAppliedPoint);
  return (normalizedRequested - normalizedLast).distance >=
      kCameraFocusMinDistance;
}

bool shouldSkipCameraFocusUpdate({
  required bool isFocusUpdateInFlight,
  required DateTime now,
  required DateTime? lastAppliedAt,
  required Offset? lastAppliedPoint,
  required Offset requestedPoint,
}) {
  return isFocusUpdateInFlight ||
      !shouldApplyCameraFocusUpdate(
        now: now,
        lastAppliedAt: lastAppliedAt,
        lastAppliedPoint: lastAppliedPoint,
        requestedPoint: requestedPoint,
      );
}

VideoStabilizationMode preferredVideoStabilizationMode(
  Iterable<VideoStabilizationMode> supportedModes,
) {
  final supported = supportedModes.toSet();
  for (final mode in const [
    VideoStabilizationMode.level3,
    VideoStabilizationMode.level2,
    VideoStabilizationMode.level1,
  ]) {
    if (supported.contains(mode)) return mode;
  }
  return VideoStabilizationMode.off;
}

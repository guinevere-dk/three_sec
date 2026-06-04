import 'dart:math' as math;

const double kTrimTimelineHandleHitWidth = 24.0;
const double kTrimTimelinePlayheadHitWidth = 28.0;

bool shouldTrimPlayheadReceivePointer({
  required double startPercent,
  required double endPercent,
  required double currentPercent,
  required double timelineWidth,
  double handleHitWidth = kTrimTimelineHandleHitWidth,
  double playheadHitWidth = kTrimTimelinePlayheadHitWidth,
}) {
  if (!timelineWidth.isFinite ||
      timelineWidth <= 0 ||
      !handleHitWidth.isFinite ||
      handleHitWidth <= 0 ||
      !playheadHitWidth.isFinite ||
      playheadHitWidth <= 0) {
    return true;
  }

  final startPx = _clampPercent(startPercent) * timelineWidth;
  final endPx = _clampPercent(endPercent) * timelineWidth;
  final currentPx = _clampPercent(currentPercent) * timelineWidth;
  final overlapDistance = (handleHitWidth + playheadHitWidth) / 2;

  return math.min((currentPx - startPx).abs(), (currentPx - endPx).abs()) >
      overlapDistance;
}

double _clampPercent(double value) {
  if (!value.isFinite) return 0.0;
  return value.clamp(0.0, 1.0).toDouble();
}

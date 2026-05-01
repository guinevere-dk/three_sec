import '../constants/clip_policy.dart';

const int kClipDurationTwoSecondMinMs = kTargetClipMinAcceptableMs;
const int kClipDurationTwoSecondMaxMs = kTargetClipMaxAcceptableMs;

int clipDurationBadgeSeconds(Duration duration) {
  final int totalMs = duration.inMilliseconds;
  if (totalMs <= 0) return 0;

  if (totalMs >= kClipDurationTwoSecondMinMs &&
      totalMs <= kClipDurationTwoSecondMaxMs) {
    return 2;
  }

  return (totalMs ~/ 1000).clamp(0, 999999);
}

String formatClipDurationBadge(Duration duration) {
  return '${clipDurationBadgeSeconds(duration)}s';
}

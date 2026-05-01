const int kTargetClipMs = 2100;
const int kTargetClipSecForDisplay = 2;
const int kTargetCaptureSafetyMs = 500;
const int kTargetCaptureMs = kTargetClipMs + kTargetCaptureSafetyMs;
const int kTargetCaptureMinMs = kTargetClipMs + 100;
const int kNearTargetClipMinMs = 2030;
const int kTargetClipMetadataToleranceMs = 10;
const int kTargetClipSaveFrames = 63;
const int kTargetClipSaveFps = 30;
const int kTargetClipSaveMs =
    ((kTargetClipSaveFrames * 1000) + (kTargetClipSaveFps - 1)) ~/
    kTargetClipSaveFps;

const int kTargetClipMinAcceptableMs =
    kTargetClipMs - kTargetClipMetadataToleranceMs;
const int kTargetClipMaxAcceptableMs =
    kTargetClipMs + kTargetClipMetadataToleranceMs;
const int kClipSaveMinExclusiveMs = 2000;

bool isClipDurationWithinTargetContract(int? durationMs) {
  if (durationMs == null) return false;
  return durationMs >= kTargetClipMinAcceptableMs &&
      durationMs <= kTargetClipMaxAcceptableMs;
}

bool isClipDurationAcceptableForSave(int? durationMs) {
  if (durationMs == null) return false;
  return durationMs > kClipSaveMinExclusiveMs;
}

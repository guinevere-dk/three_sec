const int kTargetClipMs = 2000;
const int kTargetClipSecForDisplay = 2;
const int kTargetCaptureSafetyMs = 400;
const int kTargetCaptureMs = kTargetClipMs + kTargetCaptureSafetyMs;
const int kTargetClipSaveFrames = 61;
const int kTargetClipSaveFps = 30;
const int kTargetClipSaveMs =
    ((kTargetClipSaveFrames * 1000) + (kTargetClipSaveFps - 1)) ~/
    kTargetClipSaveFps;


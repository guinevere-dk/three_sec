# MOA 2.1.6 Release Report

## Scope

- Version: `2.1.6+216`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% requested explicitly by the user for this hotfix

## App Update Policy

- `latestVersion` changed to `2.1.6`.
- `latestVersionCode` changed to `216`.
- `minimumRequiredVersion` remains `1.3.6`.
- No forced-update expansion was made for `2.1.6`; clients below `1.3.6` remain the forced-update floor.

## QA Evidence

- `dart format lib/screens/video_edit_screen.dart lib/services/app_update_service.dart test/app_update_service_test.dart` passed.
- `flutter analyze lib/screens/video_edit_screen.dart lib/services/app_update_service.dart test/app_update_service_test.dart` passed.
- `flutter test` passed.
- `flutter build appbundle --release` passed.
- Play API `validate-only` passed for versionCode `216` before commit.
- Play API commit succeeded for production release `MOA 2.1.6 (216)`.

## UI Verification Evidence

Final emulator verification before release covered:

- VideoEditScreen opened.
- CLIP playback loop and boundary behavior.
- ALL playback across clips.
- `clip.endTime == 0` fallback behavior.
- Play overlay tap starts playback correctly.
- Brightness panel auto playback and loop.
- Filter/color panel auto playback and loop.
- Trim playhead remains stable after drag release.
- Logcat check found no `FATAL EXCEPTION`, `FlutterError`, `RangeError`, or `LateInitializationError`.

## Release Tool Safety

After review, `tools/google_play_release.py` requires both:

- `--confirm-production`
- `--confirm-full-production`

for future 100% production releases.

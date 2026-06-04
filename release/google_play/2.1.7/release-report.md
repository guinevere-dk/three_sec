# MOA 2.1.7 Release Report

## Scope

- Version: `2.1.7+217`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% requested explicitly by the user for this hotfix

## App Update Policy

- `latestVersion` changed to `2.1.7`.
- `latestVersionCode` changed to `217`.
- `minimumRequiredVersion` remains `1.3.6`.
- No forced-update expansion was made for `2.1.7`; clients below `1.3.6` remain the forced-update floor.

## Change Summary

- Fixed right Trim handle interaction when it overlaps the playhead hit area.
- Strengthened MOA color filter presets for more visible visual changes.
- Regenerated export LUT assets to match the stronger preset direction.

## QA Evidence

- `flutter pub get` passed without changing `pubspec.lock`.
- `dart format --set-exit-if-changed lib/screens/video_edit_screen.dart lib/utils/color_filter_preset_policy.dart lib/utils/trim_timeline_interaction_policy.dart test/color_filter_preset_policy_test.dart test/trim_timeline_interaction_policy_test.dart` passed.
- `flutter analyze lib/screens/video_edit_screen.dart lib/utils/color_filter_preset_policy.dart lib/utils/trim_timeline_interaction_policy.dart test/color_filter_preset_policy_test.dart test/trim_timeline_interaction_policy_test.dart` passed.
- `flutter analyze` full-repo check exited 1 with 507 existing info-level lints across unrelated files; changed-file analysis was clean.
- `flutter test` passed with 152 tests.
- `flutter build appbundle --release` with auth and update-config dart-defines produced:
  - `build/app/outputs/bundle/release/app-release.aab`
  - `build/app/outputs/mapping/release/mapping.txt`
- Play API `validate-only` passed for production versionCode `217` before commit.
- Play API commit succeeded for production release `MOA 2.1.7 (217)`.
- `firebase deploy --only hosting` completed for `fir-3s-8edb9`.
- Live `https://fir-3s-8edb9.web.app/app-update.json` returned `latestVersion: 2.1.7` and `latestVersionCode: 217`.

## Release Tool Safety

- Production uploads require `--confirm-production`.
- 100% production releases require `--confirm-full-production`.

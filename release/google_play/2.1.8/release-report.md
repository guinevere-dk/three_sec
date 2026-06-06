# MOA 2.1.8 Release Report

## Scope

- Version: `2.1.8+218`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% requested explicitly by the user for this hotfix

## App Update Policy

- `latestVersion` changed to `2.1.8`.
- `latestVersionCode` changed to `218`.
- `minimumRequiredVersion` remains `1.3.6`.
- No forced-update expansion was made for `2.1.8`; clients below `1.3.6` remain the forced-update floor.

## Change Summary

- Fixed Standard plan recordings remaining local instead of completing Cloud upload.
- Fixed same-account Cloud Project visibility on a fresh emulator/device state.
- Stabilized Project default-folder counts when entering and leaving the folder.

## QA Evidence

- `flutter pub get` passed without changing `pubspec.lock`.
- `flutter test test\cloud_upload_preflight_service_test.dart test\video_manager_cloud_sync_regression_test.dart test\video_manager_clip_storage_state_test.dart test\user_status_manager_r3_test.dart` passed with 59 tests.
- `flutter build appbundle --release` with auth and update-config dart-defines produced:
  - `build/app/outputs/bundle/release/app-release.aab` (57.8MB)
  - `build/app/outputs/mapping/release/mapping.txt`
- Play API `validate-only` passed for production versionCode `218`.
- Play API commit succeeded for production release `MOA 2.1.8 (218)` with rollout `1.0`.
- `firebase deploy --only hosting --project fir-3s-8edb9` completed.
- Live `https://fir-3s-8edb9.web.app/app-update.json` returned `latestVersion: 2.1.8` and `latestVersionCode: 218`.

## Release Tool Safety

- Production uploads require `--confirm-production`.
- 100% production releases require `--confirm-full-production`.

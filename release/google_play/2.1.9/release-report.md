# MOA 2.1.9 Release Report

## Scope

- Version: `2.1.9+219`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 5% staged rollout

## App Update Policy

- `latestVersion` changed to `2.1.9`.
- `latestVersionCode` changed to `219`.
- `minimumRequiredVersion` remains `1.3.6`.
- No forced-update expansion was made for `2.1.9`; clients below `1.3.6` remain the forced-update floor.

## Change Summary

- Fixed multi-video, multi-clip media import registration order so selected clips are registered newest segment first within each selected source video.
- Mixed Cloud-only and local Clip library entries by capture/create date instead of grouping them separately.
- Added percent/state feedback while imported clips are extracted and saved.
- Added clip-specific editor filter and brightness persistence/export support.
- Improved camera recording stability by selecting supported video stabilization and smoothing rapid focus changes.

## QA Evidence

- `flutter pub get` passed.
- `flutter analyze` full-repo check exited 1 with 503 info-level lints; `dart analyze --format=machine` returned no `ERROR` or `WARNING` diagnostics.
- `flutter test` passed with 208 tests.
- Android emulator QA verified:
  - multi-video import queue order `3, 2, 1`;
  - per-video clip save order `3-2, 3-1, 2-3, 2-2, 2-1, 1-2, 1-1`;
  - mixed local/cloud library ordering by date.
- `flutter build appbundle --release` with auth and update-config dart-defines produced:
  - `build/app/outputs/bundle/release/app-release.aab` (59MB)
  - `build/app/outputs/mapping/release/mapping.txt` (82MB)
- Play API `validate-only` passed for production versionCode `219` before release commit.
- Play API commit succeeded for production release `MOA 2.1.9 (219)` with rollout `0.05`.
- `firebase deploy --only hosting --project fir-3s-8edb9` completed.
- Live `https://fir-3s-8edb9.web.app/app-update.json` returned `latestVersion: 2.1.9` and `latestVersionCode: 219`.

## Release Tool Safety

- Production uploads require `--confirm-production`.
- 100% production releases require `--confirm-full-production`.

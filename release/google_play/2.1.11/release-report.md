# MOA 2.1.11 Release Report

## Scope

- Version: `2.1.11+221`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% production release

## Change Summary

- Fixed Library folder detail loading so folder tile counts and opened-folder `All` counts use the same final local plus cloud-only clip list.
- Prevented a local-only intermediate publish from making folders briefly show the wrong clip count.
- Added regression coverage for all-source folder publishing and local-only folder publishing.

## App Update Policy

- `latestPublishedVersion` changed to `2.1.11`.
- `latestPublishedBuild` changed to `221`.
- `latestCandidateVersion`, `latestCandidateBuild`, and `candidateStatus` remain cleared after publication.
- `minSupportedBuild` remains `218`.
- `forceUpdateMinBuild` remains `0`; no forced-update expansion was made.

## QA Evidence

- `flutter pub get` passed.
- `flutter test` passed with 220 tests.
- Focused Library/cloud tests passed with 51 tests.
- `dart analyze --format=machine` returned no `ERROR` or `WARNING` diagnostics.
- `flutter analyze lib\managers\video_manager.dart test\video_manager_clip_storage_state_test.dart` exited 1 for existing info-level lints only.
- Android emulator QA verified Library tile count and opened-folder detail count converge after load.
- Play API `validate-only` passed for production versionCode `221`.
- Play API commit succeeded for production release `MOA 2.1.11 (221)` with rollout `1.0`.
- Production track verification returned `MOA 2.1.11 (221)` with `status: completed`.
- User confirmed the update was published on 2026-06-10.

## Release Tool Safety

- Production uploads required `--confirm-production`.
- 100% production release required `--confirm-full-production`.
- App update popup activation was performed only after Play publication was confirmed.

# MOA 2.1.10 Release Report

## Scope

- Version: `2.1.10+220`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% production release

## Change Summary

- Fixed the Library folder detail flow so each folder renders only its own local and cloud-placeholder clips.
- Added stale-load guards so fast folder switching cannot leave a previous folder's clip list visible.
- Updated app-update config parsing so user-visible update prompts are based on Play-published builds, not release candidates.
- Added the `100%출시해라` operating sequence to `RELEASE_RULES.md`.

## App Update Policy

- `latestPublishedVersion` changed to `2.1.10`.
- `latestPublishedBuild` changed to `220`.
- `latestCandidateVersion`, `latestCandidateBuild`, and `candidateStatus` were cleared after publication.
- `minSupportedBuild` remains `218`.
- `forceUpdateMinBuild` remains `0`; no forced-update expansion was made.

## QA Evidence

- `flutter pub get` passed.
- `flutter analyze` exited 1 for existing info-level lints only; `dart analyze --format=machine` returned no `ERROR` or `WARNING` diagnostics.
- `flutter test` passed with 218 tests.
- Android emulator QA verified `일상` and `고덕스테이` Library folders render distinct album-scoped clip lists.
- Play API `validate-only` passed for production versionCode `220`.
- Play API commit succeeded for production release `MOA 2.1.10 (220)` with rollout `1.0`.
- Production track verification returned `MOA 2.1.10 (220)` with `status: completed`.
- User confirmed the update was published on 2026-06-09.

## Release Tool Safety

- Production uploads require `--confirm-production`.
- 100% production releases require `--confirm-full-production`.
- App update popup activation is performed only after Play publication or store reflection is confirmed.

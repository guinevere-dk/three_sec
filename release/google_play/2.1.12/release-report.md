# MOA 2.1.12 Release Report

## Scope

- Version: `2.1.12+222`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% production release

## Change Summary

- Fixed clip count mismatches between Library, album details, and Profile.
- Improved Local, Cloud, and All clip count synchronization inside albums.
- Improved clip save state handling and Library loading stability.

## App Update Policy

- `firebase/hosting/app-update.json` was not updated during review submission.
- `latestPublishedVersion` and `latestPublishedBuild` must stay on the already-published store version until Play approval and store reflection are confirmed.
- No Firebase, package identity, IAP, Storage, Firestore, or SharedPreferences contract was changed for this submission.

## QA Evidence

- `flutter test test\video_manager_clip_storage_state_test.dart test\library_album_detail_loading_state_test.dart` passed with 40 tests before release submission.
- Android emulator QA verified the fixed Library/Profile clip count behavior before release submission, then the emulator was shut down.
- Auth-included release AAB build succeeded for `build\app\outputs\bundle\release\app-release.aab`.
- AAB artifact size at submission: `61,428,428` bytes.
- Play API `validate-only` passed for production versionCode `222`, rollout `1.0`, release `MOA 2.1.12 (222)`.
- Initial Play API commit attempt timed out during AAB upload before commit; the release script HTTP timeout was raised to 300 seconds.
- Play API commit then succeeded for production release `MOA 2.1.12 (222)` with rollout `1.0`; commit edit id `15852879693250313957`.
- Production track verification returned `MOA 2.1.12 (222)` with versionCode `222` and `status: completed`.

## Release Tool Safety

- Production uploads require `--confirm-production`.
- 100% production release requires `--confirm-full-production`.
- The release script now uses an explicit 300-second Google API HTTP timeout for large AAB uploads.
- App update popup activation is deferred until Play approval and store reflection are confirmed.

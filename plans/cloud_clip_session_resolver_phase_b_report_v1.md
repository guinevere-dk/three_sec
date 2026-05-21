# Cloud Clip Session Resolver Phase B Report v1

## 1. Scope

Phase B implemented the first testable unit for Cloud-only clip edit/export support.

This phase does not connect the resolver to the edit screen or export flow yet. It only fixes the contract that later phases will use:

- Keep project `clipPaths` as original `cloud_only://...` placeholders.
- Materialize Cloud-only clips into a session cache path for edit/export engines.
- Keep session cache separate from library raw clip download paths.
- Do not call the cloud-to-device move/finalize path from session materialization.

## 2. Changed Files

- `lib/services/cloud_clip_session_resolver.dart`
  - Added `CloudClipSessionResolver`.
  - Added placeholder parser for `cloud_only://{album}/{videoId}/{fileName}`.
  - Added edit/export session cache path generation.
  - Added result/failure types for invalid placeholder, metadata missing, storage path missing, invalid file size, cache collision, download failure, missing cache file, and cache size mismatch.
  - Added `CloudServiceSessionDownloadClient` adapter that reuses `CloudService.downloadVideo(...)` without calling `markVideoMovedToDevice(...)`.
- `test/cloud_clip_session_resolver_test.dart`
  - Added unit tests for parser, failure reasons, cache path contract, session download success/cache reuse, and download failure modes.

## 3. Contract

Session cache path:

```text
<appDocuments>/cloud_clip_session_cache/<edit_session_cache|export_session_cache>/<safeVideoId>/<safeFileName>
```

Rules:

- Edit and export use separate cache directories.
- Session cache does not write into `vlogs/raw_clips`.
- Existing correct-size cache files are reused.
- Existing wrong-size cache files fail with `cachePathCollision`.
- Downloaded files must exist and match `VideoMetadata.fileSize`.
- `VideoMetadata.storagePath` and positive `fileSize` are required before download.
- Session materialization does not mark the Cloud clip as moved to device.

## 4. QA Result

Commands:

```powershell
dart format lib\services\cloud_clip_session_resolver.dart test\cloud_clip_session_resolver_test.dart
flutter analyze lib\services\cloud_clip_session_resolver.dart test\cloud_clip_session_resolver_test.dart
flutter test test\cloud_clip_session_resolver_test.dart
flutter test test\video_manager_clip_storage_state_test.dart
```

Results:

- `dart format`: passed.
- `flutter analyze` on the new Phase B files: passed with no issues.
- `test/cloud_clip_session_resolver_test.dart`: 12 tests passed.
- `test/video_manager_clip_storage_state_test.dart`: 20 tests passed.

## 5. Not Changed

- Firestore collections and fields were not changed.
- Storage paths and prefixes were not changed.
- IAP product ids were not changed.
- Project JSON and Firestore `clipPaths` contract was not changed.
- Edit preview and export flows were not wired to the resolver yet.

## 6. Remaining Risks

- `CloudService.downloadVideo(...)` still reads Firestore metadata internally and writes the target file. Phase C/D integration must confirm that using it for session cache does not surface library restore copy or status to users.
- Resolver does not yet handle cancellation, progress UI, or TTL cleanup.
- Edit screen still shows `File Missing` for Cloud-only clips until Phase C connects preview loading to this resolver.
- Export still blocks Cloud-only clips until Phase D replaces export preflight with materialized inputs.

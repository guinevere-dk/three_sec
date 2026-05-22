# Cloud Thumbnail Pipeline Phase A Report v1

## Scope

Implemented Phase A: thumbnail metadata read model only.

Not implemented:

- thumbnail generation
- thumbnail Storage upload/download
- Firebase rules/index/schema changes
- migration/backfill
- legacy Cloud clip auto repair
- Storage physical delete
- deploy

No raw uid, local path, Storage path, or file name values were added to logs or reports.

## Changed Files

- `lib/services/cloud_service.dart`
- `lib/services/local_index_service.dart`
- `lib/managers/video_manager.dart`
- `test/cloud_thumbnail_metadata_model_test.dart`
- `test/video_manager_clip_storage_state_test.dart`

## Implementation Summary

### VideoMetadata

Added nullable read-model fields:

- `thumbnailStoragePath`
- `thumbnailStatus`
- `thumbnailWidth`
- `thumbnailHeight`
- `durationMs`

Added compatibility helpers:

- `VideoMetadata.fromMap(...)` for Firestore-compatible map parsing and tests.
- `VideoMetadata.fromFirestore(...)` now delegates to `fromMap`.
- `hasCompletedThumbnail`
- `hasFailedThumbnail`

Legacy Firestore documents without thumbnail fields parse successfully with null metadata.

### LocalIndexEntry

Added nullable persisted fields:

- `thumbnailStoragePath`
- `thumbnailStatus`
- `thumbnailWidth`
- `thumbnailHeight`
- `durationMs`

Existing local index entries remain compatible because missing fields read as null.

### CloudService.getCompletedUserVideos()

Existing completed video read path is preserved:

- still filters by current uid
- still requires `uploadStatus == completed`
- still excludes trash/tombstone
- still requires `storagePath` or `downloadUrl`

When thumbnail fields exist in Firestore data, `VideoMetadata.fromFirestore()` now reads them.

### VideoManager

`syncCloudMetadataToLibrary()` continues to preserve Cloud metadata in `_cloudMetadataByPath` and local index. `_upsertLocalIndexCloudClip()` now writes thumbnail/duration metadata when present.

Added count-only diagnostics:

- `completedCloudCount`
- `thumbnailReadyCount`
- `thumbnailMissingCount`
- `thumbnailFailedCount`
- `fallbackCloudCardCount`

Added helpers:

- `hasCompletedCloudThumbnail(path)`
- `isCloudThumbnailRepairNeeded(path)`
- `getCloudThumbnailDebugCounts(...)`

Cloud-only renderer behavior remains unchanged for missing thumbnails: fallback Cloud card remains active.

## Test Results

Command:

```text
flutter test test\cloud_thumbnail_metadata_model_test.dart test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart test\media_widgets_cloud_only_renderer_test.dart
```

Result: PASS, 22 tests passed.

Covered:

- thumbnail fields present metadata parse
- legacy missing thumbnail fields parse
- local index thumbnail/duration field save/load
- Cloud-only placeholder remains Cloud-only
- thumbnail diagnostics distinguish ready/missing/failed/fallback
- existing transfer action tests still pass
- existing Cloud-only fallback renderer test still passes

## Analyzer

Command:

```text
flutter analyze lib\services\cloud_service.dart lib\services\local_index_service.dart lib\managers\video_manager.dart test\cloud_thumbnail_metadata_model_test.dart test\video_manager_clip_storage_state_test.dart
```

Result: analyzer completed with existing lint debt. It reported pre-existing info-level `avoid_print`, style lints, and an existing unused private method warning in `cloud_service.dart`. No compile errors were reported by tests.

## Data Safety

- No Storage object was created, modified, or deleted.
- No Firestore write/schema/rules/index change was made.
- No local data migration or cleanup was performed.
- Existing Cloud clips without thumbnail metadata remain fallback/repair-needed only.

## Verdict

Phase A implementation: PASS.

Ready for next phase planning: thumbnail generation/upload write path can be designed separately, with local video cleanup gated on thumbnail success.

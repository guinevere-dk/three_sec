# Cloud Clip Thumbnail Pipeline Phase C1 Report v1

## Scope

Implemented Phase C1: Cloud thumbnail loader and local performance cache.

Out of scope:

- Library renderer integration
- Firebase rules/index/schema changes
- migration/backfill
- legacy Cloud clip auto repair
- Storage physical delete
- deploy
- Cloud copy

## Changed Files

- `lib/managers/video_manager.dart`
- `test/video_manager_clip_storage_state_test.dart`

## Implementation Summary

Added `VideoManager.getCloudThumbnail(String path)`.

Behavior:

- returns `null` for non-Cloud-only paths
- reads thumbnail metadata from `_cloudMetadataByPath`
- fetches only when:
  - path is `cloud_only://...`
  - `thumbnailStatus == completed`
  - `thumbnailStoragePath` is present
- checks in-memory cache first
- checks app-private local cache second
- fetches bytes from Firebase Storage on cache miss
- stores fetched bytes in memory and app-private cache
- returns `null` on Storage/cache failure so UI can keep fallback Cloud card

Local cache:

- cache key is derived from stable Cloud metadata id/status
- raw cloud-only path and raw Storage path are not used in logs
- cache write failure is ignored because Storage remains canonical

## Diagnostics

Added count/status-only runtime diagnostics:

- `cloud_thumbnail_fetch_attempt_count`
- `cloud_thumbnail_fetch_success_count`
- `cloud_thumbnail_fetch_failure_count`
- `cloud_thumbnail_cache_hit_count`
- `cloud_thumbnail_cache_miss_count`

API:

- `getCloudThumbnailRuntimeDebugCounts()`

Testing-only seams:

- `debugSetCloudThumbnailFetcher(...)`
- `debugResetCloudThumbnailRuntimeDebugCounts()`
- `debugClearCloudThumbnailMemoryCache()`

No raw uid/path/storagePath/fileName logging was added.

## Tests Added

Updated `test/video_manager_clip_storage_state_test.dart`.

Added coverage:

- completed thumbnail metadata fetches Storage bytes and then uses memory cache
- missing thumbnail metadata does not fetch Storage
- failed thumbnail status does not fetch Storage
- Storage fetch failure returns `null` for fallback
- localOnly clip does not use Cloud thumbnail loader and remains localOnly

## Verification

Format:

```text
dart format lib\managers\video_manager.dart test\video_manager_clip_storage_state_test.dart
```

Result: PASS.

Tests:

```text
flutter test test\video_manager_clip_storage_state_test.dart test\cloud_thumbnail_metadata_model_test.dart test\library_clip_transfer_action_test.dart test\media_widgets_cloud_only_renderer_test.dart
```

Result: PASS, 29 tests.

Targeted analyzer:

```text
flutter analyze lib\managers\video_manager.dart test\video_manager_clip_storage_state_test.dart
```

Result: FAIL due to existing analyzer debt in `video_manager.dart`.

Observed categories:

- existing `avoid_print` info entries
- existing `curly_braces_in_flow_control_structures` info entries
- existing `unnecessary_brace_in_string_interps` info entries
- existing `no_leading_underscores_for_local_identifiers` info entries

No new compile failure was observed in targeted tests.

## Notes

Phase C1 does not yet change Library card rendering. Cloud-only cards will continue to show the existing fallback until Phase C2 wires `getCloudThumbnail(...)` into the renderer.

The loader is ready for Phase C2 UI integration.

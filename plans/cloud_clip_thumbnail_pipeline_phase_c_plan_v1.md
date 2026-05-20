# Cloud Clip Thumbnail Pipeline Phase C Plan v1

## 1. Status

Phase B MMQA-01 is closed as:

```text
CONDITIONAL PASS
```

Basis:

- functional upload move path passed
- thumbnail generation/upload/metadata commit succeeded
- local cleanup executed after Cloud completion
- Storage permission-denied blocker resolved
- remaining `I/flutter` path-like hits documented as `plugin_runtime_exception` WARN

Reference:

```text
plans/cloud_clip_thumbnail_pipeline_phase_b_mmqa01_final_verdict_v1.md
```

## 2. Phase C Objective

Render Cloud-only clip thumbnails from Firebase Storage when Firestore metadata indicates a completed thumbnail.

Target behavior:

- if `ClipStorageState.cloudOnly`
- and `thumbnailStatus == completed`
- and `thumbnailStoragePath` is present
- then Library card loads the thumbnail image from Firebase Storage and displays it

Fallback behavior:

- missing thumbnail metadata
- `thumbnailStatus == failed`
- legacy Cloud clip
- Storage thumbnail read failure

must keep the existing explicit Cloud fallback card.

## 3. Product Policy

Canonical thumbnail source for Cloud clips:

- Firebase Storage thumbnail image
- Firestore metadata fields:
  - `thumbnailStoragePath`
  - `thumbnailStatus`
  - `thumbnailWidth`
  - `thumbnailHeight`
  - `durationMs`

Local thumbnail files are performance cache only.

App uninstall/reinstall behavior:

- local cache is gone
- app reads Firestore Cloud metadata
- app recreates cloudOnly placeholders
- app fetches thumbnail from Storage using metadata
- Library displays thumbnail if fetch succeeds

## 4. Data Safety Constraints

Do not:

- change Firebase rules/index/schema
- run migration/backfill
- auto-repair existing legacy Cloud clips
- physically delete Storage objects
- deploy
- implement Cloud copy
- print raw uid/path/storagePath/fileName

Existing legacy Cloud clips without thumbnail metadata remain visible through fallback Cloud card and repair-needed diagnostics.

## 5. Current Read Model

Already available from Phase A:

- `VideoMetadata.thumbnailStoragePath`
- `VideoMetadata.thumbnailStatus`
- `VideoMetadata.thumbnailWidth`
- `VideoMetadata.thumbnailHeight`
- `VideoMetadata.durationMs`
- `VideoMetadata.hasCompletedThumbnail`
- local index persistence of nullable thumbnail fields
- `VideoManager.getCloudThumbnailDebugCounts(...)`
- `VideoManager.hasCompletedCloudThumbnail(path)`
- `VideoManager.isCloudThumbnailRepairNeeded(path)`

Already available from Cloud-only renderer work:

- Library can detect `ClipStorageState.cloudOnly`
- Cloud-only clips bypass local thumbnail renderer
- missing/legacy thumbnails render explicit Cloud fallback card

## 6. Proposed Architecture

Add a Storage-backed Cloud thumbnail loader that is separate from local video thumbnail generation.

Recommended owner:

- `VideoManager`

Recommended API:

```dart
Future<Uint8List?> getCloudThumbnail(String cloudOnlyPath)
```

or:

```dart
Future<Uint8List?> getDisplayThumbnail(String path)
```

where `cloudOnly` dispatches to Storage thumbnail and local clips keep existing local generation.

Preferred minimal Phase C API:

```dart
Future<Uint8List?> getCloudThumbnail(String path)
```

Rationale:

- keeps local thumbnail cache behavior unchanged
- makes Cloud-only rendering explicit
- avoids routing `cloud_only://` paths into local file thumbnail generation

## 7. Cache Strategy

Local cache is allowed only as performance cache.

Recommended cache key:

- derived from stable cloud metadata id, not raw path in logs
- do not log raw `thumbnailStoragePath`
- cache invalidation can use `videoId` + thumbnail status/version

Cache behavior:

1. If cached bytes exist, render cached bytes.
2. If no cache exists and metadata is completed, fetch from Storage.
3. Store fetched bytes in app-private cache.
4. On cache read/write failure, render fallback Cloud card.

The cache must not become canonical. Missing local cache must not mark the Cloud clip repair-needed if Storage metadata is complete.

## 8. Rendering Semantics

Library card decision:

| Clip State | Thumbnail Metadata | Render |
| --- | --- | --- |
| localOnly | N/A | existing local thumbnail renderer |
| cloudOnly | completed + path present | Storage thumbnail image |
| cloudOnly | missing metadata | existing Cloud fallback card |
| cloudOnly | failed thumbnail | existing Cloud fallback card |
| cloudOnly | Storage fetch fails | existing Cloud fallback card + count-only diagnostic |
| cloudSyncedLocal | legacy/repair-needed | current non-normal handling; do not introduce sync normal state |

Tap behavior:

- single tap on cloudOnly should not attempt local preview unless video is downloaded
- existing snackbar/guide behavior remains

Long-press behavior:

- existing download/move-to-device selection action remains

## 9. Logging / Diagnostics

Logs must be count/status-only.

Allowed diagnostics:

- `cloud_thumbnail_fetch_attempt_count`
- `cloud_thumbnail_fetch_success_count`
- `cloud_thumbnail_fetch_failure_count`
- `cloud_thumbnail_cache_hit_count`
- `cloud_thumbnail_cache_miss_count`
- `fallbackCloudCardCount`
- `thumbnailReadyCount`
- `thumbnailMissingCount`
- `thumbnailFailedCount`

Forbidden in logs/docs:

- raw uid
- raw local path
- raw `thumbnailStoragePath`
- raw `storagePath`
- raw file name
- raw `cloud_only://` path if it contains identifying metadata

## 10. Failure Handling

If Storage thumbnail fetch fails:

- do not fail Library load
- do not delete metadata
- do not mark Cloud clip as downloaded
- do not auto-repair
- render fallback Cloud card
- record count-only failure diagnostic

If cache write fails:

- render fetched image for current frame if available
- do not fail Cloud card
- record count-only cache failure if needed

If metadata is missing:

- do not attempt Storage fetch
- render fallback
- count as repair-needed/missing

## 11. Implementation Phases

### Phase C1: Loader and Cache

- Add Storage thumbnail loader.
- Add local cache read/write for Cloud thumbnail bytes.
- Add count-only diagnostics.
- Keep UI unchanged until loader is tested.

### Phase C2: Library Renderer Integration

- In Cloud-only renderer, if thumbnail metadata is completed, use Storage thumbnail loader.
- If bytes are unavailable, keep fallback Cloud card.
- Ensure duration badge behavior does not assume local video.

### Phase C3: Reinstall / Cache Empty QA

- Clear only local thumbnail cache if a safe targeted cache clear exists.
- Do not clear app data or login session unless explicitly approved.
- Verify Cloud-only thumbnail can be fetched from Storage after cache miss.

## 12. Test Plan

Unit/widget tests:

- cloudOnly + completed thumbnail metadata chooses Storage thumbnail path
- cloudOnly + missing thumbnail metadata uses fallback Cloud card
- cloudOnly + failed thumbnail status uses fallback Cloud card
- Storage fetch failure uses fallback Cloud card
- localOnly still uses local thumbnail renderer
- raw path/storagePath is not logged by diagnostics

Runtime QA:

- use the Cloud clip created by Phase B MMQA-01
- confirm thumbnailReadyCount >= 1
- confirm Library card displays thumbnail image instead of fallback card
- clear local thumbnail cache only, then confirm reload from Storage
- reinstall/cache-empty validation only with explicit data preservation plan

## 13. Go / No-Go Criteria

Go:

- Cloud-only completed thumbnail renders from Storage
- fallback remains for missing/failed/legacy clips
- local cache is optional
- download/move-to-device action remains unchanged
- count-only sensitive log gate passes or documented plugin runtime WARN remains limited

No-Go:

- Cloud-only renderer routes `cloud_only://` into local thumbnail generation
- Storage fetch failure hides or removes the Cloud clip
- legacy Cloud clips are auto-repaired or rewritten
- raw uid/path/storagePath/fileName appears in app-controlled logs
- any Storage object is deleted

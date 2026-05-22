# Cloud Clip Thumbnail Pipeline Phase B Report v1

## Scope

Implemented Phase B upload move write path for the active paid immediate Cloud move flow.

Out of scope and unchanged:

- Firebase rules/index/schema
- migration/backfill
- legacy Cloud clip repair
- Storage physical delete
- Cloud copy
- queued/background upload thumbnail pipeline

## Pre-Implementation Findings

1. Thumbnail package exists:
   - `pubspec.yaml` already includes `video_thumbnail`.
2. Existing local thumbnail/cache logic exists:
   - `VideoManager.getThumbnail()` uses `video_thumbnail` for local cache generation.
   - `cloud_only://` paths are not routed to local thumbnail generation.
3. Existing immediate upload sequence:
   - `CloudService.uploadVideoImmediate()` created Firestore metadata, uploaded video, marked `uploadStatus=completed`, then ran local cleanup.
4. Existing cleanup point:
   - local cleanup is called after immediate upload commit through `removeLocalClipAfterCloudMove(...)`.
5. Required safety change:
   - local cleanup now runs only after video upload, thumbnail generation, thumbnail upload, and metadata commit all succeed.

## Implementation Summary

Changed `lib/services/cloud_service.dart`.

Added active paid immediate upload thumbnail pipeline:

- Generates a JPEG poster thumbnail from the local video.
- Reads duration from the local video before local cleanup.
- Writes initial Firestore metadata with `thumbnailStatus=pending`.
- Uploads video to existing video Storage path.
- Uploads thumbnail to:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

- Uses `contentType=image/jpeg`.
- Commits Firestore metadata only after thumbnail upload succeeds:
  - `thumbnailStatus=completed`
  - `thumbnailStoragePath`
  - `thumbnailWidth`
  - `thumbnailHeight`
  - `durationMs`
  - `uploadStatus=completed`
- Preserves local video/local index if thumbnail generation, thumbnail upload, or metadata commit fails.

Added raw-safe diagnostics:

- `thumbnail_generation_attempt_count`
- `thumbnail_generation_success`
- `thumbnail_generation_failure`
- `thumbnail_upload_attempt_count`
- `thumbnail_upload_success`
- `thumbnail_upload_failure`
- `thumbnail_metadata_commit_success`
- `thumbnail_metadata_commit_failure`
- `local_cleanup_executed`

The new diagnostic line does not print raw uid, local path, Storage path, file name, email, token, order id, or provider.

## Failure Behavior

Thumbnail generation failure:

- Returns upload failure.
- Marks thumbnail metadata failed on a best-effort basis.
- Preserves local active video/index.

Thumbnail upload failure:

- Returns upload failure.
- Does not physically delete any Storage object.
- Preserves local active video/index.

Firestore metadata commit failure:

- Returns upload failure.
- Does not physically delete any Storage object.
- Preserves local active video/index.

Video upload success but thumbnail failure:

- Not treated as successful Cloud move.
- Local cleanup is not executed.

## Tests

Updated `test/cloud_thumbnail_metadata_model_test.dart`.

Added coverage:

- completed thumbnail metadata is required for Cloud move success
- missing thumbnail metadata does not classify a new upload as successful Cloud move
- local cleanup is gated by video upload, thumbnail generation, thumbnail upload, and metadata commit success
- generation/upload/metadata failure combinations preserve local by returning `false` from cleanup gate

Existing legacy coverage retained:

- legacy Cloud metadata without thumbnail fields still parses
- missing thumbnail remains compatible with fallback Cloud card behavior

## Verification

Format:

```text
dart format lib\services\cloud_service.dart test\cloud_thumbnail_metadata_model_test.dart
```

Result: PASS.

Tests:

```text
flutter test test\cloud_thumbnail_metadata_model_test.dart test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart test\media_widgets_cloud_only_renderer_test.dart
```

Result: PASS, 24 tests.

Analyzer:

```text
flutter analyze lib\services\cloud_service.dart test\cloud_thumbnail_metadata_model_test.dart
```

Result: FAIL due to existing lint debt in `cloud_service.dart`.

Observed analyzer categories:

- existing `avoid_print` info entries across `cloud_service.dart`
- existing unused private helper warning: `_checkStandardOrAbove`

No new compile error was reported by the test run.

## Data Safety

- No Storage physical delete added.
- No Firebase rules/index/schema change.
- No migration/backfill.
- No legacy Cloud clip auto repair.
- Local cleanup is gated after all Cloud completion conditions.
- Failure metadata logging was redacted for video id and uid, and path-like/error values are sanitized before storing `errorMessage`.

## Known Limitations

- Phase B is implemented for the immediate upload move path used by Library move/upload QA.
- The queued/background upload path does not yet generate/upload canonical thumbnails and should be handled in a separate approved phase if auto-upload must satisfy the same thumbnail completion contract.
- Cloud-only thumbnail rendering from Storage remains Phase C; legacy/missing thumbnails continue to use fallback Cloud card.

## Go / No-Go

Go for runtime MMQA recheck of active paid immediate upload move.

No-Go for declaring the full thumbnail pipeline complete until:

- Storage-backed Cloud-only thumbnail rendering is implemented and verified.
- queued/background uploads are either updated or explicitly excluded from the product path.
- runtime QA confirms thumbnail Storage object and Firestore metadata are created before local cleanup.

# Cloud Clip Thumbnail Pipeline Implementation Plan v1

## 1. Why local-only thumbnail cache is insufficient

The current fallback-only Cloud placeholder is acceptable for legacy clips, but it is not the target state for new Cloud clips. A local cache cannot survive uninstall/reinstall and cannot represent a Cloud-only clip once the local video is removed.

Implementation objective: make Firebase Storage thumbnail image plus Firestore metadata the source of truth for Cloud clip thumbnails, while keeping local cache as an optimization.

## 2. Canonical thumbnail storage model

Target model:

- Firebase Storage stores:
  - video object
  - thumbnail image object
- Firestore `videos/{videoId}` stores:
  - video metadata
  - thumbnail metadata
  - duration metadata
- Local app storage stores:
  - optional thumbnail cache
  - optional decoded image cache

No thumbnail binary data is stored in Firestore.

## 3. Firestore metadata fields

Add dual-read compatible metadata handling in app code in a future implementation phase:

- `thumbnailStoragePath: string`
- `thumbnailStatus: string`
- `thumbnailWidth: number`
- `thumbnailHeight: number`
- `durationMs: number`

Compatibility behavior:

- Missing fields mean legacy or repair-needed Cloud clip.
- New upload move writes all fields before local cleanup.
- Reads must tolerate missing fields without crashing.
- Existing `VideoMetadata` and local index models should expose nullable thumbnail/duration fields.

This plan does not execute schema migration/backfill.

## 4. Storage path convention

Use a child path under the existing video ownership prefix:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

Implementation notes:

- Use a fixed name for one poster thumbnail per video.
- Content type should be `image/jpeg` unless a future design chooses another format.
- The path must be written to `thumbnailStoragePath` only after upload success.
- Do not introduce a new top-level Storage collection in this phase.

Firebase Storage rules are not changed in this plan. If rules do not already allow this child path, implementation must stop and request a separate rules plan/approval.

## 5. Upload move sequence with thumbnail

Planned code path:

1. In the upload move handler, preserve the local video until all Cloud completion checks pass.
2. Before `uploadVideoImmediate` removes local data, generate a poster thumbnail from the local video.
3. Calculate `durationMs`.
4. Create Firestore metadata with:
   - `uploadStatus = uploading`
   - `thumbnailStatus = pending`
   - no completed Cloud success state yet
5. Upload video object.
6. Upload thumbnail object.
7. Verify both uploads.
8. Update Firestore with:
   - `uploadStatus = completed`
   - active Cloud state
   - `thumbnailStatus = completed`
   - `thumbnailStoragePath`
   - dimensions
   - duration
9. Sync Cloud metadata to Library.
10. Remove local video/index only after step 8 succeeds.

Failure behavior:

- Any failure before step 8 keeps the local clip active.
- The UI state becomes failedUpload/retryable where appropriate.
- Incomplete Cloud metadata is not considered a successful Cloud move.

## 6. Download/reinstall behavior

Planned read path:

1. `getCompletedUserVideos()` returns `VideoMetadata` with nullable thumbnail fields.
2. `syncCloudMetadataToLibrary()` stores thumbnail/duration metadata in `_cloudMetadataByPath` and local index.
3. Library detects `cloudOnly`:
   - if thumbnail metadata complete, render Storage-backed thumbnail.
   - if missing/incomplete, render fallback Cloud card.
4. Thumbnail bytes are cached locally after first load.

Reinstall:

- Local cache is empty.
- Cloud metadata pull reconstructs placeholders.
- Thumbnail is fetched from Storage using `thumbnailStoragePath`.

Download/move-to-device:

- Video download remains the required operation.
- Thumbnail cache can be preserved or regenerated locally after the video becomes device-active.
- Cloud active metadata is tombstoned only after local video registration succeeds.

## 7. Fallback behavior for missing thumbnail

Implementation behavior:

- Add a derived diagnostic flag such as `hasCloudThumbnail` or `isCloudThumbnailRepairNeeded`.
- Existing fallback Cloud card remains for:
  - missing `thumbnailStoragePath`
  - `thumbnailStatus != completed`
  - Storage thumbnail load failure
- Do not route Cloud-only thumbnail misses through the generic local thumbnail renderer.
- Missing thumbnail does not block Cloud read/download.

The fallback card should remain visually intentional, matching the current Cloud-only renderer.

## 8. Legacy Cloud clip repair policy

Legacy handling in this implementation phase:

- No automatic repair.
- No migration/backfill.
- No Storage video reads solely to generate legacy thumbnails.
- No Cloud metadata rewrite for old clips unless user action explicitly requires a normal move/download path.

Diagnostics may count:

- completed Cloud clips with thumbnail metadata
- completed Cloud clips missing thumbnail metadata
- Storage thumbnail load failures
- fallback Cloud card render count

Diagnostics must be count-only and must not print raw uid, local path, Storage path, or file name.

## 9. Failure/rollback rules

Upload move:

- Thumbnail generation fails: return failure; local file/index stay active.
- Thumbnail upload fails: return failure; local file/index stay active.
- Firestore thumbnail metadata update fails: return failure; local file/index stay active.
- Video upload succeeds but thumbnail fails: mark incomplete/failed metadata if possible; do not remove local file.
- Any partial Cloud artifact cleanup must not physically delete Storage objects in R3/current scope.

Download:

- Missing thumbnail does not fail download.
- Video download failure preserves Cloud metadata.
- Cloud tombstone failure after download causes move failure; local partial file handling must preserve data safety.

Rollback:

- Roll back app logic by ignoring thumbnail fields and using fallback Cloud card.
- Do not require data rollback because metadata fields are additive and nullable.

## 10. QA matrix

| ID | Scenario | Evidence | Expected |
| --- | --- | --- | --- |
| TH-QA-01 | Active paid upload move with thumbnail | Firestore metadata count, Storage video count, Storage thumbnail count, local file count | Cloud-only with completed thumbnail; local active copy removed |
| TH-QA-02 | Thumbnail generation failure | app log count-only, local count before/after | move fails; local video preserved |
| TH-QA-03 | Thumbnail Storage upload failure | Storage thumbnail absent, local count before/after | move fails; local video preserved |
| TH-QA-04 | Firestore thumbnail metadata failure | metadata status count, local count | move fails; local video preserved |
| TH-QA-05 | App reinstall/cache empty | local cache count, metadata pull count, thumbnail fetch count | Cloud-only thumbnail renders from Storage |
| TH-QA-06 | Legacy missing thumbnail | repair-needed count, fallback render count | fallback card shown; no auto repair |
| TH-QA-07 | Grace download | subscription state, download count | Cloud clip can move to device; thumbnail absence does not block |
| TH-QA-08 | After grace blocked | subscription state, download count | no Cloud video/thumbnail read allowed |
| TH-QA-09 | Sensitive log gate | app-controlled log scan | no raw uid/path/storagePath/fileName/token/email output |

## Implementation phases

### Phase A: Model and metadata read

- Extend `VideoMetadata` with nullable thumbnail/duration fields.
- Extend local index model with nullable thumbnail/duration fields.
- Keep reads tolerant of missing fields.
- Add count-only diagnostics.

### Phase B: Upload move write path

- Generate thumbnail before local cleanup.
- Upload thumbnail to Storage.
- Commit thumbnail metadata with completed upload state.
- Gate local cleanup on thumbnail success.

### Phase C: Cloud-only thumbnail rendering

- Add Storage thumbnail loader for Cloud-only clips with completed thumbnail metadata.
- Cache thumbnail locally for performance.
- Preserve fallback Cloud card for missing/failed thumbnails.

### Phase D: QA hardening

- Add tests for success and failure branches.
- Run active paid upload move QA.
- Run reinstall/cache-empty display QA.
- Run legacy missing-thumbnail fallback QA.

## Go / No-Go criteria

Go:

- New Cloud upload move cannot complete without thumbnail Storage upload and metadata.
- Reinstall can display Cloud-only thumbnails from Storage.
- Missing legacy thumbnails remain fallback/repair-needed only.
- Local video is preserved on thumbnail pipeline failure.

No-Go:

- Local thumbnail cache is the only source for Cloud-only thumbnails.
- Local file is removed before thumbnail upload and metadata commit.
- Legacy Cloud clips are auto-repaired/backfilled.
- Firebase rules/index/schema changes are executed without separate approval.
- Storage physical delete is introduced.

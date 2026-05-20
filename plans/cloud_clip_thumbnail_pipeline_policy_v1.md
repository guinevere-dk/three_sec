# Cloud Clip Thumbnail Pipeline Policy v1

## 1. Why local-only thumbnail cache is insufficient

Local thumbnails are a performance cache only. They are not a valid canonical source for Cloud clips because:

- App uninstall/reinstall deletes local cache and app-private thumbnails.
- A Cloud-only clip has no active local video file under the move model.
- Library must still show a recognizable thumbnail after reinstall, device replacement, or cache eviction.
- A Cloud clip is not complete as a user-facing Cloud asset if its only thumbnail exists in local storage.

Policy: local thumbnail files may be used for speed, but Cloud clip display must be recoverable from Firebase Storage plus Firestore metadata.

## 2. Canonical thumbnail storage model

For normal Cloud clips, the canonical thumbnail image is stored in Firebase Storage.

- Video object: Firebase Storage video file.
- Thumbnail object: Firebase Storage image file.
- Firestore `videos/{videoId}` document: metadata only.
- Local thumbnail: optional cache, never canonical.

Under the move model, a Cloud clip is active only in Cloud. A complete active Cloud clip therefore requires:

- active completed video metadata
- video Storage object reference
- thumbnail Storage object reference
- duration metadata needed for Library display

## 3. Firestore metadata fields

Firestore stores metadata fields only. It must not store thumbnail binary content.

Required fields for new completed Cloud clips:

- `thumbnailStoragePath`: Firebase Storage path for the thumbnail image.
- `thumbnailStatus`: lifecycle/status of thumbnail generation and upload.
- `thumbnailWidth`: image width in pixels.
- `thumbnailHeight`: image height in pixels.
- `durationMs`: video duration in milliseconds.

Recommended `thumbnailStatus` values:

- `pending`: thumbnail generation/upload started but not complete.
- `completed`: thumbnail Storage object exists and metadata is ready.
- `failed`: thumbnail generation/upload failed.
- `missing`: legacy or incomplete Cloud clip has no thumbnail metadata.

Existing fields such as `storagePath`, `uploadStatus`, `fileSize`, `albumName`, `cloudState`, and `lifecycleState` remain unchanged.

## 4. Storage path convention

Thumbnail objects should live under the same user/video ownership prefix as the video object:

```text
users/{uid}/videos/{videoId}/thumbnails/{thumbnailFileName}
```

Recommended file name:

```text
poster.jpg
```

Rationale:

- Keeps thumbnail ownership aligned with `users/{uid}/videos/{videoId}`.
- Avoids a new top-level Storage namespace.
- Allows rules to follow the same uid/video ownership model when rules are explicitly updated in a future approved step.

This policy document does not execute a Storage path migration and does not change Firebase rules.

## 5. Upload move sequence with thumbnail

Device to Cloud move succeeds only if both video and thumbnail Cloud assets are committed.

Required sequence:

1. Validate signed-in user and Cloud write permission.
2. Validate the selected clip is device/localOnly or failedUpload retry.
3. Generate a thumbnail from the local video before deleting the local file.
4. Extract or calculate `durationMs`.
5. Create/update Firestore video metadata with upload in progress state and thumbnail pending state.
6. Upload video object to Storage.
7. Upload thumbnail image object to Storage.
8. Verify video Storage upload success.
9. Verify thumbnail Storage upload success.
10. Update Firestore metadata:
    - `uploadStatus = completed`
    - active Cloud state
    - `thumbnailStatus = completed`
    - `thumbnailStoragePath`
    - `thumbnailWidth`
    - `thumbnailHeight`
    - `durationMs`
11. Only after the Firestore active completed state and both Storage objects are confirmed, remove the local video file and active local index.
12. Merge Cloud-only placeholder into Library.

Upload move must not delete the local video until thumbnail upload and metadata commit are complete.

## 6. Download/reinstall behavior

Reinstall behavior:

- On app reinstall/login, the app reads completed Cloud metadata.
- Cloud-only placeholders are created from Firestore metadata.
- If `thumbnailStatus == completed` and `thumbnailStoragePath` is present, the app downloads or caches the thumbnail from Storage for display.
- The local thumbnail cache may be rebuilt from Storage on demand.

Download/move-to-device behavior:

- Downloading a Cloud clip to device should download the video Storage object.
- Thumbnail cache may be warmed from `thumbnailStoragePath`, but the canonical thumbnail remains Storage-backed while the Cloud metadata is active.
- After successful move-to-device and Cloud active metadata tombstone, the local video becomes the active source. Local thumbnail generation/cache can resume from the device video.

## 7. Fallback behavior for missing thumbnail

If a Cloud-only clip lacks a completed thumbnail:

- Library must show the explicit Cloud fallback card, not a gray local-thumbnail failure.
- The clip remains selectable for download/move-to-device if subscription rules allow read/download.
- The clip is classified as `cloudOnly` plus `repair-needed` for diagnostics.
- Missing thumbnail must not block download of an existing Cloud video.

Fallback is acceptable for legacy/incomplete clips. It is not acceptable as the normal result for new upload move success.

## 8. Legacy Cloud clip repair policy

Legacy Cloud clips without `thumbnailStoragePath` are repair-needed.

Policy:

- Do not automatically repair existing Cloud clips in this phase.
- Do not auto-generate thumbnails from Storage video objects without a separate approved repair plan.
- Do not backfill Firestore metadata automatically.
- Do not delete, tombstone, or rewrite legacy metadata merely because thumbnail fields are missing.
- Surface missing thumbnail as diagnostics and fallback UI only.

Any repair/backfill requires a separate plan with dry-run, data inventory, rollback strategy, and explicit approval.

## 9. Failure/rollback rules

Upload move failure rules:

- Thumbnail generation failure: upload move fails; local video remains active.
- Thumbnail Storage upload failure: upload move fails; local video remains active.
- Firestore thumbnail metadata update failure: upload move fails; local video remains active.
- Video upload success but thumbnail upload failure: do not remove local video. Mark Cloud metadata as incomplete/failed where possible.
- Thumbnail upload success but video upload failure: do not remove local video. Do not treat thumbnail alone as an active Cloud clip.
- Local cleanup failure after all Cloud assets are committed: classify as legacy/repair-needed `cloudSyncedLocal`; do not delete additional data automatically.

Download failure rules:

- Missing thumbnail must not block video download.
- Video download failure preserves Cloud active metadata and placeholder.
- Cloud tombstone failure after video download must not create a successful move result.

Storage physical delete remains out of scope for R3/current work.

## 10. QA matrix

| Scenario | Preconditions | Expected Result | PASS Criteria |
| --- | --- | --- | --- |
| New active paid upload move | signed-in active paid, localOnly clip | video and thumbnail upload, metadata completed, local video removed | Cloud-only clip has `thumbnailStoragePath`, `thumbnailStatus=completed`, and no active local copy |
| Thumbnail generation failure | local video exists, simulated generation failure | move fails | local video/index remain active; no successful Cloud-only state |
| Thumbnail Storage upload failure | video upload possible, thumbnail upload fails | move fails | local video preserved; Cloud metadata not treated as complete |
| Firestore thumbnail metadata failure | Storage uploads done, metadata update fails | move fails | local video preserved; incomplete Cloud metadata is not normal active success |
| App reinstall | signed-in user with completed Cloud clip | thumbnail reloads from Storage | Library shows thumbnail, not gray fallback |
| Missing thumbnail legacy clip | existing Cloud clip without thumbnail fields | fallback Cloud card | clip is available for download; diagnostics mark repair-needed |
| Grace download | expired within grace, Cloud clip with thumbnail | download/move-to-device allowed | video download succeeds; thumbnail absence does not block |
| After grace download | expired after grace | read/download blocked | no video or thumbnail download occurs |
| Free never paid | signed-in free | Cloud access blocked | no new video or thumbnail Storage object |

## Go / No-Go

Go:

- New Cloud move success requires video object, thumbnail object, and metadata completion.
- Library Cloud-only cards can use Storage thumbnails after reinstall.
- Missing thumbnail legacy clips remain visible through fallback and are repair-needed.

No-Go:

- Local-only thumbnail cache is treated as canonical.
- Local video is removed after upload when thumbnail upload/metadata failed.
- Existing Cloud clips are automatically repaired/backfilled without approval.
- Storage physical delete or Firebase rules/index changes are folded into this phase.

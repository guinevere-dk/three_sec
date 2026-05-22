# Cloud-only Placeholder Visibility Triage v1

## Scope

- Trigger: Cloud upload succeeded and Library shows a Cloud placeholder, but the card body renders as a gray tile instead of a clip thumbnail/content preview.
- Mode: code audit plus raw-safe runtime count-only evidence.
- No Firebase rules/index/schema changes, migration/backfill, Storage delete, deploy, or legacy cleanup were performed.
- No raw uid, local path, Storage path, or file name is recorded in this report.

## Runtime Count Evidence

| Probe | Result |
| --- | ---: |
| SharedPreferences read | PASS |
| Local index entries total | 10 |
| Local index clip entries | 10 |
| Local index `cloud_only://` entries | 10 |
| Cloud-only entries with videoId | 10 / 10 |
| Cloud-only entries with fileName metadata | 10 / 10 |
| Cloud-only entries with storagePath metadata | 10 / 10 |
| Cloud-only entries with albumName | 10 / 10 |
| Cloud-only entries with fileSize | 10 / 10 |
| Cloud-only entries with duration metadata | 0 / 10 |
| Cloud-only entries with thumbnail metadata | 0 / 10 |
| Cloud-only album groups | 1 |
| Largest album group Cloud-only count | 10 |

Firestore direct count was not queried from the host because this triage avoids credentials and raw data access. The local index evidence shows that completed Cloud metadata has already been materialized into Library placeholders. A fresh logcat tail did not retain a `metadata_pull` line, so `getCompletedUserVideos()` runtime returned count is unavailable for this capture.

## Firestore Metadata Merge

Code path:

- `CloudService.getCompletedUserVideos()` queries `videos` for the signed-in uid where `uploadStatus == completed`, filters out trash/tombstone, and requires either `storagePath` or `downloadUrl`.
- `VideoManager.syncCloudMetadataToLibrary()` calls `getCompletedUserVideos()`, creates one placeholder per returned video via `_cloudPlaceholderPath()`, stores metadata in `_cloudMetadataByPath`, adds the placeholder marker to `_cloudSyncedPaths`, upserts a local index Cloud clip, then calls `_mergeCloudOnlyPlaceholdersForCurrentAlbum()`.
- `_mergeCloudOnlyPlaceholdersForCurrentAlbum()` adds placeholders for the current album when no matching local file exists by file name plus file size.

Finding: merge is functioning at least to local index level. There are 10 Cloud-only local index entries with required identity/storage metadata present.

## Placeholder Model

`_cloudPlaceholderPath()` creates synthetic paths with the `cloud_only://` scheme. `getClipStorageState()` treats these as `ClipStorageState.cloudOnly`, and `getClipStatusBadge()` returns `Cloud`.

The placeholder is not a local media file and is intentionally excluded from local file existence checks.

## Metadata Completeness

Present for all observed Cloud-only entries:

- video id
- file name metadata
- storage path metadata
- album name
- file size

Missing for all observed Cloud-only entries:

- thumbnail path/url
- duration metadata

`VideoMetadata` currently has no thumbnail field. `LocalIndexEntry` also does not persist duration or thumbnail metadata for Cloud-only entries.

## Rendering Path

`LibraryScreen` passes every clip path, including Cloud-only placeholders, into `MediaWidgets.buildMediaGridItem()` with:

- `statusBadge: videoManager.getClipStatusBadge(path)`
- `getThumbnail: videoManager.getThumbnail`
- `getDuration: videoManager.getVideoDuration`

`VideoManager.getThumbnail()` returns `null` immediately for `cloud_only://` paths. `VideoManager.getVideoDuration()` returns `Duration.zero` for `cloud_only://` paths.

`MediaWidgets.buildMediaGridItem()` renders a gray container when the thumbnail future has no data. It does not special-case Cloud-only cards beyond the badge overlay.

Finding: Cloud-only cards do enter the generic thumbnail widget path, but the manager short-circuits thumbnail loading to `null`. The gray card is therefore the current fallback behavior, not evidence that Firestore metadata failed to merge.

## Tap / Download UX

Current tap behavior in `LibraryScreen`:

- Normal local clip tap opens preview.
- Cloud-only placeholder tap does not open preview. It shows a SnackBar instructing the user to long-press and restore with the download icon.
- Long-selecting Cloud-only clips resolves the transfer action to download/move-to-device.
- The download path calls `CloudService.downloadVideo()`, then `CloudService.deleteVideo()` to tombstone Cloud active metadata, then `VideoManager.registerCloudMovedToDeviceClip()`.

Finding: Cloud-only tap does not directly start download. Download is available through long-select transfer. That is functional, but the visual UX is weak because the gray card looks like a broken thumbnail instead of an intentional Cloud-only placeholder.

## Verdict

Status: **BUG / UX GAP, not metadata merge failure**

The required Cloud metadata is present in local index placeholders, and the state model classifies them as Cloud-only. The gray card occurs because the current Library renderer has no Cloud-only visual renderer and there is no thumbnail/duration metadata for Cloud-only entries.

## Required Fix Direction

1. Add an explicit Cloud-only card rendering branch instead of relying on the generic local thumbnail fallback.
2. Keep the badge/icon semantics to exactly two active states under move model:
   - Device: local file exists, local preview/tap enabled, upload action on transfer.
   - Cloud: Cloud metadata exists, local preview disabled, download/move-to-device action on transfer.
3. For Cloud-only card body, render a deliberate Cloud visual state using metadata that is already available count-safe at runtime:
   - Cloud icon
   - file size if desired
   - duration only if a future metadata field exists
4. Do not treat gray fallback as a normal final UX unless it is explicitly styled as a Cloud placeholder.
5. If real Cloud thumbnails are required later, add a metadata/design phase for thumbnail generation/storage; do not infer thumbnails from local files after move-to-cloud.

## Risks

- Cloud-only cards currently have no previewable local media, so any future tap-to-preview behavior must first download or stream from Cloud.
- `CloudService.deleteVideo()` is used for the move-to-device tombstone step. This must remain logical trash/tombstone only; Storage physical deletion remains a QA FAIL condition.
- `VideoMetadata` and `LocalIndexEntry` lack thumbnail fields, so thumbnail UI cannot be fixed by rendering code alone unless a deliberate non-thumbnail Cloud placeholder design is used.

## Go / No-Go

- Go for a UI-only Cloud-only placeholder renderer fix.
- No-Go for Firebase schema/rules/index changes, migration/backfill, Storage deletion, or legacy cleanup in this step.

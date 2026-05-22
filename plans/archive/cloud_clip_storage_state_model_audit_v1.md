# Cloud/Device Clip State Model Audit v1

작성일: 2026-05-19

범위: R3 QA를 중단하고 Cloud/Device clip 상태 모델, count, badge, upload button 분기 로직을 코드 변경 없이 감사한다.

보안/운영 원칙:
- raw email/password/token/order id/provider 값은 기록하지 않는다.
- uid와 raw local path는 기록하지 않는다.
- Firebase rules/index/schema, migration/backfill, Storage 삭제, Cloud copy 구현, deploy는 수행하지 않는다.
- 이 문서는 수정 전 설계 감사 문서이며 코드 변경은 없다.

## 1. Intended Product Policy

정책 기준:

| Tier | Intended behavior |
| --- | --- |
| Free | 촬영/미디어 가져오기는 기기에만 저장된다. Cloud upload/download는 불가하다. |
| Standard | 기존 Free 상태에서 기기에 저장된 local-only media는 Cloud에 업로드할 수 있어야 한다. |
| Standard | Standard 상태에서 촬영/미디어 가져오기를 하면 자동으로 Cloud에 저장된다. |
| Standard | Cloud에 저장된 media는 기기로 다운로드/복원할 수 있어야 한다. |

정책상 clip 상태는 최소한 다음 네 가지가 구분되어야 한다.

| State | Local file exists | Cloud metadata/object exists | New Cloud upload action |
| --- | --- | --- | --- |
| local-only | yes | no | allowed for Standard |
| pending-upload | yes | queued/uploading metadata may exist | upload in progress, no duplicate action |
| cloud-synced local | yes | completed Cloud metadata/object exists | upload action not applicable |
| cloud-only | no local media file | completed Cloud metadata/object exists | download/restore action |

## 2. Current State Model in Code

### Primary local list

`VideoManager.loadClipsFromCurrentAlbum()` builds `recordedVideoPaths` from actual `.mp4` files in the current raw album directory, then merges Cloud placeholders.

Relevant code:
- `lib/managers/video_manager.dart:3105` `loadClipsFromCurrentAlbum()`
- `lib/managers/video_manager.dart:3107` reads current album directory
- `lib/managers/video_manager.dart:3111` filters `.mp4`
- `lib/managers/video_manager.dart:3118` assigns local files to `recordedVideoPaths`
- `lib/managers/video_manager.dart:3119` calls `_mergeCloudOnlyPlaceholdersForCurrentAlbum()`

### Cloud-synced marker

`isClipCloudSynced(path)` is not derived from Firestore at query time. It is a local SharedPreferences-backed membership check.

Relevant code:
- `lib/managers/video_manager.dart:62` key is `cloud_synced_paths`
- `lib/managers/video_manager.dart:96` `_cloudSyncedPaths`
- `lib/managers/video_manager.dart:4927` `_loadCloudSyncedPaths()`
- `lib/managers/video_manager.dart:4940` `_persistCloudSyncedPaths()`
- `lib/managers/video_manager.dart:4404` `isClipCloudSynced(path) => _cloudSyncedPaths.contains(path)`

`_loadCloudSyncedPaths()` keeps entries if either:
- `File(path).existsSync()` is true, or
- path starts with `cloud_only://`

Therefore both real local file paths and placeholder paths can be "cloud synced" in the same set.

### Cloud-only placeholder

Cloud-only state is represented as synthetic `cloud_only://{album}/{videoId}/{fileName}` path.

Relevant code:
- `lib/managers/video_manager.dart:3193` `_cloudPlaceholderPath(...)`
- `lib/managers/video_manager.dart:3201` `_isCloudOnlyPlaceholderPath(...)`
- `lib/managers/video_manager.dart:3214` `isCloudOnlyPlaceholder(...)`

### Firestore metadata pull

`syncCloudMetadataToLibrary()` pulls completed Cloud videos, creates placeholder paths, stores metadata by placeholder path, adds placeholders to `_cloudSyncedPaths`, upserts local index Cloud entries, then merges placeholders into the current album list.

Relevant code:
- `lib/managers/video_manager.dart:3126` `syncCloudMetadataToLibrary(...)`
- `lib/managers/video_manager.dart:3133` calls `CloudService().getCompletedUserVideos()`
- `lib/managers/video_manager.dart:3139` creates placeholder
- `lib/managers/video_manager.dart:3140` `_cloudMetadataByPath[placeholder] = video`
- `lib/managers/video_manager.dart:3141` `_cloudSyncedPaths.add(placeholder)`
- `lib/managers/video_manager.dart:3142` `_upsertLocalIndexCloudClip(...)`
- `lib/managers/video_manager.dart:3148` `_persistCloudSyncedPaths()`
- `lib/managers/video_manager.dart:3149` `_mergeCloudOnlyPlaceholdersForCurrentAlbum()`

### Placeholder merge de-duplication

`_mergeCloudOnlyPlaceholdersForCurrentAlbum()` adds placeholders only when it does not find a local clip matching the Cloud metadata by filename and file size.

Relevant code:
- `lib/managers/video_manager.dart:3161` `_mergeCloudOnlyPlaceholdersForCurrentAlbum()`
- `lib/managers/video_manager.dart:3174` filters metadata for current album
- `lib/managers/video_manager.dart:3176` avoids duplicate placeholder key
- `lib/managers/video_manager.dart:3177` avoids placeholder if `_hasLocalClipMatchingCloudVideo(...)`
- `lib/managers/video_manager.dart:3184` `_hasLocalClipMatchingCloudVideo(...)`
- `lib/managers/video_manager.dart:3187` compares `p.basename(path)` to `video.fileName`
- `lib/managers/video_manager.dart:3189` compares local file length to `video.fileSize`

This de-duplication is filename+size based. It does not use Cloud document id, localPath, checksum, or explicit local index linkage.

## 3. Current Count Logic

### Device clip count

Profile's `기기 CLIP` count uses `videoManager.totalClipCount`.

Relevant code:
- `lib/screens/profile_screen.dart:1066` formats `videoManager.totalClipCount`
- `lib/screens/profile_screen.dart:1084` renders `기기 CLIP`
- `lib/managers/video_manager.dart:2969` `totalClipCount`
- `lib/managers/video_manager.dart:1456` `_updateAlbumClipCounts()`
- `lib/managers/video_manager.dart:1464` counts actual `.mp4` files in each local album directory

Therefore `기기 CLIP` is local file count. It does not mean local-only count.

### Cloud clip count

Profile's `Cloud CLIP` count uses Cloud stats from `CloudService.refreshCloudStatsSnapshot()`.

Relevant code:
- `lib/screens/profile_screen.dart:110` `_loadCloudStats()`
- `lib/screens/profile_screen.dart:122` `refreshCloudStatsSnapshot(...)`
- `lib/screens/profile_screen.dart:132` `_cloudClipCount = snapshot.cloudClipCount`
- `lib/screens/profile_screen.dart:1088` renders `Cloud CLIP`
- `lib/services/cloud_service.dart:1361` `refreshCloudStatsSnapshot(...)`
- `lib/services/cloud_service.dart:1378` `getCompletedVideoCount()`
- `lib/services/cloud_service.dart:1343` `getCompletedVideoCount()`
- `lib/services/cloud_service.dart:1348` queries `videos`
- `lib/services/cloud_service.dart:1351` filters `uploadStatus == completed`
- `lib/services/cloud_service.dart:1354` excludes trash/tombstone

Therefore `Cloud CLIP` is Firestore completed document count. It does not mean cloud-only count.

### Important product interpretation gap

`기기 CLIP 7 + Cloud CLIP 7` can be a valid "same seven clips exist locally and in Cloud" state. It is not necessarily 14 distinct clips.

Current labels are ambiguous:
- `기기 CLIP` means "local file exists".
- `Cloud CLIP` means "completed Cloud metadata exists".
- Neither count means "local-only uploadable clips".

## 4. Current Badge Logic

`getClipStatusBadge(path)` returns:

| Condition | Badge |
| --- | --- |
| path starts `cloud_only://` | `Cloud` |
| transfer state pending upload/download | `로딩중` |
| transfer state failed upload/download | `동기화 실패` |
| `isClipCloudSynced(path)` | `동기화됨` |
| else | `기기` |

Relevant code:
- `lib/managers/video_manager.dart:4963` `getClipStatusBadge(...)`
- `lib/managers/video_manager.dart:4964` cloud-only placeholder => `Cloud`
- `lib/managers/video_manager.dart:4968` pending upload/download => `로딩중`
- `lib/managers/video_manager.dart:4978` cloud synced local path => `동기화됨`
- `lib/managers/video_manager.dart:4979` fallback => `기기`

Implication:
- A real local file can show `동기화됨` if its local path is in `cloud_synced_paths`.
- A real local file does not remain `기기` after successful upload.
- `기기` currently means "not in cloud_synced_paths and not cloud_only", not simply "exists on device".

## 5. Current Upload Button Logic

Library detail list is filtered by `VideoManager.isClipVisibleByStorageFilter(path, _storageFilter)`.

Relevant code:
- `lib/screens/library_screen.dart:482` builds `visibleClipPaths`
- `lib/screens/library_screen.dart:486` calls `isClipVisibleByStorageFilter(...)`
- `lib/managers/video_manager.dart:4982` `isClipVisibleByStorageFilter(...)`

Filter behavior:

| Filter | Current code behavior |
| --- | --- |
| `all` | all paths in `recordedVideoPaths` |
| `device` / `기기` | paths where `!isClipCloudSynced(path) && !cloud_only` |
| `cloud` | paths where `isClipCloudSynced(path)` |

Note: current UI shown in `library_screen.dart` has chips for `전체`, `기기`, and `하트만`. A Cloud filter chip was not visible in the inspected snippet/current UI, although the model supports `cloud`.

### Selection action state

The lower Cloud transfer button changes based only on whether selected paths are in `_cloudSyncedPaths`.

Relevant code:
- `lib/screens/library_screen.dart:976` `_resolveSelectionActionState()`
- `lib/screens/library_screen.dart:982` counts selected paths where `isClipCloudSynced(path)`
- `lib/screens/library_screen.dart:987` `cloudCount == 0` => local
- `lib/screens/library_screen.dart:988` `cloudCount == selected length` => cloud
- `lib/screens/library_screen.dart:990` otherwise mixed

Button mapping:
- `local` => `Icons.cloud_upload_rounded` and `_moveSelectedLocalToCloud`
- `cloud` => `Icons.download_rounded` and `_removeSelectedCloudBackup`
- `mixed` => `Icons.download_for_offline_rounded` and disabled handler

Relevant code:
- `lib/screens/library_screen.dart:993` `_transferIconForSelectionState(...)`
- `lib/screens/library_screen.dart:1004` `_transferHandlerForSelectionState(...)`
- `lib/screens/library_screen.dart:1014` local => `_moveSelectedLocalToCloud`
- `lib/screens/library_screen.dart:1016` cloud => `_removeSelectedCloudBackup`
- `lib/widgets/media_widgets.dart:517` Cloud transfer button is second icon in selection panel

### Button visibility gate

The whole Cloud transfer button is only included in the selection panel if `UserStatusManager.isStandardOrAbove()` is true.

Relevant code:
- `lib/screens/library_screen.dart:727` selection panel requires `_isClipSelectionMode && _selectedClipPaths.isNotEmpty`
- `lib/screens/library_screen.dart:748` normal album uses `buildLibrarySelectionPanel(...)`
- `lib/screens/library_screen.dart:755` `showTransferButton: _userStatusManager.isStandardOrAbove()`
- `lib/widgets/media_widgets.dart:518` transfer button included only if `showTransferButton`

Therefore the upload button can be absent for two different reasons:
1. Selection panel is not visible because selection mode has not been entered.
2. Selection panel is visible, but transfer button is hidden because app memory tier is not Standard/Premium.

It can also appear as a download button rather than upload if the selected path is cloud-synced.

## 6. Why Device 7 + Cloud 7 Appears

The current code intentionally counts local files and Cloud completed metadata from different sources.

Observed sanitized emulator evidence:

| Probe | Result |
| --- | ---: |
| `cloud_synced_paths` entry present | yes |
| `cloud_synced_paths` comma-like count | 11 |
| `cloud_synced_paths` `cloud_only://` entries | 5 |
| `cloud_synced_paths` local path entries | 7 |
| `local_index_entries_v1` present | yes |
| local index clip entries | 10 |
| local index cloud metadata entries | 6 |
| local index cloud-only entries | 6 |

Interpretation:
- There are 7 real local paths in `cloud_synced_paths`.
- Thus the currently visible 7 local files are likely not local-only; they are local files with Cloud sync markers.
- Profile can show `기기 CLIP 7` because there are 7 local `.mp4` files in the album.
- Profile can show `Cloud CLIP 7` because Firestore has 7 completed Cloud video docs.
- These can be the same logical clips represented in both local and Cloud domains.

The current count model is therefore not "Device-only count vs Cloud-only count"; it is "local file count vs Cloud completed count".

## 7. Why Upload Button Does Not Appear

There are two findings.

### A. In the latest capture, selection mode was not active

The latest UI hierarchy probe showed:
- Library ordinary album detail was open.
- `전체` filter was selected.
- `기기` filter existed but was not selected.
- 7 thumbnails were visible.
- `1개 선택됨`/`Select All` was not present.
- Bottom floating selection panel was not present.

Since `library_screen.dart:727` requires `_isClipSelectionMode && _selectedClipPaths.isNotEmpty`, no Cloud transfer button can appear before long-press selection mode is active.

### B. Even after selection, the current 7 local clips are probably cloud-synced, not local-only

The audit found 7 local path entries in `cloud_synced_paths`.

Consequences:
- If one of those local paths is selected in `전체`, `_resolveSelectionActionState()` returns `cloud`.
- The second selection-panel button becomes `download_rounded`, not `cloud_upload_rounded`.
- If the user switches to `기기` filter, those cloud-synced local files are excluded by `isClipVisibleByStorageFilter(..., 'device')`.
- Therefore no current clip may qualify as local-only/uploadable.

This explains the user's report that no upload button appears "in any state": the current clips appear to be already classified as Cloud-synced, so upload is not an available action for them.

## 8. Risk Assessment

### Product risk

High: The UI labels can mislead QA/users. `기기 CLIP 7 + Cloud CLIP 7` looks like separate Device and Cloud inventories, but current code can count the same logical clips in both numbers.

### State model risk

High: `cloud_synced_paths` mixes two concepts:
- real local file path that has completed Cloud sync
- synthetic `cloud_only://` placeholder

This makes `isClipCloudSynced()` serve as both "has Cloud copy" and "is Cloud inventory item". The Library button logic then uses this single boolean to decide upload vs download.

### De-duplication risk

Medium to high: `_mergeCloudOnlyPlaceholdersForCurrentAlbum()` de-dupes Cloud metadata against local files by filename and file size only. If a Cloud doc's filename/size does not match the local file exactly, a placeholder can be added even when it represents the same logical media. If two different clips share filename/size, it can also incorrectly suppress a placeholder.

### Upload success marking risk

Medium: normal upload marking is mostly success-based:
- `CloudService.uploadVideoImmediate()` marks local path synced after Storage upload and Firestore completed update at `lib/services/cloud_service.dart:733`.
- queued upload marks local path synced after upload completion at `lib/services/cloud_service.dart:1015`.
- `LibraryScreen._moveSelectedLocalToCloudInBackground()` also marks synced after `uploadVideoImmediate()` returns at `lib/screens/library_screen.dart:1108`, duplicating but not pre-success.

However, one suspicious non-upload path exists:
- `lib/managers/video_manager.dart:5057` `saveMergedProject(...)` calls `markClipCloudSynced(candidate)` after copying a file, without visible Cloud upload in that function. This should be reviewed before any fix because it can create false cloud-synced local paths.

### Local index risk

Medium: local index can store Cloud metadata entries keyed by placeholder or restored local path via `_upsertLocalIndexCloudClip(...)`, but the core Library state still relies on `_cloudSyncedPaths` and `_cloudMetadataByPath`. There is no single canonical `ClipStorageState` object.

## 9. Required Fix Plan

No code changes were made in this audit. Recommended design before implementation:

1. Introduce an explicit derived storage state model.

```text
ClipStorageState:
  localOnly
  pendingUpload
  cloudSyncedLocal
  cloudOnly
  failedUpload
  failedDownload
```

The derived state should be based on:
- local file exists
- path is `cloud_only://`
- transfer state
- local path has confirmed completed Cloud metadata linkage
- Cloud metadata exists and is active

2. Split local count labels from local-only count labels.

Recommended product wording:
- `기기 CLIP`: local files present on device
- `Cloud CLIP`: active completed Cloud clips
- optionally add `업로드 가능`: local-only count

Do not interpret `기기 CLIP` as local-only.

3. Stop using `_cloudSyncedPaths` as the only source for both local synced and cloud-only placeholder state.

Recommended split:
- `cloud_synced_local_paths`: real local paths with completed Cloud metadata
- `cloud_only_placeholders`: derived from active Cloud metadata, not persisted as sync marker unless needed for cache
- local index Cloud metadata linkage keyed by a stable cloud video id or localPath when available

4. Make placeholder de-duplication more deterministic.

Preferred match order:
- Firestore `localPath` exact match when local path exists and is within app raw clip dir
- local index `cloudVideoId` linkage
- filename+size fallback only as defensive heuristic

5. Update Library filter semantics.

Recommended:
- `기기`: local files on device, including cloud-synced local files
- `업로드 가능` or `로컬만`: local-only files not yet cloud-synced
- `Cloud`: Cloud inventory, including cloud-only and synced local clips if the product wants a combined cloud view

If existing `기기` must mean local-only, rename it to avoid confusion.

6. Update transfer button logic to use explicit state.

Recommended:
- selected all localOnly => upload
- selected all cloudOnly => download/restore
- selected all cloudSyncedLocal => maybe "download" is not meaningful because already local; consider hide/disable or "Cloud 관리"
- mixed => disabled with explanatory toast
- pendingUpload => disabled/progress state

7. Add QA diagnostics without sensitive values.

Add count-only debug logging or a debug screen for:
- local file count
- local-only count
- cloud-synced local count
- cloud-only placeholder count
- pending upload count
- completed Cloud metadata count

8. Review and fix false marker paths before migration.

Specifically inspect:
- `saveMergedProject(...)` calling `markClipCloudSynced(candidate)` without upload
- any restore/copy/move path that transfers `_cloudSyncedPaths` without confirming metadata linkage
- any path where metadata pull adds placeholders to `_cloudSyncedPaths`

## 10. Go/No-Go Verdict

NO-GO for continuing R3 Cloud upload fixture QA against the current 7 clips.

Reasons:
- Current evidence shows 7 real local paths already present in `cloud_synced_paths`; they are not local-only candidates.
- Profile `기기 CLIP 7 + Cloud CLIP 7` is explainable as local file count plus Firestore completed count, not uploadable local-only inventory.
- The current Library transfer button logic will show upload only for selections with `cloudCount == 0`. The current 7 clips likely produce `cloudCount == selectedCount`, causing download behavior or no uploadable item in the `기기` filter.
- The state model and UI labels are ambiguous enough that QA cannot reliably create a local-only upload fixture without first creating or injecting a clearly local-only clip and verifying it is absent from `cloud_synced_paths`.

GO only after one of these is true:
- a verified local-only fixture exists: local file present, not `cloud_only://`, not in `cloud_synced_paths`, no completed Cloud metadata linkage; or
- the state model is fixed so Library exposes a clear `local-only/uploadable` state and count.

Recommended immediate next step: implement no product behavior yet. First create a scoped fix plan for explicit `ClipStorageState` derivation and UI label/filter semantics, then review it before code changes.

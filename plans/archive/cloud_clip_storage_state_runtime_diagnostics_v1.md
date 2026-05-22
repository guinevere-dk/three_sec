# Cloud/Device Clip Storage Runtime Diagnostics v1

작성일: 2026-05-19

기준:
- `plans/cloud_clip_storage_state_model_fix_plan_v1.md`
- `plans/cloud_clip_storage_state_model_phase1_report_v1.md`
- `plans/cloud_clip_storage_state_model_phase2a_report_v1.md`

범위:
- 현재 signed-in active paid 상태에서 Library clip storage state count를 count-only로 진단한다.
- raw local path, uid, email, token, order id, provider raw value는 기록하지 않는다.
- Firebase rules/index/schema, migration/backfill, Storage 삭제, Cloud copy, deploy는 수행하지 않는다.

## Runtime Context

| 항목 | 결과 |
| --- | --- |
| emulator 연결 | PASS |
| package | `com.dk.three_sec` |
| active paid local state | PASS |
| tier | `UserTier.standard` |
| product id | present only, raw value 미기록 |
| purchase date | present only, raw value 미기록 |
| current UI | Library 일반 앨범 상세 |
| current album count label | `일상 7 / 7 Clips` observed |
| visible clip thumbnail count | 7 |
| selected filter | `전체` |
| selection mode | false |

## Count-Only Inputs

SharedPreferences count-only probe:

| 항목 | count/result |
| --- | ---: |
| `cloud_synced_paths` entry present | true |
| `cloud_synced_paths` comma-like count | 11 |
| `cloud_synced_paths` local path marker count | 7 |
| `cloud_synced_paths` `cloud_only://` marker count | 5 |
| `local_index_entries_v1` entry present | true |
| local index clip entries | 10 |
| local index cloud metadata entries | 6 |
| local index cloud-only entries | 6 |

UI count-only probe:

| 항목 | count/result |
| --- | ---: |
| current Library visible clip thumbnails | 7 |
| current Library filter `전체` selected | true |
| current Library filter `기기` selected | false |
| current selection mode present | false |

## Derived Runtime Counts

There is no runtime debug endpoint in the app UI that directly prints `getStorageStateDebugCounts()`. The following counts are therefore computed using the same Phase 1/2A derived-state rules from count-only runtime inputs:

Rule basis:
- visible local file count is 7 from current Library UI.
- real local paths in legacy `cloud_synced_paths` are 7.
- Phase 1 `_hasCompletedCloudLink(path)` treats legacy real local path marker as Cloud linkage compatibility input.
- Phase 2A maps local file + Cloud linkage to `cloudSyncedLocal`.
- current visible list shows 7 entries and no visible Cloud-only placeholders in `전체`.

Derived counts for the current visible Library set:

| count | value | basis |
| --- | ---: | --- |
| `localFileCount` | 7 | current Library visible local clip count |
| `localOnlyCount` | 0 | all 7 visible local clips have legacy Cloud linkage markers |
| `cloudSyncedLocalCount` | 7 | 7 visible local clips + 7 real local markers |
| `cloudOnlyCount` | 0 | current visible set has no extra placeholder entries; global legacy placeholder markers exist but are not visible in current list |
| `pendingUploadCount` | 0 | no runtime pending upload evidence in current visible set |
| `failedUploadCount` | 0 | no runtime failed upload evidence in current visible set |
| `failedDownloadCount` | 0 | no runtime failed download evidence in current visible set |
| `uploadableCount` | 0 | `localOnly + failedUpload = 0` |

Global legacy marker note:
- `cloud_synced_paths_cloud_only_count=5` and `local_index_cloud_only_entries=6` show legacy Cloud-only metadata exists globally.
- Those entries are not counted as current visible `cloudOnlyCount` because the current Library UI shows 7 total entries, matching the local visible clip count.

## Selection Reducer Verification

Command:

```powershell
flutter test test\library_clip_transfer_action_test.dart
```

Result:

```text
All tests passed. 6 tests.
```

Verified reducer behavior:

| input state | expected action | result |
| --- | --- | --- |
| `localOnly` | upload / `cloud_upload_rounded` | PASS |
| `failedUpload` | upload retry / `cloud_upload_rounded` | PASS |
| `cloudOnly` | download / `download_rounded` | PASS |
| `cloudSyncedLocal` | cloudDone / `cloud_done_rounded` | PASS |
| mixed local/cloud | disabled / mixed icon | PASS |
| `pendingUpload` | progress / `sync_rounded` | PASS |

## Current 7 Clip Classification

Current 7 visible Library clips are classified as:

```text
cloudSyncedLocalCount=7
localOnlyCount=0
uploadableCount=0
```

Phase 2A expected action for selecting only these 7 synced local clips:

```text
LibraryClipTransferAction.cloudDone
icon=cloud_done_rounded
```

Therefore the old problem is now explicitly classified rather than ambiguous:
- These 7 clips are present on device.
- They also have legacy Cloud linkage markers.
- They are not local-only.
- They are not upload fixture candidates.

## R3 QA Resume Verdict

R3 upload fixture QA resume: NO-GO for the current 7 clips.

Reason:
- `uploadableCount == 0`
- current 7 visible clips derive to `cloudSyncedLocal`, not `localOnly`
- Phase 2A correctly prevents `cloudSyncedLocal` from appearing as upload or download action

## Required Next Step

새 local-only fixture가 필요하다.

Verified local-only fixture conditions:
- local file exists in a normal Library album.
- path is not `cloud_only://`.
- path is not present in legacy `cloud_synced_paths`.
- local index entry has no Cloud metadata linkage.
- no active completed Cloud metadata linkage is known for that file.
- derived state resolves to `localOnly`.
- `uploadableCount >= 1`.
- selecting the fixture resolves to upload / `cloud_upload_rounded`.

Recommended next workflow:
1. Stop using the current 7 clips as upload candidates.
2. Create or import a new local-only fixture without triggering Cloud auto-upload.
3. Re-run this count-only diagnostics.
4. Resume R3 upload capture only if `uploadableCount >= 1`.

No local fixture was created during this diagnostics run.

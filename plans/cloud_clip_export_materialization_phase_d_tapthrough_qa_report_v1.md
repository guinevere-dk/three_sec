# Cloud Clip Export Materialization Phase D Tap-through QA Report v1

## 1. Environment

- Device: Android emulator `emulator-5554`
- App package: `com.dk.three_sec`
- Date: 2026-05-21
- Account state from logs:
  - `tier=UserTier.standard`
  - `productId=3s_standard_monthly`

## 2. Scenario

Project:

- Project id: `1779326889309`
- Title: `Vlog_2026521`
- Clip count: 3
- Cloud-only clip count: 1
- Local clip count: 2

QA flow:

1. Relaunched emulator and app.
2. Confirmed Standard subscription state.
3. Entered edit screen for a project containing one Cloud-only clip.
4. Confirmed edit screen did not show `File Missing`.
5. Started export from the edit screen.
6. Confirmed Cloud-only clip was materialized into export session cache.
7. Confirmed native export succeeded and was saved to gallery.
8. Confirmed local project JSON preserved the original `cloud_only://...` path.

## 3. Key Logs

Project save before export:

```text
[VideoManager][ProjectCloudSave][start] isGuest=false clipCount=3 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
[VideoManager][ProjectCloudSave][done] localWrite=success cloudSaveStatus=success clipCount=3 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
```

Cloud-only materialization:

```text
[CloudService] 다운로드 요청: videoId=eA5Y...yDsx
[CloudService] 다운로드 완료: localPath=<redacted-path>
[EditScreen][Export][CloudClip][resolved] index=0 fromCache=false
[EditScreen][Export][CloudClip][inputs_ready] clipCount=3 cloudOnlyProjectClipCount=1 materializedClipCount=1 projectHasCachePath=false
```

Native export input:

```text
missingAudioSamples=/data/user/0/com.dk.three_sec/app_flutter/cloud_clip_session_cache/export_session_cache/eA5YIecPjHdgAEtMyDsx/clip_1779275872421.mp4|...
paths: [/data/user/0/com.dk.three_sec/app_flutter/cloud_clip_session_cache/export_session_cache/eA5YIecPjHdgAEtMyDsx/clip_1779275872421.mp4, ...]
```

Export result:

```text
[VideoManager][Export] invoke_merge_done ... result=/data/user/0/com.dk.three_sec/app_flutter/Vlogs/vlog_1779327057633.mp4 clipCount=3 quality=1080p attempt=1 resultExists=true resultBytes=740389
[VideoManager][Export] SavedToGallery result=/data/user/0/com.dk.three_sec/app_flutter/Vlogs/vlog_1779327057633.mp4 album=2S_Vlog
[exportComplete] ... "durationMs":6323,"fileSize":740389
```

Project save after export:

```text
[VideoManager][ProjectCloudSave][start] isGuest=false clipCount=3 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
[VideoManager][ProjectCloudSave][done] localWrite=success cloudSaveStatus=success clipCount=3 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
```

## 4. Local JSON Verification

Checked with:

```powershell
adb shell run-as com.dk.three_sec cat app_flutter/vlog_projects/1779326889309.json
```

Result:

- First clip path remained:

```text
cloud_only://일상/eA5YIecPjHdgAEtMyDsx/clip_1779275872421.mp4
```

- No `cloud_clip_session_cache` or `export_session_cache` path was written into project `clips`.
- `cloudProjectId` and `cloudSyncedAt` were present after export save.

## 5. Verdict

Phase D tap-through QA passed for the mixed project path:

- Cloud-only clip was materialized only for export input.
- Native export succeeded with 3 clips.
- Gallery save succeeded.
- Project state preserved the original `cloud_only://...` clip path.
- Project cloud save did not contain cache-like clip paths.

## 6. Remaining Risks

- Export cancellation during Cloud download was not tested.
- Export with a Cloud-only-only project was not separately tested.
- Session cache TTL/cleanup remains unimplemented.

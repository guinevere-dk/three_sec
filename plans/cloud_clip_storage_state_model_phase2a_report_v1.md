# Cloud/Device Clip Storage State Model Phase 2A Report v1

작성일: 2026-05-19

기준 문서:
- `plans/cloud_clip_storage_state_model_fix_plan_v1.md`
- `plans/cloud_clip_storage_state_model_phase1_report_v1.md`

범위:
- Library badge와 Cloud transfer button action을 `ClipStorageState` 기반으로 전환
- Profile count label 변경 없음
- Firebase rules/index/schema 변경 없음
- migration/backfill 실행 없음
- Storage path 변경/삭제 없음
- Cloud copy 구현 없음
- `cloud_synced_paths` destructive cleanup 없음

## 변경 파일

| 파일 | 변경 |
| --- | --- |
| `lib/managers/video_manager.dart` | `getClipStatusBadge(path)`를 `ClipStorageState` 기반으로 전환 |
| `lib/screens/library_screen.dart` | 선택 상태 reducer를 `ClipStorageState` 기반으로 전환, upload/download/cloud-done/progress/disabled action 분리 |
| `test/video_manager_clip_storage_state_test.dart` | badge copy/state 테스트 추가 |
| `test/library_clip_transfer_action_test.dart` | Library transfer action/icon reducer 테스트 추가 |
| `plans/cloud_clip_storage_state_model_phase2a_report_v1.md` | 구현/검증 보고서 추가 |

## 구현 요약

### Badge Semantics

`lib/managers/video_manager.dart:5086`

`getClipStatusBadge(path)`가 `getClipStorageState(path)`를 사용하도록 변경됐다.

| `ClipStorageState` | Badge |
| --- | --- |
| `localOnly` | `기기` |
| `pendingUpload` | `업로드 중` |
| `cloudSyncedLocal` | `동기화됨` |
| `cloudOnly` | `Cloud` |
| `failedUpload` | `업로드 실패` |
| `failedDownload` | `복원 실패` |

기존보다 pending/failed 상태가 더 명확히 분리된다.

### Transfer Action Reducer

`lib/screens/library_screen.dart:19`

새 enum:

```dart
enum LibraryClipTransferAction {
  upload,
  download,
  cloudDone,
  progress,
  disabled,
}
```

`lib/screens/library_screen.dart:27`

`resolveLibraryClipTransferAction(...)`는 selected clip들의 `ClipStorageState` 목록을 받아 action을 결정한다.

| Selection states | Action | Icon |
| --- | --- | --- |
| all `localOnly` or `failedUpload` | `upload` | `cloud_upload_rounded` |
| all `cloudOnly` or `failedDownload` | `download` | `download_rounded` |
| all `cloudSyncedLocal` | `cloudDone` | `cloud_done_rounded` |
| any `pendingUpload` | `progress` | `sync_rounded` |
| mixed local/cloud/synced | `disabled` | `download_for_offline_rounded` |

### Library Integration

`lib/screens/library_screen.dart:1029`

`_resolveSelectionActionState()` now maps selected paths through `videoManager.getClipStorageState`.

`lib/screens/library_screen.dart:1039`

`_transferHandlerForSelectionState(...)` behavior:
- `upload`: keeps `canStartNewCloudWrite()` gate, then `_moveSelectedLocalToCloud`
- `download`: keeps `canReadExistingCloudClips()` gate, then `_removeSelectedCloudBackup`
- `cloudDone`: shows a clear toast that the clip is already synced on device and Cloud
- `progress`: shows a clear toast that Cloud work is in progress
- `disabled`: shows a clear mixed-state toast

`lib/screens/library_screen.dart:1143`

`_moveSelectedLocalToCloudInBackground(...)` now validates upload targets using derived state. It proceeds only for:
- `localOnly`
- `failedUpload`

This prevents `cloudSyncedLocal` from being treated as uploadable while allowing failed upload retry semantics.

## Non-Changes

Intentionally unchanged:
- Profile `기기 CLIP` / `Cloud CLIP` labels and count sources
- `isClipVisibleByStorageFilter(...)` semantics
- CloudBackupScreen
- Firestore rules/index/schema
- Storage paths/objects
- migration/backfill
- `cloud_synced_paths` persistence/cleanup
- Cloud copy behavior

`lib/widgets/media_widgets.dart` did not require a code change. Existing `IconButton` accepts the new icons and existing disabled styling still applies when `onTransfer` is null. In Phase 2A, cloud-done/progress/mixed states are tappable to show an explanatory toast rather than silently doing nothing.

## 테스트 결과

### Focused Tests

명령:

```powershell
flutter test test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

결과:

```text
All tests passed. 14 tests.
```

추가/검증 항목:
- localOnly selection => upload action/icon
- cloudOnly selection => download action/icon
- cloudSyncedLocal selection => cloud-done disabled state/icon
- mixed selection => disabled action/icon
- failedUpload selection => upload retry action/icon
- pendingUpload selection => progress disabled action/icon
- badge copy is state-specific

### Full Test Suite

명령:

```powershell
flutter test
```

결과:

```text
All tests passed. 20 tests.
```

## Analyzer 결과

전체 명령:

```powershell
flutter analyze
```

결과:

```text
Exit code: 1
507 issues found.
```

분류:
- analyzer는 기존 저장소의 warning/info 누적으로 실패한다.
- 주요 유형은 기존 `avoid_print`, `deprecated_member_use`, `curly_braces_in_flow_control_structures`, unused warning 등이다.
- Phase 2A 신규 테스트 파일과 신규 reducer/helper 구간의 compile error는 관찰되지 않았다.

대상 파일 한정 명령:

```powershell
flutter analyze lib\managers\video_manager.dart lib\screens\library_screen.dart test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

결과:

```text
Exit code: 1
39 issues found.
```

분류:
- 39건은 기존 `video_manager.dart`/`library_screen.dart` 내부 info다.
- 신규 test 파일의 analyzer issue는 관찰되지 않았다.
- 신규 reducer/helper line range에서는 analyzer issue가 관찰되지 않았다.

## Risk Notes

- Phase 2A는 `cloudSyncedLocal` selection을 upload/download로 처리하지 않으므로 기존 7개 synced local clip에 대해 upload 버튼이 나타나지 않는 것은 의도된 동작이다.
- `failedUpload`는 upload retry로 분류된다. 만약 legacy marker가 붙은 failed upload path가 있다면 duplicate upload risk가 있으므로 Phase 2B에서 failed upload metadata와 marker repair policy를 검토해야 한다.
- `isClipVisibleByStorageFilter(..., 'device')`는 아직 기존 동작을 유지한다. 즉 `기기` filter semantics 문제는 Phase 2A 범위 밖이다.

## Verdict

Phase 2A implementation: PASS

R3 upload fixture QA resume:
- CONDITIONAL GO only if diagnostics show `uploadableCount >= 1` and the selected fixture resolves to `localOnly` or `failedUpload`.
- NO-GO against the previously observed 7 cloud-synced local clips, because they now correctly resolve to `cloudDone` rather than upload/download.

# Cloud/Device Clip Storage State Model Phase 1 Report v1

작성일: 2026-05-19

기준 문서:
- `plans/cloud_clip_storage_state_model_audit_v1.md`
- `plans/cloud_clip_storage_state_model_fix_plan_v1.md`

범위:
- Phase 1 derived `ClipStorageState` helper 구현
- UI filter/button/Profile label semantics 변경 없음
- Firebase rules/index/schema 변경 없음
- migration/backfill 실행 없음
- Storage 삭제 없음
- Cloud copy 구현 없음
- raw local path/uid/email/token/order id/provider 값 기록 없음

## 변경 파일

| 파일 | 변경 |
| --- | --- |
| `lib/managers/video_manager.dart` | `ClipStorageState` enum, state helper, uploadable predicate, count-only diagnostics 추가 |
| `test/video_manager_clip_storage_state_test.dart` | Phase 1 derived state focused tests 추가 |
| `plans/cloud_clip_storage_state_model_phase1_report_v1.md` | 구현/검증 보고서 추가 |

주의:
- 작업 시작 전부터 저장소에는 여러 dirty/untracked 파일이 있었다.
- 이번 Phase 1에서 의도적으로 수정한 코드 파일은 `lib/managers/video_manager.dart`와 `test/video_manager_clip_storage_state_test.dart`다.
- `dart format`이 `lib/managers/video_manager.dart` 전체 파일에 적용되면서, 이미 존재하던 인접 변경도 diff에 함께 보일 수 있다.

## 구현 요약

### Added enum

`lib/managers/video_manager.dart:34`

```dart
enum ClipStorageState {
  localOnly,
  pendingUpload,
  cloudSyncedLocal,
  cloudOnly,
  failedUpload,
  failedDownload,
}
```

### Added helper APIs

`lib/managers/video_manager.dart:4415`

추가 API:
- `getClipStorageState(String path)`
- `isLocalOnlyClip(String path)`
- `isCloudSyncedLocalClip(String path)`
- `isCloudOnlyClip(String path)`
- `isUploadableClip(String path)`
- `getStorageStateDebugCounts({Iterable<String>? paths})`

### State precedence

현재 Phase 1 판정 순서:
1. `pendingUpload` transfer state => `ClipStorageState.pendingUpload`
2. `failedUpload` transfer state => `ClipStorageState.failedUpload`
3. `failedDownload` transfer state => `ClipStorageState.failedDownload`
4. `cloud_only://` path => `ClipStorageState.cloudOnly`
5. local file exists + completed Cloud linkage or legacy marker => `cloudSyncedLocal`
6. local file exists + no Cloud linkage => `localOnly`
7. no local file + Cloud linkage => `cloudOnly`

### Legacy compatibility

`cloud_synced_paths`는 destructive cleanup 없이 compatibility input으로만 사용한다.

`lib/managers/video_manager.dart:4511` `_hasCompletedCloudLink(...)`:
- `cloud_only://` placeholder는 real local synced path와 분리해서 처리한다.
- real local path는 `_cloudMetadataByPath[path]` completed/active metadata 또는 legacy `_cloudSyncedPaths.contains(path)`로 Cloud linkage를 판정한다.
- 기존 UI 동작을 바꾸지 않기 위해 기존 `isClipCloudSynced(...)`, badge, filter, transfer button 로직은 그대로 유지했다.

### Count-only diagnostics

`getStorageStateDebugCounts(...)`는 raw path/uid를 출력하지 않고 다음 count만 반환한다.

반환 key:
- `localFileCount`
- `localOnlyCount`
- `cloudSyncedLocalCount`
- `cloudOnlyCount`
- `pendingUploadCount`
- `failedUploadCount`
- `failedDownloadCount`
- `uploadableCount`

`uploadableCount`는 `localOnly + failedUpload`만 포함한다.

## 테스트 결과

### Focused test

명령:

```powershell
flutter test test\video_manager_clip_storage_state_test.dart
```

결과:

```text
All tests passed. 7 tests.
```

검증한 항목:
- local file exists, no marker => `localOnly`
- local file exists, legacy `cloud_synced_paths` marker => `cloudSyncedLocal`
- `cloud_only://` placeholder => `cloudOnly`
- pending upload state wins
- failed upload state wins and remains uploadable
- failed download state wins
- placeholder is not counted as local file
- uploadable count includes only `localOnly` and `failedUpload`

### Full test suite

명령:

```powershell
flutter test
```

결과:

```text
All tests passed. 13 tests.
```

## Analyzer 결과

전체 명령:

```powershell
flutter analyze
```

결과:

```text
Exit code: 1
508 issues found.
```

분류:
- analyzer는 기존 저장소의 warning/info 누적으로 실패했다.
- 출력에는 `lib/main.dart`, `lib/services/iap_service.dart`, `lib/services/auth_service.dart`, 기존 `avoid_print`, `deprecated_member_use`, `curly_braces_in_flow_control_structures`, unused warning 등이 포함된다.
- Phase 1 신규 테스트 파일 또는 신규 `ClipStorageState` helper에 대한 compile error는 관찰되지 않았다.
- 전체 `flutter test`는 통과했다.

대상 파일 한정 명령:

```powershell
flutter analyze lib\managers\video_manager.dart test\video_manager_clip_storage_state_test.dart
```

결과:

```text
Exit code: 1
34 issues found.
```

분류:
- 34건은 모두 기존 `video_manager.dart` 내부의 `avoid_print`, `curly_braces_in_flow_control_structures`, `no_leading_underscores_for_local_identifiers`, `unnecessary_brace_in_string_interps` info다.
- 신규 테스트 파일의 analyzer issue는 관찰되지 않았다.
- 신규 helper line range에서는 analyzer issue가 관찰되지 않았다.

## 현재 제한

Phase 1은 helper만 추가했다. 다음 항목은 의도적으로 변경하지 않았다.
- Library filter semantics
- Library transfer button semantics
- Profile `기기 CLIP` / `Cloud CLIP` label 및 count
- Firestore/Storage schema
- `cloud_synced_paths` persistence split
- migration/backfill/cleanup

따라서 현재 UI에서 upload button이 바로 바뀌지는 않는다. R3 QA 재개에는 Phase 2 또는 verified local-only fixture 확보가 여전히 필요하다.

## 다음 단계

권장 Phase 2:
- `getClipStatusBadge(...)`를 `ClipStorageState` 기반으로 전환
- Library selection reducer를 `ClipStorageState` 기반으로 전환
- `기기` filter와 `업로드 가능` count/filter 의미를 제품 정책에 맞춰 확정
- 기존 7개 clip에 대해 count-only diagnostics로 `uploadableCount`를 확인

## Verdict

Phase 1 implementation: PASS

R3 upload fixture QA resume: NO-GO until one of the following is true:
- derived diagnostics show `uploadableCount >= 1`, or
- a verified local-only fixture is created, or
- Phase 2 updates UI transfer semantics and QA route is revalidated.

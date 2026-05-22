# Cloud Clip Direct Edit, Export, Project Cloud Save Plan v1

## 1. 목적

Standard 구독의 핵심 UX는 Cloud Clip을 라이브러리로 명시 다운로드하지 않아도 편집 화면에서 바로 사용할 수 있어야 한다. 현재 QA에서는 Cloud 이동 후 생성된 `cloud_only://...` 클립이 편집 화면에서 로컬 파일처럼 검사되어 `File Missing`으로 표시되었다.

이 문서는 아직 구현하지 않고, 다음 세 가지를 계획한다.

- Cloud-only clip을 다운로드 UX 없이 편집 화면에 연결하는 방식.
- Export 시점에 Cloud-only clip이 포함된 프로젝트를 어떻게 처리할지.
- 편집 중인 프로젝트가 기본적으로 Cloud에 저장되는 현재 상태 확인과 보강 계획.

## 2. 보존해야 할 계약

다음 계약은 변경하지 않는다.

- Firestore 컬렉션: `videos`, `users`, `vlog_projects`.
- Storage 경로: `users/{uid}/videos/{videoId}/{fileName}`.
- IAP product id: `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual`.
- 로컬 프로젝트 저장 계열: `vlogs/vlog_projects`, `vlog_projects/{projectId}.json`.
- 프로젝트의 `clipPaths`에는 기존 로컬 path와 `cloud_only://...` placeholder를 계속 허용한다.

임시 편집 캐시는 사용자 라이브러리의 다운로드된 클립으로 취급하지 않는다.

## 3. 현재 상태 요약

### 3.1 Cloud-only clip 상태

관련 코드:

- `lib/managers/video_manager.dart`
  - `ClipStorageState.cloudOnly`
  - `_cloudPlaceholderPath(...)`가 `cloud_only://{album}/{videoId}/{fileName}` 생성.
  - `isCloudOnlyPlaceholder(...)`, `getCloudMetadataForPath(...)` 제공.
  - `getVideoDuration(...)`은 `cloud_only://`에 대해 `Duration.zero` 반환.
  - `getThumbnail(...)`은 `cloud_only://`에 대해 로컬 썸네일 생성을 하지 않음.

QA 로그:

```text
[LibraryTransfer] render selected_count=1 state_counts localOnly=0 cloudOnly=1 ...
[EditScreen][Diag][Missing][load] index=0 path=cloud_only://.../clip_....mp4
[EditScreen][Diag][Missing][not_found] index=0 path=cloud_only://...
```

판정:

- Cloud 업로드/Cloud-only 목록화는 동작한다.
- 편집 화면은 Cloud-only placeholder를 재생 가능한 원본으로 resolve하지 않는다.
- 현재 UX는 `Cloud Clip 직접 편집` 요구사항을 만족하지 못한다.

### 3.2 편집 화면 로딩

관련 코드:

- `lib/screens/video_edit_screen.dart`
  - `_loadClip(...)`에서 `File(clip.path).exists()`로 원본 존재를 판단.
  - 파일이 없으면 `_missingClipIndexes`에 추가하고 `File Missing` UI로 전환.
  - `_handleExport()`에서도 모든 clip에 대해 `File(clip.path).existsSync()` 선검사를 수행.

판정:

- `cloud_only://`는 파일 시스템 경로가 아니므로 현재 구조에서는 preview와 export 모두 막힌다.
- `File Missing`은 실제 원본 손상과 Cloud-only 미해결 상태를 구분하지 못한다.

### 3.3 Export

관련 코드:

- `lib/screens/video_edit_screen.dart`
  - `_handleExport()`가 export dialog 전에 파일 존재를 검사.
  - export 직전 `videoManager.saveProject(widget.project)` 호출.
  - `videoManager.exportVlog(...)` 호출.
- `lib/managers/video_manager.dart`
  - `exportVlog(...)`는 native engine에 전달할 로컬 입력 path 목록을 전제로 동작한다.

판정:

- 현재 Cloud-only clip은 export 전에 `Source file missing` dialog로 차단된다.
- preflight를 통과시키더라도 native export engine은 실제 로컬 파일 path가 필요할 가능성이 높다.
- 따라서 export 시점에는 Cloud-only clip을 반드시 export용 local materialized file로 변환해야 한다.

### 3.4 프로젝트 Cloud 저장

관련 코드:

- `lib/managers/video_manager.dart`
  - `saveProject(project)`는 로컬 JSON 저장 전, 게스트가 아니면 `CloudService().upsertVlogProjectMetadata(project)` 호출.
  - cloud upsert 성공 시 `cloudProjectId`, `cloudSyncedAt`을 로컬 프로젝트에 반영.
- `lib/services/cloud_service.dart`
  - `upsertVlogProjectMetadata(project)`는 `vlog_projects/{projectDocId}`에 `uid`, `localProjectId`, `title`, `clipPaths`, `clipCount`, `folderName`, `lockState`, timestamp 계열을 저장.
- `lib/screens/video_edit_screen.dart`
  - `_persistProjectAutosave(...)`, close, dispose, export 직전에 `saveProject(...)` 호출.

판정:

- 구조상 비게스트 사용자의 편집 중 프로젝트는 autosave와 export 직전 저장을 통해 Cloud metadata 저장 경로가 있다.
- 단, Cloud 저장 실패가 사용자에게 명확히 노출되는지, autosave 중복/순서/종료 시 누락이 없는지는 QA로 확인해야 한다.
- 프로젝트 Cloud 저장은 영상 파일 업로드가 아니라 `vlog_projects` metadata 저장이다. Cloud-only clip 자체는 `clipPaths`에 placeholder로 남겨야 한다.

## 4. 목표 UX

### 4.1 편집 진입

사용자는 Cloud Clip을 선택하고 편집 화면으로 들어간다. 별도의 다운로드 버튼을 누르지 않는다.

앱 내부 동작:

1. `cloud_only://...` clip을 감지한다.
2. `VideoManager.getCloudMetadataForPath(path)` 또는 Cloud resolver로 `videoId`, `storagePath`, `fileName`, `duration`, thumbnail metadata를 얻는다.
3. 편집 세션 전용 캐시 파일을 준비한다.
4. 준비가 끝난 clip은 기존 `VideoPlayerController.file(...)` 경로로 재생한다.
5. 프로젝트에 저장되는 clip path는 계속 `cloud_only://...`이다.

사용자에게 보이는 상태:

- `File Missing`이 아니라 `Cloud Clip 준비 중` 또는 기존 로딩 UI.
- 준비 실패 시 `Cloud Clip을 불러올 수 없음` 계열 오류.
- 오프라인/권한/삭제/Storage missing을 별도 reason으로 구분.

### 4.2 다운로드와 세션 캐시의 차이

명시 다운로드:

- 라이브러리 raw clip 폴더에 저장.
- Cloud-only 상태를 local/cloud synced 상태로 변경할 수 있음.
- 사용자의 클립 보관 상태에 영향을 줌.

편집 세션 캐시:

- 앱 내부 임시 편집 캐시 폴더에 저장.
- 라이브러리 상태는 계속 Cloud-only.
- 프로젝트 JSON/Firestore `clipPaths`에는 임시 path를 저장하지 않음.
- 편집 종료, 앱 재시작, 용량 제한, TTL에 따라 정리 가능.

## 5. 설계 계획

### 5.1 Cloud Clip Resolver

새 책임을 둔다.

```text
cloud_only://... -> CloudClipSource
CloudClipSource -> session local file path
```

후보 API:

```dart
class CloudClipResolvedSource {
  final String originalClipPath; // cloud_only://...
  final String videoId;
  final String storagePath;
  final String sessionLocalPath;
  final int fileSize;
  final Duration? duration;
  final bool fromCache;
}
```

필요 기능:

- placeholder parse.
- metadata lookup.
- auth/read gate 확인: `canReadExistingCloudClips()`.
- Storage download to temp file.
- file size 검증.
- atomic rename.
- cache index 관리.
- 실패 reason code 정규화.

주의:

- 기존 `CloudService.downloadVideo(...)`를 그대로 쓰면 라이브러리 다운로드 의미와 섞일 수 있다.
- 내부 구현은 공통 download primitive를 재사용하되, public action은 `download_move`와 분리한다.
- `markVideoMovedToDevice(...)`는 세션 캐시에서는 호출하지 않는다.

### 5.2 편집 화면 변경 계획

대상:

- `lib/screens/video_edit_screen.dart`
- 필요 시 `lib/managers/video_manager.dart`
- 필요 시 `lib/services/cloud_service.dart`

변경 방향:

1. `_loadClip(index)`에서 `cloud_only://`를 먼저 분기한다.
2. Cloud-only면 `File(clip.path).exists()` 검사로 가지 않는다.
3. resolver가 session file을 준비한다.
4. preview controller에는 session file path를 전달한다.
5. `_clips[index].path`는 변경하지 않는다.
6. controller dataSource 비교는 original path가 아니라 resolved playback source를 기준으로 보조 맵을 둔다.

상태 예시:

```dart
enum EditClipLoadState {
  localReady,
  cloudResolving,
  cloudReady,
  cloudFailed,
  localMissing,
}
```

편집 UI 처리:

- `localMissing`: 기존 File Missing UI 유지.
- `cloudResolving`: 로딩 표시.
- `cloudFailed`: 재시도 버튼, 오류 copy.
- `cloudReady`: 기존 편집 UI.

### 5.3 Duration, thumbnail, timeline

현재 `getVideoDuration(cloud_only://...)`은 `Duration.zero`를 반환한다.

계획:

- 세션 캐시 준비 전에는 Firestore metadata의 duration이 있으면 사용한다.
- metadata duration이 없으면 세션 캐시 파일 준비 후 로컬 duration 측정.
- timeline thumbnail은 다음 우선순위로 처리한다.
  1. Cloud thumbnail metadata가 있으면 즉시 표시.
  2. session file 준비 후 로컬 timeline thumbnail 생성.
  3. 실패 시 placeholder.

프로젝트에 duration cache를 저장할 때:

- 가능하면 original `cloud_only://` path 기준으로 duration metadata를 저장한다.
- session local path 기준 영구 저장은 피한다.

### 5.4 Export 시점 처리

Export는 preview보다 더 엄격해야 한다.

현재 차단 지점:

- `_handleExport()`의 `File(clip.path).existsSync()` preflight.

변경 방향:

1. export preflight를 `clip.path` 파일 존재 검사에서 `ExportInputResolver` 검사로 바꾼다.
2. local clip은 기존 path를 그대로 사용한다.
3. cloud-only clip은 session/export cache file을 준비한다.
4. 모든 clip이 materialized된 뒤에만 export dialog를 진행한다.
5. native `exportVlog(...)`에는 materialized local path를 가진 export-only clip list를 전달한다.
6. `widget.project.clips`에는 original `cloud_only://` path를 유지한다.

권장 흐름:

```text
Export button
  -> flush autosave with original clipPaths
  -> resolve export inputs
       local path: exists check
       cloud_only: prepare session/export cache
  -> build exportClips = project clips copied with materialized paths
  -> exportVlog(clips: exportClips, ...)
  -> keep project.clips unchanged
  -> saveProject(project) after export metadata update if needed
```

실패 처리:

- `cloud_auth_required`: 로그인 필요.
- `cloud_read_blocked`: 구독 만료/grace 정책으로 읽기 불가.
- `cloud_metadata_missing`: `videos/{videoId}` 없음.
- `cloud_storage_missing`: `storagePath` 객체 없음.
- `cloud_network`: 네트워크 실패.
- `cloud_cache_write_failed`: 로컬 임시 저장 실패.
- `local_source_missing`: 기존 로컬 파일 missing.

사용자 copy:

- Cloud-only 실패는 `Source file missing`으로 표시하지 않는다.
- 예: `Cloud Clip을 불러오지 못해 내보내기를 진행할 수 없습니다.`

취소 처리:

- export 준비 중 사용자가 취소하면 진행 중인 Cloud materialize 작업을 취소하거나 결과를 폐기한다.
- 이미 받은 session cache는 TTL 정리 대상으로 둔다.

### 5.5 Project Cloud Save

목표:

- Standard 이상 사용자가 편집 중인 프로젝트는 기본적으로 Cloud metadata에 저장된다.
- Cloud-only clip path는 `vlog_projects.clipPaths`에 `cloud_only://...` 형태로 저장된다.
- 세션 캐시 path는 저장하지 않는다.

현재 구조는 대체로 목표에 맞다.

확인해야 할 것:

1. 편집 진입 직후 autosave가 `vlog_projects` upsert를 수행하는지.
2. state change 후 debounce autosave가 Cloud upsert까지 성공하는지.
3. close 버튼, Android back, dispose에서 마지막 변경이 누락되지 않는지.
4. export 직전 저장이 Cloud까지 완료되는지.
5. Cloud upsert 실패 시 로컬 저장만 성공하고 사용자가 모르는 상태가 되는지.
6. `cloudProjectId`, `cloudSyncedAt`이 로컬 프로젝트와 리스트 상태에 반영되는지.
7. `clipPaths`에 session cache path가 섞이지 않는지.

보강 계획:

- `saveProject` 결과를 성공/부분성공/실패로 표현하는 반환 타입 검토.
- autosave 로그에 `cloud_upsert_success`, `cloud_upsert_skipped_guest`, `cloud_upsert_failed`를 명확히 남긴다.
- 편집 화면 상단 또는 project metadata에 `Cloud saved` 상태를 표시할지 별도 판단한다.
- export 직전 `flushAutosave`는 original project state 기준으로 먼저 수행한다.
- export용 materialized clip list는 project state에 write-back하지 않는다.

## 6. 구현 순서 제안

### Phase A: Read-only 확인

- 현재 QA 로그에서 `vlog_projects` upsert가 편집 autosave/export 직전에 발생하는지 확인.
- Firestore emulator 또는 실제 test 계정에서 `clipPaths` 값 확인.
- Cloud-only clip이 포함된 project 저장 시 `cloud_only://...`가 유지되는지 확인.

완료 기준:

- 현재 프로젝트 Cloud 저장 상태를 `정상`, `부분 정상`, `실패`로 판정.
- Cloud save 실패가 로그에서 식별 가능해야 한다.

### Phase B: Resolver 설계/테스트 단위 추가

- placeholder parse 테스트.
- metadata missing/storage missing reason 테스트.
- session cache path 생성 규칙 테스트.
- library download path와 session cache path가 분리되는지 테스트.

완료 기준:

- Firestore/Storage schema 변경 없음.
- `markVideoMovedToDevice`가 session cache에서 호출되지 않음.

### Phase C: 편집 preview 연동

- `_loadClip`에 Cloud resolving 상태 추가.
- Cloud-only clip preview 재생.
- mixed project에서 local/cloud clip 전환.
- duration/timeline thumbnail fallback.

완료 기준:

- Cloud-only 단독 프로젝트가 `File Missing`을 표시하지 않음.
- local + cloud mixed project에서 swipe/timeline 선택이 정상.

### Phase D: Export materialization

- `_handleExport` preflight 교체.
- export-only clip list 도입.
- export 준비 progress에 Cloud materialize phase 추가.
- 실패 reason별 dialog/toast 분리.

완료 기준:

- Cloud-only 포함 프로젝트 export 성공.
- project JSON/Firestore에는 original `cloud_only://` path 유지.
- export 실패 시 기존 로컬 missing과 Cloud load failure가 구분됨.

### Phase E: Project Cloud Save 보강

- `saveProject` cloud upsert 결과 계측 강화.
- autosave/close/export 직전 Cloud 저장 검증.
- QA checklist에 Firestore `vlog_projects` 확인 항목 추가.

완료 기준:

- 편집 중 변경이 Cloud project metadata에 저장됨.
- export 전 최종 상태가 Cloud에 반영됨.
- offline/Cloud 실패 시 로컬 보존과 재시도 계획이 명확함.

## 7. QA 체크리스트

### 7.1 Cloud Clip direct edit

- Standard 계정으로 로그인.
- local clip을 Cloud로 이동.
- Cloud-only clip만 선택해 프로젝트 생성/편집 진입.
- `File Missing` 미표시 확인.
- preview 재생 확인.
- trim 변경 후 autosave 로그 확인.
- 앱 재시작 후 같은 프로젝트 재진입 확인.

### 7.2 Mixed project

- local clip 1개 + cloud-only clip 1개로 프로젝트 생성.
- cloud clip이 첫 번째/중간/마지막에 있을 때 모두 확인.
- timeline 선택, swipe, playback speed, trim, volume 변경 확인.

### 7.3 Export

- Cloud-only 단독 프로젝트 export.
- local + cloud mixed project export.
- Cloud materialize 중 취소.
- 네트워크 차단 후 export 실패 copy 확인.
- export 결과 파일 생성, 길이, 클립 순서 확인.
- export 후 프로젝트 `clipPaths`가 임시 cache path로 바뀌지 않았는지 확인.

### 7.4 Project Cloud save

- 편집 진입 직후 `vlog_projects` upsert 로그 확인.
- 편집 변경 후 autosave upsert 로그 확인.
- export 직전 saveProject upsert 로그 확인.
- Firestore `vlog_projects/{projectId}.clipPaths`에 `cloud_only://...`가 유지되는지 확인.
- `cloudProjectId`, `cloudSyncedAt` 로컬 반영 확인.
- Cloud save 실패 상황에서 로컬 저장 보존 확인.

## 8. 주요 리스크

- 네트워크 파일 스트리밍을 직접 preview에 쓰면 trim/timeline/export와 동작 차이가 생길 수 있다.
- 세션 캐시를 project path에 섞으면 다른 기기/재시작/Cloud restore가 깨질 수 있다.
- export-only clip list를 project에 되돌려 쓰면 Cloud project metadata가 임시 경로로 오염될 수 있다.
- cache cleanup이 과하면 export 중 원본이 사라질 수 있고, 느슨하면 저장공간이 증가한다.
- Cloud save 실패가 조용히 묻히면 사용자는 프로젝트가 Cloud에 저장됐다고 오해할 수 있다.

## 9. 결론

다운로드 없는 Cloud Clip 편집 UX는 가능하다. 단, 실제 preview/export 엔진은 로컬 파일 입력을 요구하므로 내부적으로는 세션 또는 export 캐시에 materialize해야 한다. 중요한 점은 이 materialize를 사용자 라이브러리 다운로드와 분리하고, 프로젝트 저장 계약에는 `cloud_only://...` 원본 참조만 남기는 것이다.

프로젝트 Cloud 저장은 현재 구조상 비게스트 사용자에게 기본 경로가 존재한다. 다음 단계에서는 런타임 로그와 Firestore 문서로 autosave/export 직전 저장이 실제로 성공하는지 확인하고, 실패가 조용히 묻히지 않도록 계측과 결과 표현을 보강해야 한다.

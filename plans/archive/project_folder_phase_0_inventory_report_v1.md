# Project Folder Phase 0 Inventory Report v1

작성일: 2026-05-21

## 범위

Phase 0은 Project 탭 재노출 전 기존 숨김 처리와 라우팅 계약을 확인하는 단계다.

이번 단계에서는 Flutter UI, Firebase, DB schema, Storage path, IAP product id를 변경하지 않았다. 기존 프로젝트 데이터와 경로 계약을 보존하기 위해 inventory와 영향 분류만 수행했다.

## 확인한 파일

- `AGENTS.md`
- `CURRENT_PHASE.md`
- `DATA_COMPATIBILITY.md`
- `plans/project_folder_reintroduction_standard_plan_v1.md`
- `plans/archive/ver1_free_initial_launch_plan_v1.md`
- `lib/main.dart`
- `lib/services/notification_settings_service.dart`
- `lib/screens/project_screen.dart`
- `lib/managers/video_manager.dart`

## 현재 상태 요약

### Project 화면

- `lib/screens/project_screen.dart`에 `ProjectScreen`이 존재한다.
- ProjectScreen은 폴더 목록, 폴더 상세, 프로젝트 선택 모드, 이동/복사/삭제/복원 액션을 이미 포함한다.
- ProjectScreen은 `VideoManager.filteredProjects`, `VlogProject.folderName`, `moveProjectToFolder`, `copyProjectToFolder`, `moveProjectToTrash`, `restoreProjectFromTrash`를 사용한다.
- ProjectScreen 내부에는 Standard 이상이면 편집 화면으로 이동하고, Free에서는 720p direct export를 수행하는 `_openProjectWithTierRouting` 흐름이 있다.

### 메인 탭 구조

현재 `lib/main.dart`의 메인 탭은 3개다.

| index | 현재 탭 | builder |
|---:|---|---|
| 0 | Camera | `_buildCaptureTab()` |
| 1 | Library | `_buildLibraryTab()` |
| 2 | Profile | `_buildProfileTab()` |

확인 지점:

- `IndexedStack` children은 `_buildCaptureTab()`, `_buildLibraryTab()`, `_buildProfileTab()`만 포함한다.
- `_buildBenchmarkBottomNav()`의 item은 `Camera`, `Library`, `Profile`만 포함한다.
- `ProjectScreen`은 `main.dart`에 import되어 있지 않고, 메인 탭에 연결되어 있지 않다.

판단:

- Project 기능은 삭제된 것이 아니라 main tab surface에서 숨겨진 상태다.
- Phase P1에서는 ProjectScreen을 새로 만들기보다 기존 ProjectScreen을 main tab에 다시 연결하는 방향이 적절하다.

### 알림 라우팅

`lib/services/notification_settings_service.dart`의 `_mainTabRouteMap`은 현재 3탭 구조를 기준으로 한다.

현재 매핑:

- `capture`, `camera` -> `0`
- `library`, `album` -> `1`
- `profile`, `settings` -> `2`

`resolveMainTabIndexFromPayload`도 숫자 payload를 `0..2`까지만 허용한다.

`lib/main.dart`의 `_applyNotificationRoute`도 반환 index가 `0..2` 범위를 벗어나면 invalid로 무시한다.

판단:

- Project 탭을 추가하면 notification route의 허용 범위와 route map을 함께 확장해야 한다.
- `project`, `projects`, `vlog`, `vlog_project` 같은 payload alias를 어느 index로 보낼지 Phase P1에서 고정해야 한다.

### 편집/내보내기 완료 후 복귀 지점

`lib/main.dart`의 `_handleMerge`는 Standard 이상 사용자가 편집 화면에서 돌아온 뒤 `_selectedIndex = 1`로 이동한다.

현재 index `1`은 Library다.

코드 주석은 “프로젝트 목록으로 복귀시키는 UX가 자연스럽다”는 의도를 갖고 있지만, Project 탭이 숨겨진 상태라 Library로 복귀하고 있다.

판단:

- Project 탭이 재노출되면 이 복귀 지점은 Project index로 바뀌어야 한다.
- 단, 튜토리얼 흐름은 Library 중심으로 설계되어 있으므로 tutorial completion 흐름의 `_selectedIndex = 1`은 별도 검토가 필요하다.

### Tutorial index 의존성

튜토리얼 관련 로직은 Library index `1`을 직접 사용한다.

확인된 예:

- 샘플 클립 준비 후 `_selectedIndex = 1`
- export 후 tutorial phase 4 진입 시 `_selectedIndex = 1`
- Library create project 버튼 visibility callback은 `_selectedIndex`를 로그에 포함한다.

판단:

- Project 탭을 Camera와 Library 사이에 끼우면 Library index가 바뀌어 tutorial이 깨질 수 있다.
- Phase P1에서는 기존 index 보존을 우선해 Project를 `Profile` 앞, 즉 `Camera=0`, `Library=1`, `Project=2`, `Profile=3`으로 두는 안이 가장 안전하다.

### Profile index 의존성

`_buildBenchmarkBottomNav()`의 onTap은 `index == 2`일 때 Profile 탭 진입 로그를 남긴다.

판단:

- Project를 index `2`로 추가하면 현재 Profile 로그가 Project 탭에서 실행되는 버그가 생긴다.
- Phase P1에서 Profile index를 상수화하거나 `index == kProfileTabIndex`로 변경해야 한다.

### Project folder 데이터 경계

`ProjectScreen`은 현재 folder list에 `videoManager.vlogAlbums`를 사용한다.

`VideoManager`에는 `_vlogFoldersBaseName = 'vlog_folders'`, `currentVlogFolder`, `vlogAlbums`, `vlogProjects`가 존재한다.

판단:

- 현재 구현은 Project folder와 Library album이 같은 list처럼 취급될 위험이 있다.
- Phase P1은 탭 재노출과 라우팅 복구까지로 제한하고, Project folder 데이터 분리는 Phase P2에서 다루는 것이 안전하다.

## Phase P1 권장 index 계약

Project 탭 추가 시 기존 Library index를 유지하는 안을 권장한다.

| index | Phase P1 권장 탭 | 이유 |
|---:|---|---|
| 0 | Camera | 기존 캡처/알림 계약 유지 |
| 1 | Library | tutorial, import, merge 시작 흐름 유지 |
| 2 | Project | 신규 재노출 |
| 3 | Profile | 기존 Profile index 의존성 수정 필요 |

이 구조는 Library index를 유지하므로 튜토리얼과 Library 기반 merge 시작 흐름의 변경 폭이 가장 작다.

## Phase P1 변경 후보

- `main.dart`
  - `project_screen.dart` import 추가
  - `_buildProjectTab()` 추가
  - `IndexedStack` children에 `_buildProjectTab()` 추가
  - bottom nav item에 `Project` 추가
  - Profile tab logging 조건을 `index == 3` 또는 상수 기반으로 변경
  - `_applyNotificationRoute`의 허용 index 상한을 `3`으로 변경
  - `_handleMerge` 편집/내보내기 완료 후 `_selectedIndex = 2`로 변경
- `notification_settings_service.dart`
  - `_mainTabRouteMap`에 Project alias 추가
  - numeric index 허용 범위를 `0..3`으로 확장
  - 주석의 지원 값 문구 갱신

## 이번 단계에서 변경하지 않은 것

- Project 탭을 실제로 노출하지 않았다.
- Project folder API를 새로 만들지 않았다.
- `vlog_projects`, `vlog_folders`, `folderName` 계약을 변경하지 않았다.
- Free/Standard gate 정책을 변경하지 않았다.
- ProjectScreen의 `vlogAlbums` 재사용 문제를 수정하지 않았다.
- 깨진 UI 문자열을 정리하지 않았다.

## 남은 리스크

- Phase P1에서 Profile index 의존성을 모두 고치지 않으면 Project 탭 진입 시 Profile 관련 로그/동작이 섞일 수 있다.
- 알림 payload가 숫자 index를 직접 보내는 경우, 기존 서버/캠페인 payload와 새 4탭 index 계약의 호환성을 확인해야 한다.
- ProjectScreen이 `vlogAlbums`를 재사용하므로, 탭만 재노출하면 Project folder와 Library album이 섞여 보일 수 있다.
- ProjectScreen의 Free direct export 흐름은 Standard 유료 정책과 충돌 가능성이 있어 Phase P4에서 제품 결정을 반영해야 한다.

## Phase 0 결론

Project 기능은 코드상 삭제된 상태가 아니라 main tab에서 숨겨진 상태다.

다음 단계는 기존 Library index를 유지하면서 Project를 index `2`로 추가하고, Profile을 index `3`으로 밀어내는 방식이 가장 작고 안전하다. 이때 알림 라우팅, Profile onTap 조건, merge 완료 후 복귀 index를 함께 수정해야 한다.

# Project Folder Reintroduction Plan v1

작성일: 2026-05-21

## 목적

Standard 유료 구독과 편집 프로젝트가 정식 기능이 되었으므로, 사용자가 편집 중이거나 저장된 프로젝트를 찾고 관리할 수 있는 `Project` 폴더 영역을 다시 노출한다.

구현 전 목표는 기존에 숨김 처리된 Project 구조가 있으면 재노출 계획을 세우고, 없다면 Library와 유사한 폴더/상세 구조로 확장하는 것이다.

## 현재 확인된 기반

- `lib/screens/project_screen.dart`가 이미 존재한다.
- Project 화면은 폴더 목록, 폴더 상세, 프로젝트 선택 모드, 이동/복사/삭제/복원 액션, 썸네일 카드 구조를 이미 일부 포함한다.
- `lib/managers/video_manager.dart`는 `VlogProject`, `vlog_projects`, `vlog_folders`, `folderName`, `filteredProjects`, `moveProjectToFolder`, `copyProjectToFolder`, `moveProjectToTrash`, `restoreProjectFromTrash` 흐름을 이미 가진다.
- `plans/archive/ver1_free_initial_launch_plan_v1.md` 기준으로 Free 초기 출시 때 Project 탭이 의도적으로 숨김 처리된 이력이 있다.
- `DATA_COMPATIBILITY.md` 기준 기존 로컬/클라우드 계약은 유지해야 한다.

## 보존해야 할 계약

- `vlog_projects/{projectId}.json` 로컬 프로젝트 JSON 경로는 변경하지 않는다.
- Firestore `vlog_projects/{projectId}` 컬렉션/문서 계약은 변경하지 않는다.
- `folderName`, `clipPaths`, `clipCloudIds`, `cloudProjectId`, `cloudSyncedAt` 등 기존 프로젝트 필드는 rename하지 않는다.
- `vlogs/vlog_folders/{folderName}` 계열의 기존 프로젝트 폴더 구조는 삭제하거나 초기화하지 않는다.
- Cloud-only clip을 편집/내보내기용 세션 캐시에 materialize하더라도 프로젝트 JSON의 `clipPaths`는 원본 `cloud_only://...` 참조를 보존한다.
- IAP product id와 Standard 구독 검증 계약은 변경하지 않는다.

## 목표 UX

### Project 탭

- 하단 탭에 `Project`를 다시 노출한다.
- Standard 시대의 핵심 작업 공간으로, 사용자가 편집 프로젝트를 Library와 분리해서 찾을 수 있어야 한다.
- 기존 프로젝트 데이터가 있는 사용자는 구독 상태와 무관하게 프로젝트 목록 자체가 숨겨지지 않아야 한다.
- Standard 전용 액션은 구독 상태에 따라 gate 처리한다.

### 폴더 목록

- Library의 앨범 목록과 유사한 폴더 그리드 구조를 사용한다.
- 기본 폴더, 사용자 생성 폴더, 휴지통을 분리해서 보여준다.
- 각 폴더는 프로젝트 개수, 대표 썸네일, Cloud 저장 상태 요약을 표시할 수 있다.
- 폴더 생성, 이름 표시, 선택 모드, 삭제/정리 액션은 Library와 조작 감각을 맞춘다.

### 폴더 상세

- 프로젝트 카드 그리드로 표시한다.
- 카드에는 대표 썸네일, 프로젝트명, 수정일, 클립 개수, Cloud 저장 상태, 구독 필요 상태를 표시한다.
- Cloud-only clip이 포함된 프로젝트도 `File Missing`처럼 보이지 않아야 한다.
- 선택 모드에서 이동, 복사, 휴지통 이동, 복원, 삭제를 지원한다.

### 편집/내보내기 진입

- Standard 사용자는 Project에서 프로젝트를 열면 편집 화면으로 진입한다.
- Cloud-only 또는 mixed 프로젝트는 다운로드 화면을 거치지 않고 편집 세션에서 필요한 소스만 resolver/cache를 통해 준비한다.
- 편집 후 뒤로가기, 저장, 내보내기 완료 후에는 Library가 아니라 Project 컨텍스트로 돌아오는 것이 기본이다.
- 내보내기 시점에는 Phase D의 export materialization 규칙을 유지한다.

## 구현 계획

### Phase P0. 기존 숨김 처리 확인

- `main.dart`의 bottom navigation item, tab index, IndexedStack/page builder에서 Project가 숨겨진 지점을 확인한다.
- notification route, initial tab route, edit/export 완료 후 이동 index가 3탭 구조를 가정하는지 확인한다.
- 숨김 처리된 Project 코드를 삭제하지 않고 재노출 가능한 형태인지 판단한다.

### Phase P1. Project 탭 재노출

- Bottom navigation에 `Project` 탭을 추가한다.
- ProjectScreen을 main tab 구성에 다시 연결한다.
- 기존 `Library`, `Profile`, capture/home 탭 index와 충돌하지 않도록 route index contract를 정리한다.
- 편집 생성/편집 완료/내보내기 완료 후 이동 대상을 Project 탭으로 조정한다.
- 알림 payload에서 tab index를 해석하는 코드가 있다면 Project 포함 구조로 확장한다.

### Phase P2. Project 폴더 데이터 구조 정리

- Project 폴더는 clip Library album과 분리된 개념으로 유지한다.
- 현재 ProjectScreen이 `vlogAlbums`를 재사용하는 부분은 구현 전 재검토한다.
- 권장 방향은 `VideoManager`에 project folder 전용 read/write API를 명확히 두는 것이다.
- 기존 `vlog_folders` 경로와 `VlogProject.folderName`은 유지한다.
- 기존 프로젝트의 `folderName`이 비어 있으면 화면 표시 단계에서 기본 폴더로 fallback한다.
- 실제 데이터 migration은 하지 않고 dual-read/fallback 우선으로 처리한다.

### Phase P3. Library 유사 Project UX 보강

- Library와 같은 폴더 그리드, 상세 그리드, 선택 패널, 액션 패널 패턴을 적용한다.
- 프로젝트 카드 썸네일은 로컬 파일, Cloud thumbnail, edit session fallback 순서로 안전하게 표시한다.
- Cloud-only project가 Missing처럼 보이는 상태를 Project 화면에서도 제거한다.
- 폴더 이동/복사/휴지통/복원 동작 후 `saveProject`와 Cloud sync 상태가 보존되는지 확인한다.
- UI 문자열 인코딩이 깨진 부분은 구현 시 별도 점검한다.

### Phase P4. 구독 상태 연동

- Project 탭 자체는 기존 프로젝트 보존을 위해 숨기지 않는 방향을 기본안으로 둔다.
- Standard 미구독자는 프로젝트 열기, 고급 편집, 내보내기 같은 Standard 기능에서 upgrade entry를 보여준다.
- 기존 무료 사용자가 가진 로컬 프로젝트가 목록에서 사라지지 않도록 한다.
- 무료 사용자의 과거 720p export fallback을 유지할지, Standard paywall로 전환할지는 구현 전 제품 결정이 필요하다.

### Phase P5. Cloud 저장/동기화 확인

- 편집 중인 프로젝트는 기본적으로 Cloud 저장 대상이어야 한다.
- Project 생성, 편집 저장, 폴더 이동, 복사, 휴지통 이동 후 `saveProject`가 호출되고 Cloud metadata가 갱신되는지 확인한다.
- `vlog_projects` 문서의 `folderName`이 Project 폴더 이동 결과와 일치하는지 확인한다.
- export session cache 경로가 프로젝트 JSON에 저장되지 않는지 확인한다.

## QA 체크리스트

- Standard 계정에서 Project 탭이 보인다.
- 기존 `vlog_projects/*.json` 프로젝트가 Project 탭에 표시된다.
- 기본 폴더, 사용자 생성 폴더, 휴지통이 표시된다.
- 폴더 생성 후 앱 재시작 시 폴더가 유지된다.
- 프로젝트를 다른 폴더로 이동하면 로컬 JSON과 Cloud 문서의 `folderName`이 유지된다.
- Cloud-only 프로젝트가 Project 목록에서 Missing으로 표시되지 않는다.
- Cloud-only 프로젝트를 Project에서 바로 열면 편집 화면으로 진입한다.
- Project에서 열린 mixed 프로젝트를 export하면 Phase D와 동일하게 export materialization이 동작한다.
- export 후 프로젝트 원본 `clipPaths`는 `cloud_only://...` 값을 보존한다.
- 편집/내보내기 완료 후 Library가 아니라 Project 컨텍스트로 돌아온다.
- Standard 미구독 상태에서 프로젝트 목록 보존과 Standard 액션 gate가 의도대로 동작한다.
- 로그아웃/로그인 후 Project 목록과 Cloud sync 상태가 유지된다.

## 구현 전 결정 필요 사항

- Free 사용자에게 Project 탭을 항상 보일지, Standard 사용자에게만 보일지 결정해야 한다.
- 권장안은 데이터 보존 관점에서 Project 탭은 보이고, Standard 전용 액션만 gate하는 것이다.
- 프로젝트 폴더를 Library album과 완전히 분리할지 확정해야 한다.
- 권장안은 분리다. 현재 `vlogAlbums` 재사용은 clip album과 project folder가 섞일 위험이 있다.
- 새 프로젝트 생성 시 기본 저장 폴더를 항상 `기본`으로 둘지, 현재 선택된 Project 폴더를 따를지 결정해야 한다.
- 무료 사용자의 과거 720p 프로젝트 export fallback을 유지할지 Standard paywall로 바꿀지 결정해야 한다.

## 주요 리스크

- Bottom tab index 재도입으로 notification route, back navigation, edit/export 완료 routing이 깨질 수 있다.
- Library album과 Project folder를 같은 list로 다루면 클립 폴더와 프로젝트 폴더가 섞일 수 있다.
- ProjectScreen 내부 UI 문자열 일부가 깨진 상태라 구현 중 copy 정리가 필요할 수 있다.
- Cloud-only thumbnail fallback이 부족하면 Project 목록에서 Missing처럼 보일 수 있다.
- 구독 gate를 탭 단위로 걸면 기존 로컬 프로젝트 접근성이 떨어질 수 있다.

## 완료 기준

- Project 탭이 다시 노출된다.
- 기존 프로젝트가 삭제, migration, rename 없이 표시된다.
- Project 폴더 구조가 Library와 유사한 방식으로 동작한다.
- Standard 사용자는 Project에서 편집과 내보내기까지 정상 흐름을 탄다.
- Cloud-only/mixed 프로젝트는 다운로드 화면 없이 편집/내보내기 resolver 흐름을 사용한다.
- 프로젝트 원본 JSON에는 export cache 경로가 저장되지 않는다.
- Free/미구독자의 기존 프로젝트 접근성과 Standard 기능 gate 정책이 명확히 검증된다.

# Project Folder Phase 2 Report v1

작성일: 2026-05-21

## 범위

Phase 2에서는 Project 화면이 Library album 개념에 직접 의존하지 않도록 Project folder 전용 API를 추가하고 화면 연결을 교체했다.

저장 경로와 기존 데이터 계약은 변경하지 않았다. `vlog_folders`, `vlog_projects`, `folderName`은 그대로 유지한다.

## 변경 파일

- `lib/managers/video_manager.dart`
- `lib/screens/project_screen.dart`
- `plans/project_folder_phase_2_report_v1.md`

## 핵심 변경

### Project folder 전용 API

`VideoManager`에 Project folder 의미를 명확히 하는 호환 API를 추가했다.

- `projectFolders`
- `normalizeProjectFolderName(String name)`
- `createProjectFolder(String name)`
- `deleteProjectFolders(Set<String> names)`
- `isReservedProjectFolder(String name)`

기존 `vlogAlbums`, `createNewVlogAlbum`, `deleteVlogAlbums`는 삭제하지 않았다. 레거시 호출과 기존 경로 호환을 위해 유지한다.

### ProjectScreen 의존성 교체

`ProjectScreen`에서 직접 사용하던 `vlogAlbums`, `createNewVlogAlbum`, `deleteVlogAlbums` 의존성을 Project 전용 API로 교체했다.

- 폴더 목록: `videoManager.projectFolders`
- 폴더 생성: `videoManager.createProjectFolder`
- 폴더 삭제: `videoManager.deleteProjectFolders`
- 이동/복사 대상 목록: `videoManager.projectFolders`

### 폴더명 정규화

Project folder 생성 API가 실제 저장 폴더명을 반환하도록 했다.

이전에는 `a/b` 같은 이름이 디스크에는 `a_b`로 생성되지만 프로젝트 `folderName`에는 원문이 들어갈 수 있는 위험이 있었다. 이제 새 폴더 생성 후 이동/복사 대상은 정규화된 실제 폴더명으로 설정된다.

## 변경하지 않은 것

- `vlog_folders` 로컬 경로를 변경하지 않았다.
- Firestore `vlog_projects.folderName` 계약을 변경하지 않았다.
- 기존 프로젝트 JSON migration을 수행하지 않았다.
- ProjectScreen의 Free direct export 정책은 변경하지 않았다.
- Project folder UI 레이아웃은 변경하지 않았다.

## 검증

실행 명령:

```powershell
dart format lib\managers\video_manager.dart lib\screens\project_screen.dart
flutter analyze lib\managers\video_manager.dart lib\screens\project_screen.dart
flutter test test\cloud_clip_session_resolver_test.dart test\video_manager_clip_storage_state_test.dart
```

결과:

- `dart format`: 완료.
- `flutter test ...`: 34개 테스트 통과.
- `flutter analyze lib\managers\video_manager.dart lib\screens\project_screen.dart`: 새 컴파일 에러는 확인되지 않았으나, 기존 info 39개 때문에 exit code 1로 종료했다.

## 남은 리스크

- `vlogAlbums` 이름은 내부 레거시 상태명으로 아직 남아 있다. 외부 화면 의존성은 줄였지만 완전 rename은 데이터 호환성 검토 후 별도 단계에서만 진행해야 한다.
- 기존에 이미 정규화되지 않은 `folderName`을 가진 프로젝트가 있다면 화면에서 보이지 않을 수 있다. 이번 단계에서는 migration을 하지 않았다.
- 실제 Project 탭에서 폴더 생성, 이동, 삭제 tap-through QA가 아직 필요하다.

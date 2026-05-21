# Project Folder Phase 5 Cloud Sync Implementation Report v1

작성일: 2026-05-21

## Scope

Phase P5는 Standard 사용자의 편집 프로젝트가 Project 생성, 편집 저장, 폴더 이동, 복사, 휴지통 이동, 내보내기 직전 저장 시 Cloud metadata와 함께 동기화되는지 확인 가능한 상태로 만드는 작업이다.

이번 변경은 Firestore 컬렉션명, Storage 경로, 로컬 프로젝트 JSON 경로, IAP product id를 변경하지 않는다.

## Implemented

- `VideoManager.saveProject`에 `reason` 파라미터를 추가해 Project 저장 호출의 원인을 로그로 구분한다.
- Project 생성, 폴더 이동, 복사, 휴지통 이동, 폴더 삭제에 따른 휴지통 이동, 즐겨찾기 변경 저장 호출에 명시적 `reason`을 연결했다.
- 편집 화면의 duration preload, timeline thumbnail metadata 저장, autosave, 닫기 저장, quality 변경, export 직전 저장 호출에도 명시적 `reason`을 연결했다.
- `ProjectCloudSave` 로그에 `reason`, 안전한 folder 표시값, clip count, cloud-only count, session-cache-like path count, cloud sync 결과를 남긴다.
- `edit_session_cache`, `export_session_cache`, `cloud_clip_session_cache` 경로가 프로젝트 clip path에 포함된 경우 로컬 JSON 저장과 Cloud upsert를 차단한다.
- Project 영구 삭제 시 Cloud metadata 삭제도 Guest가 아니고 신규 Cloud write 권한이 있는 경우로 제한했다. Free never-paid 및 grace read-only 상태는 DB write/delete를 수행하지 않는다.

## QA Focus

- Standard 계정에서 Project 생성 로그가 `reason=project_create`, `cloudSaveStatus=success`로 기록되는지 확인한다.
- Project 폴더 이동 후 로그가 `reason=project_folder_move`이고 Cloud `vlog_projects.folderName`이 이동 대상과 일치하는지 확인한다.
- 편집 저장/autosave 로그가 `reason=edit_autosave_*` 또는 `edit_close_button_save`로 기록되고 Cloud 저장이 성공하는지 확인한다.
- Export 직전 저장 로그가 `reason=edit_export_pre_resolve_save`이고 `cacheLikeClipCount=0`인지 확인한다.
- Cloud-only/mixed project export 후 원본 Project JSON의 `clipPaths`가 `cloud_only://...`를 유지하고 `export_session_cache`를 포함하지 않는지 확인한다.
- Guest/Free never-paid 상태에서 Project DB read/write/delete가 발생하지 않는지 확인한다.

## Verification

- `dart format lib\managers\video_manager.dart lib\screens\video_edit_screen.dart`: pass.
- `git diff --check`: pass, CRLF warning only.
- `flutter test test\video_manager_clip_storage_state_test.dart test\user_status_manager_r3_test.dart test\cloud_clip_session_resolver_test.dart`: pass, 39 tests.
- `flutter analyze lib\managers\video_manager.dart lib\screens\video_edit_screen.dart`: fail due existing lint warnings/info in the target files; no compile errors were reported.

## Remaining Risk

- Firestore `vlog_projects.folderName` exact value still needs live Standard tap-through verification because current QA session was in Guest/Free state.
- Existing analyzer warnings in `video_manager.dart` and `video_edit_screen.dart` remain outside this Phase 5 scope.

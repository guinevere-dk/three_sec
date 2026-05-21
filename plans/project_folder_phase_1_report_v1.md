# Project Folder Phase 1 Report v1

작성일: 2026-05-21

## 범위

Phase 1에서는 숨겨져 있던 Project 화면을 메인 탭에 다시 연결했다.

이번 단계는 탭 재노출과 라우팅 index 복구에 한정했다. Project folder 데이터 분리, Free/Standard gate 정책 변경, ProjectScreen 내부 UX 보강은 수행하지 않았다.

## 변경 파일

- `lib/main.dart`
- `lib/services/notification_settings_service.dart`

## 핵심 변경

### 메인 탭 계약

기존 Library index를 유지하기 위해 다음 index 계약을 적용했다.

| index | 탭 |
|---:|---|
| 0 | Camera |
| 1 | Library |
| 2 | Project |
| 3 | Profile |

`main.dart`에는 탭 index 상수를 추가해 magic number 의존성을 줄였다.

### Project 탭 연결

- `ProjectScreen`을 `main.dart`에 import했다.
- `IndexedStack`에 `_buildProjectTab()`을 추가했다.
- 하단 navigation item에 `Project`를 추가했다.
- Project 탭 진입 시 `_refreshData()`를 호출하도록 했다.

### Profile index 보정

- 기존 `index == 2`였던 Profile 탭 진입 로그 조건을 Profile index 상수 기반으로 변경했다.
- Project가 index `2`가 되면서 Profile 로그가 Project 탭에서 실행되는 문제를 방지했다.

### 편집/내보내기 완료 후 복귀

- Library에서 프로젝트 생성 후 편집/내보내기 완료 시 복귀 index를 `Library=1`에서 `Project=2`로 변경했다.
- 튜토리얼 흐름은 기존대로 Library index `1`을 유지했다.

### 알림 라우팅

`notification_settings_service.dart`의 main tab route map을 4탭 구조로 확장했다.

- `project`, `projects`, `vlog`, `vlog_project` -> `2`
- `profile`, `settings` -> `3`
- numeric payload 허용 범위: `0..2`에서 `0..3`으로 확장

`main.dart`의 notification route validation도 `0..3`을 허용하도록 변경했다.

## 변경하지 않은 것

- `vlog_projects`, `vlog_folders`, `folderName` 계약은 변경하지 않았다.
- ProjectScreen이 `vlogAlbums`를 재사용하는 구조는 변경하지 않았다.
- Free 사용자의 Project direct export fallback은 변경하지 않았다.
- Project folder 전용 API는 추가하지 않았다.
- Firebase, Storage, IAP product id, SharedPreferences key는 변경하지 않았다.

## 검증

실행 명령:

```powershell
dart format lib\main.dart lib\services\notification_settings_service.dart
flutter analyze
flutter analyze lib\main.dart lib\services\notification_settings_service.dart
flutter test test\cloud_clip_session_resolver_test.dart test\video_manager_clip_storage_state_test.dart
```

결과:

- `dart format`: 완료.
- `flutter test ...`: 34개 테스트 통과.
- `flutter analyze`: 새 컴파일 에러는 확인되지 않았으나, 저장소 기존 lint/warning 519개 때문에 exit code 1로 종료했다.
- `flutter analyze lib\main.dart lib\services\notification_settings_service.dart`: 새 컴파일 에러는 확인되지 않았으나, 기존 `main.dart` warning/info 20개 때문에 exit code 1로 종료했다.

## 남은 리스크

- ProjectScreen의 folder list가 아직 `vlogAlbums`를 사용하므로 Library album과 Project folder가 섞일 수 있다. Phase 2에서 분리해야 한다.
- ProjectScreen의 Free direct export 흐름은 Standard 유료 정책과 충돌 가능성이 있다. Phase 4에서 정책 결정이 필요하다.
- 실제 emulator tap-through QA는 아직 수행하지 않았다.

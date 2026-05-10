# SKILLS.md

이 문서는 AI가 MOA 저장소에서 실제 작업할 때 적용할 절차형 스킬과 기술 작업 가이드를 정의합니다. 정책 충돌 시 `AGENTS.md`의 우선순위와 금지사항이 우선합니다.

## 1. 기술 스택 요약

- 앱: Flutter/Dart, null safety, Provider 기반 일부 상태 주입.
- 주요 패키지: Firebase Core/Auth/Firestore/Storage/Messaging, camera, video_player, video_thumbnail, gal, image_picker, in_app_purchase, shared_preferences, path_provider.
- 서버: Firebase Functions Node.js 20, `firebase-functions`, `firebase-admin`.
- 데이터: 로컬 파일 시스템, SharedPreferences, Firestore, Firebase Storage.
- 플랫폼: Android 중심 QA, iOS/Web 설정 일부 포함.

## 2. 기본 검증 명령

프로젝트 루트에서 실행합니다.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Functions 작업 시 `functions` 디렉터리 기준입니다.

```bash
npm install
npm run lint
npm run serve
```

Firebase 배포는 필요한 대상만 분리합니다.

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage:rules
firebase deploy --only functions
```

Android QA 보조는 `tools/android_capture_session.cmd`를 사용합니다.

## 3. rebranding-safe-edit

브랜드/카피/문서 문자열을 안전하게 정렬할 때 사용합니다.

1. 사용자 노출 문자열인지 레거시 식별자인지 먼저 분류합니다.
2. 사용자 노출은 `MOA`와 `2초 촬영 + Vlog` 기준으로 정렬합니다.
3. `three_sec_vlog`, `three_s`, `com.dk.three_sec`, `fir-3s-8edb9`, `3s_*`, `vlog_projects`, `vlog_folders`는 호환 영역으로 유지합니다.
4. 앱 ID, DB 키, Storage 경로, 로컬 저장 키, IAP product id 변경이 필요하면 중단하고 승인 계획을 요구합니다.
5. 변경 후 사용자 노출 검색과 레거시 식별자 변경 여부를 확인합니다.

## 4. compatibility-impact-check

저장 데이터, 로컬 인덱스, Firebase, 사용자 프로젝트에 닿는 변경 전 사용합니다.

1. 원본 영상, 프로젝트 JSON, 로컬 인덱스, 계정 소유권, 구독 상태에 영향이 있는지 확인합니다.
2. 기존 read/write key와 경로가 유지되는지 확인합니다.
3. 삭제/초기화가 포함되면 deprecated, fallback, migration-free 우회가 가능한지 검토합니다.
4. Firestore/Storage 규칙 변경은 보안 완화와 기존 클라이언트 호환성을 점검합니다.
5. 영향도 높음 이상이면 dry-run, backup, rollback plan 없이 실행하지 않습니다.
6. 검증에는 저장, 불러오기, 앱 재시작 복구, 로그아웃/로그인, 네트워크 실패를 포함합니다.

## 5. flutter-safe-code-change

Flutter/Dart 코드를 수정할 때 사용합니다.

1. 기존 `lib/screens`, `lib/services`, `lib/managers`, `lib/models` 경계를 확인합니다.
2. Firebase/Storage/API 처리는 기존 `lib/services` 레이어를 우선 재사용합니다.
3. null safety를 유지하고 nullable 입력은 명시적으로 처리합니다.
4. async 이후 UI 상태 갱신에는 `mounted` 체크를 확인합니다.
5. 저장/삭제/동기화 호출은 호출 조건, 실패 처리, rollback 가능성을 명확히 합니다.
6. debug print, magic number, 임시 플래그를 남발하지 않습니다.
7. 변경 후 `flutter analyze`와 관련 테스트를 우선 검토합니다.

## 6. firebase-safe-change

Firestore, Storage, Functions를 다룰 때 사용합니다.

1. `firebase/firestore.rules`, `firebase/storage.rules`, `firebase/firestore.indexes.json`, `firebase.json`, `.firebaserc`를 함께 확인합니다.
2. 보안 규칙은 완화하지 않고, 기존 uid 소유권 조건을 유지합니다.
3. `videos`, `users`, `vlog_projects`, `usageEvents` 계약을 임의 변경하지 않습니다.
4. Storage `users/{uid}/videos/{videoId}/{fileName}`와 `users/{uid}/profile/{fileName}` 경로를 임의 변경하지 않습니다.
5. Functions는 `npm run lint`로 문법 검증 후 배포 범위를 분리합니다.
6. 실배포 전 에뮬레이터 또는 staging 검증, rollback 명령, 변경 전 규칙 백업을 준비합니다.

## 7. release-precheck

릴리스, 배포, QA 직전 사용합니다.

1. 현재 변경이 MVP와 `CURRENT_PHASE.md` 허용 범위인지 확인합니다.
2. 저장/불러오기, 촬영, 외부 미디어 가져오기, Vlog 생성, 로그인, 결제, 클라우드 이동, 알림 영향을 식별합니다.
3. Android release는 서명, R8/shrink, 권한, Firebase 설정, Play Console 문서를 확인합니다.
4. iOS/Web은 해당 릴리스 계획과 manifest/스토어 메타데이터 정합성을 확인합니다.
5. 검증 미수행 항목은 이유와 리스크를 완료 보고에 남깁니다.

## 8. 파일별 작업 가이드

- `lib/main.dart`: 앱 초기화, Firebase, Kakao SDK, FCM, AuthGate, MainNavigation, 튜토리얼, 네이티브 채널이 섞여 있어 작은 단위 변경만 허용합니다.
- `lib/managers/video_manager.dart`: 로컬 파일, 프로젝트, 클립, 내보내기, 썸네일, 동기화 상태를 포괄하므로 데이터 보존 영향도를 먼저 확인합니다.
- `lib/services/cloud_service.dart`: Firestore/Storage write/delete와 업로드 큐를 담당하므로 삭제/정리 함수는 특히 보수적으로 검토합니다.
- `lib/services/local_index_service.dart`: `local_index_entries_v1` 호환 키를 변경하지 않습니다.
- `lib/managers/user_status_manager.dart`: `3s_user_tier` 등 구독 관련 SharedPreferences key와 자동 강등 정책을 임의 변경하지 않습니다.
- `functions/index.js`: social exchange와 IAP verify 계약을 다루므로 product id, provider uid, service account, CORS 정책 변경은 승인 필요입니다.
- `android/app/build.gradle.kts`: `namespace`, `applicationId`, release signing, R8 설정을 임의 변경하지 않습니다.
- `firebase/*.rules`: uid 소유권 조건과 파일 타입/크기 제한을 완화하지 않습니다.

## 9. documentation-update

문서만 수정하거나 코드 변경에 맞춰 문서를 정리할 때 사용합니다.

1. 문서 목적을 정책, 절차, 현재 범위, 아키텍처, 데이터 호환성, 릴리스, 이슈로 분류합니다.
2. 실제 파일명, 실제 서비스명, 실제 키/경로를 사용합니다.
3. 추상 원칙만 쓰지 말고 금지 대상, 승인 필요 대상, 검증 명령, 롤백 기준을 명시합니다.
4. 오래된 브랜드명은 사용자 노출 기준과 레거시 식별자 기준으로 분리해 설명합니다.
5. 문서 변경 후 `AGENTS.md`, `DATA_COMPATIBILITY.md`, `RELEASE_RULES.md`와 충돌하지 않는지 확인합니다.

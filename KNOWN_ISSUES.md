# KNOWN_ISSUES.md

## 1. 알려진 위험 요약

이 문서는 현재 코드와 계획 문서 분석 기준으로 AI 작업자가 주의해야 할 취약 흐름과 검증 필요 영역을 정리합니다. 새로운 버그 재현 결과가 생기면 이 문서를 업데이트합니다.

## 2. 데이터 보존 위험

- `VideoManager.deleteProject`는 로컬 프로젝트 JSON 삭제, cloud metadata 삭제, local index 제거를 수행합니다. 호출 경로 변경 시 프로젝트 유실 가능성이 있습니다.
- `CloudService.deleteVideo`는 Storage 객체와 Firestore `videos` 문서를 삭제하고 사용량을 차감합니다.
- `CloudService.purgeCurrentUserCloudData`는 `videos`, `vlog_projects`, `users/{uid}`를 삭제하는 고위험 함수입니다. 계정 탈퇴/명시 정리 외 호출 금지입니다.
- clip save queue 성공 후 임시 source file 삭제 로직이 있으므로 source/destination 구분을 변경하면 원본 유실 위험이 있습니다.

## 3. 로컬 저장/복구 위험

- 로컬 프로젝트 경로가 `vlog_projects`, `vlogs/vlog_projects`, `vlogs/raw_clips`, `vlogs/vlog_folders`, `thumbnails` 계열로 나뉘어 있어 경로 rename은 고위험입니다.
- SharedPreferences에 duration, ownership, cloud sync, queue 상태가 저장됩니다. key 변경 시 앱 재시작 복구와 클라우드 상태가 깨질 수 있습니다.
- 튜토리얼 완료는 `tutorial_completed_user_{uid}`와 legacy `isFirstRun`을 함께 사용합니다. 계정별 온보딩 회귀에 주의합니다.

## 4. 클라우드 동기화 위험

- 업로드 큐는 로컬 `SyncQueueStore`와 Firestore `videos.uploadStatus`가 함께 움직입니다.
- 네트워크 실패, 권한 거부, quota 초과, Storage object not found는 각기 다른 retry/terminal 정책을 갖습니다.
- `localPath` 기준 dedupe와 fileName fallback 조회가 있어 경로 변경 시 중복 업로드 또는 다운로드 실패가 생길 수 있습니다.
- 게스트 모드는 클라우드 접근이 차단되어야 합니다.

## 5. 인증/구독 위험

- Kakao/Naver social exchange는 Functions에서 provider uid와 custom token을 생성합니다. uid 생성 규칙 변경은 계정 분리에 직결됩니다.
- `SOCIAL_AUTH_EXCHANGE_URL`, `KAKAO_NATIVE_APP_KEY`, OIDC 관련 dart-define 누락 시 로그인 진단 로그가 발생합니다.
- IAP product id는 `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual`로 검증됩니다. 표시명 변경과 product id 변경을 혼동하면 기존 구독자 승계가 깨질 수 있습니다.
- `UserStatusManager`는 로컬 만료 기준으로 Free 자동 강등을 수행합니다. 서버 검증 결과와 충돌하지 않도록 주의합니다.

## 6. 영상 처리 위험

- `MethodChannel('com.dk.three_sec/video_engine')`는 촬영 정규화, 이미지-비디오 변환, 클립 추출, Vlog 병합과 연결됩니다.
- 내보내기 실패는 Asset loader, encoder, 외부 force stop 등으로 분류되며 단순 재시도만으로 해결되지 않을 수 있습니다.
- 4K/1080p 품질, clip count, 메모리 압박 이벤트에 따라 내보내기 안정성이 달라집니다.
- Android 권한 정책은 SDK 버전에 따라 videos/photos/storage/audio 권한 흐름이 다릅니다.

## 7. 릴리스 회귀 방지 메모

- 촬영 후 앱 재시작 시 클립과 album count가 유지되는지 확인합니다.
- 외부 미디어 다중 가져오기 중 취소/실패/재시도 상태를 확인합니다.
- Vlog 프로젝트 생성 후 편집, 저장, 삭제, 휴지통 복원 흐름을 확인합니다.
- 클라우드 업로드 중 앱 background/resume 후 queue 복구를 확인합니다.
- 로그인 직후 구독 동기화 대기와 알림 라우팅 queue가 크래시 없이 동작하는지 확인합니다.
- release build에서 R8/shrink로 네이티브 영상 처리와 Firebase가 깨지지 않는지 확인합니다.

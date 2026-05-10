# CURRENT_PHASE.md

## 1. 현재 운영 단계

현재 단계는 MVP 안정화와 MOA 브랜드 정렬 단계입니다. 리브랜딩은 사용자 노출 중심 Phase 0~2 범위가 기본 허용 범위이며, 데이터/식별자/DB/패키지 변경은 보류합니다.

## 2. 현재 MVP 범위

- 카메라 촬영과 2초 클립 저장 안정화.
- 외부 미디어 가져오기와 클립 추출 흐름 안정화.
- 라이브러리, 앨범, 휴지통, 프로젝트 저장/복원 안정화.
- Vlog 편집/내보내기 안정화.
- Firebase Auth, 게스트 모드, 소셜 로그인 흐름 유지.
- Free/Standard/Premium 구독 tier와 자동 강등 정책 유지.
- Standard 이상 클라우드 이동/백업 흐름 안정화.
- Android 릴리스 품질과 Play Console 대응.

## 3. 즉시 허용 작업

- Markdown 운영 문서 정리.
- 사용자 노출 카피와 문서의 MOA 기준 정렬.
- 낮음/중간 영향도 UI 문구 정리.
- 검증 체크리스트, 릴리스 게이트, 알려진 이슈 문서화.
- 기존 동작을 바꾸지 않는 작은 버그 수정.

## 4. 승인 필요 작업

- 로컬 저장 key 또는 파일 디렉터리 변경.
- Firestore/Storage schema, path, rules 변경.
- Functions endpoint, product id, provider uid 생성 규칙 변경.
- Android/iOS package/bundle id 변경.
- 대량 rename 또는 파일 구조 개편.
- DB migration, 백필, purge, 사용자 데이터 삭제.
- 상태관리 프레임워크 전환 또는 대규모 아키텍처 교체.

## 5. 보류 작업

- `three_s` 패키지명 변경.
- `com.dk.three_sec` applicationId/namespace 변경.
- `fir-3s-8edb9` Firebase project 변경.
- `3s_*` IAP product id 변경.
- `videos`, `users`, `vlog_projects` 컬렉션명 변경.
- Storage `users/{uid}/videos/{videoId}/{fileName}` 경로 변경.
- SharedPreferences `3s_*`, `local_index_entries_v1`, cloud sync key 변경.
- 워크스페이스 루트명 변경.

## 6. 단계별 승인 기준

### Phase 0 기준선

- 변경 전 inventory와 영향도 분류를 완료합니다.
- 실제 코드/설정 변경은 하지 않습니다.

### Phase 1 사용자 노출

- 앱 표시명, 사용자 카피, manifest 등 노출 문자열 중심으로 제한합니다.
- 식별자와 저장 key는 유지합니다.

### Phase 2 문서 정렬

- README, 운영 문서, plans, benchmark 문구를 정리합니다.
- 과거 기록은 legacy/as-is로 보존하고 무리하게 삭제하지 않습니다.

### Phase 3 이상

- 로컬 key, DB, Storage, Firebase, package/bundle id를 포함합니다.
- 반드시 별도 승인, dry-run, 백업, rollback plan, staged rollout이 필요합니다.

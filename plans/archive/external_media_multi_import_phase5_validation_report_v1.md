# 외부 이미지/영상 다중 가져오기 Phase 5 검증 리포트 v1

기준 계획서: `plans/external_media_multi_import_plan_v1.md`

## 1) 목적/범위
- 목적: Phase 1~4 구현 결과가 Android/iOS에서 **순서 보존/안정성/집계 정확성/길이 정합성**을 만족하는지 검증
- 범위: 외부 가져오기 배치 처리 전 구간
  - 다중 선택 수집
  - `orderIndex` 기반 순서 보존
  - 이미지 변환 + 영상 추출 직렬 처리
  - 실패/취소 best-effort 처리
  - 완료 요약/앨범 갱신
  - `targetDurationMs`/`normalizedDurationMs` 기준 길이 정합 검증

## 2) 사전 조건
- 앱 빌드: `main` 브랜치 Phase 4 반영본
- 테스트 앨범: 빈 앨범 1개 + 기존 클립 포함 앨범 1개
- 테스트 미디어 세트 준비
  - 이미지 50개(해상도 혼합)
  - 영상 10개(길이/코덱 혼합)
  - 손상/미지원 파일 2~3개(실패 집계 확인용)

## 3) 공통 검증 포인트
- 선택 결과 순서가 `orderIndex` 로그와 일치
- 처리 로그가 `progress=n/m`로 누락 없이 증가
- 실패/취소 발생 시 다음 항목 계속 진행
- 최종 토스트 집계와 실제 결과가 일치
- 완료 후 현재 앨범이 1회 갱신됨
- 길이 처리 로그(`targetDurationMs`, `normalizedDurationMs`)가 1500ms 기준으로 수집됨

> 로그 기준(코드)
> - `[ExternalImport][Phase1] selectedCount=...`
> - `[ExternalImport][Phase2] queue_item orderIndex=...`
> - `[ExternalImport][Phase3] process_item progress=...`
> - `[ExternalImport][Phase3] video_result ...`
> - `[ExternalImport][Phase3] item_failed ...`

## 4) 시나리오별 체크리스트 (Phase 5)

### 4-1. 역순 선택(C→A→B) 순서 일치
- [ ] Android: 갤러리에서 C→A→B 순서로 선택
- [ ] Android: 등록 결과가 C→A→B 순서로 반영
- [ ] iOS: 갤러리에서 C→A→B 순서로 선택
- [ ] iOS: 등록 결과가 C→A→B 순서로 반영
- [ ] 로그 `orderIndex`와 실제 등록 순서 100% 일치

### 4-2. 혼합 선택(영상-이미지-영상-이미지) 순서 일치
- [ ] Android: V-I-V-I 선택 후 동일 순서 등록
- [ ] iOS: V-I-V-I 선택 후 동일 순서 등록
- [ ] 영상 추출 화면이 동시에 여러 개 열리지 않음(직렬)
- [ ] 이미지 항목 변환 성공 시 즉시 결과 반영
- [ ] 이미지/영상 처리 항목의 `normalizedDurationMs`가 1500ms 근사치인지 확인

### 4-2.1. 길이 정합(이미지/영상)
- [ ] 이미지 변환 완료 항목: `targetDurationMs == 1500` 또는 정책 상수와 일치
- [ ] 영상 추출 완료 항목: `targetDurationMs == 1500` 또는 정책 상수와 일치
- [ ] `normalizedDurationMs` 오차가 허용 범위(예: ±120ms) 내인지 확인
- [ ] 허용 범위를 벗어난 항목은 실패 집계로 별도 표기

### 4-3. 대량 선택(10/30/50) 안정성
- [ ] Android 10개: 중단/크래시 없이 완료
- [ ] Android 30개: 중단/크래시 없이 완료
- [ ] Android 50개: 중단/크래시 없이 완료
- [ ] iOS 10개: 중단/크래시 없이 완료
- [ ] iOS 30개: 중단/크래시 없이 완료
- [ ] iOS 50개: 중단/크래시 없이 완료
- [ ] 처리 중 UI 프리징/ANR 재현 없음

### 4-4. 실패/취소 포함 집계 정확성
- [ ] 일부 항목 실패 유도 시 전체 루프 지속
- [ ] 영상 추출 취소 시 `cancelledCount` 증가 확인
- [ ] 실패/취소/성공 합이 총 선택 수와 일치
- [ ] 요약 토스트 수치와 앨범 반영 수치 일치
- [ ] 텍스트 노출은 `1s` 유지(토스트/버튼/라벨)
- [ ] 사용자 노출 문구와 로그 메타 `targetDurationMs`/`normalizedDurationMs`가 혼재되지 않음

## 5) 플랫폼 실행 기록

### Android 실행 결과
- 실행 일시: 2026-03-31 (실측 로그 신규 수집 없음)
- 기기/OS: 미측정
- 앱 버전/커밋: 미기록
- 결과 요약: **HOLD (수치 미확정)**
- 이슈:
  - length_check_result: 코드 정책상 `1500ms` 기준 확인, 실측 분포 미수집
  - ui_label_check_result: 정책 문서상 `1s` 유지 기준 확인, 실기기 캡처 미수집

### iOS 실행 결과
- 실행 일시: 2026-03-31 (실측 로그 신규 수집 없음)
- 기기/OS: 미측정
- 앱 버전/커밋: 미기록
- 결과 요약: **HOLD (수치 미확정)**
- 이슈:
  - length_check_result: 코드 정책상 `1500ms` 기준 확인, 실측 분포 미수집
  - ui_label_check_result: 정책 문서상 `1s` 유지 기준 확인, 실기기 캡처 미수집

## 6) 릴리즈 게이트 판정
- Phase 5 게이트 기준: 핵심 수동 시나리오 전부 통과
- 최종 판정: **HOLD**
- 근거:
  - Task E(최종 게이트): `flutter analyze` 신규 error `0` 확인(총 406건은 warning/info), `flutter test` `1 passed` 확인
  - Android 결과: 수치 미확정(HOLD)
  - iOS 결과: 수치 미확정(HOLD)
  - 길이 정합 통과 여부: **HOLD** (코드 기준 통과 가능성 높음, 실측 미완료)
  - 노출 텍스트(`1s`) 통과 여부: **HOLD** (정책 기준 충족, 실기기 증빙 미완료)
  - 미해결 이슈:
    - 100개 임포트 TTFI 실측값 미확보
    - 50% 취소 stop latency 실측값 미확보
    - 10클립 저장 최종 성공률 실측값 미확보
    - 위치 표시 mismatch 실측값 미확보
    - 1.5초 루프 label/seek 오차 실측값 미확보

## 7) 결론
- 본 문서는 Phase 5 산출물(체크리스트 기반 검증 리포트)이다.
- Android/iOS 실기기 검증 결과를 채워야 게이트를 `PASS`로 상향할 수 있으며, 현재는 보수적으로 `HOLD`를 유지한다.

---

## 8) QA 시나리오 정합성 증빙(요구 반영본)

> 아래 5개 항목은 기존 체크리스트를 유지하면서, 실제 구현 코드/로그와 매핑된 증빙 템플릿으로 추가한다.

### 8-1. 대량 임포트 100개: 반응성 + 2초 내 첫 영상 표시
- [ ] 대상 세트 100개 준비(이미지/영상 혼합) - 미측정
- [ ] 시작 로그 채집: `[ExternalImport][Phase1] selectedCount=100` - 미측정
- [ ] 첫 항목 로드 시각 채집(`markItemLoaded` 또는 첫 `process_item`) - 미측정
- [ ] `TTFI <= 2000ms` 검증(실측값 기입) - 미측정
- [ ] 처리 중 UI 프리징/ANR 없음 - 미측정
- [x] 코드 연계 포인트 확인
  - `lib/main.dart` `_buildImportQueueBuckets`, `_preloadImportItem`, `_runBackgroundPreloadQueue`
  - `lib/models/import_state.dart` `progressText()`, `orderedItems`
  - `lib/managers/video_manager.dart` `_rebuildImportState`

증빙 기록:
- device / os: 미측정
- selected_at: 미측정
- first_item_loaded_at: 미측정
- TTFI(ms): 미측정
- UI responsiveness note: 로그 부재로 판정 불가

### 8-2. 50% 취소: 즉시 정지 + UI 무정지
- [ ] 진행률 50% 지점에서 취소 실행 - 미측정
- [x] 취소 직후 `cancelRequested=true` 전파 확인(코드 경로)
- [ ] 취소 이후 신규 `process_item` 진행 로그 0건(이미 실행 중 항목 종료 로그는 예외) - 미측정
- [ ] UI 입력(스크롤/탭) 반응 유지 - 미측정
- [x] 코드 연계 포인트 확인
  - `lib/managers/video_manager.dart` `requestCancelAllQueues()`, `markRemainingImportItemsCanceled`
  - `lib/main.dart` `if (videoManager.cancelRequested)` 분기
  - `lib/managers/video_manager.dart` `_clipSaveWorkerLoop`, `_runClipSaveJobWithRetry`

증빙 기록:
- cancel_requested_at: 미측정
- last_process_item_at: 미측정
- stop_latency_ms: 미측정
- UI freeze observed: 미측정

### 8-3. 클립 다중 저장: 단일 영상 10개 + 재시도 + 최종 성공률 95% 이상
- [ ] 단일 영상에서 10개 세그먼트 저장 큐 등록 - 미측정
- [x] 일부 실패 유도 후 개별 재시도 버튼 동작 확인(코드 경로)
- [x] 실패 항목 전체 재시도 버튼 동작 확인(코드 경로)
- [ ] 최종 성공률 `>=95%` 검증 - 미측정
- [x] 코드 연계 포인트 확인
  - `lib/screens/clip_extractor_screen.dart` `_extractClips`, `retryClipSaveJob`, `retryFailedClipSaveJobs`
  - `lib/managers/video_manager.dart` `_runClipSaveJobWithRetry`, `_setClipSaveJobRetrying`
  - `lib/models/clip_save_job_state.dart` `ClipSaveJobStatus`, `ClipSaveErrorKind`

증빙 기록:
- total_jobs: 미측정
- retry_count: 미측정
- success/fail/skip/cancel: 미측정
- final_success_rate: 미측정

### 8-4. 위치 확인: 임의 탐색/자동 이동 시 `현재/총` 지표 정합
- [ ] 임의 순서 탐색(앞/뒤 이동) 시 지표 오차 0건 - 미측정
- [ ] 자동 이동(다음 아이템 처리) 시 지표 오차 0건 - 미측정
- [ ] `progress=n/m`와 상태 집계(완료/실패/취소/건너뜀) 일치 - 미측정
- [x] 코드 연계 포인트 확인
  - `lib/main.dart` `orderIndex`, `itemIdByOrderIndex`, `process_item progress=...`
  - `lib/models/import_state.dart` `orderedItems`, `progressText()`

증빙 기록:
- random_navigation_mismatch_count: 미측정
- auto_advance_mismatch_count: 미측정
- progress_consistency: 미측정

### 8-5. 1.5초 구간 UX: 구간 이동 후 1.5초 반복 재생
- [ ] 슬라이더 이동 후 구간 시작점 즉시 반영 - 미측정
- [x] 반복 재생 구간이 `windowStart ~ windowStart+1500ms`와 일치(코드 상수 기준)
- [ ] 시간 라벨과 실제 seek 구간 오차 허용범위 내(권장 <=100ms) - 미측정
- [x] 코드 연계 포인트 확인
  - `lib/screens/clip_extractor_screen.dart` `_fixedWindowMs`, `_updateWindowStartFromSlider`
  - `lib/screens/clip_extractor_screen.dart` `_scheduleWindowSeek`, `_enforceFixedWindowLoop`

증빙 기록:
- window_start_ms: 미측정
- expected_end_ms: 미측정
- measured_loop_window_ms: 미측정
- label_seek_delta_ms: 미측정

### 8-6. Task D 통합 KPI 요약 (배포 판정용)

| KPI | 값 | 기준 | 판정 | 근거 출처 | 미측정 사유 |
|---|---|---|---|---|---|
| 100개 임포트 TTFI | 미측정 | `<=2000ms` | HOLD | `plans/externer_media_more_ux_plan.md`, `lib/main.dart` 계측 지점 | 실행 로그 부재 |
| 50% 취소 stop latency | 미측정 | 즉시 정지 | HOLD | `lib/managers/video_manager.dart`, `lib/main.dart` 취소 분기 | 타임스탬프 로그 부재 |
| 10클립 저장 성공률 | 미측정 | `>=95%` | HOLD | `lib/screens/clip_extractor_screen.dart`, `lib/models/clip_save_job_state.dart` | 집계 로그 부재 |
| 위치(`현재/총`) mismatch | 미측정 | `0` | HOLD | `lib/main.dart` `orderIndex`, `itemIdByOrderIndex`; `lib/models/import_state.dart` | 실측 시나리오 로그 부재 |
| 1.5초 루프 오차 | 미측정(상수 1500ms 확인) | `<=100ms` 권장 | HOLD | `lib/screens/clip_extractor_screen.dart`, `lib/widgets/trim_editor_modal.dart` | 기기 계측 부재 |

---

## 9) 성능/크래시 모니터링 보완안

### 9-1. 메모리/프레임 드롭/메모리 누수 지표 정의
- [ ] `rss_mb`, `dart_heap_mb`, `native_heap_mb` 수집
- [ ] `fps_avg`, `jank_ratio`, `frame_build_ms_p95` 수집
- [ ] `thumbnail_cache_size`, `_durationCache` 크기 추이 수집
- [ ] 화면 종료 후 controller/listener 잔존 수(`controller_alive_count`) 점검

### 9-2. 크래시 로그 수집 포인트(임포트/썸네일/저장/재생) 라우팅
- [ ] 임포트: `lib/main.dart` `_pickMediaBatch`
- [ ] 썸네일/프리뷰: `lib/main.dart` `_preloadImportItem` + `prepareImportPreview`
- [ ] 저장: `lib/managers/video_manager.dart` `_runClipSaveJobWithRetry`
- [ ] 재생: `lib/screens/clip_extractor_screen.dart` `_enforceFixedWindowLoop`
- [ ] 라우팅 제안
  - 로컬 1차: `logs/` 폴더 구조화 JSON
  - 원격 2차: Crashlytics custom keys/event
  - 운영 3차: 사용자 공유 텍스트(`lib/utils/error_copy.dart`) fallback

### 9-3. 임시 리소스 정리 훅 점검 체크리스트
- [ ] 항목 전환 시 `releaseImportPreparationResourcesForPath` 호출
- [ ] 배치 종료/예외 시 `releaseImportPreparationResourcesForPaths` 호출
- [ ] 클립 저장 종료 상태별 `releaseClipSaveResourcesForJob` 호출
- [ ] `dispose()`에서 리스너 제거/컨트롤러 dispose
- [ ] 캐시 상한 정책 및 주기적 정리 확인

### 9-4. 회귀 테스트 체크리스트(회귀 포인트별)
- [ ] 대량 임포트(10/30/50/100) 완료/취소/실패 집계 일치
- [ ] 혼합 선택(V-I-V-I) 순서 보존
- [ ] 저장 재시도 버튼 동작 및 최종 성공률 유지
- [ ] 위치 지표 정합성(임의 탐색/자동 이동)
- [ ] 1.5초 반복 재생 및 시간 라벨 정합

### 9-5. 릴리스 후 1주 KPI 초안
- [ ] crash-free sessions >= 99.5%
- [ ] 100개 임포트 첫 항목 표시 p95 <= 2.0s
- [ ] 취소 즉시 정지 성공률 >= 99%
- [ ] 클립 저장 최종 성공률 >= 95%
- [ ] import flow fatal error rate < 0.5%

---

## 10) 기능별 리스크 분석 및 잔여 기술부채

### 기능별 리스크
- 임포트 프리로드 경쟁
  - 리스크: 저사양 기기에서 프레임 저하
  - 대응: 동시성 다운스케일 + preload timeout skip
- 클립 저장 큐 재시도
  - 리스크: 디스크 혼잡 시 재시도 폭증
  - 대응: 재시도 백오프 + errorKind별 안내 문구
- 위치 지표
  - 리스크: 화면별 표시 규칙 분산
  - 대응: 공통 `현재/총` UI 컴포넌트로 통합 예정
- 1.5초 루프
  - 리스크: 일부 기기 seek 글리치
  - 대응: seek throttle/debounce 파라미터 튜닝

### 남은 기술부채(technical debt)
- [ ] `현재/총` 배지 전역 컴포넌트 미구현
- [ ] 성능 지표 자동 수집/집계 파이프라인 미완성
- [ ] 로컬 로그 ↔ 원격 크래시 라우팅 공통 어댑터 부재
- [ ] QA 증빙 자동 추출 스크립트 부재


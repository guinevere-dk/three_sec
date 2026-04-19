# External Media Phase5 QA 체크리스트 v1

기준 문서:
- `plans/externer_media_more_ux_plan.md`
- `plans/external_media_multi_import_phase5_validation_report_v1.md`

목적:
- 다중 임포트/클립 저장/위치 지표/1.5초 반복 UX의 QA 실행 체크리스트를 단일 문서로 통합
- 기존 체크리스트 항목을 반복 포함하고, 상태 모델/큐화 코드 포인트를 함께 명시

---

## 1) 테스트 시나리오 정합성 점검 (필수 5항목)

### 1-1. 대량 임포트 100개 (반응성 + 2초 내 첫 영상 표시)
- [ ] 100개 선택 시 앱 프리징/ANR 없음
- [ ] 첫 항목 표시(loaded/process 시작)까지 2초 이내
- [ ] 진행 텍스트 `x / N`와 실제 처리량 일치
- [ ] 실패/취소/건너뜀 집계가 합산 일치

로그 포인트:
- [ ] `[ExternalImport][Phase1] selectedCount=...`
- [ ] `[ExternalImport][Phase2] queue_item orderIndex=...`
- [ ] `[ExternalImport][Phase3] process_item progress=...`

코드 연계 포인트:
- [ ] `lib/main.dart` `_buildImportQueueBuckets`, `_preloadImportItem`, `_runBackgroundPreloadQueue`
- [ ] `lib/models/import_state.dart` `progressText()`, `orderedItems`
- [ ] `lib/managers/video_manager.dart` `_rebuildImportState`

측정 기록:
- [ ] phase1_selected_at
- [ ] first_item_loaded_at
- [ ] TTFI(ms)

### 1-2. 50% 취소 (즉시 정지 + UI 무정지)
- [ ] 총량 50% 근처에서 취소 실행
- [ ] 취소 후 신규 진행 즉시 중단
- [ ] UI 입력 반응 유지(스크롤/탭 가능)
- [ ] 잔여 항목 상태가 `canceled`로 수렴

로그 포인트:
- [ ] cancel trigger timestamp
- [ ] 취소 이후 `process_item` 신규 진행 0건 확인

코드 연계 포인트:
- [ ] `lib/managers/video_manager.dart` `requestCancelAllQueues()`, `markRemainingImportItemsCanceled`
- [ ] `lib/main.dart` `if (videoManager.cancelRequested)` 분기
- [ ] `lib/managers/video_manager.dart` `_clipSaveWorkerLoop`, `_runClipSaveJobWithRetry`

### 1-3. 클립 다중 저장 (10개 + 재시도 + 95% 이상)
- [ ] 단일 영상에서 10개 세그먼트 저장 큐 등록
- [ ] 실패 시 개별 `재시도` 버튼 동작
- [ ] 실패 항목 `전체 재시도` 버튼 동작
- [ ] 최종 성공률 95% 이상

코드 연계 포인트:
- [ ] `lib/screens/clip_extractor_screen.dart` `_extractClips`, `retryClipSaveJob`, `retryFailedClipSaveJobs`
- [ ] `lib/managers/video_manager.dart` `_runClipSaveJobWithRetry`, `_setClipSaveJobRetrying`
- [ ] `lib/models/clip_save_job_state.dart` `ClipSaveJobStatus`, `ClipSaveErrorKind`

### 1-4. 위치 확인 (`현재/총` 지표 정합)
- [ ] 임의 탐색에서 지표 오차 0건
- [ ] 자동 이동에서 지표 오차 0건
- [ ] `progress=n/m`와 완료 집계 일치

코드 연계 포인트:
- [ ] `lib/main.dart` `orderIndex`, `itemIdByOrderIndex`, `process_item progress=...`
- [ ] `lib/models/import_state.dart` `orderedItems`, `progressText()`

### 1-5. 1.5초 구간 UX (반복 재생)
- [ ] 구간 이동 시 `windowStart` 즉시 반영
- [ ] 1.5초 반복 재생이 끊김 없이 동작
- [ ] 라벨 시간과 실제 seek 구간 오차 허용범위 내

코드 연계 포인트:
- [ ] `lib/screens/clip_extractor_screen.dart` `_fixedWindowMs`, `_updateWindowStartFromSlider`
- [ ] `lib/screens/clip_extractor_screen.dart` `_scheduleWindowSeek`, `_enforceFixedWindowLoop`

---

## 2) 기존 체크리스트 반복 포함 (회귀 방지용)

아래 항목은 기존 문서의 체크리스트를 반복 포함한다.

### 순서/집계/길이 정합
- [ ] 역순 선택(C→A→B) 결과 순서 일치
- [ ] 혼합 선택(V-I-V-I) 결과 순서 일치
- [ ] `orderIndex`와 실제 등록 순서 100% 일치
- [ ] `progress=n/m` 누락 없이 증가
- [ ] 실패/취소 발생 시 다음 항목 계속 처리
- [ ] 최종 요약 토스트 수치와 실제 결과 일치
- [ ] `targetDurationMs`/`normalizedDurationMs` 1500ms 기준 정합

### 안정성
- [ ] 대량 선택(10/30/50) Android 크래시 없음
- [ ] 대량 선택(10/30/50) iOS 크래시 없음
- [ ] 처리 중 UI 프리징/ANR 재현 없음

### 실패/취소
- [ ] 실패/취소/성공 합계 = 총 선택 수
- [ ] 취소 시 `cancelledCount` 증가 확인

---

## 3) 성능/크래시 모니터링 실행 체크

### 지표 생성
- [ ] 메모리 지표: `rss_mb`, `dart_heap_mb`, `native_heap_mb`
- [ ] 프레임 지표: `fps_avg`, `jank_ratio`, `frame_build_ms_p95`
- [ ] 누수 지표: `controller_alive_count`, cache size 추이

### 크래시 후보 구간 라우팅
- [ ] 임포트 구간 이벤트 채집
- [ ] 썸네일/프리뷰 구간 이벤트 채집
- [ ] 저장 구간 이벤트 채집
- [ ] 재생/루프 구간 이벤트 채집
- [ ] 로컬 로그(`logs/`) + 원격(Crashlytics) 이중 라우팅 확인

### 리소스 정리 훅
- [ ] `releaseImportPreparationResourcesForPath` 호출 검증
- [ ] `releaseImportPreparationResourcesForPaths` 호출 검증
- [ ] `releaseClipSaveResourcesForJob` 상태별 호출 검증
- [ ] `dispose()` 리스너 제거/컨트롤러 해제 검증

---

## 4) QA 결과 요약 템플릿

- [ ] 실행일시:
- [ ] 실행자:
- [ ] 기기/OS:
- [ ] 앱 버전/커밋:
- [ ] 결과: PASS / FAIL
- [ ] 미해결 이슈 목록:
- [ ] 재현 조건:
- [ ] 임시 우회:
- [ ] 다음 액션 오너/기한:

---

## 5) Task D KPI 실측/근거 반영 (P1)

기준 시각: 2026-03-31

| 시나리오 | KPI 항목 | 실측/최신 근거 값 | 기준 | 판정 | 근거 출처 | 미측정 사유 |
|---|---|---|---|---|---|---|
| 100개 임포트 | 첫 미리보기 시간(TTFI) | 미측정 | `<= 2000ms` | HOLD | `plans/externer_media_more_ux_plan.md` 목표값, `lib/main.dart` 임포트/프리로드 루프 코드 존재 | 저장된 실행 로그(`logs/`) 부재로 시각 차 계산 불가 |
| 100개 임포트 | 진행률 정합 | 계산식 근거 확인(`progressText(): completed/total`) / 실측 미측정 | 실제 처리량과 일치 | HOLD | `lib/models/import_state.dart` `progressText()`, `orderedItems` / `lib/main.dart` `process_item progress=...` 로그 포맷 | 실제 100개 실행 로그 샘플 부재 |
| 50% 취소 | 즉시 정지 지연(ms) | 미측정 | 취소 후 신규 진행 0건, 즉시 정지 | HOLD | `lib/managers/video_manager.dart` `requestCancelAllQueues()`, `markRemainingImportItemsCanceled`; `lib/main.dart` 취소 분기 | 취소 시점/마지막 진행 로그 타임스탬프 부재 |
| 단일 영상 10클립 저장 | 재시도 포함 최종 성공률 | 미측정(분모 10, 계산식만 확인) | `>= 95%` | HOLD | `lib/screens/clip_extractor_screen.dart` 재시도 버튼/전체 재시도 연결, `lib/managers/video_manager.dart` 재시도 상태머신, `lib/models/clip_save_job_state.dart` `maxRetry=2` | 10클립 실주행 결과 집계값 부재 |
| 위치 표시 | 현재/총 정합 | 로직 근거 확인 / 실측 미측정 | mismatch 0건 | HOLD | `lib/main.dart` `orderIndex`, `itemIdByOrderIndex`; `lib/models/import_state.dart` `orderedItems` | 임의 탐색/자동 이동 실측 로그 부재 |
| 1.5초 반복 | 루프 정확성 | 고정 윈도우 `1500ms` 코드 확인 / 라벨-seek 오차 실측 미측정 | 라벨 오차 `<=100ms` 권장 | HOLD | `lib/screens/clip_extractor_screen.dart` `_fixedWindowMs = kTargetClipMs`, `_enforceFixedWindowLoop`; `lib/widgets/trim_editor_modal.dart` `_fixedWindowMs = 1500` | 기기별 seek 실측 데이터 부재 |

### Task D QA 판정
- 실행일시: 2026-03-31
- 실행자: 문서 보강 자동화(Task D)
- 기기/OS: 미측정
- 앱 버전/커밋: 미기록
- 결과: **HOLD**
- 근거 요약:
  - 코드/계획 기준의 KPI 정의와 계측 포인트는 확인됨.
  - 실측 로그 또는 최신 저장 측정값이 없어 수치 확정 불가.
  - 릴리스 판정은 보수적으로 HOLD 유지.
- 미해결 이슈 목록:
  - 100개 임포트 TTFI 실측값 미확보
  - 50% 취소 지연(ms) 미확보
  - 10클립 저장 성공률 실측값 미확보
  - 위치 지표 mismatch 실측값 미확보
  - 1.5초 라벨/seek 오차 실측값 미확보


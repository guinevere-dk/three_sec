# External Media Phase5 릴리스 체크리스트 v1

참조 문서:
- `plans/externer_media_more_ux_plan.md`
- `plans/external_media_multi_import_phase5_validation_report_v1.md`
- `plans/external_media_phase5_qa_checklist_v1.md`

목적:
- Phase5 QA 결과를 릴리스 게이트 기준으로 전환
- 성능/크래시/회귀/운영 KPI를 릴리스 1주 모니터링까지 연결

---

## 1) 릴리스 게이트(출시 전)

### 필수 시나리오 통과
- [ ] 대량 임포트 100개: 반응성 유지, 2초 내 첫 항목 표시
- [ ] 50% 취소: 취소 후 즉시 정지, UI 멈춤 없음
- [ ] 클립 10개 저장: 재시도 동작, 최종 성공률 95% 이상
- [ ] 위치 지표: 임의 탐색/자동 이동 시 정합 100%
- [ ] 1.5초 구간 UX: 구간 이동 후 반복 재생 정합

### 기존 항목 반복(중복 포함 요구 반영)
- [ ] 역순/혼합 선택 순서 보존
- [ ] 실패/취소/성공 집계 합산 일치
- [ ] `targetDurationMs`/`normalizedDurationMs` 길이 정합
- [ ] Android/iOS 10/30/50 안정성 시나리오 통과

---

## 2) 상태 모델/큐화 코드 포인트 점검

### Import 상태 모델
- [ ] `lib/models/import_state.dart` `ImportItemStatus` 전이 누락 없음
- [ ] `lib/models/import_state.dart` `progressText()` 집계 정합
- [ ] `lib/models/import_state.dart` `orderedItems` 정렬 기준 유지

### Clip Save 큐 상태 모델
- [ ] `lib/models/clip_save_job_state.dart` `ClipSaveJobStatus` 전이 정합
- [ ] `lib/models/clip_save_job_state.dart` `ClipSaveErrorKind` 분류 검증
- [ ] `maxRetry` 정책(기본 2회) 준수

### Queue Worker
- [ ] `lib/managers/video_manager.dart` `requestCancelAllQueues()` 전파 확인
- [ ] `lib/managers/video_manager.dart` `_clipSaveWorkerLoop` 취소 분기 확인
- [ ] `lib/managers/video_manager.dart` `_runClipSaveJobWithRetry` 재시도/종결 상태 확인

---

## 3) 성능/크래시 모니터링 릴리스 준비

### 지표 준비
- [ ] 메모리: `rss_mb`, `dart_heap_mb`, `native_heap_mb`
- [ ] 프레임: `fps_avg`, `jank_ratio`, `frame_build_ms_p95`
- [ ] 품질: `import_ttfi_ms_p95`, `clip_save_success_rate`
- [ ] 취소: `cancel_stop_latency_ms`, `cancel_immediate_stop_rate`

### 크래시 수집 포인트
- [ ] 임포트 루프(`lib/main.dart` `_pickMediaBatch`) 이벤트 수집
- [ ] 프리뷰 준비(`lib/main.dart` `_preloadImportItem`) 이벤트 수집
- [ ] 저장 워커(`lib/managers/video_manager.dart` `_runClipSaveJobWithRetry`) 이벤트 수집
- [ ] 반복 재생(`lib/screens/clip_extractor_screen.dart` `_enforceFixedWindowLoop`) 이벤트 수집

### 라우팅
- [ ] 로컬 로그 저장(`logs/`)
- [ ] 원격 전송(Crashlytics custom keys/events)
- [ ] 사용자 공유 fallback(`lib/utils/error_copy.dart`) 동작

---

## 4) 회귀 테스트 체크리스트

- [ ] 대량 임포트(10/30/50/100) 회귀 없음
- [ ] 혼합 미디어(V-I-V-I) 순서/집계 회귀 없음
- [ ] 클립 저장 재시도 버튼/전체 재시도 회귀 없음
- [ ] 1.5초 반복 재생 seek/라벨 정합 회귀 없음
- [ ] 취소 전파 및 잔여 작업 canceled 수렴 회귀 없음

---

## 5) 릴리스 후 1주 KPI 모니터링 계획(초안)

### Day 0~1 (핫 모니터링)
- [ ] crash-free sessions >= 99.5%
- [ ] import fatal error rate < 0.5%
- [ ] 긴급 장애 발생 시 hotfix 판단 회의체 가동

### Day 2~4 (성능 추세)
- [ ] 100개 임포트 첫 항목 표시 p95 <= 2.0s
- [ ] import 중 jank ratio p95 < 5%
- [ ] cancel 즉시 정지 성공률 >= 99%

### Day 5~7 (품질/잔존 이슈)
- [ ] 클립 저장 최종 성공률 >= 95%
- [ ] 재시도율/실패유형 분포 분석
- [ ] 이슈 티켓 우선순위 재정렬 및 다음 스프린트 반영

---

## 6) 기능별 리스크 분석

### 임포트/프리로드
- 리스크: 저사양 단말 메모리 급증/프레임 저하
- 대응: 동시성 자동 다운스케일, preload timeout skip

### 클립 저장 큐
- 리스크: I/O 병목으로 재시도 폭증, 완료 지연
- 대응: backoff 적용, 실패유형별 메시지/재시도 제한

### 위치 지표
- 리스크: 지표 표준 미통일로 화면 간 해석 불일치
- 대응: 공통 `현재/총` 컴포넌트 정의 및 전 화면 적용

### 1.5초 반복 재생
- 리스크: 특정 디바이스 seek 글리치
- 대응: seek throttle/debounce 파라미터 기기군 튜닝

---

## 7) 남은 기술부채(technical debt)

- [ ] `현재/총` 지표 공통 위젯화 미완료
- [ ] 성능 지표 자동 수집 파이프라인 미완료
- [ ] 로컬/원격 크래시 라우팅 어댑터 미완료
- [ ] QA 증빙 자동 리포트(로그 파싱) 스크립트 미완료

---

## 8) 최종 릴리스 판정

- [x] 판정: **HOLD**
- [x] 근거 링크:
  - Task E 최종 게이트(정적분석/테스트): `flutter analyze` 신규 error `0` (총 406건은 warning/info), `flutter test` `1 passed` (All tests passed)
  - QA 리포트: `plans/external_media_phase5_qa_checklist_v1.md` (Task D KPI 섹션)
  - 검증 리포트: `plans/external_media_multi_import_phase5_validation_report_v1.md` (Task D 실측/근거 반영 섹션)
  - 이슈 목록: Task D KPI 실측 로그 부재로 KPI 확정 보류(문서 내 미측정 사유 참조)
  - 모니터링 대시보드: 미연결(운영 수집 파이프라인 미완료)
- [x] 오너/승인자: External Media Phase5 QA Gate
- [x] 승인 시각: 2026-03-31

---

## 9) Task D KPI 채움 결과 (P1)

기준 시각: 2026-03-31

| KPI | 현재 값 | 목표/게이트 | 판정 | 근거 출처 | 미측정 사유 |
|---|---|---|---|---|---|
| `import_ttfi_ms_p95` (100개 임포트 첫 미리보기) | 미측정 | `<= 2000ms` | HOLD | `plans/externer_media_more_ux_plan.md` KPI 목표, `lib/main.dart` 임포트/프리로드 계측 가능 지점 | `logs/` 실행 산출물 부재로 p95 계산 불가 |
| 진행률 정합성(`x/N` vs 실제 처리량) | 로직 근거 확인, 실측값 미측정 | 정합 100% | HOLD | `lib/models/import_state.dart` `progressText()`, `orderedItems`; `lib/main.dart` `process_item progress` | 100개 실주행 로그 샘플 부재 |
| `cancel_stop_latency_ms` (50% 취소 즉시성) | 미측정 | 취소 후 신규 진행 0건/즉시 정지 | HOLD | `lib/managers/video_manager.dart` `requestCancelAllQueues()`, `markRemainingImportItemsCanceled`; `lib/main.dart` 취소 분기 | 취소 시각과 마지막 진행 로그 타임스탬프 미수집 |
| `clip_save_success_rate` (10클립 저장) | 미측정 | `>= 95%` | HOLD | `lib/screens/clip_extractor_screen.dart` 재시도/전체 재시도 연결, `lib/models/clip_save_job_state.dart` `maxRetry=2` | 10클립 실측 집계값 미확보 |
| 위치 표시(`현재/총`) mismatch | 미측정 | mismatch `0` | HOLD | `lib/main.dart` `orderIndex`, `itemIdByOrderIndex`; `lib/models/import_state.dart` `orderedItems` | 임의 탐색/자동 이동 실측 기록 부재 |
| 1.5초 반복 정확성(`label_seek_delta_ms`) | 미측정(구현 상수 확인) | 권장 `<= 100ms` | HOLD | `lib/screens/clip_extractor_screen.dart` `_fixedWindowMs`, `_enforceFixedWindowLoop`; `lib/widgets/trim_editor_modal.dart` `_fixedWindowMs=1500` | 기기 실측 로그 부재 |

릴리스 결론:
- KPI 정의/계측 포인트는 준비됨.
- 배포 판단에 필요한 실측 수치가 핵심 항목에서 비어 있어 보수적으로 **HOLD** 유지.


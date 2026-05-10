# 외부 미디어 다중 임포트 UX 개선 계획 (개선본)

## 1) 배경 및 목표

현재 외부 미디어 다중 임포트/클립 선택 흐름에서 아래 문제가 반복적으로 발생한다.

1. 다량 선택 시 앱 멈춤/크래시 가능성
2. 전체 임포트 완료까지 사용자에게 진행 상태가 보이지 않음
3. 현재 시청 중인 영상 위치 표시 부재
4. 한 영상에서 6~7개 이상 클립 저장 시 앱 크래시
5. 1.5초 구간을 정확히 고르고 반복 재생하기 어려움

**목표(1주 내 목표치)**

- 대량 임포트/클립 저장 중 OOM/크래시 `0%`
- 첫 영상은 전체 처리 완료를 기다리지 않고 `최대 2초` 내 미리보기 제공
- 진행 상태(`처리 중/완료/실패/건너뜀`) 실시간 표시 + 취소 가능
- 선택 중인 영상 위치를 `현재 번호 / 전체` 형식으로 표시
- 클립 저장은 백그라운드 큐로 분리해 UI 블로킹 제거
- 1.5초 구간 이동/반복 재생 UX로 정확한 클립 선택 가능

---

## 2) 개선 범위

- 범위: 외부 미디어 임포트 화면, 미디어 미리보기/선택 화면, 클립 저장/트리밍 흐름
- 제외: 결제, 인증, 동기화 큐의 서버 API 변경

---

## 3) 요구사항 재정의

### A. 임포트 안정성 및 성능

#### 요구
- 한 번에 다수 영상(`N=100` 수준) 선택해도 앱이 멈추거나 종료되지 않아야 함
- 영상 준비가 완료되는 순서대로 UI를 점진적으로 갱신
- 모든 영상 준비 완료 전에도 첫 영상은 최소한 기본 썸네일/프리뷰 노출

#### 구현 아이디어
- **2단계 로더**
  - `준비 우선 큐`: 현재 표시될 영상의 썸네일/첫 프레임 우선 로드
  - `백그라운드 큐`: 나머지 영상은 제한 동시수로 백그라운드 처리
- **동시 처리량 제한**: 동시 디코딩/메타 수집은 기기 성능 기반으로 2~3개로 제한
- **메모리 보호**: 미리보기 전환 시 이전 영상 리소스 즉시 해제
- **타임아웃/폴백**: 8~12초 무응답 시 실패 처리 후 사용자에게 스킵/재시도 옵션 제공

### B. 로딩 진행률 및 취소

#### 요구
- 전체 임포트 상태를 정량적으로 보여야 함
- 중간 취소 가능해야 함

#### 구현 아이디어
- 집계 상태 유지
  - `total`, `inProgress`, `completed`, `failed`, `skipped`, `canceled`
- 진행 텍스트 예시: `27 / 60 처리 완료 · 실패 2개`
- 취소 액션
  - 큐 상태를 `cancelRequested=true`로 전환
  - 진행 중 워커는 즉시 중단 시그널 반영
  - 완료 항목은 유지하고 미완료 항목은 `취소됨`으로 마킹

### C. 현재 시청 위치 표시

#### 요구
- 사용자에게 지금 보고 있는 영상의 상대 위치 표시

#### 구현 아이디어
- 화면 상단에 `현재 14 / 73` 배지 노출
- 스와이프/버튼 이동/자동전환 시 즉시 상태 갱신
- 목록(미니 썸네일)과 위치값 동기화

### D. 클립 저장 안정성

#### 요구
- 영상 하나에서 다수 클립(예: 10개) 선택해도 크래시 없이 저장 완료
- 저장 중에도 다음 영상 미리보기/선택이 가능해야 UX 끊김 없음

#### 구현 아이디어
- 저장 파이프라인 분리
  - UI 스레드: 클립 선택/삭제/재생
  - 백그라운드 작업 큐: `clip_save_jobs`
- 동시 저장 제한: 기본 1개(안정성 우선), 고성능 기기에서 2개 가능하도록 토글
- 실패 처리: 재시도 카운트(`maxRetry=2`) 및 실패 이유 분류(입력 오류, 디스크, 권한, 코덱)
- 리소스 정리: 저장 완료 즉시 원본 디코더/텍스처 캐시 해제

### E. 1.5초 구간 반복 재생 UX(트림 방식)

#### 요구
- 1.5초 구간을 이동 가능하게 만들고 그 구간 내를 반복 재생해 미리 볼 수 있어야 함

#### 구현 아이디어
- 재생바 위에 고정 길이(1.5s) 선택창 오버레이 추가
- 드래그로 `windowStart` 이동, `windowEnd = windowStart + 1.5`
- 구간 변화 시 자동으로 해당 구간 반복 재생
- 시작/끝 시간(예: `00:12.000 ~ 00:13.500`) 실시간 표시

---

## 4) 실행 단계(개발 로드맵)

### Phase 1: 상태 모델 및 큐 공통화 (1일)
- `ImportState` / `ClipSaveJobState` 도메인 정의
- 진행률 집계/취소 토큰/현재 인덱스 상태를 단일 원천으로 통합

### Phase 2: 임포트 렌더링 개선 (1.5일)
- 우선 큐 + 백그라운드 큐 구현
- 전체 진행률 배너 및 부분 준비 카드(loaded/processing/skeleton) 적용

### Phase 3: 클립 저장 파이프라인 전환 (1.5일)
- 동기 저장 로직을 큐 기반 비동기로 리팩터
- 저장 실패 재시도/실패 아이템 표시 구현

### Phase 4: 위치 표시 + 1.5초 구간 플로우 (1일)
- 현재 인덱스 배지 추가
- 1.5초 고정 구간 반복 재생 컴포넌트 구현

### Phase 5: 안정성 검증 및 QA 정리 (1일)
- 메모리/프레임 드롭/크래시 모니터링
- 회귀 테스트 체크리스트 정리 및 릴리스 노트 작성

---

## 5) 테스트 시나리오(수락 기준)

1. **대량 임포트**
   - 100개 영상 선택: 앱 반응성 유지, 2초 내 첫 영상 표시
   - 로딩 중 `x / N` 갱신 정확도 98% 이상

2. **중간 취소**
   - 50% 처리 시점에서 취소 → 진행이 즉시 정지되고 UI가 멈추지 않아야 함

3. **클립 다중 저장**
   - 단일 영상에서 10개 클립 저장
   - 실패 시 재시도 버튼 동작, 최종 저장 성공률 목표 95% 이상

4. **위치 확인**
   - 임의 탐색/자동 이동 시 `현재/총` 지표 정확히 갱신

5. **1.5초 구간 UX**
- 구간 이동 후 1.5초 내외 반복 재생되며 지정 구간이 정확히 반영

---

## 5-1) QA 시나리오 정합성 점검(코드 연계 포인트 포함)

> 아래 항목은 기존 수락 기준을 유지하면서, 실제 구현 코드와 로그 포인트를 연결해 검증 가능하도록 보강한다.

### A. 대량 임포트 100개
- 목표
  - 앱 반응성 유지(프리징/ANR 없음)
  - 첫 영상 표시 TTI(Time To First Item) `<= 2초`
- 로그/계측 포인트
  - 선택 시작: `[ExternalImport][Phase1] selectedCount=...`
  - 큐 적재: `[ExternalImport][Phase2] queue_item orderIndex=...`
  - 처리 진행: `[ExternalImport][Phase3] process_item progress=...`
  - 측정식: `first_item_loaded_at - phase1_selected_at <= 2000ms`
- 코드 연계
  - 임포트 큐 생성/정렬: `lib/main.dart` (`_buildPendingImportItems`, `_buildImportQueueStates`)
  - 리드 큐/백그라운드 프리로드 분리: `lib/main.dart` (`_buildImportQueueBuckets`, `_runBackgroundPreloadQueue`)
  - 상태 집계/표시 문자열: `lib/models/import_state.dart` (`progressText()`)
  - 상태 갱신/합산 로직: `lib/managers/video_manager.dart` (`_rebuildImportState`)

### B. 50% 취소
- 목표
  - 취소 직후 신규 진행 즉시 중단
  - UI 멈춤 없음(입력 반응 유지)
- 로그/계측 포인트
  - 취소 요청 시각 기록: `cancel_requested_at`
  - 취소 이후 `process_item` 추가 로그 0건(허용: 이미 실행 중 1건 이내 종료 로그)
  - `cancelRequested=true` 전파 시간 `< 100ms` 목표
- 코드 연계
  - 전체 취소 요청: `lib/managers/video_manager.dart` (`requestCancelAllQueues()`)
  - 임포트 루프 취소 분기: `lib/main.dart` (`if (videoManager.cancelRequested) ...`)
  - 잔여 항목 취소 마킹: `lib/managers/video_manager.dart` (`markRemainingImportItemsCanceled`)
  - 클립 저장 워커 취소 분기: `lib/managers/video_manager.dart` (`_clipSaveWorkerLoop`, `_runClipSaveJobWithRetry`)

### C. 클립 다중 저장(단일 영상 10클립)
- 목표
  - 10개 저장 큐에서 실패 발생 시 재시도 동작
  - 최종 성공률 `>= 95%`
- 로그/계측 포인트
  - 큐 등록 개수/완료 개수/실패 개수/재시도 횟수
  - 성공률: `(success / total) * 100 >= 95`
- 코드 연계
  - 큐 등록: `lib/screens/clip_extractor_screen.dart` (`_extractClips` -> `enqueueClipSaveJobs`)
  - 재시도 버튼: `lib/screens/clip_extractor_screen.dart` (`retryClipSaveJob`, `retryFailedClipSaveJobs` 호출)
  - 재시도 상태머신: `lib/managers/video_manager.dart` (`_runClipSaveJobWithRetry`, `_setClipSaveJobRetrying`)
  - 실패 분류: `lib/models/clip_save_job_state.dart` (`ClipSaveErrorKind`)

### D. 위치 확인(`현재/총`)
- 목표
  - 임의 탐색/자동 이동 시 위치 지표 정확 갱신(정확도 100%)
- 로그/계측 포인트
  - `orderIndex`와 실제 처리 순서 불일치 0건
  - 임포트 진행 `progress=n/m`와 상태 집계값 일치
- 코드 연계
  - 순서 기준키: `lib/main.dart` (`orderIndex`, `itemIdByOrderIndex`)
  - 순서 정렬 보장: `lib/models/import_state.dart` (`orderedItems`)
  - 진행 로그: `lib/main.dart` (`[ExternalImport][Phase3] process_item progress=...`)
  - 참고: UI 배지(`현재 x / 총 y`)는 별도 화면 컴포넌트로 표준화가 남아 있으며 현재는 진행 텍스트 중심으로 검증

### E. 1.5초 구간 UX
- 목표
  - 구간 이동 직후 지정 구간(1.5초) 반복 재생
  - 시작/종료 시간 라벨과 실제 seek 구간 오차 `<= 100ms`
- 로그/계측 포인트
  - `windowStartMs`, `windowEndMs`, 실제 seek position 수집
  - 루프 재진입 간격/스로틀(90~150ms 보호 로직) 확인
- 코드 연계
  - 고정 윈도우 길이: `lib/screens/clip_extractor_screen.dart` (`_fixedWindowMs = kTargetClipMs`)
  - 구간 이동/seek 디바운스: `lib/screens/clip_extractor_screen.dart` (`_updateWindowStartFromSlider`, `_scheduleWindowSeek`)
  - 반복 재생 강제: `lib/screens/clip_extractor_screen.dart` (`_enforceFixedWindowLoop`)

---

## 5-2) 성능/크래시 모니터링 보완

### A. 메모리/프레임 드롭/메모리 누수 지표
- 런타임 메모리
  - `rss_mb`, `dart_heap_mb`, `native_heap_mb`
  - 임포트 100건 시 피크/평균
- 렌더링
  - `frame_build_ms_p50/p95`, `jank_ratio`, `fps_avg`
- 누수 의심
  - `controller_alive_count`(화면 종료 후 잔존 수)
  - `thumbnail_cache_size`, `duration_cache_size` 변화량

### B. 크래시 로그 수집 포인트 및 라우팅 제안
- 후보 구간
  - 임포트: `_pickMediaBatch` 처리 루프
  - 썸네일/프리뷰: `prepareImportPreview` 경로
  - 저장: `_runClipSaveJobWithRetry`, `saveExtractedClip`
  - 재생/루프: `ClipExtractorScreen`의 `_enforceFixedWindowLoop`
- 라우팅 제안
  - 1차: 앱 로컬 파일(`logs/`)에 구조화 JSON 적재
  - 2차: 네트워크 가능 시 Firebase Crashlytics custom key/events 전송
  - 3차: 릴리즈 주간에는 `error_copy` 유틸 기반 사용자 공유 경로 유지

### C. 임시 리소스 정리 훅 점검 체크리스트
- [ ] 임포트 전환 시 `releaseImportPreparationResourcesForPath` 호출
- [ ] 배치 종료/예외 시 `releaseImportPreparationResourcesForPaths` 호출
- [ ] 클립 저장 완료/실패/취소별 `releaseClipSaveResourcesForJob` 호출
- [ ] 화면 dispose에서 listener 제거/컨트롤러 dispose 보장
- [ ] 캐시 맵(`thumbnailCache`, `_timelineCache`, `_durationCache`) 상한/정리 정책 검증

### D. 회귀 테스트 체크리스트(회귀 포인트별)
- [ ] 대량 임포트(10/30/50/100) 진행률/취소/완료 토스트 일관성
- [ ] 혼합 미디어(V-I-V-I) 순서 보존(`orderIndex`) 회귀 없음
- [ ] 영상 추출 후 저장 큐/재시도 버튼 동작 회귀 없음
- [ ] 1.5초 구간 이동/반복 재생/시간 라벨 정합성 유지
- [ ] 백그라운드 큐 동시성 변경 시 UI 프리징/크래시 없음

### E. 릴리즈 후 1주 모니터링 KPI(초안)
- 안정성
  - crash-free session `>= 99.5%`
  - import flow fatal error rate `< 0.5%`
- 성능
  - 100개 임포트 첫 항목 표시 p95 `<= 2.0s`
  - import 중 jank ratio p95 `< 5%`
- 품질
  - 클립 저장 최종 성공률 `>= 95%`
  - 취소 후 즉시 정지 성공률 `>= 99%`

---

## 6) 위험요소 및 대응

- 디코더 성능 편차로 인한 지연
  - 대응: 기기별 동시 처리 수 동적 조정(저사양 축소)
- 백그라운드 저장 과부하
  - 대응: 저장 큐 우선순위 상향/하향 + 전환 시 임시 보류 정책
- 권한/스토리지 예외
  - 대응: 에러코드 분류 후 사용자 안내 및 재시도 유도

---

## 7) 산출물

- `[개선 계획서]` 본문 반영본: `plans/externer_media_more_ux_plan.md`
- 큐/상태 다이어그램 및 에러 플로우 다이어그램(별도 문서)
- QA 체크리스트: 임포트, 저장, 위치 표시, 1.5초 구간 반복 재생
- 배포 후 1주 모니터링 지표 리포트

---

## 8) 기능별 리스크 분석 및 남은 기술부채(Technical Debt)

### 기능별 리스크
- 임포트/프리로드
  - 리스크: 저사양 단말에서 프리로드 경쟁으로 프레임 드랍
  - 완화: 동시성 1~2까지 자동 강등, 타임아웃 스킵
- 클립 저장 큐
  - 리스크: I/O 혼잡 시 연쇄 재시도로 지연 급증
  - 완화: 재시도 백오프, 실패 원인별 UX 가이드
- 위치 지표
  - 리스크: 화면별 표시 정책 불일치로 사용자 혼동
  - 완화: 공통 컴포넌트(`현재/총`) 도입 예정
- 1.5초 반복 재생
  - 리스크: seek 빈도 증가로 특정 기기에서 오디오 글리치
  - 완화: seek 스로틀/디바운스 유지, 기기군별 임계값 튜닝

### 남은 기술부채
- [ ] 위치 배지(`현재/총`)의 전역 표준 UI 컴포넌트 미정
- [ ] 프리로드/저장 성능 지표의 자동 수집 파이프라인 미완성
- [ ] 크래시 이벤트를 로컬 로그와 원격 분석으로 이중 라우팅하는 공통 어댑터 미구현
- [ ] 큐 상태 스냅샷을 QA 리포트로 자동 추출하는 스크립트 부재


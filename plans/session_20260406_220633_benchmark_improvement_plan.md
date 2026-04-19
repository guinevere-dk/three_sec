# 세션 220633 벤치마킹 기반 개선 계획

## 1) 배경 및 진단 확정

이번 세션에서 병합 실패는 다음 순서로 확인됨.

1. 병합 시작 및 프로젝트 생성 완료
   - [`[Tutorial][Diag] MergeFlow createProject snapshot`](logs/session_20260406_220633_full.log:31672)
2. export preflight 로그 정상
   - [`[VideoManager][Export] preflight_summary`](logs/session_20260406_220633_full.log:31678)
3. 네이티브 병합 실패 (`EXPORT_FAILED`, `Asset loader error`)
   - [`[VideoManager][Export][MergeFail] ... code=EXPORT_FAILED`](logs/session_20260406_220633_full.log:41543)
4. 이후 외부 프로세스 기반 force-stop 발생
   - [`Force stopping ... from pid 22169`](logs/session_20260406_220633_full.log:44998)
   - [`Killing 20797:com.dk.three_sec ... from pid 22169`](logs/session_20260406_220633_full.log:45000)

### 확정한 우선 원인(Top 2)
- 1순위: Media3 Transformer 입력 처리 중 `Asset loader error`
- 2순위: 실패 후 외부 force-stop(테스트/운영 환경 요인)

참조 코드:
- [`_handleMerge()`](lib/main.dart:1574)
- [`VideoManager.exportVlog()`](lib/managers/video_manager.dart:1614)

---

## 2) 벤치마킹 목표 (무엇을 비교할 것인가)

### 목표 A. 병합 안정성(성공률) 벤치마크
- 지표: `merge success rate`, `EXPORT_FAILED rate`, `retry 성공률`
- 기준 데이터셋:
  - `무음 photo clip 다수(현재 재현 케이스와 동일)`
  - `영상+무음혼합`
  - `영상만`

### 목표 B. 병합 복원력(회복 전략) 벤치마크
- 지표: `1차 실패 후 fallback 성공률`, `총 소요시간 증가율`
- 비교 전략:
  1. 기본 Transformer 단일 경로
  2. 실패 시 품질 하향(720p→540p) 재시도
  3. 실패 시 오디오 믹스 단순화(clip audio only) 재시도

### 목표 C. 환경 분리력(앱 실패 vs 외부 종료) 벤치마크
- 지표: `앱 내부 예외 종료 비율` vs `외부 force-stop 비율`
- 목적: 원인 분리 정확도 향상 (디버그 시간 단축)

### 목표 D. 사용자 체감 성능 벤치마크
- 지표: `P50/P95 export latency`, `토스트 표시까지 시간`, `실패 메시지 명확도`

---

## 3) 벤치마킹 가능한 개선 항목 (실행 후보)

아래 항목은 “벤치마킹 가능 + 단계적 적용 가능” 기준으로 선정.

1. **입력 프리플라이트 강화 (오디오 트랙 타입 분류)**
   - 현재 [`preflight_summary`](logs/session_20260406_220633_full.log:31678) 는 개수 중심.
   - 개선: `photo 기반 무음`, `video 무음`, `정상 오디오`를 분리 집계.
   - 기대효과: 실패 패턴 유형화 정확도 증가.

2. **Transformer 실패 코드 정규화 매핑 테이블 도입**
   - `EXPORT_FAILED` 내부 `errorCode/causeClass`를 표준 코드로 매핑.
   - 기대효과: 재시도 정책 자동 분기 가능.

3. **재시도 정책 A/B 벤치마크**
   - A안: 품질 하향 재시도
   - B안: 오디오 단순화 재시도
   - 기대효과: 실패 복원 성공률 비교.

4. **병합 전 리소스 가드 강화**
   - 기존 memory pressure 로그 + codec 리소스 지표 연계.
   - 기대효과: 고위험 조건 사전 차단/경고.

5. **외부 force-stop 시그니처 자동 라벨링**
   - `from pid`, `runForceStop`, `Killing ... due to from pid` 자동 분류.
   - 기대효과: 앱 결함 오인 감소.

6. **에러 UX 벤치마킹 (메시지 실험)**
   - 일반 실패 문구 vs 원인군 기반 문구(재시도/품질 변경 권장).
   - 기대효과: 재시도 성공률 및 이탈률 개선.

7. **결과 파일 무결성 체크 벤치마크**
   - 이미 추가된 `resultExists/resultBytes` 로그를 기준으로 성공 정의 강화.
   - 기대효과: “결과 path는 있으나 재생 불가” 유형 조기 탐지.

---

## 4) 실행 계획 (Phase)

## Phase 1: 계측 보강 및 데이터 수집 (D+0 ~ D+2)
- 범위:
  - [`VideoManager.exportVlog()`](lib/managers/video_manager.dart:1614) 에 실패 코드 정규화 로그 추가
  - 외부 force-stop 시그니처 탐지 스크립트(로그 후처리) 추가
- 산출물:
  - 세션별 원인 분류 표 (AssetLoader / ExternalForceStop / Unknown)

## Phase 2: 복원 전략 실험 (D+3 ~ D+5)
- 범위:
  - 재시도 A/B 구현 (품질 하향 vs 오디오 단순화)
  - 동일 데이터셋 30회 반복 테스트
- 성공 기준:
  - `EXPORT_FAILED` 발생 세션에서 복원 성공률 60% 이상

## Phase 3: 정책 확정 및 UX 반영 (D+6 ~ D+7)
- 범위:
  - 성능/성공률 우수 전략을 기본 정책으로 채택
  - 실패 메시지 개선 및 사용자 액션(재시도/품질변경) 제공
- 성공 기준:
  - P95 병합시간 증가율 25% 이내
  - 실패 후 이탈률 감소

---

## 5) 벤치마크 측정 표준 (필수 KPI)

- 안정성 KPI
  - `merge_attempts`
  - `merge_success`
  - `merge_fail_export_failed`
  - `merge_fail_force_stop_external`

- 성능 KPI
  - `export_elapsed_ms_p50`
  - `export_elapsed_ms_p95`
  - `retry_overhead_ms`

- 품질 KPI
  - `result_exists_rate`
  - `result_nonzero_bytes_rate`

---

## 6) 리스크 및 대응

1. 재시도 정책이 전체 지연을 증가시킬 수 있음
   - 대응: 1회만 재시도, 타임아웃 상한 설정

2. 외부 force-stop이 계속 섞이면 내부 개선 효과 측정이 왜곡될 수 있음
   - 대응: force-stop 라벨 세션을 별도 분리 집계

3. 무음 clip 비중이 높은 세션 편향
   - 대응: 데이터셋 균형(무음/유음/혼합) 유지

---

## 7) 즉시 실행 항목 (이번 주)

- [ ] `EXPORT_FAILED` 상세코드 정규화 로깅 추가
- [ ] force-stop 외부종료 자동 라벨러 작성
- [ ] 재시도 A/B 플래그 추가
- [ ] 3개 데이터셋 × 10회씩 1차 벤치마크 수행
- [ ] 결과 리포트(md) 작성 및 기본 정책 선정


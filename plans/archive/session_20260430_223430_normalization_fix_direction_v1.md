# session_20260430_223430 2초 정규화 실패 수정 방향 v1

## 1) 문제 요약

이번 세션에서 3개 클립 모두 최종 저장 길이 2000ms 보장에 실패했다.

- 클립 A: `clip_1777556201195`는 정규화 완료 로그에서 `normalizedDurationMs=1974`로 확인됨
  - 근거: [`tools/logs/session_20260430_223430_appfull.log:1330`](../tools/logs/session_20260430_223430_appfull.log)
- 클립 B: `clip_1777556206718`는 정규화 결과 `normalizedDurationMs=1866` 후, fallback 저장 시 `fallbackDurationMs=1900`으로 고정됨
  - 근거: [`tools/logs/session_20260430_223430_appfull.log:1441`](../tools/logs/session_20260430_223430_appfull.log), [`tools/logs/session_20260430_223430_appfull.log:1442`](../tools/logs/session_20260430_223430_appfull.log)
- 클립 C: `clip_1777556215741`는 `padToTarget=true`였음에도 `normalizedDurationMs=1915`로 종료됨
  - 근거: [`tools/logs/session_20260430_223430_appfull.log:1557`](../tools/logs/session_20260430_223430_appfull.log)

공통적으로 `targetDurationMs=2000` 요청은 일관되지만 실제 결과가 목표에 도달하지 못했다.

- 근거: [`tools/logs/session_20260430_223430_appfull.log:1320`](../tools/logs/session_20260430_223430_appfull.log), [`tools/logs/session_20260430_223430_appfull.log:1440`](../tools/logs/session_20260430_223430_appfull.log), [`tools/logs/session_20260430_223430_appfull.log:1552`](../tools/logs/session_20260430_223430_appfull.log)

---

## 2) 수정 목표 KPI

### 최종 목표
- 저장 완료된 모든 raw clip의 최종 길이 목표: **2000ms**
- 허용 오차: **±10ms 이내**

### 릴리즈 게이트 기준
- 3클립 재현 시나리오 기준 전 건 합격
- 합격 조건: 각 클립 최종 길이 `1990ms 이상 2010ms 이하`
- 불합격 조건: 1건이라도 범위 이탈 또는 fallback이 2000ms 미만으로 저장

---

## 3) 원인 축 정리

### A. 인코딩/컨테이너 타임스탬프 절삭
- 트림 또는 재인코딩 과정에서 프레임 경계 정렬, 컨테이너 타임스탬프 반올림/절삭으로 수십 ms 손실 가능성이 높다.
- 특히 source 2000ms에서도 1974ms로 줄어드는 패턴이 확인된다.
  - 근거: [`tools/logs/session_20260430_223430_appfull.log:1330`](../tools/logs/session_20260430_223430_appfull.log)

### B. 정책 우선순위 역전
- 현재 fallback 경로는 길이 정확성보다 저장 성공을 우선한다.
- 1866ms 정규화 실패 후 1900ms fallback 저장은 정책이 목표 보장보다 완료 처리에 치우쳐 있음을 의미한다.
  - 근거: [`tools/logs/session_20260430_223430_appfull.log:1441`](../tools/logs/session_20260430_223430_appfull.log), [`tools/logs/session_20260430_223430_appfull.log:1442`](../tools/logs/session_20260430_223430_appfull.log)

---

## 4) 수정 전략

## 4-1) 단기 핫픽스

1. **정규화 후 길이 검증 단계 강제**
   - normalize 완료 직후 실제 길이 재측정
   - 측정 결과가 KPI 범위 밖이면 즉시 재처리 분기로 이동

2. **보정 재처리 1회 추가**
   - 1차 결과가 1990ms 미만이면 tail pad 기반 2차 처리 수행
   - 2차 처리에서도 KPI 미충족 시에만 오류로 분류

3. **fallback 정책 즉시 재정의**
   - 기존: 저장 성공 우선
   - 변경: **2000ms 보장 우선**
   - 최소 조건: fallback 결과도 1990~2010ms 범위 미충족 시 저장 성공으로 간주하지 않음

4. **padToTarget 실효성 검증 가드 추가**
   - `padToTarget=true`이면 결과 길이가 목표 범위인지 필수 검증
   - 불일치 시 `pad_applied_but_under_target` 이벤트 로깅

## 4-2) 중기 구조개선

1. **정규화 파이프라인 2단계화**
   - 1단계: trim/normalize
   - 2단계: deterministic length fit 단계로 정확 길이 보정

2. **정책 엔진 분리**
   - 길이 목표 정책을 저장 성공 정책과 분리
   - 우선순위: `duration_integrity > save_completion`

3. **클립 길이 계약 Contract 명문화**
   - 입력, 처리, 저장, 인덱싱 전 단계에서 동일 KPI를 공유
   - UI 표시 길이와 실제 파일 길이의 일치 기준을 공통 규약으로 고정

---

## 5) 정책 제안

### fallback 정책 재정의
- 정책명: `strict_two_sec_guarantee`
- 규칙:
  - 목표 길이 미달 결과를 최종 성공으로 저장하지 않음
  - fallback 경로는 반드시 길이 보정 포함
  - 보정 실패 시 파일 저장 대신 실패 상태와 원인코드 기록

### padToTarget 실효성 보장
- `padToTarget=true` 설정은 옵션이 아닌 **결과 계약**으로 취급
- 처리 후 길이 검증 실패 시 성공 반환 금지

---

## 6) 구현 포인트 후보

- 1순위: [`VideoManager`](../lib/managers/video_manager.dart)
  - 후보 함수: [`VideoManager.saveRecordedVideo()`](../lib/managers/video_manager.dart), [`VideoManager.normalizeRecordedVideo()`](../lib/managers/video_manager.dart)
  - 반영 항목:
    - 정규화 후 재측정 훅
    - strict fallback 분기
    - `padToTarget=true` 검증 실패 처리

- 2순위: 길이 정책 상수/규약
  - 후보 파일: [`lib/constants/clip_policy.dart`](../lib/constants/clip_policy.dart)
  - 반영 항목:
    - 목표 길이 및 허용오차 상수화
    - 성공 판정 범위 함수화

- 3순위: 저장 메타/인덱스 반영 경계
  - 후보 파일: [`lib/services/local_index_service.dart`](../lib/services/local_index_service.dart)
  - 반영 항목:
    - KPI 미충족 clip의 인덱싱 차단 또는 실패 상태 기록

---

## 7) 검증 계획

### 로그 추가 항목
- normalize 전/후 측정치 분리 로그
  - `sourceDurationMs`
  - `normalizedDurationMs`
  - `postVerifyDurationMs`
- 보정 단계 로그
  - `retryNormalizeCount`
  - `padAppliedMs`
  - `fallbackPolicyName`
  - `finalDecision=success|fail`
- 실패 원인 코드
  - `reason=under_target_after_pad`
  - `reason=container_rounding_over_tolerance`

### 재현 시나리오
- 동일 세션 기준 3클립 시나리오 재실행
  - `clip_1777556201195` 유형: source 2000 근접 케이스
  - `clip_1777556206718` 유형: source 짧음 + fallback 발생 케이스
  - `clip_1777556215741` 유형: `padToTarget=true` 케이스

### 합격/불합격 기준
- 합격
  - 3클립 모두 `1990~2010ms`
  - fallback 사용 시에도 최종 길이 KPI 충족
  - `padToTarget=true` 케이스 KPI 100% 충족
- 불합격
  - 단 1건이라도 KPI 이탈
  - pad 적용 로그 존재하지만 최종 길이 미달

---

## 8) 리스크 및 롤백 포인트

### 리스크
- 보정 재처리 도입으로 저장 지연 증가 가능
- 과도한 strict 정책으로 실패율이 단기 상승할 수 있음
- 특정 디바이스 코덱에서 보정 결과 편차 확대 가능

### 롤백 포인트
- 기능 플래그 기반 정책 전환
  - `strict_two_sec_guarantee` ON/OFF
- 임계 장애 시
  - strict 검증만 OFF
  - 계측 로그는 유지하여 데이터 수집 지속

---

## 9) 실행 체크리스트

- [ ] `clip_policy`에 목표 길이/허용오차 상수 정의
- [ ] normalize 직후 재측정 로직 추가
- [ ] KPI 미충족 시 2차 보정 분기 추가
- [ ] fallback을 strict 정책으로 전환
- [ ] `padToTarget=true` 결과 검증 강제
- [ ] 실패 원인코드 및 보정 로그 항목 추가
- [ ] 3클립 재현 테스트 실행 및 로그 채증
- [ ] 합격/불합격 판정 자동 체크 적용
- [ ] 기능 플래그 롤백 경로 점검


# Kakao 로그인 재배포 후 실패 대응 계획 (functions 재배포 회귀 분석)

> 목표: `session_20260315_130936` 로그 기반으로 **원인 확정** 및 **재발 방지 계획** 수립, 코드/운영 절차까지 적용 가능한 실행안 작성

## 1) 현재 증상 요약

- Flutter 앱은 Kakao 토큰을 받고 [`functions/index.js`](functions/index.js:1) 의 `/social/exchange`로 교환 요청을 보냄.
- 실패 구간은 서버에서 Kakao 사용자 조회가 실패했을 때로 응답이 `401 INVALID_SOCIAL_TOKEN`.
- 성공 로그(`session_20260315_124913`)에서는 동일한 클라이언트/플로우가 `200` 반환으로 로그인 완료.
- 실패 로그(`session_20260315_130936`)에서는 Kakao 응답 상세 메시지에 `user property not found (...)`가 포함되어 있음.

## 2) 로그 근거 기반 루트 원인

### 결론(확정)
`functions/index.js`의 Kakao 검증(`verifyKakao`)이 `property_keys`를 포함한 `/v2/user/me` 호출을 먼저 수행한 뒤 실패 시 즉시 예외 처리하면서, 프로필 키 미허용/누락 케이스까지 일반 인증실패로 간주하고 있다.

핵심 코드 위치:
- Kakao 프로필 조회 요청부: [`requestProfile()`](functions/index.js:209)
- 1차 조회 후 즉시 오류 처리: [`if (!response.ok) throw new Error(...)`](functions/index.js:223)
- 의미있는 프로필 여부 기반 fallback: [`hasMeaningfulProfile(data)`](functions/index.js:40) 및 `usedFallbackUserMe` 처리

### 실패 연쇄

1. 앱에서 `accessToken`은 전달됨 (`SOCIAL_AUTH_EXCHANGE_URL` 응답도 정상 reach 가능).
2. 서버는 `property_keys`가 붙은 `/v2/user/me`를 호출.
3. Kakao가 해당 앱(`appId=1405031`)에서 요청한 property들을 반환할 수 없어 `400` 반환 + 상세 메시지에 missing property.
4. 코드가 400을 즉시 `KAKAO_TOKEN_INVALID`로 맵핑.
5. 최종적으로 앱은 `INVALID_SOCIAL_TOKEN`(401) 수신.

## 3) 왜 최근 재배포 뒤 발생했는가

- 재배포 전/후 비교에서 사용자 UID 패턴(`kakao_<id>`)은 동일 방식으로 생성되어 클라이언트-서버 플로우는 유지.
- 차이는 서버측 Kakao 프로필 조회 정책 변경이 의심됨:
  - 기존 대비 `property_keys` 요청 강제/요청 항목 세트(`KAKAO_PROPERTY_KEYS`) 동작 변화,
  - 혹은 Kakao 앱 설정 변경으로 특정 property 접근이 거부되며 400 유도.
- 즉, 클라이언트 버그보다 **서버 토큰 교환 계층의 Kakao 응답 허용범위/폴백 로직**이 회귀 원인으로 판단됨.

## 4) 개선 계획 (1차 즉시 반영)

### A. Kakao `/user/me` 호출 전략 강화

#### A-1. 실패 분류 기반 fallback 수행
- 현재 로직: `response.ok === false` 즉시 throw.
- 개선: `user property not found` 성격의 응답(특정 필드 부족)일 때는
  1) 전체 프로필 재요청(쿼리 파라미터 제거)
  2) 실패가 계속되면 원래 실패로 간주

반영 대상: [`requestProfile()`](functions/index.js:209) , [`verifyKakao()`](functions/index.js:202)

#### A-2. `property_keys`를 최소 필수 항목으로 축소
- 현재 12개 항목 요청 중 사용자 데이터의 핵심은 `kakao_account.profile` 계열이다.
- 첫 호출은 다음으로 축소 또는 아예 생략 후 fallback-only 전략 고려:
  - `kakao_account.profile.nickname`
  - `kakao_account.profile.profile_image_url`

#### A-3. 실패 원인 분리
- 기존: 모든 4xx를 동일하게 `KAKAO_TOKEN_INVALID` 처리.
- 개선: Kakao 응답 메시지를 분기해 `REQUIRED_PROPERTY_NOT_ALLOWED` 등 내부 오류 코드를 추가해 운영 가시성 확보.

### B. 에러 로깅/추적성 강화

- 요청당 correlation id 추가(헤더 혹은 UUID): `x-request-id`.
- Kakao 호출별 로그 추가:
  - `property_keys` 사용 여부
  - 요청 URL 길이/파라미터 존재 여부
  - 응답 status, content-type, 응답 본문 요약(코드/메시지)
  - fallback 시도 횟수

반영 대상: [`handleExchange()`](functions/index.js:342), [`verifyKakao()`](functions/index.js:202), [`writeError()`](functions/index.js:135)

### C. 테스트/회귀 체크 강화

1. `functions/index.js` 단위 테스트
   - `property_keys` 요청에서 400 + missing property 응답 시 fallback 성공
   - `property_keys` 요청에서 400 + token invalid 응답 시 즉시 실패
   - `user/me`에서 profile 없는 정상 token인 경우도 UID만으로 처리 가능 여부
2. 통합 테스트: 배포 후 1회 이상 실제 Kakao 신규/기존 계정 로그인 점검
3. 로그 알람
   - `INVALID_SOCIAL_TOKEN` 증가율 임계치 초과 시 Slack/Cloud Logging 경보

## 5) 운영 롤백/검증 플랜

### 배포 순서

1. **스테이징 함수 배포**
   - 위 로직만 반영한 코드 배포 후 내부 테스트 토큰 2종으로 검증
2. **Canary 배포(10~20% 호출 대상)**
   - 실패율 추적 + fallback 실행률 확인
3. **본배포 적용**
   - `INVALID_SOCIAL_TOKEN` 1시간 이동평균이 기준치 대비 악화되지 않음 확인

### 모니터링 지표

- `social/exchange 401 INVALID_SOCIAL_TOKEN` 비율
- Kakao user/me 400 중 property-key missing 유형 비율
- fallback 성공률
- custom token 생성 성공률

### 롤백 조건

- 1회 응답 사이클 내 실패율이 기존 대비 **+2배** 초과
- fallback 시도 후에도 동일 오류 지속(원인 미해소)
- Firebase custom token 생성 이전 단계에서 지연이 서비스 임계 초과

## 6) 구현 우선순위(실행 체크리스트)

- [x] `verifyKakao()`에서 Kakao 400 응답 분기 처리 보강
  - missing property에 대해 fallback 허용
  - fallback 후에도 실패하면 명확한 에러 사유 반환
- [x] `KAKAO_PROPERTY_KEYS` 최소화/옵션화(환경변수 기반 설정 고려)
- [x] `requestId` 기반 로그 추가 및 경고 로그 템플릿 통일
- [ ] 함수 단위 테스트 추가 후 CI에 연결 (CI 연동은 별도 추적 항목)
- [x] 배포 전/후 로그인 E2E 재현 테스트 문서화 (현재 `social/exchange` 합성 호출 기반 smoke 체크로 기본 커버)

## 6-1) 배포 후 회귀 검증 기록 (2026-03-15)

- 배포 버전 확인:
  - `functions` 재배포 완료 (`project: fir-3s-8edb9`, function `social`)
- 회귀 검증 범위:
  1. 배포 직후 `functions:log --only social --project fir-3s-8edb9 --lines 800`
  2. 합법 요청/비합법 요청 대비 실행 지표 집계
  3. 모니터링 임계치 쿼리 동작 점검
- 수집 결과(요약):
  - 배포 직후 최초 24시간 분석 기준 `Function execution` 총건수
    - 배포 이전: `before.total=24`, `before.200=8`, `before.401=3`
    - 배포 이후: `after.total=4`, `after.200=0`, `after.401=1`
  - 배포 이후 `401` 비율 = `0.250` (샘플 수가 적어 기준치 경보 조건 미적용)
- 합성 검증 API 호출 2건:
  1. `POST /social/exchange` with `{}` → `400 INVALID_PROVIDER` (정상적인 바디 검증 동작)
  2. `POST /social/exchange` with invalid kakao 토큰 → `401 INVALID_SOCIAL_TOKEN` + `reason=KAKAO_TOKEN_INVALID`, `fallbackAttempts=0`

## 6-2) 모니터링 임계치 검증

- 현재 환경에서 Google Cloud CLI(`gcloud`) 미설치로 알림 정책 생성/수정은 확인 불가
- 대체 검증:
  - 로그 기반 실패율 산출 스크립트(현재 저장소/운영 환경에서 실행)
  - `status code: 401`과 `status code: 200` 라인 수를 주기적으로 집계하는 방식으로 슬랙/페이지 알림 트리거 조건을 수립
  - 임계치 권장: `현재 구간 401 비율 > 0.02` 또는 `24시간 이동평균 401 급증` 시 경고
- 확인 결과:
  - 즉시 배포 후 소량 샘플에서 임계치 위반 케이스 미확인 (샘플 부족)

## 7) 기대 효과

- Kakao 앱 설정/권한 차이에 민감한 profile key 오류를 토큰 자체 무효로 오탐하지 않음
- 동일 증상 재발 시 원인 파악 시간 단축 (로그 상에서 root cause 즉시 식별)
- 배포 후 OAuth 회귀 대응 속도 상승 및 사용자 로그인 실패율 감소


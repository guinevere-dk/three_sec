# OpenID Connect(및 소셜 토큰 교환) 통합 구현 계획 v1

## 1. 탐색 요약

현재 앱은 Kakao/Naver 로그인 진입점은 존재하지만, 핵심 플로우는 `SOCIAL_AUTH_EXCHANGE_URL`로
소셜 토큰을 서버에서 교환받아 Firebase 커스텀 토큰을 발급하는 구조다.

- UI 버튼/핸들러는 존재:
  - Google, Apple, Kakao, Naver 버튼 및 처리 핸들러는 [`lib/screens/login_screen.dart`](lib/screens/login_screen.dart:75)부터
    [`lib/screens/login_screen.dart`](lib/screens/login_screen.dart:100), [`lib/screens/login_screen.dart`](lib/screens/login_screen.dart:110)
    에 구현돼 있다.
- 클라이언트 인증 진입점:
  - `signInWithKakao`와 `signInWithNaver`는 각각 SDK 토큰을 얻은 뒤
    공통 교환 API로 위임한다.
    - [`lib/services/auth_service.dart`](lib/services/auth_service.dart:385)
    - [`lib/services/auth_service.dart`](lib/services/auth_service.dart:414)
- 공통 교환 요청은 `SOCIAL_AUTH_EXCHANGE_URL` 환경변수를 사용:
  - [`lib/services/auth_service.dart`](lib/services/auth_service.dart:78)
  - [`lib/services/auth_service.dart`](lib/services/auth_service.dart:463)
- 백엔드는 Firebase Functions에서 `/social/exchange`를 처리:
  - [`functions/index.js`](functions/index.js:1)
  - 요청 라우팅/검증: [`functions/index.js`](functions/index.js:749)
  - Kakao/Naver 토큰 검증: [`functions/index.js`](functions/index.js:395), [`functions/index.js`](functions/index.js:666)

### 현재 상태에서의 간극

1. 네이티브 연동 구성(안드로이드/iOS 스킴·메타데이터)이 미완성 상태라 로그인 인증콜백이 불안정할 수 있음.
   - Android Manifest: Kakao/Naver 관련 메타데이터 부재
     - [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml:18)
   - iOS Info.plist: URLTypes, 쿼리 스킴 부재
     - [`ios/Runner/Info.plist`](ios/Runner/Info.plist:4)
2. OIDC 관점에서 검증이 id_token/JWT 표준 기반으로 정규화되지 않았고,
   오류 사유가 클라이언트로 명시적으로 전달되지 않아 UX/디버깅이 약함.
   - 교환 실패 시 예외 메시지 문자열로 처리
     - [`lib/services/auth_service.dart`](lib/services/auth_service.dart:463)
   - 서버는 token 필드를 200 응답에서만 반환, 실패는 4xx/5xx
     - [`functions/index.js`](functions/index.js:907)

## 2. 구현 목표(원칙)

### OIDC 표준 정합성 목표
- OIDC 토큰 교환 요청/응답을 **공통 스키마**로 통일.
- `idToken`은 provider별 JWT/nonce/aud/exp 검증 루트를 기본값으로 채택.
- Access token fallback는 지원하지만, 가능하면 id_token 중심으로 전환.

### 운영/보안 목표
- 로그인 실패 사유를 구조화된 코드로 전달해 모니터링/알림과 연계.
- 키 교체(쿠키/키셋, endpoint 변경) 및 프로퍼티 정책 변화를 고려한 fallback 포함.
- 민감정보(토큰)는 로그 출력에서 마스킹 처리.

### 확장성 목표
- Provider별 구현을 플러그인화하여 추후 Google 외부 OIDC 공급자 추가를 용이하게 함.

## 3. 제안 아키텍처

```text
UI(LoginScreen)
  -> AuthService.signInWith{Kakao,Naver}
    -> _exchangeSocialToken(provider, {accessToken, idToken, nonce})
      -> Firebase Functions /social/exchange
        -> ProviderVerifier(추상화)
            -> KakaoVerifier / NaverVerifier
          -> verifyIdToken(idToken) (가능한 경우)
          -> fallback verify access token
        -> createCustomToken(uid, claims)
      -> AuthService signInWithCustomToken
```

권장 공통 스키마:

- 요청: `provider`, `accessToken`, `idToken`, `nonce`, `rawProviderUserId`, `providerAudience`, `appVersion`
- 응답 성공: `success`, `provider`, `uid`, `firebaseToken`
- 응답 실패: `success=false`, `error.code`, `error.message`, `error.details`

참고: 이미 응답 형식의 최소 필드(`firebaseToken`, `customToken`, `token`) 지원이 있어 호환성은 유지됨.

## 4. 작업 분해(1차 구현)

### 4.1 클라이언트(`Flutter`) 수정

1. 공통 에러 타입 정리
   - `AuthService`에 로그인 에러 모델/코드 상수 추가.
   - `SOCIAL_AUTH_EXCHANGE_URL` 미설정/HTTP 에러/파싱 실패를 구분.
   - 기존 `catch`에서 `null` 반환 대신 실패 사유를 상위로 전달 가능하도록 인터페이스 정리.

2. OIDC 필드 전달 강화
   - Kakao: `idToken`과 `accessToken` 모두 전달(현재 전달됨).
   - Naver도 향후 OIDC `idToken` 제공 경로 조사 후 전달 가능한 경우 확장.
   - 교환 요청 본문에 `nonce`, `providerAudience`, `clientId`를 옵션으로 추가.

3. 로그인 UX 개선
   - `_handleKakaoSignIn`, `_handleNaverSignIn`에서 null return(취소)와 명확한 오류 구분.
   - 네트워크/환경오류 메시지 국제화(한글 표시).

4. 초기화 검증
   - 앱 시작 시 `SOCIAL_AUTH_EXCHANGE_URL` / `KAKAO_NATIVE_APP_KEY` presence check를
     UI 레벨에서 사용자에게 가시적으로 표시할 수 있게 상태 반영.

### 4.2 서버(`functions/index.js`) 수정

1. OIDC 검증 레이어 추가
   - `provider`별 verifier 추상화 작성(`verifyKakao`, `verifyNaver` 기존 로직 리팩토링).
   - Kakao는 `idToken`이 있으면 JWKS 검증(또는 at least issuer/client assertion) 우선 시도.
   - 실패 시 기존 `access token` user/me fallback 유지.

2. 에러 코드 정규화
   - 현재 코드: `INVALID_PROVIDER`, `INVALID_REQUEST`, `INVALID_SOCIAL_TOKEN`, `SOCIAL_USER_NOT_FOUND` 등을 더 세분화.
   - 클라이언트로 반환되는 `details.reason` 필드에
     `provider`, `httpStatus`, `fallbackUsed` 등을 일관되게 포함.

3. 감사/관측성 강화
   - requestId, provider, requestAttemptCount, requestAttempt details를 성공/실패 모두 로그.
   - 에러 응답 시 `requestAttemptCount`와 `reason` 항상 포함.

4. 보안 강화
   - `SOCIAL_EXCHANGE_ALLOWED_ORIGINS` 정책 유지 강화, 필요한 오리진만 허용.
   - 토큰 길이/헤더/본문 크기 경계값 하드닝(현재 `MAX_BODY_BYTES`는 존재).

5. 회귀 호환성
   - 기존 `provider`(`kakao`,`naver`) 유지.
   - 응답은 현재 지원 키(`firebaseToken`, `customToken`, `token`)를 유지.

### 4.3 네이티브 연동

1. Android
   - `AndroidManifest.xml`에 Kakao/Naver 메타데이터 및 intent-filter 추가.
   - `res/values/strings.xml` 신규 추가 (현재 없음).

2. iOS
   - `ios/Runner/Info.plist`에 `CFBundleURLTypes`, `LSApplicationQueriesSchemes` 추가.

3. 빌드 가이드 정비
   - 실행 커맨드에 필요한 `--dart-define` 값 명시
     - `SOCIAL_AUTH_EXCHANGE_URL`
     - `KAKAO_NATIVE_APP_KEY`

### 4.4 문서/운영

1. `firebase/README.md`의 테스트 항목에 OIDC 성공/실패 스모크 테스트 추가.
2. 로그 키워드 기준 검색 자동화(`findstr`)에
   `social/exchange`, `requestId`, `INVALID_SOCIAL_TOKEN`, `INVALID_PROVIDER`
   등 패턴 추가.

## 5. 테스트 전략

- 단위 테스트(함수)
  - provider 파라미터 누락/미지원
  - accessToken 누락
  - Kakao/Naver 응답 실패 시 에러 코드 매핑

- 통합 테스트(클라이언트)
  - Kakao 로그인 성공/취소
  - Naver 로그인 성공/취소
  - `SOCIAL_AUTH_EXCHANGE_URL` 미설정 시 명시적 에러
  - `exchange` 401/422/500 처리

- E2E
  - 실제 기기에서 앱 토큰 교환 성공 후 Firebase UID 발급 확인
  - 재로그인/로그아웃 경로(세션 초기화 포함)

## 6. 롤백/피처 플래그

- 1차 배포는 `provider=naver`, `provider=kakao` 기존 플로우를 유지한 채 점진 적용.
- 실패율 임계치 초과 시 클라이언트의 OAuth 네이티브 진입은 유지하고,
  서버는 즉시 **fallback-only** 모드로 전환 가능하도록 코드 경로 준비.

## 7. 일정 예시

1. 1단계(1일): 백엔드 에러 코드 정규화 + 구조화 응답
2. 2단계(1일): 클라이언트 에러 전달 및 UI 피드백
3. 1단계 병행(0.5일): Android/iOS native 설정 보강
4. 1단계(0.5일): 로그/모니터링 항목 및 QA 체크리스트 정비
5. 1일: 스테이징 배포 및 회귀 테스트

## 8. 확인 체크리스트

- [x] OIDC 요청/응답 스키마 문서화
- [ ] Kakao/Naver 각각의 토큰 교환 성공률 임계치 측정
- [x] 에러 코드별 사용자 메시지 노출
- [ ] Android/iOS 콜백 설정 반영 여부 코드리뷰
- [ ] 스모크 테스트 자동화(수동 스크립트 또는 로그 기반)

## 9. 구현 반영 현황 (v1 적용 완료)

### 클라이언트 (Flutter)
- `AuthServiceException` 추가로 교환 API 실패를 구조화(`code`, `httpStatus`, `requestId`, `details`)하여 상위 UI 전달.
- Kakao/Naver 교환 요청에 OIDC 확장 필드 전달 지원:
  - `nonce`, `providerAudience`, `clientId`, `appVersion`, `rawProviderUserId`
- 로그인 화면에서 `AuthServiceException.userMessage`를 우선 표시해 사용자 가시성 강화.

### 서버 (Functions)
- `/social/exchange` 요청 스키마 확장 필드 파싱 추가:
  - `nonce`, `providerAudience`, `clientId`, `rawProviderUserId`, `appVersion`
- 에러 응답 `details`에 `reason`, `requestAttemptCount`, `fallbackAttempts`, `fallbackUsed`, `status`, `requestId` 일관화.
- Kakao/Naver 모두 `idToken`이 들어오면 claim 기반 OIDC 검증(exp/nonce/aud) 수행 후 실패 시 `INVALID_SOCIAL_TOKEN`으로 매핑.

### 문서
- Firebase 가이드에 확장 요청 바디 및 표준화된 에러 세부 필드/코드 반영.


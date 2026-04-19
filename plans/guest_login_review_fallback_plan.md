# Google Play 심사 대응 게스트 로그인(Guest Login) 실행 계획

## 0) 배경
- 심사 계정에서 소셜 로그인(특히 Google) 진입이 반복 실패하여 심사 반려가 발생하고 있음.
- 우선 `로그인 실패=출시차단` 상황을 막기 위해, **게스트 모드로 앱 본편 진입이 가능한 임시/백업 경로**를 먼저 확보.
- 기존 소셜 로그인 기능은 유지하되, 게스트 모드는 오프라인/로컬 중심 기능만 허용.

## 1) 목표(DoD)
- 심사 계정 없이도 앱 실행 직후 핵심 흐름(촬영/클립 선택/영상 생성) 진입 가능.
- 게스트 세션에서 구독/클라우드 기능이 비활성화되어 결제/데이터 유실 이슈가 없도록 보장.
- 로그아웃/계정 전환 동선이 명확하여 재심사 시 리뷰 계정이 아닌 테스트 계정 없이도 접근성이 높음.
- 다음 버전에서는 게스트에서 정식 회원 전환이 자연스럽게 가능.

---

## 2) 현재 구조 영향 분석
- 현재 앱은 로그인 상태(`FirebaseAuth.currentUser`)가 없으면 바로 로그인 화면으로 강제 이동함.
  - 진입점: [`AuthGate`](lib/main.dart:225)
- 로그인 화면은 Google/Apple/Kakao 버튼만 노출돼, 현재는 게스트 진입 버튼이 없음.
  - 버튼/핸들러: [`_handleGoogleSignIn`](lib/screens/login_screen.dart:216), [`_handleAppleSignIn`](lib/screens/login_screen.dart:237), [`_handleKakaoSignIn`](lib/screens/login_screen.dart:258)
- 소셜 로그인 실패 시 예외 처리/피드백이 충분하지 않아 사용자 입장에서 실패 원인 파악이 어려움.
  - 예: [`_handleKakaoSignIn`](lib/screens/login_screen.dart:258), [`_handleNaverSignIn`](lib/screens/login_screen.dart:286)
- 클라우드 계층은 현재 사용자 인증을 엄격히 요구하고 있음.
  - 사용자 UID 획득: [`CloudService._getCurrentUserId`](lib/services/cloud_service.dart:130)
- 사용자 등급은 `UserStatusManager`로 관리되고 기본값이 free.
  - 초기값/초기화: [`UserStatusManager`](lib/managers/user_status_manager.dart:27), [`UserStatusManager.initialize`](lib/managers/user_status_manager.dart:99)

---

## 3) 설계 원칙 (필수)
1. **게스트 = 로컬 기본 사용자**
   - Firebase 인증 계정이 없는 상태라도 앱 진입 가능.
   - 동영상 편집/미리보기/클립 생성/로컬 저장은 허용.

2. **게스트 = 클라우드/과금 기능 차단**
   - 업로드/동기화/클라우드 메타데이터 조회 등은 차단.
   - 현재 CloudService 의존 로직과의 충돌을 방지.

3. **게스트 → 정식회원 즉시 전환**
   - 프로필 또는 설정에서 소셜 로그인으로 전환 시 기존 로컬 데이터를 유지하고 세션만 교체.

4. **심사용 계정 의존도 제거**
   - 앱 실행 즉시 “소셜 로그인 안 되면 사용 불가” 상태를 피함.

---

## 4) 구현 단계

### Phase A. 인증 레이어 분리(핵심)
1. 게스트 세션 상태 모델 도입
   - `AuthService` 또는 별도 세션 상태 관리에 `AuthMode.guest / AuthMode.signedIn` 추가.
   - Firebase 사용자 미연결 시에도 `isGuest` 상태를 보유.
   - 권장 참조: 현재 인증 모듈 중심 파일은 [`AuthService`](lib/services/auth_service.dart:121).

2. 게스트 시작/종료 API 추가
   - `signInAsGuest()` / `signOutGuest()` 추가.
   - guest 시작 시 로컬 프리플레어 데이터(`3s_user_id` 등) 정합성 초기화.

3. 인증 게이트 변경
   - [`AuthGate`](lib/main.dart:225)에서 `snapshot.data == null`일 때도
     `isGuest`면 메인 화면으로 진입, 아니면 로그인 화면.
   - 다만 세션 부트스트랩은 기존대로 유지.

### Phase B. UI/UX(심사 대응 우선)
4. 게스트 진입 버튼 추가
   - 로그인 화면 하단 또는 별도 안내 영역에 `게스트로 시작` 버튼 배치.
   - 버튼 동작은 [`_handleGoogleSignIn`](lib/screens/login_screen.dart:216) 패턴을 참고해 상태 변경 + 토스트/스낵바 피드백.

5. 게스트 라벨 및 안내 배너
   - 게스트 진입 시 상단/프로필에서 "게스트 모드" 표시.
   - 현재 프로필 기본 문자열이 `Guest User`로 출력되는 형태를 정리해 일관되게 사용.
     - 기존 표시 로직: [`_profileDisplayName`](lib/screens/profile_screen.dart:112)

6. 프로필에서 계정 전환 동선 보강
   - 계정 메뉴에 `게스트에서 로그인하기` 또는 기존 버튼 활성화 로직 정리.
   - `로그아웃`/`계정 삭제`는 게스트 모드일 때 비활성화 또는 안내 변경.
   - 대상: [`ProfileScreen`](lib/screens/profile_screen.dart:18), [`_confirmSignOut`](lib/screens/profile_screen.dart:387), [`_confirmDeleteAccount`](lib/screens/profile_screen.dart:419)

### Phase C. 데이터/기능 차단 정책
7. 클라우드 접근 통합 가드
   - 현재 `CloudService._getCurrentUserId`가 인증 기반인 점을 유지하되,
     게스트 진입 시 즉시 동작 차단 UX를 명시적으로 띄움.
   - 업로드/동기화 시작 버튼에서 먼저 `AuthService`의 게스트/로그인 상태 검사.

8. 보안 및 Firestore 규칙 점검
 - 게스트 UID 없는 세션에서 `users`, `videos`, `vlog_projects` 접근이 일어나지 않도록 앱 레이어와 규칙 레이어 모두 확인.
 - 규칙 변경이 필요한 경우에는 `CloudService`에서 null auth 경로가 호출되지 않도록 방어 코드를 우선 정렬.

9. 리뷰 계정 대응 모드 플래그
   - 임시 운영 플래그(예: `_isGuestModeEnabled`)를 두어, 심사 제출 빌드에서 기본 게스트 모드 노출을 보장.
   - 이후 GA에선 운영 정책에 맞춰 점진 비활성화 가능.

### Phase D. 계측/로그/복구
10. 진입률 및 게스트 실패율 로그
   - 로그로 `소셜 로그인 실패`, `게스트 진입`, `클라우드 진입 차단` 이벤트를 별도 카운트.

11. 긴급 롤백 경로
   - 게스트 모드가 문제를 유발할 경우, 즉시 플래그 off/버튼 숨김 배포로 기존 로그인 강제 모드로 복귀 가능.

---

## 5) 테스트 및 심사 대응 체크리스트

### 로컬 확인
- [ ] 앱 설치 후 로그인 없이 `게스트로 시작` 클릭 시 메인 화면 진입.
- [ ] 로그인 없이 촬영/클립 선택/영상 생성 기본 플로우 동작.
- [ ] 클라우드 동기화 버튼(또는 클라우드 관련 기능)에서 게스트 안내 후 차단.
- [ ] 프로필에서 게스트 상태가 표시되고, 정식 로그인 전환 흐름 진입 가능.

### 심사 대응 시나리오
- [ ] 심사 계정 없이도 앱 시작과 핵심 기능 데모 가능.
- [ ] 소셜 로그인 버튼 클릭 실패 시에도 앱이 블랙스크린/강제 종료 없이 처리 가능.
- [ ] 플레이 콘솔 테스트 계정이 아닌 디바이스에서 재현 가능한 안정적 앱 진입.

### 보안/데이터
- [ ] 게스트 세션에서 `users/videos/vlog_projects`에 쓰기 요청이 발생하지 않음.
- [ ] 로컬 데이터는 로컬 스토리지 정책(보관/삭제 정책)에 맞게 유지.
- [ ] 정식 로그인 전환 시 기존 로컬 프로젝트가 사라지지 않고 계속 사용 가능.

---

## 6) 리스크 & 대응

### 리스크
- **기능 범위 오해**: 심사자가 게스트에서 일부 기능이 제한되어 있으면 불만으로 이어질 수 있음.
  - 대응: 게스트는 핵심 시연 흐름을 우선 지원하고, 제한 항목은 첫 화면에 명확 고지.
- **게스트/회원 상태 동기화 누락**: 로그인 후에도 일부 화면이 게스트 상태를 기준으로 동작.
  - 대응: 인증 전환 시 `AuthService` + `UserStatusManager` 재초기화를 강제.
- **CloudService 이중 방어 미흡**: 앱 화면에서만 못 막고 백그라운드 호출에서 실패.
  - 대응: cloud call 진입점 별 가드 + 에러 코드 처리 추가.

### 의사결정 포인트
- 게스트 계정은 Firebase `signInAnonymously`로 처리할지, 순수 앱 로컬 세션으로 처리할지
  - 로컬 세션이 단순하지만 일부 기능 전환 시 정합성 구현이 추가되어야 함.
  - Firebase 익명 계정은 규칙 정합성에 대한 검토가 필요함.

---

## 7) 마감 산출물
- 게스트 로그인 UX/로직 설계 문서 확정 및 리뷰 제출용 테스트 가이드 문구 정리.
- 빌드 노트에 "심사 대응용 임시 경로(게스트) 도입" 명시.
- 1차 패치 릴리즈 후 24~48시간 내에 재심사 제출.


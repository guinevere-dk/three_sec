# 3s v1.0 Free Only 출시 계획 (구현 미실행)

## 1) 목표
- **목표**: 구독 결제(업그레이드/구독 관리) 유입 경로를 UI에서 모두 제거하고, **Ver 1.0 = Free 기능만** 노출
- **원칙**: 기능 구현은 이번 단계에서 하지 않음. 문서/계획만 확정
- **출시 상태 문구**: Profile/앱 공지 영역에 `Ver 1.0 (Free)` 또는 동등한 버전 라벨 반영 검토

## 2) 현재 발견된 과금 관련 진입점 스냅샷

### 2-1. 메인 네비/탭
- `main` 네비게이션에서 Project 탭이 하단 탭/페이지 구성 항목으로 노출되는 구조: [`items`](lib/main.dart:564), [`IndexedStack`](lib/main.dart:526), [`_buildBenchmarkBottomNav`](lib/main.dart:563)

### 2-7. 추가 개선 포인트(요청 반영)
- Project 탭을 UI에서 완전히 숨김: 하단 탭 항목, 페이지 매핑, 인덱스 예외 분기까지 제거/정리
- 프로필 화면 `stats`에서 `PROJECT`/`CLOUD` 카드 노출 제거: [`_buildStatsCard`](lib/screens/profile_screen.dart:713), [`_buildStatItem(clipCount, 'CLIP')`](lib/screens/profile_screen.dart:726)

### 2-8. 구현 전 추가 산출 항목
- Project 탭 제거는 하단 탭 개수 변경으로 인한 인덱스 이동 경계(`_selectedIndex`) 회귀 리스크를 동반하므로, 네비게이션 라우팅 정합성 검토를 별도 항목으로 수행
- Profile 통계 카드에서 `PROJECT`/`CLOUD` 제거 시 카드 개수/간격 변경이 레이아웃에 미치는 영향까지 동시 반영

### 2-9. 소셜 로그인/로그아웃 메시지 정리(추가 반영)
- 로그인 화면의 Kakao/Naver 버튼을 활성화하고 실제 AuthService 연동 핸들러를 바인딩: [`_buildSocialButton`](lib/screens/login_screen.dart:98), [`_handleKakaoSignIn`](lib/screens/login_screen.dart:227), [`_handleNaverSignIn`](lib/screens/login_screen.dart:247)
- Kakao/Naver 연동의 실제 인증 처리(토큰 획득 + Firebase 커스텀 토큰 교환)로 이동: [`signInWithKakao`](lib/services/auth_service.dart:194), [`signInWithNaver`](lib/services/auth_service.dart:227), [`_signInWithSocialProviderCustomToken`](lib/services/auth_service.dart:262)
- 로그아웃 시 Cloud 보존 안내 문구는 다이얼로그에서 제거됨: [`_confirmSignOut`](lib/screens/profile_screen.dart:336), [`Text('로그아웃하시겠습니까')`](lib/screens/profile_screen.dart:345)

### 2-2. 라이브러리 탭
- `paywall` 라우팅 함수가 존재하며, 앱바 우측 별표 버튼에서 호출됨: [`_openPaywallAndRefresh`](lib/screens/library_screen.dart:139), [`Icons.star` 액션 버튼](lib/screens/library_screen.dart:210)

### 2-3. 프로젝트 탭
- 프로젝트 진입 직전 `paywall` 진입 함수가 존재함: [`_openPaywallAndRefresh`](lib/screens/project_screen.dart:145)
- 프로젝트 목록 앱바 우측 별표 버튼에서 `paywall` 호출: [`Icons.star`](lib/screens/project_screen.dart:229)
- 무료 사용자는 바로 편집 진입이 안 되고 `isStandardOrAbove()` 기반으로 분기: [`_openProjectWithTierRouting`](lib/screens/project_screen.dart:46)

### 2-4. 프로필 탭
- 프로필 메뉴에 구독 관리 항목 노출: [`_buildMenuItem` - `구독 관리`](lib/screens/profile_screen.dart:596)
- 구독 라우팅 함수: [`_openSubscriptionManagement`](lib/screens/profile_screen.dart:157)
- 프로필 카드에 구독 티어 배지 노출 (`Free/Standard/Premium`): [`_buildProfileCard` 배지 영역](lib/screens/profile_screen.dart:765)
- 계정 삭제/차단 다이얼로그에 구독/해지 문구 노출: [`_confirmDeleteAccount`](lib/screens/profile_screen.dart:454), [`_showAccountDeletionBlockedDialog`](lib/screens/profile_screen.dart:506)

### 2-5. 편집 화면
- 편집 화면 진입 시 구독 미달이면 업그레이드 다이얼로그 + `PaywallScreen` 이동: [`_runAccessGateThenInit`](lib/screens/video_edit_screen.dart:355), [`편집 잠금`](lib/screens/video_edit_screen.dart:369), [`Navigator.push(PaywallScreen)`](lib/screens/video_edit_screen.dart:386)

### 2-6. 과금 화면 자체
- `PaywallScreen` 자체 존재: [`class PaywallScreen`](lib/screens/paywall_screen.dart:10)
- `SubscriptionManagementScreen`에서 `paywall` 진입 포함: [`_openPaywallAndRefresh`](lib/screens/subscription_management_screen.dart:73)

## 3) Ver 1.0 표시 범위(고정)

### 포함
- 기존 핵심 플로우는 유지: 촬영/라이브러리/프로젝트/프로필 기본 기능의 Free 체험
- 사용자 안내 문구에서 Premium/Standard/구독 관리/업그레이드/해지 경로 제거

### 제외
- 프로필 구독 메뉴 및 티어 뱃지, 구독 상태 라벨
- Library/Project 헤더 별표 버튼
- 메인 탭의 프로젝트 잠금표시(별표) 및 접근 제한 분기(Free로 인한 잠금) 제거
- 메인 탭에서 `Project` 탭 자체 비노출
- 편집화면/프로젝트 관련 내부 업그레이드 다이얼로그 삭제(또는 비활성) 및 Paywall 진입 경로 제거
- 구독 관리/페이월 화면이 UI에서 직접 접근되지 않도록 처리
- 프로필 통계 카드에서 `PROJECT`/`CLOUD` 카드 노출 제외

## 4) 1차 실행 기준(구현 전 확정 문서)

### 4-1. UI 변경 범위(구현 전 확인 리스트)
1. **main.dart**
    - `Project` 탭 숨김 처리: 하단 탭 구성에서 Project 항목/페이지 매핑 제거
      - [`items`](lib/main.dart:564), [`IndexedStack` children](lib/main.dart:526), [`_buildProfileTab`](lib/main.dart:879)
    - 탭 분기 보정: Profile/복귀 인덱스 보정 로직 정합성 재검토
      - [`onTap` 프로필 분기](lib/main.dart:591), [`_handleMerge` 내 `_selectedIndex = 1`](lib/main.dart:784)
    - 추가 점검: Project 탭 삭제 후 `_selectedIndex` 상한값 조정 로직(`0~2`)이 일관되게 동작하도록 코드 정합성 확인
      - [`_buildBenchmarkBottomNav`](lib/main.dart:563), [`_selectedIndex`](lib/main.dart:526), [`_handleMerge`](lib/main.dart:787)

2. **library_screen.dart**
   - `paywall` 액션 버튼 제거 또는 숨김: [`_openPaywallAndRefresh`](lib/screens/library_screen.dart:139), [`Icons.star`](lib/screens/library_screen.dart:210)

3. **project_screen.dart**
   - 프로젝트 헤더 별표/페이월 진입 제거: [`Icons.star`](lib/screens/project_screen.dart:230)
   - 편집 잠금/표시 문구/분기 정합성 검토: [`_openProjectWithTierRouting`](lib/screens/project_screen.dart:54)

4. **profile_screen.dart**
    - `구독 관리` 메뉴 제거: [`_buildMenuItem(구독 관리)`](lib/screens/profile_screen.dart:596)
    - 구독 배지 표시 제거: [`_buildProfileCard`에서 `tierLabel`](lib/screens/profile_screen.dart:540)
    - 구독/해지 관련 삭제 메시지 문구 정리: [`_confirmDeleteAccount`](lib/screens/profile_screen.dart:454), [`_showAccountDeletionBlockedDialog`](lib/screens/profile_screen.dart:506)
       - 프로필 통계 카드를 `PROJECT`/`CLOUD` 제외 형태로 변경
       - [`_buildStatsCard`](lib/screens/profile_screen.dart:713), [`_buildStatItem(clipCount, 'CLIP')`](lib/screens/profile_screen.dart:724)
    - 추가 점검: `PROJECT`/`CLOUD` 카드 제외 후 통계 카드 레이아웃(그리드/간격/정렬) 재확정

5. **video_edit_screen.dart**
    - 편집 접근 시 Paywall 호출 루트 제거/비활성 검토: [`_runAccessGateThenInit`](lib/screens/video_edit_screen.dart:355)

6. **login_screen.dart + auth_service.dart**
   - Kakao/Naver 로그인 연동 범위 결정 및 플래그/문구 정리:
     - 버튼 라벨/상태를 `Coming Soon` 상태에서 단계별 연동 상태로 전환 여부 결정
     - `_handleKakaoSignIn`/`_handleNaverSignIn` 플레이스홀더 제거 후 실 연동 또는 화면 비노출 처리
     - 관련 라우트/콜백 일관성 점검: [`_handleKakaoSignIn`](lib/screens/login_screen.dart:228), [`_handleNaverSignIn`](lib/screens/login_screen.dart:236)
     - 연동 API/파라미터 정합성: [`signInWithKakao`](lib/services/auth_service.dart:188), [`signInWithNaver`](lib/services/auth_service.dart:203)
     - 필요한 패키지/설정 정리 항목 등록: [`dependencies`](pubspec.yaml:30), [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml:1), [`Info.plist`](ios/Runner/Info.plist:1)

7. **profile_screen.dart**
   - 로그아웃 안내문구에서 Cloud 관련 안내 라인 제거 또는 지연 노출 처리:
     - 로그아웃 확인 다이얼로그 본문에서 Cloud 안내 제거: [`_confirmSignOut`](lib/screens/profile_screen.dart:336)
     - 관련 다이얼로그 문구 정합성 검증: [`Text('* Cloud에 업로드 되지 않은 로컬 파일은 유지됩니다.')`](lib/screens/profile_screen.dart:348)

### 4-2. 비기능/운영
- 과금 로직 관련 데이터(`UserStatusManager`, `AuthService`, `IAPService`)는 삭제하지 않고, **데이터/백엔드 동기화는 유지**하는 것을 기본안으로 유지(실제 결제 미노출만 보장)
- 제거된 화면은 추후 `v1.1`에서 단계적으로 폐기 또는 복구할 수 있도록 문서로 관리

## 5) QA 항목(릴리즈 전 체크)
- **화면 진입 금지 검증**: Library/Project/Profile/편집에서 `PaywallScreen` 직접 접근 불가
- **표시 제거 검증**: UI에 `Icons.star` 결제 트리거, `구독 관리`, `Standard/Premium`, `구독/해지` 문구가 보이지 않음
- **탭 노출 검증**: 하단 네비게이션에서 `Project` 탭이 더 이상 노출되지 않음
- **기능 연속성 검증**: 촬영→라이브러리→프로젝트→프로필 기본 경로가 Free 정책 하에서 정상 동작
- **프로필 통계 카드 검증**: `PROJECT`/`CLOUD` 카드가 표시되지 않음
- **로그아웃 메시지 검증**: 로그아웃 다이얼로그에서 Cloud 안내 문구가 표시되지 않음
- **소셜 로그인 검증**: Kakao/Naver 로그인 버튼/액션이 연동 정책과 일치하며, `Coming Soon` 임시 메시지가 노출되지 않음
- **회귀 점검**: 기존 병합/내보내기 플로우(`main.dart`의 `_handleMerge`, `_handleEditRequest`)가 강제 토스트/실패 흐름을 포함해 안정 동작

## 6) 차후 과금 재개 대비
- `PaywallScreen`, `SubscriptionManagementScreen`, IAP 초기화(`_warmUpStartupServices`, `IAPService`)는 **코드상 보존**하여 v1.1 이상에서 빠르게 재활성화 가능
- `v1.0`에서 제거된 라우팅/버튼/문구는 `Git diff` 기준으로 재도입 포인트를 `plans` 문서에 기록

## 7) 단계 산출물
- 이번 단계 산출물: `plans/ver1_free_initial_launch_plan_v1.md` (본 문서) 확정
- 구현 산출물: 사용자 승인 후 개발 티켓 분해(`UI 숨김`, `문구 정리`, `회귀 테스트`)로만 진행

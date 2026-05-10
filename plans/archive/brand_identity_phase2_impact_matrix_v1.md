# 브랜드명 개편 Phase 2 연동 영향 매트릭스 v1

작성일: 2026-03-30  
범위: `three_sec_vlog` 브랜드명 개편의 Phase 2(기술 식별자 영향 분석)

---

## 0) 기준 식별자/연동 현황 (As-Is)

- Android `applicationId` / namespace: `com.dk.three_sec`
  - 근거: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/google-services.json`
- iOS `PRODUCT_BUNDLE_IDENTIFIER`: `com.dk.three_sec`
  - 근거: `ios/Runner.xcodeproj/project.pbxproj`
- Firebase 프로젝트 기본값: `fir-3s-8edb9`
  - 근거: `.firebaserc`
- Social exchange 함수 서비스 계정: `fir-3s-8edb9@appspot.gserviceaccount.com`
  - 근거: `functions/index.js`
- 결제 상품 ID: `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual`
  - 근거: `lib/services/iap_service.dart`
- OAuth 교환 엔드포인트: `SOCIAL_AUTH_EXCHANGE_URL` (런타임 `--dart-define`)
  - 근거: `lib/services/auth_service.dart`

---

## 1) 영향 매트릭스

| 영역 | 현재 연동 키/값 (As-Is) | 식별자 유지 시 영향 | 식별자 변경 시 영향 | 리스크 등급 | 통제/검증 포인트 |
|---|---|---|---|---|---|
| Android 앱 식별자 | `applicationId = com.dk.three_sec` | 영향 없음 | Play에서 신규 앱 취급 가능성, 기존 설치/업데이트 체인 단절 가능 | 높음 | Play Console 앱 매핑 사전 검증, 내부트랙 별도 리허설 |
| iOS 앱 식별자 | `PRODUCT_BUNDLE_IDENTIFIER = com.dk.three_sec` | 영향 없음 | App Store Connect 신규 앱/신규 번들 취급 가능성, 기존 배포 라인 분기 | 높음 | 번들 ID 변경 전/후 SKU, 앱 레코드, 권한 재연결 검증 |
| Firebase 앱 등록 | Android 패키지/ iOS 번들 기반 등록 | 영향 낮음 | 새 식별자에 대해 Firebase Android/iOS app 추가 등록 필요, 키 파일/구성 재배포 필요 | 높음 | Firebase Console app 추가 후 Auth/Firestore/Storage/FCM E2E |
| Firebase Auth | `FirebaseAuth.instance` + custom token | 영향 없음 | bundle/package mismatch 시 토큰 교환 후 로그인 실패 가능 | 높음 | 소셜 교환 → custom token → Firebase signIn E2E 테스트 |
| Firestore/Storage | UID 기반 경로 접근 | 영향 거의 없음 | 앱 식별자 변경 자체는 데이터 모델 영향 적으나 신규 앱 설정 누락 시 권한/연결 실패 | 중간 | 동일 UID로 조회/업로드/동기화 회귀 테스트 |
| FCM | `firebase_messaging` 권한/토픽 | 영향 없음 | 신규 app instance 토큰 재발급, 구독 토픽 재동기화 필요 | 중간 | 알림 권한 획득/토픽 구독/수신 통합 테스트 |
| OAuth (Kakao/Naver) | 네이티브 SDK + `/social/exchange` | 영향 중간(현재도 네이티브 설정 점검 필요) | 패키지명/번들ID/스킴 재등록 누락 시 로그인 즉시 실패 | 높음 | 공급자 콘솔 redirect/scheme, Android Manifest, iOS Info.plist 정합성 검증 |
| Google/Apple 로그인 | Firebase/Auth provider 기반 | 영향 낮음 | iOS 번들ID/Android package 변경 시 콘솔 재설정 필요 가능 | 중간~높음 | 공급자 콘솔의 앱 식별자/sha/capability 재검증 |
| 결제 (Play Billing/IAP) | 상품 ID `3s_*` | 영향 없음 | 상품 ID 변경 시 기존 구독 승계 리스크 매우 큼 | 매우 높음 | 상품 ID 유지 원칙, 서버/클라 매핑 테이블 고정 |
| 딥링크/앱링크 | 앱 고유 스킴/앱링크 선언 미정리 상태 | 영향 낮음 | 식별자 변경 시 연동 도메인/스킴/assetlinks 재검증 필요 | 중간 | Android intent-filter, iOS URL Scheme/Associated Domains 명시 검증 |
| Functions / Backend | `social/exchange` + custom token | 영향 낮음 | Firebase 프로젝트 분리 시 함수 배포 프로젝트/서비스 계정 변경 필요 | 높음 | 스테이징/프로덕션 project alias 분리 및 smoke test |
| 로컬 저장 키 | `3s_*` 키 사용 (`SharedPreferences`) | 영향 없음 | 브랜드명 변경과 무관, 마이그레이션 불필요 | 낮음 | 키 유지, 사용자 세션/구독 데이터 연속성 확인 |

---

## 2) 항목별 상세 체크리스트

### 2-1. Android

- 확인 파일
  - `android/app/build.gradle.kts`
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/google-services.json`
- 체크
  - `applicationId`/`namespace`/Manifest `package` 일치 여부
  - Firebase `google-services.json`의 `package_name` 일치 여부
  - OAuth/딥링크 intent-filter 존재 및 스킴 정합성

### 2-2. iOS

- 확인 파일
  - `ios/Runner.xcodeproj/project.pbxproj`
  - `ios/Runner/Info.plist`
- 체크
  - `PRODUCT_BUNDLE_IDENTIFIER`(Runner/RunnerTests) 식별
  - `CFBundleURLTypes`, `LSApplicationQueriesSchemes` 등 OAuth 관련 설정 존재 여부
  - Apple 로그인 Capability/Team 설정 영향

### 2-3. Firebase/Functions

- 확인 파일
  - `.firebaserc`
  - `functions/index.js`
- 체크
  - 기본 프로젝트 alias와 함수 서비스 계정 정합성
  - 식별자 변경 시 Firebase 앱(안드/ios) 추가 등록 및 배포 타겟 분리 필요성

### 2-4. 결제

- 확인 파일
  - `lib/services/iap_service.dart`
  - `lib/managers/user_status_manager.dart`
  - `lib/services/auth_service.dart`
- 체크
  - `3s_*` 상품 ID 유지 원칙
  - 구독 상태 동기화 필드(`productId`, `subscriptionTier`)의 연속성

---

## 3) Phase 2 결론(매트릭스 기반)

1. 브랜드명 개편 릴리즈에서는 `applicationId`/`PRODUCT_BUNDLE_IDENTIFIER`를 **유지**하는 것이 타당.
2. 결제 상품 ID `3s_*`는 **유지**가 필수.
3. 식별자 변경이 필요할 경우, 브랜드 개편과 분리된 별도 트랙에서
   - Firebase 앱 재등록,
   - OAuth 콘솔 값 재등록,
   - 결제/로그인/푸시/딥링크 E2E,
   - 롤백 시나리오
   를 사전 확보한 뒤 실행해야 함.


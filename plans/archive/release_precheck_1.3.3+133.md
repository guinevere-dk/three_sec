# release_precheck_1.3.3+133

## 1) 점검 개요
- 버전 타깃: `1.3.3+133`
- 점검 기준: 코드/설정 기준 정적 검토 + 프로젝트 내 산출물 근거
- 대상 플랫폼 가정: **Android 출시 기준**(iOS는 출시 범위에서 제외, iOS/푸시 항목은 출시 후 개선 항목으로 이관)
- 최종 판정(임시): **Android Go (출시 대상)**

## 2) 핵심 Go/No-Go 판단

### No-Go 해소 여부 (P0 4개)
| 항목 | 상태 | 근거 |
|---|---|---|
| 1) 버전/빌드 값 소스 정합성(P0) | **완료** | 선언 버전 `1.3.3+133`: [`pubspec.yaml`](../pubspec.yaml:19), Android 빌드가 Flutter 버전값 참조: [`android/app/build.gradle.kts`](../android/app/build.gradle.kts:51), [`android/app/build.gradle.kts`](../android/app/build.gradle.kts:52) |
| 2) 클라우드 업로드 큐 영속 복구 로직(P0) | **완료** | 저장 큐 복구 엔트리/재시작 구현: [`restoreUploadQueueFromStore()`](../lib/services/cloud_service.dart:107), 재처리 시작: [`lib/services/cloud_service.dart`](../lib/services/cloud_service.dart:207), [`lib/services/cloud_service.dart`](../lib/services/cloud_service.dart:208) |
| 3) 앱 시작/복귀 시 큐 복구 트리거(P0) | **완료** | 라이프사이클 복귀 시 호출: [`lib/main.dart`](../lib/main.dart:401), [`lib/main.dart`](../lib/main.dart:402), 초기 데이터 로드 시 호출: [`lib/main.dart`](../lib/main.dart:1188), 로그인 복귀 시 호출: [`lib/services/auth_service.dart`](../lib/services/auth_service.dart:1257) |
| 4) IAP 서버 영수증 검증 경로(P0) | **완료** | 서버 검증 함수 구현/호출: [`_verifyPurchase()`](../lib/services/iap_service.dart:453), 서버 검증 호출: [`lib/services/iap_service.dart`](../lib/services/iap_service.dart:514), 복원 재검증 경로: [`lib/services/iap_service.dart`](../lib/services/iap_service.dart:1389) |

- 판정: **Android 출시 차단 No-Go 항목(P0) 4/4 해소**


### 보류 항목 (출시 후 개선, Android 출시 판정 대상 아님)
1. **iOS Firebase 초기화/푸시 구성 누락 가능성 (P0, iOS 전용)**
    - 앱 시작 시 [`Firebase.initializeApp()`](../lib/main.dart:203) 호출, iOS 서비스 파일은 저장소 기준 누락 의심
    - 근거: [`ios/Runner`](../ios/Runner), [`lib/main.dart`](../lib/main.dart:203)

2. **푸시 토큰 갱신 처리 부재 (P1~P0 경고, 푸시 개선 항목)**
    - 토큰 권한/토픽 동기화는 있으나 토큰 갱신 이벤트 처리 미확인
    - 근거: [`lib/main.dart`](../lib/main.dart:418), [`lib/services/notification_settings_service.dart`](../lib/services/notification_settings_service.dart:154)

## 3) 기능별 위험 정리(요약)

### 촬영/편집/클립 추출
- **카메라 권한 런타임 UX 미흡(P1)**: **부분 완화** — 권한 분기/안내 존재하나 UX 일관성 추가 점검 필요, 근거: [`lib/screens/capture_screen.dart`](../lib/screens/capture_screen.dart:365)
- **클립 추출 dispose 경쟁(P1~P2)**: **보류** — dispose/경합 리스크 확인, 근거: [`lib/screens/clip_extractor_screen.dart`](../lib/screens/clip_extractor_screen.dart:106)
- **클립 추출 결과 검증 취약(P1)**: **확인필요** — 실패 조건 실측 근거 미흡, 근거: [`lib/screens/clip_extractor_screen.dart`](../lib/screens/clip_extractor_screen.dart:489)

### 클라우드 동기화
- **재개/복구 실패(P0)**: **해결** — 큐 복구 및 재시작 경로 구현, 근거: [`restoreUploadQueueFromStore()`](../lib/services/cloud_service.dart:107), [`lib/main.dart`](../lib/main.dart:402), [`lib/main.dart`](../lib/main.dart:1188)
- **즉시 업로드 내구성(P1)**: **부분 완화** — 즉시 업로드 경로 존재, 장애 내구성 실주행 증적은 추가 필요, 근거: [`lib/services/cloud_service.dart`](../lib/services/cloud_service.dart:358), [`lib/screens/library_screen.dart`](../lib/screens/library_screen.dart:873)
- **중복 업로드 가능성(P1)**: **완화** — dedupe 키 기반 중복 방지 존재, 근거: [`lib/services/cloud_service.dart`](../lib/services/cloud_service.dart:157), [`lib/services/cloud_service.dart`](../lib/services/cloud_service.dart:163)

### IAP
- **서버 영수증 검증 미구현(P0)**: **해결** — 서버 검증 경로 구현, 근거: [`_verifyPurchase()`](../lib/services/iap_service.dart:453), [`lib/services/iap_service.dart`](../lib/services/iap_service.dart:514)
- **구독 복원 버튼 미연결(P1)**: **완화** — 복원 호출 경로 존재, UX 정합성은 추가 점검 권장, 근거: [`lib/screens/paywall_screen.dart`](../lib/screens/paywall_screen.dart:157), [`restorePurchases()`](../lib/services/iap_service.dart:1332)
- **기본 결제 실패 처리 존재(P2)**: **해결** — 실패/예외 분기 처리 존재, 근거: [`lib/services/iap_service.dart`](../lib/services/iap_service.dart:430), [`lib/services/iap_service.dart`](../lib/services/iap_service.dart:611)

### 로그인
- **로그인 후 동기화 실패 시 구독 강등 위험(P1)**: **부분 완화** — 재시도/보존 분기 존재, 실패 케이스 실주행 점검 필요, 근거: [`lib/services/auth_service.dart`](../lib/services/auth_service.dart:1268), [`lib/services/auth_service.dart`](../lib/services/auth_service.dart:1276)
- **세션/탈퇴 가드 분기 존재(P2)**: **해결** — 가드 분기 유지 확인, 근거: [`lib/services/auth_service.dart`](../lib/services/auth_service.dart:1987), [`lib/services/auth_service.dart`](../lib/services/auth_service.dart:2021)

### 알림
- **알림 탭 후 라우팅 단순 처리(P1)**: **부분 완화** — payload 기반 탭 라우팅 로직 존재, 근거: [`lib/services/notification_settings_service.dart`](../lib/services/notification_settings_service.dart:215), [`lib/main.dart`](../lib/main.dart:459)
- **토큰 갱신 부재(P1)**: **보류(출시 후)** — `onTokenRefresh` 처리 미확인, 근거: [`lib/main.dart`](../lib/main.dart:446), [`lib/services/notification_settings_service.dart`](../lib/services/notification_settings_service.dart:163)

## 4) 배포 체크리스트(범주별)

### 보안
| 항목 | 근거 | 상태 | 우선순위 |
|---|---|---|---|
| Firestore 규칙 uid 일치 | [`firebase/firestore.rules`](../firebase/firestore.rules:17) | 완료 | 중 |
| Storage 규칙 uid + 타입/크기 제약 | [`firebase/storage.rules`](../firebase/storage.rules:20), [`firebase/storage.rules`](../firebase/storage.rules:65) | 완료 | 중 |
| Android 릴리스 shrink/minify | [`android/app/build.gradle.kts`](../android/app/build.gradle.kts:66) | 완료 | 하 |
| 사용자 문서 스키마/개인정보 경계 검증 강화 | 규칙 내 필드 검증 제한 | 보완 필요 | 중 |

### 개인정보
| 항목 | 근거 | 상태 | 우선순위 |
|---|---|---|---|
| iOS 카메라/마이크/앨범 고지문 존재 | [`ios/Runner/Info.plist`](../ios/Runner/Info.plist:48), [`ios/Runner/Info.plist`](../ios/Runner/Info.plist:55) | 출시 제외(출시 후 개선) | 중 |
| Android 권한 선언 정합 | [`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml:6), [`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml:13) | 완료 | 중 |
| 저장소/스토어 정책 문구 최신화 | 저장소/스토어 제출 메타 직접 증거 없음 | 확인 필요 | 상 |

### 정책 준수
| 항목 | 근거 | 상태 | 우선순위 |
|---|---|---|---|
| 버전 정합 | No-Go #1 | 미충족(차단) | 상 |
| Firebase iOS 구성 정합 | 보류 항목 #1(출시 제외) | 확인 필요(출시 후 개선) | 상 |
| IAP 결제 검증 | No-Go #3 | 미충족(차단) | 상 |
| 알림 권한/푸시 동작 정합 | 보류 항목 #2(출시 후 개선) | 보완 필요(출시 후 개선) | 상 |

### 안정성
| 항목 | 근거 | 상태 | 우선순위 |
|---|---|---|---|
| 동기화 큐 저장/로드 | [`lib/services/sync_queue_store.dart`](../lib/services/sync_queue_store.dart:71) | 부분 완료 | 중 |
| 앱 재개 시 큐 재시작 | No-Go #3 | 미충족(차단) | 상 |
| 동영상 처리 실패 재시도/로깅 | [`lib/services/cloud_service.dart`](../lib/services/cloud_service.dart:635), [`lib/managers/video_manager.dart`](../lib/managers/video_manager.dart:2233) | 완료 | 중 |
| iOS 실제 기기 E2E(로그인/클라우드/푸시) | 실행 증거 없음(출시 제외) | 출시 제외(출시 후 개선) | 상 |

### 성능
| 항목 | 근거 | 상태 | 우선순위 |
|---|---|---|---|
| 릴리스 최적화 설정 | [`android/app/build.gradle.kts`](../android/app/build.gradle.kts:64) | 완료 | 하 |
| 미디어 파이프라인 안정성/오류 로그 | [`lib/managers/video_manager.dart`](../lib/managers/video_manager.dart:2003), [`lib/managers/video_manager.dart`](../lib/managers/video_manager.dart:2233) | 완료 | 중 |
| 저사양/저전력/저대역 성능 회귀 검증 | 실기기 보고서 직접 증거 없음 | 확인 필요 | 중 |

### QA
| 항목 | 근거 | 상태 | 우선순위 |
|---|---|---|---|
| 출시 빌드에서 버전값 검증 | No-Go #1 | 미충족(차단) | 상 |
| IAP 구매/복원 + 서버검증 포함 시나리오 | No-Go #3 | 미충족(차단) | 상 |
| 푸시 토큰 갱신 검증(onTokenRefresh) | 보류 항목 #2 | 보완 필요(출시 후 개선) | 상 |
| iOS 푸시/로그인/동기화 통합 QA | 실행 증거 없음(출시 제외) | 출시 제외(출시 후 개선) | 상 |

## 5) 우선 조치(출시 전/출시 후 구분)
### 5-1) 완료
1. **버전/빌드 정합 경로 통일(P0)**: Flutter 버전값 참조 구조 확인, 근거: [`pubspec.yaml`](../pubspec.yaml:19), [`android/app/build.gradle.kts`](../android/app/build.gradle.kts:51)
2. **클라우드 큐 영속복구 + 재시작(P0)**: 구현 및 라이프사이클 연결 확인, 근거: [`restoreUploadQueueFromStore()`](../lib/services/cloud_service.dart:107), [`lib/main.dart`](../lib/main.dart:402), [`lib/main.dart`](../lib/main.dart:1188)
3. **IAP 서버 검증 경로(P0)**: 서버 검증/복원 검증 연결 확인, 근거: [`_verifyPurchase()`](../lib/services/iap_service.dart:453), [`lib/services/iap_service.dart`](../lib/services/iap_service.dart:1332), [`lib/services/iap_service.dart`](../lib/services/iap_service.dart:1389)

### 5-2) 부분 완료
1. **고위험 예외 UX 보강(P1)**: 핵심 분기 구현은 반영됐으나 카메라 권한 UX/클립 dispose/즉시 업로드 내구성 실측 증빙은 추가 필요, 근거: [`lib/screens/capture_screen.dart`](../lib/screens/capture_screen.dart:365), [`lib/screens/clip_extractor_screen.dart`](../lib/screens/clip_extractor_screen.dart:106), [`lib/services/cloud_service.dart`](../lib/services/cloud_service.dart:358)
2. **알림 라우팅 고도화(P1)**: 기본 라우팅 해석 존재, 세부 시나리오 QA 추가 필요, 근거: [`lib/services/notification_settings_service.dart`](../lib/services/notification_settings_service.dart:215), [`lib/main.dart`](../lib/main.dart:459)

### 5-3) 출시 후(보류)
1. **iOS Firebase/iOS 푸시 구성 확인(P0, iOS 전용)**: Android 출시 판정 대상 제외, 근거: [`lib/main.dart`](../lib/main.dart:203), [`ios/Runner`](../ios/Runner)
2. **푸시 토큰 갱신 이벤트 처리(P1)**: `onTokenRefresh` 연결 확인 필요, 근거: [`lib/main.dart`](../lib/main.dart:446), [`lib/services/notification_settings_service.dart`](../lib/services/notification_settings_service.dart:163)

## 6) 출시 제외 항목 정리
- iOS Firebase 구성/푸시 초기화 검증은 **iOS 트랙 전용 작업**으로 분리하여 `출시 후(보류)`에 유지.
- 푸시 토큰 갱신(`onTokenRefresh`)은 **Android 필수 차단 항목에서 제외**하고 운영 안정화 과제로 관리.

## 7) 결론
Android 기준 `1.3.3+133`는 P0 No-Go 4건이 해소되어 **출시 가능(Go)** 판단입니다.

**최종 판정 라인: Android 출시 대상 (Go)**


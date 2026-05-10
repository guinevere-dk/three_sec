# Android 15 권장 조치 2건 대응 분석/계획서 (v1)

## 1) 배경
- Play Console 권장 조치 2건
  1. Android 15에서 더 넓은 화면(Edge-to-edge) 기본 적용에 따른 인셋 처리 필요
  2. Android 15에서 지원 중단된 시스템 바 색상 API 사용 경고

본 문서는 현재 코드베이스를 기준으로 영향도를 분석하고, 실제 배포 가능한 대응 순서를 정의한다.

---

## 2) 현재 코드베이스 분석

### 2-1. 타겟 SDK/런타임 전제
- 앱 모듈의 타겟 SDK는 [`android/app/build.gradle.kts`](android/app/build.gradle.kts)에서 `flutter.targetSdkVersion`을 사용한다.
- 빌드 산출 로그 기준 디버그 병합 매니페스트에는 `targetSdkVersion=36`이 반영되어 Android 15+ 구간 영향권에 이미 진입한 상태다.

### 2-2. Android 진입점/임베딩
- 메인 액티비티는 [`MainActivity`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:54)에서 `FlutterFragmentActivity`를 사용한다.
- 프로젝트 내 네이티브 코드에서 `setStatusBarColor`/`setNavigationBarColor` 직접 호출은 검색되지 않았다.
- Play Console이 제시한 시작 위치(`FlutterFragmentActivity.configureStatusBarForFullscreenFlutterExperience`, `PlatformPlugin.setSystemChromeSystemUIOverlayStyle`)는 앱 코드가 아니라 Flutter 엔진/임베딩 경로에서 기인할 가능성이 높다.

### 2-3. Flutter UI 인셋 처리 현황
- 루트/주요 화면에서 `SafeArea` 사용이 다수 확인된다 (예: [`SafeArea`](lib/main.dart:986), [`SafeArea`](lib/screens/capture_screen.dart:710), [`SafeArea`](lib/screens/video_edit_screen.dart:2078)).
- 다만 전 화면/오버레이/커스텀 바텀 컨트롤 등은 실제 기기에서 잘림/겹침 회귀가 발생할 수 있어 Android 15 실기기 기준 추가 점검이 필요하다.

---

## 3) 권장 조치 #1 대응 계획: 더 넓은 화면(Edge-to-edge) + 인셋 처리

## 목표
- Android 15 이상에서 상태바/내비게이션 바 영역과 콘텐츠가 겹치지 않도록 안전한 인셋 정책 확정.
- 단기 호환성(빠른 리스크 완화) + 중기 구조 개선(화면별 인셋 표준화) 병행.

## 실행 계획
1. **인벤토리/위험 분류 (0.5일)**
   - 전체 화면을 `A군(이미 SafeArea 안정)`, `B군(오버레이/커스텀 하단바)`, `C군(전체화면 편집/미디어)`로 분류.
   - 우선순위: 캡처/편집/내보내기/페이월.

2. **단기 호환성 가드 적용 (0.5일)**
   - Android 진입점에서 edge-to-edge 호환 가드를 적용하는 방안을 검토/적용.
   - 목적: Android 15 이상에서 시스템 바 처리 정책 변화에 대한 즉시 완충.

3. **화면별 인셋 표준화 (1~2일)**
   - 상단/하단 고정 UI(헤더, 하단 CTA, 타임라인 컨트롤)에 `viewPadding`/`SafeArea` 기준을 통일.
   - 키보드 노출/가로세로/제스처 내비게이션에서 하단 잘림 여부 검증.

4. **회귀 테스트/릴리즈 게이트 편입 (1일)**
   - 기존 QA 문서에 Android 15 전용 인셋 체크 항목 추가.
   - 스크린샷/영상 증적을 릴리즈 체크리스트에 첨부.

## 완료 기준 (DoD)
- Android 15 실기기에서 상/하단 UI 잘림, 탭 불가 영역, 제스처 충돌 0건.
- 핵심 여정(촬영→편집→내보내기→프로필/결제)에서 레이아웃 회귀 0건.

---

## 4) 권장 조치 #2 대응 계획: 지원 중단 API 이전

## 목표
- Android 15에서 경고되는 시스템 바 색상 관련 API 경로를 앱 릴리즈 체인에서 제거/완화.
- 앱 직접 호출 + Flutter 엔진 경로를 분리 대응.

## 실행 계획
1. **직접 호출 제거 확인 (완료 상태, 재검증 0.5일)**
   - 앱 네이티브 코드에 `setStatusBarColor`/`setNavigationBarColor`/`setNavigationBarDividerColor` 직접 호출 없음 확인.
   - CI 검색 규칙으로 고정(재유입 방지).

2. **Flutter SDK/엔진 경로 업데이트 (0.5~1일)**
   - Flutter stable 최신으로 업그레이드 후 동일 경고 재측정.
   - 임베딩/플러그인 버전 동기화 후 Play Console 경고 감소 여부 확인.

3. **시스템 UI 스타일 정책 재정의 (0.5일)**
   - 상태바/내비게이션 바를 투명 기반 정책으로 통일하고, 아이콘 밝기만 화면 테마로 제어.
   - 화면별 임의 색상 지정 패턴 금지.

4. **증적 수집 및 콘솔 확인 (0.5일)**
   - Internal 테스트 트랙 업로드 → Android vitals/Play Console 경고 변동 확인.
   - 경고 잔존 시 엔진/플러그인 기여 경로를 이슈로 분리 등록.

## 완료 기준 (DoD)
- 앱 코드 기준 deprecated API 직접 사용 0건(검색 + CI 규칙).
- 내부 트랙 기준 Android 15 경고가 해소되거나, 엔진 경로 잔여 이슈가 명확히 분리되어 릴리즈 리스크가 통제됨.

---

## 5) 테스트 매트릭스 (Android 15 대응 최소 세트)

### 디바이스/환경
- Pixel 계열 Android 15 (제스처 내비)
- Samsung One UI Android 15 (3버튼/제스처 각각)
- 1개 저해상도/작은 화면 + 1개 대화면 기기

### 핵심 시나리오
- 상단 앱바/하단 CTA/하단 탭 영역 터치 가능성
- 키보드 오픈 시 입력창/버튼 가림 여부
- 전체화면 편집/미디어 프리뷰에서 제스처 영역 충돌
- 다크/라이트 테마 전환 시 시스템 바 아이콘 가독성

---

## 6) 일정(제안)
- D0: 인벤토리 + 단기 가드 적용
- D1~D2: 화면별 인셋 표준화 + SDK/엔진 업그레이드
- D3: 실기기 회귀 + 내부 트랙 배포
- D4: Play Console 결과 확인 후 릴리즈 게이트 반영

---

## 7) 산출물
- 본 계획서: [`plans/android15_edge_to_edge_deprecated_api_action_plan_v1.md`](plans/android15_edge_to_edge_deprecated_api_action_plan_v1.md)
- QA 반영 대상 문서: [`plans/android_qa_journey_release_gate_v1.md`](plans/android_qa_journey_release_gate_v1.md)


# 3S 화질 정책 전환 실행 계획 v1

## 1) 목적

`plans/pixel_plan.md`의 결론(기본 촬영 1080p, 내보내기 구독 등급 제한, 4K는 지원 기기+프리미엄 중심)을 현재 앱 구조에 맞게 반영하기 위한 **변경 범위 분석 + 실행 계획** 문서다.

핵심 목표는 다음 3가지다.

1. 기본 촬영 경험을 단순화(기본 1080p)하면서
2. 성능/발열/저장공간 리스크를 Auto 폴백으로 제어하고
3. 구독 가치(특히 Premium 4K Export)를 UI/정책/엔진 파라미터에서 일관되게 만든다.

---

## 2) 정책 결정안 (v1 확정안)

### 촬영(Capture)
- 기본값: **1080p**
- 설정 노출: **Auto / 1080p / 4K**
- 4K는 **지원 기기에서만 활성화**
- 저사양/저장공간 부족/발열 조건에서는 Auto가 **1080p 또는 720p로 폴백**

### 내보내기(Export)
- Free: **720p**
- Standard: **1080p**
- Premium: **4K**

### UX 원칙
- 720p 촬영은 메인 노출 금지(필요 시 고급/자동 폴백 내부 옵션으로만 사용)
- 사용자에게는 “촬영 품질 옵션 과다”보다 “최종 결과 품질 가치”를 강조

---

## 3) 현재 코드 기준 상태 요약

### A. 촬영 화면
- 현재 촬영 설정은 `ResolutionPreset.ultraHigh/veryHigh/high`를 그대로 노출(4K/1080/720)
- 기본 프리셋은 플랫폼 분기(Android: high=720, iOS: veryHigh=1080)
- 관련 위치: `lib/screens/capture_screen.dart`

### B. 내보내기 품질 선택
- 편집 화면에서 720p/1080p/4K 선택 UI가 이미 존재
- Free는 1080p 선택 제한, Premium만 4K 가능 형태는 반영되어 있음
- 다만 값 표기(`4K` vs 내부 값 `4k`) 일관성 관리 필요
- 관련 위치: `lib/screens/video_edit_screen.dart`

### C. 비편집 경로(Free 빠른 Export)
- Free 유저는 여러 화면에서 720p 빠른 내보내기 강제 로직 존재
- 관련 위치: `lib/main.dart`, `lib/screens/project_screen.dart`, `lib/screens/vlog_screen.dart`

### D. 모델/엔진 파라미터
- 프로젝트 모델 품질 기본값은 1080p
- 네이티브 병합 호출에 `quality`, `userTier` 전달 구조 존재
- 관련 위치: `lib/models/vlog_project.dart`, `lib/managers/video_manager.dart`

### E. 구독/카피
- Paywall/구독 관리 화면에 720p/1080p/4K 혜택 카피 일부 반영
- 관련 위치: `lib/screens/paywall_screen.dart`, `lib/screens/subscription_management_screen.dart`

---

## 4) 변경 필요 항목 (Gap Analysis)

## 4-1. 촬영 품질 정책 계층 분리 (필수)

현재는 Camera 플러그인의 `ResolutionPreset`을 사용자에게 직접 노출한다.
정책 요구사항(Auto/1080p/4K)과 실제 구현 계층을 분리하기 위해 아래 구조가 필요하다.

- 신규 도메인 타입(예: CaptureQualityMode)
  - `auto`, `fhd1080`, `uhd4k`
- 내부 매핑 함수
  - 정책 모드 → 기기 지원 프리셋 시도 순서
  - 예시
    - auto: veryHigh(1080) → high(720) → medium
    - 1080p: veryHigh 우선, 실패 시 high
    - 4K: ultraHigh 우선, 실패 시 veryHigh

효과:
- UI는 정책 언어(Auto/1080p/4K)로 단순화
- 엔진은 기기별 실패 시 안전 폴백 보장

## 4-2. 기본값 통일 (필수)

- 첫 실행/기본 촬영값을 플랫폼 무관 1080p로 통일
- 현재 Android 기본 720p 분기를 제거

## 4-3. 4K 노출 조건 정교화 (필수)

- 4K 버튼을 항상 노출하지 않고, 아래 중 하나를 만족할 때만 활성
  1) 해당 카메라에서 ultraHigh 초기화 성공 이력 있음
  2) 사전 capability probe 성공

- 미지원 시 문구: “이 기기에서는 4K 촬영을 지원하지 않습니다. 1080p로 촬영됩니다.”

## 4-4. Auto 품질 모드 트리거 (권장)

v1에서는 완전한 실시간 발열/저장소 탐지 대신 **보수적 단계 적용** 권장.

- 1단계(v1):
  - 카메라 초기화 실패 시 자동 다운
  - 녹화 시작 실패/반복 실패 시 preset 강등
- 2단계(v1.1+):
  - 저장공간 임계치 기반 강등
  - 장시간 사용 시 thermal signal 연동(플랫폼별 별도)

## 4-5. 내보내기 품질 표준화 (필수)

- 문자열 표준 스펙 고정
  - `720p`, `1080p`, `4k` (내부)
- UI 표기와 내부 값 매핑 정리
  - 표시: `4K`, 내부 전달: `4k`
- export 진입 경로(편집/빠른내보내기) 모두 동일 규칙 강제

## 4-6. 구독/카피 정렬 (필수)

- Paywall, 구독관리, 토스트/잠금문구를 정책과 동일하게 정리
- 핵심 카피 방향
  - Free: 빠른 공유용 720p
  - Standard: 선명한 1080p
  - Premium: 최고 화질 4K

---

## 5) 파일 단위 실행 계획

## Phase 1 — 정책 모델/상수 정리

대상:
- `lib/screens/capture_screen.dart`
- (신규 권장) `lib/models/capture_quality_mode.dart`
- (신규 권장) `lib/utils/quality_policy.dart`

작업:
- Capture 정책 enum/상수 추가
- 기본값 1080p 고정
- Auto/1080p/4K UI 노출 계층 구성
- preset fallback 로직 함수화

완료 기준:
- Android/iOS 모두 첫 진입 시 1080p 기준으로 동작
- 미지원 기기에서도 촬영 진입 실패 없이 자동 폴백

## Phase 2 — Export 규칙 단일화

대상:
- `lib/screens/video_edit_screen.dart`
- `lib/managers/video_manager.dart`
- `lib/models/vlog_project.dart`
- `lib/main.dart`
- `lib/screens/project_screen.dart`
- `lib/screens/vlog_screen.dart`

작업:
- 품질 문자열 표준 검증 유틸 추가(입력값 normalize)
- Free/Standard/Premium 허용 품질 가드 공통화
- 빠른 내보내기와 편집 내보내기 모두 동일 함수 사용

완료 기준:
- 모든 내보내기 경로에서 등급 위반 품질 요청이 불가능
- 로그/디버그 출력에서 품질값 표기가 일관

## Phase 3 — 구독 UX/카피 동기화

대상:
- `lib/screens/paywall_screen.dart`
- `lib/screens/subscription_management_screen.dart`
- 필요 시 에러/토스트 문구 파일

작업:
- 혜택 문구 정책형으로 통일
- 잠금 아이콘/설명 문구 일관화

완료 기준:
- 화면별 문구 충돌 없음
- 사용자 입장에서 “촬영 기본=1080, 결과물 차등=구독” 메시지가 명확

---

## 6) QA 체크리스트 (화질 정책 전환 전용)

1. **기본값 검증**
   - 신규 설치 후 촬영 품질 기본값이 1080p인지

2. **기기 미지원 4K 검증**
   - 4K 선택 시 실패 없이 1080p로 폴백되는지

3. **Free 경로 검증**
   - 편집 진입 제한/빠른 export 720p 동작 일치 여부

4. **Standard 검증**
   - 1080p export 가능, 4K 잠금 확인

5. **Premium 검증**
   - 4K export 가능, 결과 파일 생성/갤러리 저장 확인

6. **문구/카피 검증**
   - Paywall/구독관리/토스트의 해상도 정책 문구 일관성

---

## 7) 리스크 및 대응

- 리스크: 단말별 Camera preset 동작 차이
  - 대응: 초기화 실패 시 단계적 preset 하향 + 사용자 안내

- 리스크: 품질 문자열 불일치(4K/4k 혼재)
  - 대응: 중앙 normalize 함수로 저장/전달 전 강제 정규화

- 리스크: 정책 변경 후 기존 프로젝트 품질 필드 호환
  - 대응: 로드 시 migration normalize (`4K`→`4k`, null→`1080p`)

---

## 8) 최종 권고

v1에서는 “항상 4K 촬영”이 아니라, 아래 순서가 가장 안전하다.

1. 촬영 기본 1080p 고정
2. 4K는 지원 기기 + 설정 진입에서만 노출
3. Export는 구독 등급 정책을 단일 가드로 강제
4. Auto 폴백으로 실패율/발열/저장공간 리스크를 완화

이 구조는 현재 코드 기반에서 가장 작은 변경으로 제품 방향(간편 촬영 + 결과물 품질 차등)을 지키는 실행안이다.

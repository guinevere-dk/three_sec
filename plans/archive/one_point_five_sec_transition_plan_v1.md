# 1초 표현 유지형 1.5초 정체성 전환 통합 계획 v1

작성일: 2026-03-31  
대상: `three_sec_vlog` 앱

---

## 0) 배경 및 적용 범위

현재는 `1`초 기반 정책이 코드/문서에 분산되어 있으며, 외부 다중 가져오기 계획도 `1초` 처리 기준으로 기록되어 있다.

- 길이 정책 변경 자체는 **실제 클립 길이 1.5초**로 진행하고,
- 사용자 노출 문구는 기존 브랜드 노출을 유지해 **`1s` 표기로 고정**한다.

적용 대상 문서:

- [`plans/one_sec_identity_transition_plan_v1.md`](plans/one_sec_identity_transition_plan_v1.md)
- [`plans/external_media_multi_import_plan_v1.md`](plans/external_media_multi_import_plan_v1.md)
- [`plans/external_media_multi_import_phase5_validation_report_v1.md`](plans/external_media_multi_import_phase5_validation_report_v1.md)

---

## 1) 목표

1. 앱 전체에서 **신규 생성되는 비디오/클립 길이를 1.5초로 통일**한다.
2. 기존 UX/브랜딩/표현상은 단위 표시를 기존처럼 `1s`로 유지한다.
3. 변경된 길이 정책이 다중 가져오기 배치 플로우와 회귀 검증 리포트에 일관되게 반영되도록 한다.

---

## 2) 핵심 원칙

- 실제 길이(`duration`)와 노출 라벨(`label`)을 분리한다.
  - 예: 길이 상수(`1500ms`)와 라벨 상수(`1`)를 분리 관리
- 임계값/기본값은 코드 하드코딩을 제거하고 상수에서 관리한다.
- 기존 3초 유산은 앱 정합성에서 제거하되, 브랜드/패키지 식별자는 본계획 범위 밖(별도 일정)으로 둔다.

---

## 3) 적용 아키텍처 (요약)

### A. 길이 정책 계층 분리

- 실제 클립 길이: `1500ms` 기반
- 표시 라벨: `1s` (또는 `kTargetDisplaySec = 1`)

권장 상수 구조(예시):

- `kTargetClipMs = 1500`
- `kTargetClipSecForDisplay = 1`
- `kRecordingUiSafetyBufferMs = 120`(기존 사용)

### B. 전파 대상

- Flutter 공통 상수: `lib/constants/clip_policy.dart`
- 촬영/저장/정규화: `lib/screens/capture_screen.dart`, `lib/managers/video_manager.dart`
- 추출/편집 플로우: `lib/screens/clip_extractor_screen.dart`, `lib/screens/video_edit_screen.dart`
- 네이티브: `android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`, `ios/Runner/AppDelegate.swift`
- 다중 가져오기: `plans/external_media_multi_import_plan_v1.md`, `lib/main.dart`(현재 배치 플로우), `plans/external_media_multi_import_phase5_validation_report_v1.md`

---

## 4) 상세 실행 단계

### Phase 0. 기준 수집 및 위험도 점검

1. 현재 1초 기준 하드코딩 지점을 문서/코드 기준점으로 고정.
2. 플랫폼별 기본값(`MainActivity.kt`, `AppDelegate.swift`)의 폴백 동작 확인.
3. 다중 가져오기 플랜([`plans/external_media_multi_import_plan_v1.md`](plans/external_media_multi_import_plan_v1.md:188))의 **1.5초 반영 상태**와 표기(`1s`) 정책 동시 점검.

산출물:

- 적용 대상 체크리스트
- 리스크 우선순위 2단계 분류(긴급도/영향도)

### Phase 1. 길이 상수/기반 정책 업데이트

1. `lib/constants/clip_policy.dart`에 실제 길이/표시 길이 분리 상수 반영.
2. 기존 코드 참조를 상수 중심으로 변경할 포인트 목록 작성.

요구 출력:

- 상수 정의 변경안 PRD(문서)
- 컴파일 영향 범위 리포트

### Phase 2. Flutter 핵심 파이프라인 전환

1. 촬영 종료/타이머: `lib/screens/capture_screen.dart`에서 타이머 기준을 1.5초 기반으로 맞춤.
2. 영상 정규화 저장: `lib/managers/video_manager.dart`의 녹화 정규화 대상 길이를 1.5초로 정합.
3. 구간 추출: `lib/screens/clip_extractor_screen.dart`의 구간 계산/토스트를 1.5초 처리 정책으로 정렬(표시 카피는 `1s` 유지).
4. 편집 fallback: `lib/screens/video_edit_screen.dart` 내 duration fallback도 1.5초로 변경(또는 정책 상수 참조).

### Phase 3. 네이티브 정합성 (Android + iOS)

1. Android: `android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`
   - `convertImageToVideo` 기본 duration, `normalizeVideoDuration` fallback, `extractClips` 기본 end 계산을 `1500ms`로 정합.
2. iOS: `ios/Runner/AppDelegate.swift`
   - normalize 경로가 Flutter의 `targetDurationMs`를 신뢰하도록 점검하고, 기본 방어값을 1500ms로 통일.

### Phase 4. 문구/UX 정책 적용

1. 사용자 노출 텍스트: 실제 노출은 `1s`를 유지.
2. `plans/one_sec_identity_transition_plan_v1.md`의 카피 변경 항목(3초→1초)는 **표시 규칙(`1s`)과 충돌 없는지** 보정.
3. 다중 가져오기 계획에서 새로 반영된 `1.5초` 처리와 `1s` 노출 분리 설명을 최상단 목표로 재강조.

### Phase 5. 검증 리포트 업데이트

1. [`plans/external_media_multi_import_phase5_validation_report_v1.md`](plans/external_media_multi_import_phase5_validation_report_v1.md) 개정
   - 새 검증 항목: 이미지 변환/영상 추출 결과 길이가 1.5초인지 오차 범위와 함께 체크.
   - 텍스트 노출/요약 토스트는 `1s` 문구 유지 여부를 별도 항목으로 추가.

2. 공통 QA 항목 추가
   - 평균/최소/최대 길이(기기별) 기록
   - 1.5초 목표 대비 편차 임계값 경고 규칙 확정

3. 수동 QA 로그 규칙 갱신
   - 로그 키: `targetDurationMs`, `normalizedDurationMs`에 `1500` 또는 실제 수치 일치 확인

---

## 5) 완료 기준(Definition of Done)

- 신규 생성 클립은 1.5초를 목표로 생성되고, 편차는 운영 규칙 범위 이내.
- 사용자 노출 카피(버튼/토스트/안내 라벨)는 `1s`를 유지.
- 다중 가져오기 파이프라인은 선택/변환/요약이 1.5초 정책 기준으로 동작하며 기존 순서 보존 정책은 유지.
- Android/iOS 모두에서 정규화 및 길이 출력 지표가 일치하고, 크래시/블로킹 이슈 없음.
- 검증 리포트(`plans/external_media_multi_import_phase5_validation_report_v1.md`)에 1.5초 길이 검증 항목이 반영되어 PASS.

---

## 6) 게이트

- Gate A: Flutter 핵심 상수와 호출 경로 반영 완료
- Gate B: 네이티브 정합성 완료(안드로이드/iOS)
- Gate C: 다중 가져오기 문서(`plans/external_media_multi_import_plan_v1.md`)와 실행 리포트(`plans/external_media_multi_import_phase5_validation_report_v1.md`) 동기화 완료
- Gate D: 1.5초 검증 시나리오 모두 PASS
- Gate E: 앱 내 사용자 문구가 `1s` 유지 검수 완료

---

## 7) 후속 액션

1. 본 계획 완료 시 `one_sec_identity_transition_plan_v1.md`의 수치를 1.5초 기준으로 리라이팅.
2. 릴리즈 노트에 "표기: 1s, 실제: 1.5초"를 명시해 QA/마케팅 혼선을 방지.
3. 1차 반영 후 7일 모니터링: 길이 편차 및 실패율 재점검.


# A안(61프레임) 저장 전용 오버타깃 범위 검증/산출물 v1

## 1) 작업 목표 및 결론

- 목표: 저장 파이프라인에만 61프레임(약 2034ms) 오버타깃 정책을 적용하고, UI/일반 정책 2초는 유지하는지 검증
- 결론: 현재 코드 기준으로 분리 정책이 반영되어 있으며, 네이티브 계약도 전달값(`targetDurationMs`) 우선/기본값 폴백 유지로 확인됨
- 제약 준수: 네이티브 로직 변경 없음 (검증/문서화만 수행)

---

## 2) 정책 상수 분리 검증

검증 파일: [`lib/constants/clip_policy.dart`](lib/constants/clip_policy.dart)

- UI/정책값 2초 유지: [`kTargetClipMs`](lib/constants/clip_policy.dart:1) = `2000`
- UI 라벨용 초 단위 유지: [`kTargetClipSecForDisplay`](lib/constants/clip_policy.dart:2) = `2`
- 저장 전용 오버타깃(ms) 유지:
  - [`kTargetClipSaveFrames`](lib/constants/clip_policy.dart:3) = `61`
  - [`kTargetClipSaveFps`](lib/constants/clip_policy.dart:4) = `30`
  - [`kTargetClipSaveMs`](lib/constants/clip_policy.dart:5) = `ceil(61/30*1000)` 계산식

판정: **요구사항 충족**

---

## 3) 저장 파이프라인 분기 검증

검증 파일: [`lib/managers/video_manager.dart`](lib/managers/video_manager.dart)

### 3-1. 저장 경로는 `kTargetClipSaveMs` 사용

- 저장 기준 duration 상수 바인딩: [`_targetRecordingDurationMs`](lib/managers/video_manager.dart:1255) = [`kTargetClipSaveMs`](lib/constants/clip_policy.dart:5)
- 사진→영상 변환 시 저장 duration 적용: [`convertPhotoToVideo()`](lib/managers/video_manager.dart:1753) 내부 [`convertDurationMs`](lib/managers/video_manager.dart:1759)
- 녹화 저장 normalize 기본 타깃: [`saveRecordedVideo()`](lib/managers/video_manager.dart:2948) → [`_normalizeRecordedVideo()`](lib/managers/video_manager.dart:2979)
- normalize 기본값이 저장 타깃으로 고정: [`effectiveTargetDurationMs`](lib/managers/video_manager.dart:3049)

### 3-2. 비저장 경로는 기존 `kTargetClipMs` 유지

- 트리머 고정 윈도우: [`_fixedWindowMs`](lib/widgets/trim_editor_modal.dart:46)
- 클립 추출 구간 계산/세그먼트 길이: [`clip_extractor_screen.dart`](lib/screens/clip_extractor_screen.dart:32), [`startMs` 보정](lib/screens/clip_extractor_screen.dart:221), [`end`](lib/screens/clip_extractor_screen.dart:510)
- 편집 fallback duration: [`video_edit_screen.dart`](lib/screens/video_edit_screen.dart:479)

판정: **요구사항 충족** (저장 경로와 일반 2초 정책 분리 확인)

---

## 4) 캡처 타이머 검증 (오버타깃 타임아웃 + 2초 라벨 유지)

검증 파일: [`lib/screens/capture_screen.dart`](lib/screens/capture_screen.dart)

- 타임아웃 계산 기준: [`_targetRecordingMilliseconds`](lib/screens/capture_screen.dart:71) = [`kTargetClipSaveMs`](lib/constants/clip_policy.dart:5)
- 자동 정지 조건: [`stopTriggerMs`](lib/screens/capture_screen.dart:450) 계산에 오버타깃 + 안전버퍼 사용
- 표시 라벨 기준 유지: 카운트다운 clamp 상한을 [`kTargetClipSecForDisplay`](lib/screens/capture_screen.dart:471)로 유지

판정: **요구사항 충족**

---

## 5) 네이티브 계약 검증 (변경 없음)

검증 파일: [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt)

- `normalizeVideoDuration` 인자 파싱:
  - [`rawTargetDuration`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:570)
  - [`targetDurationMs`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:572)
  - 타입별 파싱 실패 시 [`DEFAULT_TARGET_DURATION_MS`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:361) 폴백 유지
- normalize 처리 시 전달값 반영:
  - 채널 핸들러에서 [`normalizeVideoDuration(...)`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:589) 호출 시 `targetDurationMs` 전달
  - 내부 처리에서 [`clipMs = min(sourceDurationMs, targetDurationMs)`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:720)

판정: **요구사항 충족** (`targetDurationMs` 전달값 반영 + 기본값 폴백 유지)

---

## 6) 사용처 영향도 분류

### High (정책 핵심)
- [`lib/constants/clip_policy.dart`](lib/constants/clip_policy.dart): 정책 상수 정의 원천
- [`lib/managers/video_manager.dart`](lib/managers/video_manager.dart): 저장/normalize 경로의 실질 duration 결정
- [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt): 네이티브 normalize 계약/폴백

### Medium (사용자 체감)
- [`lib/screens/capture_screen.dart`](lib/screens/capture_screen.dart): 자동 정지 타임아웃(오버타깃 적용), 라벨 표시(2초 유지)

### Low (비저장 2초 정책 연계)
- [`lib/widgets/trim_editor_modal.dart`](lib/widgets/trim_editor_modal.dart)
- [`lib/screens/clip_extractor_screen.dart`](lib/screens/clip_extractor_screen.dart)
- [`lib/screens/video_edit_screen.dart`](lib/screens/video_edit_screen.dart)

---

## 7) 테스트 체크리스트

> 상태 표기: `[ ]` 미실행, `[x]` 완료

### 7-0. 로그 필드(필수 수집) — 코드 기준

- [ ] Dart 저장 로그 1: [`saveRecordedVideo_paths`](lib/managers/video_manager.dart:2957)
  - 필수 필드: `sourcePath`, `outputPath`, `targetDurationMs`, `trimMode`
- [ ] Dart 저장 로그 2: [`saveRecordedVideo`](lib/managers/video_manager.dart:2971)
  - 필수 필드: `sourceDurationMs`, `targetDurationMs`, `expectedClipMs`, `trimMode`, `normalize`
- [ ] Dart normalize 요청/응답: [`normalizeRecordedVideo_request`](lib/managers/video_manager.dart:3060), [`normalizeRecordedVideo_response`](lib/managers/video_manager.dart:3075)
  - 필수 필드: `targetDurationMs`, `trimMode`, `result`
- [ ] Dart 결과 로그: [`saveRecordedVideo_result`](lib/managers/video_manager.dart:2995)
  - 필수 필드: `sourceDurationMs`, `targetDurationMs`, `normalizedDurationMs`, `normalizeSuccess`
- [ ] Dart fallback 로그(실패 시): [`normalize fallback(copy)`](lib/managers/video_manager.dart:2984)
  - 필수 필드: `source`, `target`
- [ ] Native normalize 인자/산출 로그:
  - [`normalizeVideoDuration argType... parsedMs...`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:585)
  - [`normalizeVideoDuration sourceDurationMs... clipMs...`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:730)
  - [`normalizeVideoDuration complete ... normalizedDurationMs=...`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:762)
  - 필수 필드: `targetDurationMs`, `clipMs`, `startMs`, `endMs`, `trimMode`, `normalizedDurationMs`

### 7-1. 코드 기반 수치(검증 기준값)

- [ ] 저장 타깃: [`kTargetClipSaveMs`](lib/constants/clip_policy.dart:5) = `2034ms` (61/30 올림 계산)
- [ ] UI 라벨 상한: [`kTargetClipSecForDisplay`](lib/constants/clip_policy.dart:2) = `2`
- [ ] 캡처 자동정지 버퍼: [`kRecordingUiSafetyBufferMs`](lib/constants/clip_policy.dart:8) = `120ms`
- [ ] 자동정지 임계: [`stopTriggerMs`](lib/screens/capture_screen.dart:450) = `kTargetClipSaveMs + 120ms` = `2154ms`
- [ ] normalize 실효 타깃: [`effectiveTargetDurationMs`](lib/managers/video_manager.dart:3049) = 전달값 또는 저장 타깃 폴백
- [ ] normalize clip 계산: [`clipMs = min(sourceDurationMs, targetDurationMs)`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:720)

### 7-2. 패스/실패 판정 기준 (로그 기반)

- [ ] 패스 P1: 저장 경로 로그의 `targetDurationMs`가 항상 `2034`인지 확인
  - 근거: [`_targetRecordingDurationMs`](lib/managers/video_manager.dart:1255), [`convertDurationMs`](lib/managers/video_manager.dart:1759)
- [ ] 패스 P2: 자동정지가 `elapsedMs >= 2154` 조건에서만 발생하는지 확인
  - 근거: [`elapsedMs >= stopTriggerMs`](lib/screens/capture_screen.dart:463)
- [ ] 패스 P3: normalize 성공 시 `normalizeSuccess=true` 및 native `clipMs=min(...)` 규칙과 일치하는지 확인
- [ ] 패스 P4: normalize 실패 시 copy fallback 로그가 발생하고 저장 흐름이 중단되지 않는지 확인
  - 근거: [`if (!normalized) { await File(video.path).copy(currentPath); }`](lib/managers/video_manager.dart:2980)
- [ ] 실패 F1: `INVALID_DURATION`, `INVALID_SOURCE_DURATION`, `INPUT_NOT_FOUND` 채널 에러 발생 시 케이스 분류 후 즉시 재현/롤백 판단
  - 근거: [`_logChannelGuardFail()`](lib/managers/video_manager.dart:3052), [`reportChannelError(...)`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:680)

### 필수
- [ ] 캡처 녹화 자동 정지 시점이 2초보다 약간 늦게(오버타깃 + 버퍼) 발생하는지 확인
- [ ] 저장된 결과 길이가 normalize 후 목표 길이(소스가 더 길면 약 2034ms 근처, 짧으면 원본 길이) 정책과 일치하는지 확인
- [ ] [`saveRecordedVideo()`](lib/managers/video_manager.dart:2948) 경로에서 normalize 실패 시 copy fallback 동작 여부 확인
- [ ] [`convertPhotoToVideo()`](lib/managers/video_manager.dart:1753) 경로에서 duration 전달값이 [`kTargetClipSaveMs`](lib/constants/clip_policy.dart:5)인지 로그로 확인
- [ ] 클립 추출/트리머/편집 화면에서 여전히 2초 정책([`kTargetClipMs`](lib/constants/clip_policy.dart:1))으로 동작하는지 확인

### 선택
- [ ] 저사양/고해상도(1080p, 4K)별로 저장 성공률 및 normalize 시간 비교
- [ ] Android 로그에서 `normalizeVideoDuration ... targetDurationMs=...` 진단 로그 연속성 확인
- [ ] 경계 케이스(원본 길이 2초 미만, 정확히 2초, 2초 초과) 3종 샘플 검증

---

## 8) 실패 시 롤백 포인트

### 8-1. 롤백 트리거 임계값 (운영 기준)

1. 즉시 롤백(Hotfix 우선)
   - 저장 로그에서 `targetDurationMs != 2034`가 1회라도 확인될 때
   - 자동정지 조건이 `2154ms` 규칙과 불일치할 때
   - `INVALID_DURATION`/`INVALID_SOURCE_DURATION`/`INPUT_NOT_FOUND`가 스모크 1회차에서 재현될 때

2. 조건부 롤백(원인 분석 후)
   - `normalizeSuccess=false` + fallback(copy) 연속 발생으로 저장 품질/길이 정책을 충족하지 못할 때
   - native 로그의 `clipMs=min(source,target)` 규칙 불일치가 확인될 때

### 8-2. 롤백 실행 포인트

1. 정책 롤백(저장도 2초로 즉시 회귀)
   - [`_targetRecordingDurationMs`](lib/managers/video_manager.dart:1255) 기준을 [`kTargetClipMs`](lib/constants/clip_policy.dart:1)로 되돌림
   - [`convertDurationMs`](lib/managers/video_manager.dart:1759) 기준을 [`kTargetClipMs`](lib/constants/clip_policy.dart:1)로 되돌림

2. 캡처 타이머 롤백
   - [`_targetRecordingMilliseconds`](lib/screens/capture_screen.dart:71)를 [`kTargetClipMs`](lib/constants/clip_policy.dart:1)로 복귀

3. 네이티브 롤백
   - 본 작업에서는 네이티브 변경 없음. 이슈 발생 시 Dart 측 전달값만 롤백하고, [`MainActivity.kt`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt)는 현행 유지

### 8-3. 롤백 검증 순서 (고정 시퀀스)

1. [`lib/constants/clip_policy.dart`](lib/constants/clip_policy.dart)에서 저장/표시/버퍼 상수 확인
2. [`capture_screen.dart`](lib/screens/capture_screen.dart)에서 `stopTriggerMs` 계산 확인
3. [`saveRecordedVideo()`](lib/managers/video_manager.dart:2948) 저장 로그로 `targetDurationMs` 확인
4. [`normalizeVideoDuration`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:566) native 로그로 `clipMs/min 규칙` 확인
5. 실패 케이스에서 fallback(copy) 로그 및 최종 파일 길이 재확인

---

## 9) 실행/검증 상태 요약

- 코드 수정: 문서화 기준 **추가 코드 수정 불필요**로 판정
- 네이티브 코드 변경: **없음**
- 테스트 실행: 본 문서 작성 시점 **체크리스트 정리 완료(수동 실행은 미실행)**

---

## 10) 오케스트레이터 핸드오프 완료 표기

- 문서 정합성: 코드 상수/경로/로그 필드/롤백 임계 기준까지 동기화 완료
- 범위: 저장 경로 61프레임 오버타깃 + 비저장 2초 정책 유지
- 핸드오프 상태: **FINAL COMPLETE (for orchestrator handoff)**

---

## 11) 2026-04-09 재검증(요청 반영) 결과

요청: **A안(61프레임 오버타깃) 완전 반영 여부 재검증 + 누락 보정**

### 11-1. 핵심 판정

- 저장 타깃(녹화/normalize): [`kTargetClipSaveMs`](lib/constants/clip_policy.dart:5) 경로로 유지됨 (약 `2034ms`)
  - 캡처 녹화 타임아웃 기준: [`_targetRecordingMilliseconds`](lib/screens/capture_screen.dart:71)
  - 저장 normalize 기준: [`_targetRecordingDurationMs`](lib/managers/video_manager.dart:1255)
- 표시 타깃(2초): [`kTargetClipSecForDisplay`](lib/constants/clip_policy.dart:2) 유지
  - 캡처 카운트다운/리셋 표시: [`capture_screen.dart`](lib/screens/capture_screen.dart)
  - 클립 추출 안내 문구: [`clip_extractor_screen.dart`](lib/screens/clip_extractor_screen.dart:763)
- 클립 추출 화면의 구간 계산/저장 큐 duration은 비저장 정책으로 [`kTargetClipMs`](lib/constants/clip_policy.dart:1) 사용 유지
  - 고정 윈도우: [`_fixedWindowMs`](lib/screens/clip_extractor_screen.dart:32)
  - 세그먼트 end/duration: [`clip_extractor_screen.dart`](lib/screens/clip_extractor_screen.dart:510), [`clip_extractor_screen.dart`](lib/screens/clip_extractor_screen.dart:563)

판정: **요청 충족(누락 코드 없음)**

### 11-2. 네이티브 호출 계약 점검

- normalize 채널은 전달값 `targetDurationMs`를 우선 사용하며 폴백 기본값 유지
  - 파싱: [`MainActivity.kt`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:572)
  - 적용: [`MainActivity.kt`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:720)
- 기본값 상수([`DEFAULT_TARGET_DURATION_MS`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:361))는 폴백 경로이므로 본 검증에서 변경하지 않음

판정: **호출 계약 정상(변경 불필요)**

### 11-3. 정합성 점검 결과

- 실행 명령: `flutter analyze lib/constants/clip_policy.dart lib/screens/capture_screen.dart lib/managers/video_manager.dart lib/screens/clip_extractor_screen.dart`
- 결과: **Error 0 / Warning 1 / Info 다수(기존 린트 성격)**
  - 신규 기능 차단 이슈 없음
  - 주요 warning: [`video_manager.dart`](lib/managers/video_manager.dart:2011) `unused_local_variable`

### 11-4. 영향 파일 및 변경 여부

- 코드 파일(검증 대상)
  - [`lib/constants/clip_policy.dart`](lib/constants/clip_policy.dart) — 변경 없음
  - [`lib/screens/capture_screen.dart`](lib/screens/capture_screen.dart) — 변경 없음
  - [`lib/managers/video_manager.dart`](lib/managers/video_manager.dart) — 변경 없음
  - [`lib/screens/clip_extractor_screen.dart`](lib/screens/clip_extractor_screen.dart) — 변경 없음
  - [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt) — 변경 없음
- 문서 파일
  - [`plans/a61_over_target_save_range_validation_report_v1.md`](plans/a61_over_target_save_range_validation_report_v1.md) — 본 섹션 추가

### 11-5. 완료/미완료

- 완료
  - [x] 저장 타깃(2034ms 계열)과 표시 타깃(2초) 분리 반영 재확인
  - [x] 지정된 대상 파일/네이티브 계약 정합성 점검
  - [x] 분석 문서 업데이트
  - [x] 컴파일/정적 분석 실행 및 결과 수집
- 미완료
  - [ ] 린트 경고/정보 전면 정리(본 요청 범위 외)
# A안(오버타깃 저장) 마무리 검증 보고서

## 범위
- 캡처 화면: UI 표시 2초 유지 + 녹화 stop 타이밍 저장 타겟(2034ms) 정합성
- 저장 파이프라인: `normalize/convertImageToVideo` 저장 타겟 적용 여부
- 클립 추출: 편집 대상 2초 창 로직/문구 일관성
- 네이티브 계약: `targetDurationMs` 처리와 상수 폴백 계약 정합성

---

## 1) 최종 판정
- **판정: 요구사항 충족**
- 저장 타겟은 61프레임 기반 `2034ms`, 편집/표시는 `2초(2000ms)`로 분리 유지

---

## 2) 파일별 검증/보정 결과

### 2-1. 정책 상수
- [`kTargetClipMs`](lib/constants/clip_policy.dart:1) = `2000` (편집/표시)
- [`kTargetClipSecForDisplay`](lib/constants/clip_policy.dart:2) = `2` (UI 문구/카운트다운)
- [`kTargetClipSaveMs`](lib/constants/clip_policy.dart:5) = `2034` (61/30 올림)

### 2-2. capture_screen (요청 1)
- 저장 타겟 기준 유지: [`_targetRecordingMilliseconds`](lib/screens/capture_screen.dart:71)
- UI 카운트다운 2초 상한 유지: [`kTargetClipSecForDisplay`](lib/screens/capture_screen.dart:468)
- **보정 완료**: 자동 stop 임계를 안전버퍼가 아닌 저장 타겟 직접 비교로 변경
  - 이전: `elapsedMs >= stopTriggerMs(=2034+120)`
  - 현재: [`elapsedMs >= _targetRecordingMilliseconds`](lib/screens/capture_screen.dart:460)

### 2-3. video_manager (요청 2)
- 저장 기준 상수 바인딩: [`_targetRecordingDurationMs`](lib/managers/video_manager.dart:1255)
- 사진→영상 변환 duration: [`convertDurationMs = kTargetClipSaveMs`](lib/managers/video_manager.dart:1759)
- normalize 호출 타깃 전달:
  - [`targetDurationMs: _targetRecordingDurationMs`](lib/managers/video_manager.dart:1798)
  - 기본 normalize 경로에서도 [`effectiveTargetDurationMs`](lib/managers/video_manager.dart:3049)로 저장 타겟 보장
- 결론: `convertImageToVideo`/`normalizeVideoDuration` 모두 저장 타겟 사용 확인

### 2-4. clip_extractor (요청 3)
- 고정 편집 창: [`_fixedWindowMs = kTargetClipMs`](lib/screens/clip_extractor_screen.dart:32)
- 세그먼트 end/duration: [`end = start + kTargetClipMs`](lib/screens/clip_extractor_screen.dart:510), [`durationMs = kTargetClipMs`](lib/screens/clip_extractor_screen.dart:563)
- 사용자 문구: [`"${kTargetClipSecForDisplay}초 장면"`](lib/screens/clip_extractor_screen.dart:763)
- 결론: 편집 대상 2초 창 로직과 문구 일관성 유지

### 2-5. MainActivity 계약 (요청 4)
- **보정 완료**: 폴백 상수 역할 분리
  - 편집 폴백: [`DEFAULT_EDIT_TARGET_DURATION_MS = 2000L`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:361)
  - 저장 폴백: [`DEFAULT_SAVE_TARGET_DURATION_MS = 2034L`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:362)
- 저장 관련 채널 폴백을 저장 타겟으로 정렬
  - `convertImageToVideo` 파싱/기본값: [`DEFAULT_SAVE_TARGET_DURATION_MS`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:545)
  - `normalizeVideoDuration` 파싱/기본값: [`DEFAULT_SAVE_TARGET_DURATION_MS`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:579)
- 편집 추출 폴백은 2초 유지
  - [`endMs` fallback = `startMs + DEFAULT_EDIT_TARGET_DURATION_MS`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:1745)

---

## 3) 이번 작업에서 실제 수정된 항목
- [`lib/screens/capture_screen.dart`](lib/screens/capture_screen.dart)
  - stop 안전버퍼 로직 제거, 저장 타겟(2034ms) 직접 stop으로 보정
- [`lib/constants/clip_policy.dart`](lib/constants/clip_policy.dart)
  - 미사용 안전버퍼 상수 제거
- [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`](android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt)
  - `DEFAULT_*_TARGET_DURATION_MS` 상수 역할 분리(편집 2000 / 저장 2034)

---

## 4) 잔여 위험 (요청 5)
1. **타이머 해상도 지터**
   - Dart 타이머(100ms tick) 특성상 실제 stop 호출 시점이 `2034ms`를 소폭 초과할 수 있음.
   - 정책상 임계값 기준은 맞지만 기기별 실측 길이는 약간 변동 가능.

2. **네이티브 폴백 경로 의존성**
   - 정상 경로는 Dart에서 `targetDurationMs`를 전달하므로 문제 없음.
   - 다만 외부/레거시 호출에서 인자 누락 시 폴백값(저장 2034, 편집 2000)에 의존.

3. **normalize 실패 시 copy fallback 길이 편차**
   - 저장은 유지되지만 normalize 실패 시 원본 길이가 그대로 저장될 수 있음.
   - 현재 설계상 허용 동작이며 운영 로그 모니터링 필요.

---

## 5) 권장 확인 포인트
- 캡처 후 저장 로그에서 `targetDurationMs=2034` 확인
- 추출/편집 화면에서 2초 문구 및 2초 창 유지 확인
- 네이티브 로그에서 normalize 호출 파라미터 `targetDurationMs` 전달 확인

---

## 6) 결론
- A안(오버타깃 저장) 기준으로 **저장(2034ms)과 편집/표시(2000ms)** 분리 정책이 코드/네이티브 계약 모두에서 정합하게 마무리됨.

# Selective Tone Curve Implementation Plan v1

작성일: 2026-05-21

## 1. 목적

현재 Brightness 기능의 `highlights`와 `shadows`는 별도 effect 단계로 분리되어 있지만, 실제 픽셀 밝기 영역을 선별하는 tone curve는 아니다. 이 계획은 밝은 영역과 어두운 영역을 luminance mask로 분리해 조정하는 진짜 selective tone curve를 구현하기 위한 단계별 계획이다.

이 문서는 구현 계획서이며, Firebase rules/index/schema 변경, migration/backfill, Storage physical delete, Cloud copy, deploy를 포함하지 않는다.

## 2. 현재 상태

현재 구현:

- Flutter preview: `ColorFiltered` + `brightnessPreviewColorMatrix()`.
- Android export: Media3 GPU effects.
- 기본 보정: brightness, exposure, contrast, saturation, temperature, tint.
- 고급 보정:
  - highlights: 별도 RGB gain/offset pass.
  - shadows: 별도 RGB gain/offset pass.
  - sharpness: native export에서 sharpening convolution 또는 Gaussian blur.
  - clarity: 별도 contrast + saturation pass.

현재 한계:

- highlights/shadows가 luminance mask를 사용하지 않는다.
- 밝은 영역/어두운 영역만 선택적으로 조정하지 못한다.
- Flutter preview와 Android export의 selective tone parity가 아직 없다.
- `ColorFilter.matrix`만으로는 smooth luminance mask 기반 curve를 정확히 표현할 수 없다.

## 3. 목표 정책

Selective tone curve 기준:

- `highlights > 0`: 밝은 영역을 더 밝게 한다.
- `highlights < 0`: 밝은 영역을 회복/압축한다.
- `shadows > 0`: 어두운 영역을 들어 올린다.
- `shadows < 0`: 어두운 영역을 더 눌러 깊이를 만든다.
- 중간톤은 hard cutoff 없이 부드럽게 영향을 받는다.
- clipping과 banding을 줄이기 위해 `smoothstep` 기반 mask를 사용한다.
- export 결과와 preview 결과는 단계적으로 parity를 맞춘다.

## 4. 기술 방향

권장 방식은 Android Media3 custom `GlEffect` 구현이다.

핵심 shader 개념:

```glsl
float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));

float shadowMask = 1.0 - smoothstep(shadowStart, shadowEnd, luma);
float highlightMask = smoothstep(highlightStart, highlightEnd, luma);

// shadows/highlights 값의 부호에 따라 lift, crush, boost, recover 분기
```

왜 custom shader인가:

- `RgbMatrix`는 픽셀별 luminance 조건 분기가 불가능하다.
- `Contrast`는 전체 tonal range에 영향을 준다.
- LUT 방식도 가능하지만 slider 값마다 LUT 생성/전달/검증이 필요해 초기 구현 복잡도가 더 높다.
- Media3 custom effect로 export 경로부터 안정화한 뒤 Flutter preview shader parity를 붙이는 것이 가장 안전하다.

## 5. 단계별 계획

### Phase ST0. Contract and Test Fixture

목표:

- selective tone curve의 입력/출력 계약을 고정한다.

작업:

- `highlights`, `shadows` 값 범위는 기존처럼 `-100..100` 유지.
- native payload key는 기존 `highlights`, `shadows` 유지.
- Project JSON schema 변경 없이 기존 `brightnessAdjustments` map 사용.
- 테스트용 색상 샘플 정의:
  - shadow sample: RGB 0.10, 0.10, 0.10
  - mid sample: RGB 0.50, 0.50, 0.50
  - highlight sample: RGB 0.90, 0.90, 0.90

검증:

- normalize/export payload 테스트가 기존 JSON 호환성을 유지한다.
- unknown key 무시 정책 유지.

### Phase ST1. Android Export Custom GlEffect

목표:

- Android export에서 highlights/shadows를 luminance mask 기반으로 처리한다.

작업:

- Android에 `SelectiveToneCurveEffect` 추가.
- Media3 `GlEffect`/`GlShaderProgram` 구조를 사용한다.
- uniforms:
  - `uHighlights`
  - `uShadows`
  - `uShadowStart`
  - `uShadowEnd`
  - `uHighlightStart`
  - `uHighlightEnd`
- 기본 mask 값:
  - shadowStart: `0.02`
  - shadowEnd: `0.55`
  - highlightStart: `0.45`
  - highlightEnd: `0.98`
- `MainActivity.kt`의 `createGpuFilters()`에서 기존 highlights/shadows RGB pass를 custom effect로 교체한다.
- 기존 `brightness`, `exposure`, `contrast`, `saturation`, `temperature`, `tint`, `sharpness`, `clarity` 경로는 유지한다.

검증:

- `flutter build apk --debug`.
- highlights/shadows 값이 있을 때 native log에 `selective_tone_curve`가 찍힌다.
- export 성공.
- gallery album `MOA` 저장 유지.

### Phase ST2. Tone Curve Math QA

목표:

- shader 수식이 기대 방향으로 동작하는지 검증한다.

작업:

- Kotlin pure helper 또는 Dart mirror helper로 sample RGB 변환 테스트를 만든다.
- 최소 검증:
  - `highlights > 0`은 highlight sample을 mid/shadow보다 더 크게 변화시킨다.
  - `highlights < 0`은 highlight sample을 압축한다.
  - `shadows > 0`은 shadow sample을 mid/highlight보다 더 크게 lift한다.
  - `shadows < 0`은 shadow sample을 더 어둡게 만든다.
  - mid sample 변화량은 shadow/highlight mask보다 낮다.

검증:

- unit test 통과.
- 값이 `0..1` 범위를 벗어나지 않도록 clamp 확인.

### Phase ST3. Flutter Preview Parity Strategy

목표:

- preview와 export의 차이를 줄인다.

선택지:

1. 단기: Flutter preview는 기존 matrix 근사 유지.
   - 구현이 작다.
   - export와 완전 parity는 아니다.
   - UI에 별도 문구를 넣지는 않는다.

2. 권장: Flutter fragment shader preview 도입.
   - `FragmentProgram`/`ShaderMask` 또는 custom painter shader 적용 검토.
   - preview video texture에 shader 적용 가능 여부를 에뮬레이터에서 확인한다.
   - Android export shader와 같은 constants를 Dart 쪽에 중앙화한다.

권장 순서:

- ST1/ST2로 export를 먼저 안정화한다.
- ST3에서 preview shader 적용 가능성을 별도 QA한다.
- shader preview가 안정적이지 않으면 preview는 근사, export는 정식 selective curve로 유지한다.

검증:

- highlights/shadows slider 조작 시 preview가 즉시 갱신된다.
- playback 중 shader 적용 시 frame drop이 과하지 않다.
- Cloud clip materialized preview에서도 동작한다.

### Phase ST4. Export Regression

목표:

- 기존 export 정책과 Cloud clip 정책을 깨지 않는다.

검증 항목:

- Standard export dialog는 `720p`, `1080p`만 표시.
- 기본값은 `1080p`.
- 4K 요청은 `1080p`로 clamp.
- local project export 성공.
- Cloud-only clip export 성공.
- mixed local/cloud project export 성공.
- `export_session_cache` path가 Project JSON에 저장되지 않음.
- `edit_session_cache` path가 Project JSON에 저장되지 않음.
- partial output은 성공 전 gallery에 등록되지 않음.

### Phase ST5. Visual QA

목표:

- 기능이 “작동한다” 수준을 넘어 영상 보정 기능으로 납득 가능한지 확인한다.

테스트 클립:

- 역광/하늘 포함 클립.
- 실내 어두운 그림자 클립.
- 얼굴/피부톤 포함 클립.
- 고대비 야외 클립.
- Cloud-only clip.

확인:

- highlights 음수: 하늘/밝은 창문이 과하게 날아가지 않고 줄어든다.
- highlights 양수: 밝은 영역만 자연스럽게 강조된다.
- shadows 양수: 어두운 영역이 들어 올려지되 전체 화면이 회색으로 뜨지 않는다.
- shadows 음수: 어두운 영역만 깊어진다.
- 중간톤/피부톤이 과도하게 흔들리지 않는다.
- export 결과와 preview 차이가 허용 범위 안에 있다.

## 6. 리스크

- Media3 custom shader 구현은 기기/GPU 호환성 리스크가 있다.
- Flutter preview shader parity는 VideoPlayer texture와 조합 시 제약이 있을 수 있다.
- highlights/shadows의 자연스러운 계수는 수학적으로 한 번에 고정하기 어렵고 visual tuning이 필요하다.
- shader 오류 시 export 실패로 이어질 수 있으므로 fallback이 필요하다.

## 7. Fallback Policy

- custom selective shader 생성 실패 시 export를 실패시키지 않고 기존 RGB pass 또는 no-op로 fallback한다.
- fallback 발생 시 로그:
  - `selective_tone_curve_fallback`
  - reason
  - highlights/shadows value
- fallback은 Project JSON이나 사용자 원본 clip을 변경하지 않는다.

## 8. 금지 사항

- Firebase rules/index/schema 변경 금지.
- migration/backfill 금지.
- Storage physical delete 금지.
- Cloud copy 구현 금지.
- Project JSON schema breaking change 금지.
- SharedPreferences key 변경 금지.
- IAP product id 변경 금지.
- deploy 금지.

## 9. 완료 기준

- Android export에서 selective tone curve custom effect가 적용된다.
- highlights/shadows가 luminance mask 기반으로 분기된다.
- 기존 Project JSON과 Cloud project metadata 호환성이 유지된다.
- `flutter analyze --no-fatal-infos`에서 오류가 없다.
- 관련 unit test가 통과한다.
- debug APK build가 통과한다.
- Standard local/cloud/mixed export tap-through QA가 통과한다.

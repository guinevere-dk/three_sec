# Video Edit Screen Feature Improvement Plan v1

작성일: 2026-05-21

## 1. 목적

이 문서는 현재 `VideoEditScreen`의 기능 개선 요청 7가지를 실제 emulator tap-through와 코드 분석 기준으로 정리한 구현 계획이다. 본 문서는 계획서이며, 코드 변경, Firebase rules/index/schema 변경, migration/backfill, Storage physical delete, deploy를 포함하지 않는다.

## 2. 확인 범위

분석 파일:

- `lib/screens/video_edit_screen.dart`
- `lib/models/vlog_project.dart`
- `lib/managers/video_manager.dart`
- `android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`
- `plans/video_edit_screen_policy_v1.md`

emulator 확인:

- 기기: `emulator-5554`, Android 15 API 35
- 앱: `com.dk.three_sec/com.dk.three_sec.MainActivity`
- 상태: Standard 계정, `VideoEditScreen` 진입 완료, 프로젝트 `Vlog_2026521`, 클립 2개
- 확인 액션: Canvas, Trim, Transform, Brightness, Sound 버튼 tap-through 및 UI hierarchy dump

## 3. 현재 상태 요약

### 3.1 Canvas 화면비율

현재 Canvas bottom sheet에는 `9:16`, `1:1`, `16:9`만 노출된다. 코드상 `_canvasAspectRatioForPreset`, `_canvasAspectLabel`, `_showCanvasPanel`의 preset list도 `r9_16`, `r1_1`, `r16_9`만 가진다.

개선 포인트:

- `r3_4`, `r4_3` preset을 추가한다.
- 기존 Project JSON의 `canvasAspectRatioPreset` 기본값 `r9_16`은 유지한다.
- 알 수 없는 legacy preset은 기존처럼 `r9_16` fallback을 유지한다.
- export 경로가 Canvas 비율을 실제 출력 크기/letterbox/crop에 반영하는지 별도 확인이 필요하다. 현재 `exportVlog` native args에는 `canvasAspectRatioPreset`가 전달되지 않는 것으로 보이므로, Canvas UI만 바꾸면 preview와 export가 불일치할 수 있다.

### 3.2 Trim 높이 불일치

emulator에서 Trim 활성화 시 선택 clip 영역은 `bounds [26,1836][231,2072]`처럼 약 236px 높이로 잡히고, 코드상 `_buildExpandedTimelineItem`은 외부 `height: 90`, `padding vertical: 10`, 내부 trim 기준 `height = 70.0`을 혼합한다. inactive clip도 70 높이 + vertical margin 10이다.

개선 포인트:

- Trim clip thumbnail, dim overlay, trim range overlay, handle, scrubber가 같은 content rect를 공유하도록 단일 상수로 정리한다.
- 추천 구조:
  - panel height: `_inlineModePanelHeight`
  - item outer height: 90
  - visual track height: 70
  - `Stack` 전체를 70 높이 `SizedBox`로 제한
  - overlay/handle/playhead는 모두 visual track rect 기준
- 현재처럼 `Positioned.fill`이 outer item 전체에 깔리고 handle만 `height=70`을 쓰는 구조를 피한다.

### 3.3 전체 preview 재생 종료 위치

현재 `_videoListener`의 normal mode 마지막 clip 종료 처리에서 마지막 clip의 `clip.startTime`으로 seek한다. 따라서 전체 프로젝트를 끝까지 재생하면 마지막 클립 시작 지점으로 돌아간다.

개선 포인트:

- normal mode에서 마지막 clip 종료 시 `_loadClip(0, autoPlay: false)` 또는 equivalent reset helper를 사용해 첫 번째 playable clip의 `startTime`으로 이동한다.
- Trim/Sound/Brightness 같은 clip-local editing mode는 현재 clip 시작으로 돌아가는 정책을 유지한다.
- missing/cloud failed clip이 섞인 경우에는 첫 번째 playable clip index를 찾아 reset한다.
- BGM controller도 reset/pause 동기화한다.

### 3.4 Transform 수평/수직 제거

emulator에서 Transform의 Angle 패널을 열면 `기울기`, `수평`, `수직`이 노출된다. 요청 기준으로 수평/수직은 제거 대상이다.

개선 포인트:

- `_TransformAngleMode`를 `tilt`만 남기거나 mode enum 자체를 제거한다.
- `_setTransformAngleMode`, `_transformAngleModeLabel`의 수평/수직 분기를 삭제한다.
- Angle 패널은 칩 row 없이 바로 기울기 ruler만 표시한다.
- `horizontal`은 angle 0도, `vertical`은 angle 90도 snap을 수행하므로, 기존 프로젝트에 저장된 `transformAngle=90`은 유지하되 UI에서 자동 변경 버튼은 제거한다.

### 3.5 Brightness 계열 기능 미구현

UI에는 `밝기`, `노출`, `대비`, `하이라이트`, `그림자`, `채도`, `틴트`, `색온도`, `선명도`, `명료도`가 존재하고 `_brightnessAdjustments`에도 값이 저장된다. 그러나 preview의 `_getFilterMatrix()`는 `_enableDormantEditFeatures == false`일 때 항상 identity matrix를 반환하므로 현재 조절 값이 화면에 반영되지 않는다.

또한 `VideoManager.exportVlog`의 native args에는 brightness adjustment map이 전달되지 않는다. Android native에는 legacy `createGpuFilters(videoEffects, userTier)`가 있지만 현재 정책상 Premium은 dormant이고, export merge 경로가 이 brightness map을 쓰지 않는다.

개선 포인트:

- UI state 저장만으로는 부족하다. preview, autosave, project JSON, export native args, Android renderer를 함께 설계해야 한다.
- 공식 지원 기능이므로 Filter/AI와 분리해 `brightnessAdjustments`는 dormant feature guard의 영향을 받지 않아야 한다.
- 각 속성은 하나씩 구현하고 QA해야 한다.

권장 구현 순서:

1. Brightness infrastructure
   - `EditColorAdjustment` 또는 typed policy helper 도입.
   - key 목록, 기본값, min/max, display label, native key를 중앙화.
   - 기존 `Map<String, double>` 저장 호환은 유지.
   - 알 수 없는 key는 저장/복원 시 무시하거나 pass-through 정책을 명시.

2. Brightness preview
   - Flutter preview에는 단일 color matrix builder를 적용한다.
   - 우선 실시간 반응성이 높은 속성부터 구현한다: brightness, exposure, contrast, saturation, temperature, tint.
   - highlights, shadows, sharpness, clarity는 단순 4x5 color matrix만으로 품질이 낮을 수 있으므로 native 기반 구현 전까지 preview 근사치와 export 결과 일치성 기준을 별도로 둔다.

3. Brightness export contract
   - `VideoManager.exportVlog`에 `colorAdjustments`를 명시적으로 전달한다.
   - Android `mergeVideos` 경로에서 clip별 또는 project 전체 adjustment 적용 위치를 결정한다.
   - 현재 UI는 project-wide adjustment처럼 보인다. clip별 조정을 원하면 `VlogClip`으로 필드를 이동하거나 clip id keyed map이 필요하다. 첫 구현은 project-wide로 고정하는 것이 안전하다.

4. 속성별 구현 단위
   - 밝기: RGB offset 또는 Media3 RGB matrix. 범위 -100..100을 -0.5..0.5 수준으로 normalize.
   - 노출: linear gain. 밝기와 중복되지 않도록 gain 기반으로 구현.
   - 대비: center 0.5 기준 contrast matrix.
   - 하이라이트: 밝은 영역만 압축/증폭해야 하므로 shader/native effect 우선. matrix fallback은 제한적이다.
   - 그림자: 어두운 영역 lift/drop. shader/native effect 우선.
   - 채도: 기존 Android `createSaturationMatrix` 아이디어 재사용 가능하나 Premium gate 제거 필요.
   - 틴트: green-magenta balance matrix.
   - 색온도: red/blue gain balance.
   - 선명도: convolution/sharpen shader 필요. Media3 effect 또는 custom GL effect 검토.
   - 명료도: local contrast 계열이라 단순 matrix 불가. 선명도와 같은 native effect 계층에서 구현.

5. QA
   - 각 속성별로 preview 변화, undo/redo, autosave 복원, project reopen, export 결과를 확인한다.
   - export 결과와 preview가 크게 다르면 해당 속성은 beta/disabled로 남겨야 한다.

### 3.6 Sound overflow

emulator Sound panel에서 `전체 사운드`, `클립 사운드` 2개 slider가 110px inline panel 안에 세로로 배치된다. UI dump 기준 두 번째 slider가 `bounds [326,1986][909,2112]`로 toolbar 직전까지 내려오며, 사용자가 보고한 overflow와 일치한다.

개선 포인트:

- sound row 높이를 줄이고 vertical gap을 줄인다.
- 추천 조정:
  - icon box 40 -> 30 또는 제거
  - label width 66 유지, font 13 -> 12
  - slider row height를 46 이하로 고정
  - row 사이 간격 8 이하
  - panel padding vertical 6 -> 4
- 더 안전한 방향은 inline sound panel을 `Column` 2행에서 compact `ListView` 또는 `FittedBox` 없이 고정 높이 row 2개로 재구성하는 것이다.
- overflow warning은 emulator logcat 필터에서는 재현 시점에 잡히지 않았지만 UI bounds가 매우 빡빡하므로 높이 여유를 확보해야 한다.

### 3.7 기능 활성화 상태의 클립 전환

Trim 상태에서는 상단 좌우 버튼으로 clip 전환이 가능하다. 반면 Transform/Brightness/Sound에서는 상단 `다음 클립` 버튼이 활성처럼 보이지만 실제 이동하지 않는다. emulator Sound 상태에서 `다음 클립` tap 후에도 `현재 1 / 2`가 유지됐다.

코드 원인:

- `_isPlaybackLockedForEditing`은 transform/brightness/sound에서 true다.
- `_moveToAdjacentClip`은 `_isPlaybackLockedForEditing`이면 즉시 return한다.
- 상단 버튼의 enabled 조건은 `_isPlaybackLockedForEditing`을 고려하지 않아 UX가 모순된다.

개선 포인트:

- 상단 clip navigation은 editing mode별로 명시 정책을 둔다.
- 요청 기준으로 Transform/Brightness/Sound에서도 clip 전환을 허용해야 한다.
- 전환 직전 pending gesture를 commit해야 한다.
  - Transform: `_commitTransformGesture()`
  - Brightness: `_commitBrightnessGesture()`
  - Sound: slider change end state commit 또는 현재 volume state transition
- 전환 후에도 같은 mode panel은 유지하되 현재 clip 기준 값을 다시 로드한다.
- preview swipe는 editing mode에서 계속 막아도 된다. 요청은 상단 버튼 기준이다.
- 단, F1에서는 Transform/Sound만 먼저 허용한다.
- Brightness는 값의 소유권이 project-wide인지 clip-specific인지 아직 모호하므로 F2 state contract에서 확정한 뒤 clip 전환을 허용한다.
- 상단 버튼 enabled 상태와 실제 동작은 반드시 일치해야 한다. 이동을 막는 모드라면 버튼도 disabled 처리한다.

## 4. 구현 Phase 제안

### Phase F0. Access and Quality Safety Gate

F1 UI correctness 전에 권한/품질/저장 경계를 먼저 고정한다. UI 개선이 먼저 들어가면 deep link, 이전 화면 버그, 프로젝트 복원, 구독 상태 변경 같은 우회 경로에서 `VideoEditScreen` 접근 권한이 새어 나갈 수 있다.

범위:

- `VideoEditScreen` 내부에서 Standard hard gate를 둔다.
- Free 사용자가 직접 진입한 경우 편집을 시작하지 않고 quick 720p export 또는 paywall/구독 안내 경로로 회피한다.
- Premium dormant tier는 런타임 권한에서 Standard로 normalize한다.
- 4K 요청은 UI, project restore, export 직전 모든 경로에서 1080p로 clamp한다.
- `edit_session_cache`, `export_session_cache`, `cloud_clip_session_cache` path가 Project JSON/Cloud project metadata/Library local index에 저장되지 않는 guard를 재확인한다.

검증:

- Free 상태에서 `VideoEditScreen` 직접 생성/복원/deep link 유사 진입 시 편집 UI가 열리지 않는다.
- Standard 상태에서는 편집 UI가 열린다.
- Premium-like local state는 Standard equivalent로 동작한다.
- legacy 4K project를 열어도 export dialog와 저장 project quality가 1080p 이하로 clamp된다.
- Cloud clip preview/export 후 Project JSON에 session cache path가 남지 않는다.

### Phase F1. UI correctness quick fixes

범위:

- Canvas `3:4`, `4:3` preset 추가. 단, preview-only 추가로 끝내지 않는다.
  - 먼저 `exportVlog` native args와 Android merge 경로가 `canvasAspectRatioPreset`을 받는지 확인한다.
  - export까지 반영 가능하면 F1에 포함한다.
  - export parity가 확인되지 않으면 UI 추가만 하지 않고 별도 Canvas export parity task로 분리한다.
- Trim visual track 높이 정렬.
- 전체 playback 종료 시 첫 번째 clip 시작으로 reset.
- Transform Angle 패널에서 `수평`, `수직` 제거.
- Sound inline panel compact layout.
- Transform/Sound 상태에서 상단 clip 좌우 버튼 동작 허용.
- Brightness 상태의 clip 전환은 F2 state contract에서 project-wide/clip-specific 정책을 확정한 뒤 허용한다.

검증:

- emulator에서 Canvas sheet에 `9:16`, `3:4`, `4:3`, `1:1`, `16:9` 표시 확인.
- Canvas preset 변경 후 export 결과가 preview aspect와 일치하는지 확인. 불일치하면 F1 완료 조건에서 Canvas UI 추가를 제외한다.
- Trim 활성화 후 thumbnail, dim overlay, yellow handles, playhead 높이가 동일한지 확인.
- 2개 이상 clip 프로젝트를 끝까지 재생 후 `현재 1 / N`, `0:00` 근처로 복귀 확인.
- Transform Angle 패널에 `기울기`만 남는지 확인.
- Sound panel overflow warning이 없는지 logcat 확인.
- Transform/Sound 상태에서 상단 다음/이전 clip 전환 확인.
- Brightness 상태에서는 버튼 정책이 disabled인지, 또는 F2 이후 명시 정책에 맞게 동작하는지 확인한다.

### Phase F2. Brightness state contract

범위:

- brightness adjustment key/policy 중앙화.
- `EditorState`/Project JSON restore/save 호환성 점검.
- preview/export에서 사용할 normalized payload 구조 정의.
- Brightness를 project-wide로 유지할지 clip-specific으로 바꿀지 확정한다.
  - project-wide면 상단 clip 전환 시 같은 adjustment가 모든 clip preview에 적용된다.
  - clip-specific이면 `VlogClip` field 또는 clip id keyed map이 필요하며, 저장/복원/export payload도 clip 기준으로 바뀐다.
- clip 전환 전후 flush 정책을 확정한다.
  - 전환 전: 현재 clip/project 변경사항 commit, autosave enqueue, UI state flush.
  - 전환 후: 새 clip 또는 project 기준 brightness/sound/transform 값을 load, 없는 값은 기본값 사용.
  - undo stack은 project-wide 단일 stack으로 유지할지 clip-scoped command로 분리할지 결정한다.
- 단위 테스트 추가.

검증:

- 기존 프로젝트가 누락된 brightness map으로 열려도 기본값 0으로 동작.
- 알 수 없는 key가 crash를 만들지 않음.
- autosave/reopen 후 값 유지.

### Phase F3. Brightness preview implementation

범위:

- Flutter preview에 공식 지원 adjustment를 반영.
- F3-1 1차 구현 대상은 `brightness`, `contrast`, `saturation` 3개로 제한한다.
- F3-2 2차 구현 대상은 `exposure`, `temperature`, `tint`로 둔다.
- `highlights`, `shadows`, `sharpness`, `clarity`는 native parity 전까지 숨김 또는 disabled 상태로 둔다.
- F3에서는 export 반영을 하지 않는다. preview와 저장/복원 계약만 검증한다.

검증:

- F3-1의 3개 slider 변경 시 preview가 즉시 변한다.
- F3-2 추가 후 exposure/temperature/tint preview가 즉시 변한다.
- reset/undo/redo가 속성별로 정상 동작한다.
- F2에서 정한 project-wide/clip-specific 정책에 맞게 clip 전환 후 panel state와 preview가 유지된다.

### Phase F4. Brightness export implementation

범위:

- `VideoManager.exportVlog` native args에 color adjustment payload 추가.
- Android merge 경로에서 Media3 effect 또는 GL effect 적용.
- Preview와 export 결과의 허용 오차 기준 정의.
- F4-1은 F3-1 속성인 brightness/contrast/saturation만 export 반영한다.
- F4-2는 F3-2 속성인 exposure/temperature/tint를 export 반영한다.

검증:

- F4-1/F4-2 각 속성별 export 결과가 preview 방향과 일치한다.
- Standard 720p/1080p export 모두 적용된다.
- Free quick export는 편집화면 접근이 없으므로 영향 없음.
- 4K path는 계속 숨김/clamp 유지.

### Phase F5. Native advanced color effects

범위:

- 하이라이트, 그림자, 선명도, 명료도용 native effect를 구현한다.
- matrix fallback 품질이 낮으면 UI는 유지하되 export parity가 확보될 때까지 해당 속성을 disabled 또는 beta flag로 둔다.
- native parity가 확보되기 전에는 `highlights`, `shadows`, `sharpness`, `clarity`를 공식 지원 UI처럼 활성화하지 않는다.

검증:

- 고대비/저조도 샘플 clip으로 하이라이트/그림자 변화 확인.
- 텍스처가 있는 샘플로 선명도/명료도 변화 확인.
- export 실패 시 원본 Project/Clip 데이터 보존 확인.

## 5. QA 체크리스트

- Access/quality gate: Free 직접 진입 차단, Standard 진입 허용, Premium dormant normalize, 4K to 1080p clamp, session cache path 저장 차단.
- Canvas: 3:4/4:3 선택, undo/redo, project reopen, export preview parity.
- Trim: 1개 clip, 2개 clip, 짧은 clip, cloud materialized clip에서 높이 정렬 확인.
- Playback end: normal mode에서 마지막 clip 종료 후 첫 번째 clip 시작으로 이동.
- Transform: 수평/수직 UI 미노출, 기울기 slider 정상, clip 전환 후 값 유지.
- Brightness: F3-1 brightness/contrast/saturation preview, autosave, reopen 확인.
- Brightness: F3-2 exposure/temperature/tint preview, autosave, reopen 확인.
- Brightness: highlights/shadows/sharpness/clarity는 native parity 전까지 숨김 또는 disabled 확인.
- Brightness export: F4 이후에만 export 적용 확인.
- Sound: overflow warning 없음, slider 2개 접근 가능, top clip 전환 가능.
- Clip navigation: F1에서는 Trim/Transform/Sound 각각에서 상단 이전/다음 버튼 동작.
- Clip navigation: Brightness는 F2 정책 확정 후 enabled/disabled와 실제 동작 일치 확인.
- Cloud Clip edit regression: Cloud-only clip 편집 진입 시 File Missing이 뜨지 않음.
- Cloud Clip edit regression: `edit_session_cache` materialize 성공 후 preview 가능.
- Cloud Clip edit regression: session cache path가 Project JSON에 저장되지 않음.
- Cloud Clip export regression: export 전 `export_session_cache` materialize 성공.
- Cloud Clip failure regression: 네트워크/Storage 실패 시 File Missing이 아니라 Cloud Load Failed 표시.
- Cloud Clip mixed export regression: local clip + Cloud clip 혼합 프로젝트 export 가능.
- Regression: Free는 편집화면 접근 불가, Standard만 편집 가능, session cache/project save/export 정책 유지.

## 6. 구현 금지/주의

- 이 계획만으로 Firebase rules/index/schema를 변경하지 않는다.
- `vlog_projects`, `videos`, Storage prefix, SharedPreferences key, IAP product id는 변경하지 않는다.
- 기존 Project JSON 호환을 깨는 field rename은 하지 않는다.
- Brightness 구현 중 legacy dormant Filter/AI/Sticker/Advanced caption을 다시 노출하지 않는다.
- export native contract를 바꿀 때는 Android 먼저 최소 변경으로 검증하고, iOS 미지원 상태가 있으면 명시적으로 fallback 정책을 둔다.

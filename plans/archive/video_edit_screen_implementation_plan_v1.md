# Video Edit Screen Implementation Plan v1

작성일: 2026-05-21

## 1. 목적

`plans/video_edit_screen_policy_v1.md`에 고정된 정책을 실제 구현으로 반영하기 위한 단계별 계획이다. 이 문서는 계획서이며 코드 변경, Firebase rules/index/schema 변경, migration/backfill, Storage physical delete, Cloud copy 구현, deploy를 포함하지 않는다.

## 2. 기준 정책 문서

- `plans/video_edit_screen_policy_v1.md`
- `AGENTS.md`
- `DATA_COMPATIBILITY.md`
- `CURRENT_PHASE.md`

## 3. 구현 원칙

- 사용자 원본 영상, Project JSON, local index, Cloud metadata 보존을 최우선으로 한다.
- 기존 Firestore collection, Storage prefix, SharedPreferences key, IAP product id를 변경하지 않는다.
- Free quick export와 Standard edit path를 명확히 분리한다.
- Cloud-only clip은 missing file로 취급하지 않는다.
- session cache는 Project나 Library 영구 데이터로 승격하지 않는다.
- 정책 판단은 `quality_policy.dart`와 명시적 gate 함수로 중앙화한다.

## 4. Phase E0. Inventory and Guard Baseline

목표:

- 현재 편집화면 진입 경로와 export 경로를 inventory한다.
- 정책 반영 전 QA 기준선을 만든다.

대상 확인:

- `lib/main.dart`
  - Library clip merge path
  - Free quick export path
  - single clip edit request path
- `lib/screens/project_screen.dart`
  - Project open path
  - Free project export fallback
- `lib/screens/video_edit_screen.dart`
  - access gate
  - toolbar
  - autosave
  - export dialog
  - Cloud materialize
- `lib/managers/video_manager.dart`
  - `createProject`
  - `saveProject`
  - `exportVlog`
  - project load/access filtering
- `lib/utils/quality_policy.dart`
  - export quality clamp

검증:

- Free path가 `VideoEditScreen`을 열지 않는지 확인.
- Standard path가 `VideoEditScreen`을 여는지 확인.
- 4K/AI UI 노출 상태를 현재 기준으로 기록.

산출물:

- Inventory note 또는 QA log.
- 변경 대상 함수 목록.

## 5. Phase E1. Tier Gate Hardening

목표:

- `VideoEditScreen` 내부에도 Standard hard gate를 둔다.
- 진입 경로의 gate와 화면 내부 gate를 이중화한다.

작업 계획:

- `VideoEditScreen` session start tier를 기록한다.
- Free가 `VideoEditScreen`에 직접 도달하면 화면 초기화 전에 차단한다.
- 차단 방식은 사용자 흐름에 맞춰 pop 또는 quick export 안내로 정한다.
- ProjectScreen/Main에서 이미 수행 중인 Free quick export 경로는 유지한다.
- Premium tier는 런타임에서 Standard-equivalent로 normalize한다.

검증:

- Free 상태에서 Project card tap 시 편집화면이 열리지 않는다.
- Free 상태에서 선택 clip export는 `720p` quick export로 동작한다.
- Standard 상태에서 편집화면이 정상 진입한다.
- Premium-like local state를 주입해도 Standard-equivalent로 처리된다.

## 6. Phase E2. Quality Policy Centralization

목표:

- export quality 정책을 `quality_policy.dart`에 중앙화한다.

작업 계획:

- `availableExportQualities(tier)` 추가.
- `defaultExportQuality(tier)` 추가.
- `maxExportQuality(tier)` 추가.
- `clampExportQuality(tier, requestedQuality)` 추가 또는 기존 `clampExportQualityForTier`와 호환 wrapper 구성.
- Free는 `720p`만 반환.
- Standard와 Premium-normalized는 `720p`, `1080p`만 반환.
- 모든 `4k` 요청은 `1080p`로 clamp.
- export dialog는 중앙 정책 API만 사용한다.
- Project restore 또는 saved quality load 시에도 중앙 clamp를 적용한다.

검증:

- unit test로 Free/Standard/Premium-normalized/4K clamp를 확인.
- Standard export dialog 기본값이 `1080p`인지 확인.
- Standard export dialog에 `4K`가 없는지 확인.

## 7. Phase E3. Edit Feature Surface Lock

목표:

- 공식 지원 기능과 숨김/보류 기능의 UI, 저장, export 경계를 고정한다.

작업 계획:

- toolbar 노출 기능을 `Trim`, `Transform`, `Brightness`, `Sound`로 제한한다.
- Canvas는 상단 canvas control로 유지한다.
- AI, Filter, Sticker, Advanced caption 진입점을 제거 또는 dormant 처리한다.
- 숨김 기능이 Project 저장 필드에 반영되지 않도록 sync 경로를 점검한다.
- 숨김 기능이 export input에 반영되지 않도록 export state sync 경로를 점검한다.
- dormant 함수는 `unused_element` ignore만으로 방치하지 않고 향후 제거/격리 후보로 기록한다.

검증:

- UI dump에서 `AI`가 보이지 않는다.
- `4K`와 Premium 전용 문구가 보이지 않는다.
- 숨김 기능 버튼이 tap-through로 접근되지 않는다.
- 기존 지원 기능 Trim/Transform/Brightness/Sound/Canvas는 정상 작동한다.

## 8. Phase E4. Cloud Clip State Model

목표:

- Cloud-only clip을 File Missing과 분리하고 상태 기반으로 처리한다.

작업 계획:

- Cloud clip 상태 enum 또는 equivalent state를 정의한다.
  - `CloudResolving`
  - `CloudBuffering`
  - `CloudReady`
  - `CloudFailed`
- `_loadClip`에서 `cloud_only://`를 File Missing으로 보내지 않는다.
- preview/edit source는 `edit_session_cache`에 materialize한다.
- export source는 `export_session_cache`에 materialize한다.
- Cloud failure reason을 metadata missing, permission, network, storage missing, download failed로 분리한다.
- retry UI를 제공한다.

검증:

- Cloud-only clip project 진입 시 File Missing이 보이지 않는다.
- materialize 중 Cloud 준비 UI가 보인다.
- materialize 성공 후 preview가 재생된다.
- materialize 실패 시 Cloud Load Failed와 retry가 보인다.

## 9. Phase E5. Session Cache Persistence Guard

목표:

- session cache가 Project JSON, Library local index, Cloud project metadata에 저장되지 않도록 보강한다.

작업 계획:

- `saveProject` 전에 clip path에 session cache root가 있는지 검사한다.
- session cache path가 있으면 원본 `cloud_only://` 참조로 복원하거나 저장을 차단한다.
- Library local index upsert 경로에서 session cache path를 거부한다.
- Cloud project metadata upsert 전에 `clipPaths`가 session cache를 포함하지 않는지 검사한다.

검증:

- Cloud clip preview 후 Project JSON에 `edit_session_cache`가 없다.
- Cloud clip export 후 Project JSON에 `export_session_cache`가 없다.
- local index에 session cache path가 없다.
- Cloud `vlog_projects` metadata에 session cache path가 없다.

## 10. Phase E6. Save Status UI

목표:

- Standard 편집에서 local/Cloud autosave 상태를 사용자에게 표시한다.

작업 계획:

- save state model을 정의한다.
  - idle
  - saving
  - localSaved
  - cloudSaved
  - cloudFailed
  - retrying
- `saveProject` 결과를 UI가 해석할 수 있도록 결과 타입 또는 callback을 설계한다.
- Cloud save 실패 시 local 보존 상태와 retry action을 표시한다.
- 닫기 전 pending autosave flush 상태를 표시한다.

검증:

- 변경 후 저장 중 상태가 표시된다.
- Cloud 저장 성공 상태가 표시된다.
- Cloud 저장 실패를 강제로 만들었을 때 local 보존과 retry가 표시된다.
- 닫기 시 pending autosave flush가 로그와 UI 상태로 확인된다.

## 11. Phase E7. Subscription Change Handling

목표:

- 편집 중 구독 상태 변경에 대한 런타임 정책을 구현한다.

작업 계획:

- session start tier를 기록한다.
- 저장 직전 권한을 재확인한다.
- Cloud write 직전 권한을 재확인한다.
- export 직전 권한을 재확인한다.
- 편집 중 Free/expired가 되면 화면은 유지한다.
- Free/expired 상태에서는 Cloud save를 중단하고 local draft를 보존한다.
- Free/expired 상태에서는 export 품질을 `720p`로 clamp한다.
- UI에 권한 변경 안내를 표시한다.

검증:

- Standard로 편집화면 진입 후 Free로 변경하면 화면은 유지된다.
- 변경 후 Cloud save는 중단된다.
- 변경 후 local draft는 보존된다.
- 변경 후 export는 `720p`로 clamp된다.

## 12. Phase E8. Cache Cleanup

목표:

- `edit_session_cache`와 `export_session_cache`를 TTL 기반으로 정리한다.

작업 계획:

- session cache root를 명확히 식별한다.
- 진행 중 session id를 cleanup 제외 목록으로 관리한다.
- 앱 시작 시 TTL cleanup을 실행한다.
- 편집 종료 시 해당 session cleanup을 시도한다.
- export 종료 시 해당 export session cleanup을 시도한다.
- 기본 TTL은 24시간으로 둔다.

검증:

- 24시간 초과 session cache가 cleanup된다.
- 진행 중 session cache는 삭제되지 않는다.
- 원본 clip, Project JSON, Library index는 삭제되지 않는다.
- cleanup 실패 시 앱 흐름이 막히지 않는다.

## 13. Phase E9. Export Preflight

목표:

- export 전 실패 가능 조건을 명확히 확인하고 사용자에게 표시한다.

작업 계획:

- export 전 Project 저장을 시도한다.
- Cloud clip materialize 완료 여부를 확인한다.
- Cloud clip 포함 시 네트워크 필요 안내를 표시한다.
- 저장공간과 예상 export 용량을 확인한다.
- materialize 실패 시 Cloud Load Failed로 표시한다.
- local missing과 Cloud failed를 분리한다.
- partial output 처리 규칙을 구현한다.

검증:

- Cloud clip 포함 export에서 materialize 단계가 먼저 완료된다.
- 네트워크 실패 시 Cloud Load Failed가 표시된다.
- 저장공간 부족 시 export 시작 전 차단된다.
- export 취소/실패 시 partial output이 gallery에 등록되지 않는다.

## 14. Regression QA Matrix

필수 조합:

- Free local clips quick export.
- Free Project tab access.
- Standard local-only Project edit/export.
- Standard cloud-only Project edit/export.
- Standard mixed local/cloud Project edit/export.
- Standard Cloud save success.
- Standard Cloud save failure.
- Standard subscription downgrade during edit.
- Premium-like dormant state normalized to Standard.
- Saved Project quality `4k` restored as `1080p`.

공통 확인:

- Project JSON 보존.
- Cloud metadata 보존.
- session cache path 미저장.
- Library local index 오염 없음.
- gallery album `MOA` 저장.
- fatal crash 없음.

## 15. 금지 사항

이 계획서 작성 범위와 후속 구현의 기본 금지사항은 다음과 같다.

- 승인 없는 코드 외 시스템 변경 금지.
- Firebase rules/index/schema 변경 금지.
- migration/backfill 금지.
- Storage physical delete 금지.
- Cloud copy 구현 금지.
- deploy 금지.
- 사용자 원본 영상, Project JSON, local index, Cloud metadata 삭제 금지.

# Video Edit Screen Policy v1

작성일: 2026-05-21

## 1. 목적

이 문서는 MOA의 `VideoEditScreen` 편집 정책을 고정한다. 편집화면은 Standard 구독의 핵심 기능이며, Free quick export, Cloud Clip 직접 편집, Project local/Cloud 저장, export 품질 정책이 같은 화면에서 만나는 영역이다.

이 문서는 정책 문서이며 코드 변경, Firebase rules/index/schema 변경, migration/backfill, Storage physical delete, Cloud copy 구현, deploy를 포함하지 않는다.

## 2. 보존 계약

다음 계약은 이 정책 문서로 변경하지 않는다.

- Flutter package name: `three_s`
- Android namespace/applicationId: `com.dk.three_sec`
- Firebase project alias: `fir-3s-8edb9`
- Firestore collections: `users`, `videos`, `vlog_projects`
- Storage prefix: `users/{uid}/videos/{videoId}/{fileName}`
- Local project JSON path: `vlog_projects/{projectId}.json`
- Legacy project/folder identifiers: `vlog_projects`, `vlog_folders`
- IAP product ids: `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual`

## 3. Tier Policy

### Free

- Free 사용자는 `VideoEditScreen`에 접근할 수 없다.
- Free 사용자는 선택 clip에 대해 quick `720p` export만 가능하다.
- Free 사용자는 Project를 저장할 수 없다.
- Free 경로에서 생성되는 임시 Project 객체는 export 입력으로만 사용하며 local project JSON, Cloud project metadata, Project list에 저장하지 않는다.

### Standard

- Standard 사용자는 `VideoEditScreen`에 접근할 수 있다.
- Standard 사용자는 Project local 저장과 Cloud 저장을 사용할 수 있다.
- Standard export 품질은 `720p`, `1080p`만 허용한다.
- Standard export 기본값은 `1080p`이다.
- Standard 사용자의 편집 중 Project는 기본적으로 local autosave와 Cloud autosave 대상이다.

### Premium

- Premium은 dormant compatibility tier로만 유지한다.
- 현재 런타임 권한은 Standard와 동일하게 normalize한다.
- Premium 전용 UI, Premium 전용 export 품질, Premium 전용 편집 기능은 노출하지 않는다.
- 기존 데이터 또는 과거 entitlement에서 Premium이 감지되어도 현재 제품에서는 Standard 권한으로 처리한다.

### 4K

- `4K`는 모든 UI, export, project restore 경로에서 `1080p`로 clamp한다.
- 저장된 Project에 `4k` 품질 값이 남아 있더라도 편집화면 진입, export dialog 초기화, export 실행 전 정책에서 `1080p`로 정규화한다.

## 4. Edit Feature Policy

공식 지원 기능:

- Trim
- Transform
- Brightness
- Sound
- Canvas

숨김/보류 기능:

- AI
- Filter
- Sticker
- Advanced caption

숨김/보류 기능 정책:

- 별도 승인 전까지 UI 진입점을 제공하지 않는다.
- 별도 승인 전까지 저장 필드 반영을 비활성 또는 무시한다.
- 별도 승인 전까지 export 결과에 반영하지 않는다.
- legacy 코드나 dormant 함수가 남아 있더라도 사용자가 접근 가능한 경로는 없어야 한다.
- 보류 기능을 다시 활성화하려면 별도 정책 문서, QA 범위, 저장/export 호환성 검토가 필요하다.

## 5. Cloud Clip Edit Policy

- Cloud-only clip은 `File Missing`이 아니다.
- Editor 진입 시 Cloud clip은 다음 상태로 분기한다.
  - `CloudResolving`: Cloud metadata와 source 준비 여부를 확인하는 중.
  - `CloudBuffering`: preview/edit에 필요한 session source를 materialize하는 중.
  - `CloudReady`: session source 준비가 끝나 preview/edit 가능한 상태.
  - `CloudFailed`: metadata 조회, 권한, 네트워크, Storage object, download 실패 등으로 준비하지 못한 상태.
- Cloud clip은 preview/edit 시 `edit_session_cache`에 임시 materialize해서 사용한다.
- Export 시 필요한 source는 `export_session_cache`에 별도 materialize한다.
- session cache path는 Project JSON에 저장하지 않는다.
- session cache path는 Library local index에 등록하지 않는다.
- Project에는 `cloud_only://...` placeholder 또는 cloud video id 참조만 저장한다.
- Cloud clip materialize는 사용자 Library 다운로드 UX가 아니다.
- Cloud clip materialize는 편집/export session 내부 구현 세부사항이며 Project의 원본 참조를 대체하지 않는다.

## 6. Save Policy

- Standard 편집은 local autosave와 Cloud autosave를 수행한다.
- Cloud save가 실패해도 local project는 보존한다.
- UI는 저장 상태를 표시해야 한다.
  - 저장 중
  - Cloud 저장 완료
  - Cloud 저장 실패
  - 재시도
- 닫기 전 pending autosave flush를 시도한다.
- autosave 실패는 조용히 무시하지 않고 로그와 UI 상태로 남긴다.
- local 저장 성공, Cloud 저장 실패 상태에서는 사용자의 편집 데이터 보존을 우선한다.
- session cache path guard는 유지한다. Project clip path에 `edit_session_cache`, `export_session_cache`, `cloud_clip_session_cache`가 포함되면 Project 저장 대상에서 제외하거나 저장을 차단한다.

## 7. Subscription Change Policy

- 편집 진입은 session start tier 기준으로 허용한다.
- 저장, Cloud write, export 직전에는 권한을 재확인한다.
- 편집 중 Free 또는 expired 상태가 되면 화면은 유지한다.
- 편집 중 Free 또는 expired 상태가 되면 Cloud save는 중단한다.
- 편집 중 Free 또는 expired 상태가 되면 local draft는 보존한다.
- 편집 중 Free 또는 expired 상태가 되면 export 품질은 `720p`로 clamp한다.
- 권한 변경으로 Cloud write가 중단된 경우 사용자에게 Cloud 저장 중단 상태를 표시한다.
- 권한 변경으로 export 품질이 clamp된 경우 export dialog 또는 preflight에서 명확히 알려야 한다.

## 8. Cache Cleanup Policy

- `edit_session_cache`와 `export_session_cache`는 Project 저장 대상이 아니다.
- 앱 시작, 편집 종료, export 종료 시 TTL 기반 정리를 수행한다.
- 진행 중 session cache는 삭제하지 않는다.
- 기본 TTL은 24시간으로 한다.
- TTL cleanup은 사용자 원본 clip, Project JSON, Cloud metadata, Library local index를 삭제하지 않는다.
- cleanup 대상은 session cache root 아래의 임시 materialized file로 제한한다.
- cleanup 실패는 사용자 작업을 막지 않되 로그로 남긴다.

## 9. Export Preflight Policy

Export 전 다음 preflight를 수행한다.

- Project 저장 시도.
- Cloud clip materialize 완료 확인.
- Cloud clip 포함 시 네트워크 필요 여부 안내.
- 저장공간 확인.
- 예상 export 용량 확인.
- materialize 실패 시 `Cloud Load Failed` 상태로 표시.
- local source missing과 Cloud materialize failed를 구분해서 표시.
- 취소 또는 실패 시 partial output 처리 규칙을 적용한다.

Partial output 처리 규칙:

- export가 완료되기 전 생성된 partial output은 gallery 등록 대상이 아니다.
- partial output은 session/temp output으로 취급한다.
- export 성공 후에만 gallery `MOA` album 등록을 시도한다.
- export 실패 또는 취소 시 partial output은 cleanup 대상이다.
- partial output 삭제 실패는 사용자 원본이나 Project를 삭제하지 않으며 로그만 남긴다.

## 10. Quality Policy

Export quality 정책은 `quality_policy.dart`에 중앙화한다.

필수 정책 API:

- `availableExportQualities(tier)`
- `defaultExportQuality(tier)`
- `maxExportQuality(tier)`
- `clampExportQuality(tier, requestedQuality)`

정책 결과:

- Free available: `720p`
- Free default: `720p`
- Free max: `720p`
- Standard available: `720p`, `1080p`
- Standard default: `1080p`
- Standard max: `1080p`
- Premium normalized available: `720p`, `1080p`
- Premium normalized default: `1080p`
- Premium normalized max: `1080p`
- Any `4k` request: `1080p`

## 11. QA 기준

필수 QA:

- Free 선택 clip quick export는 `720p`로 동작한다.
- Free는 `VideoEditScreen`에 접근하지 못한다.
- Free quick export 후 Project JSON과 Cloud project metadata가 생성되지 않는다.
- Standard는 `VideoEditScreen`에 접근 가능하다.
- Standard export dialog에는 `720p`, `1080p`만 보인다.
- Standard export dialog 기본 선택은 `1080p`이다.
- `4K`, `AI`가 편집화면 UI에 노출되지 않는다.
- Cloud-only clip이 `File Missing`으로 표시되지 않는다.
- Cloud clip preview/edit은 `edit_session_cache`를 사용한다.
- Cloud clip export는 `export_session_cache`를 사용한다.
- Project JSON에 session cache path가 저장되지 않는다.
- Cloud save 실패 시 local Project가 보존된다.
- 닫기 전 pending autosave flush가 시도된다.
- 편집 중 구독 만료 시 Cloud save가 중단되고 export는 `720p`로 clamp된다.

## 12. 금지 사항

이 정책 문서 작성 범위에서는 다음을 수행하지 않는다.

- 코드 변경 금지.
- Firebase rules/index/schema 변경 금지.
- migration/backfill 금지.
- Storage physical delete 금지.
- Cloud copy 구현 금지.
- deploy 금지.

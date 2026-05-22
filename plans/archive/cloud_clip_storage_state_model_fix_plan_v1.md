# Cloud/Device Clip Storage State Model Fix Plan v1

작성일: 2026-05-19

기준 문서: `plans/cloud_clip_storage_state_model_audit_v1.md`

범위:
- 코드 변경 없이 Cloud/Device clip 상태 모델 수정 계획을 작성한다.
- Firebase rules/index/schema, migration/backfill 실행, Storage 삭제, Cloud copy 구현, deploy는 수행하지 않는다.
- 사용자 원본 영상, 로컬 인덱스, Cloud metadata, 구독/계정 상태 보존을 최우선으로 한다.

## 1. Problem Statement

현재 R3 QA는 Cloud upload fixture 생성 단계에서 중단되어야 한다.

확인된 문제:
- 실제 local file 7개가 `cloud_synced_paths`에도 들어 있어 local-only로 분류되지 않는다.
- Profile의 `기기 CLIP 7 + Cloud CLIP 7`은 같은 논리 clip이 local file count와 Firestore completed count 양쪽에 잡힌 상태로 해석된다.
- Library upload 버튼은 selected set이 local-only일 때만 `cloud_upload_rounded`로 뜬다.
- 현재 clip들이 cloud-synced로 분류되면 upload 버튼이 아니라 download/restore 계열로 분기한다.
- `cloud_synced_paths`가 real local synced marker와 `cloud_only://` placeholder marker를 섞어 관리한다.

핵심 원인:
- 앱의 상태 모델이 "로컬 파일 존재 여부", "Cloud metadata 존재 여부", "Cloud-only placeholder 여부", "transfer 진행/실패 상태"를 명시적으로 분리하지 않는다.
- `isClipCloudSynced(path)`라는 단일 boolean이 badge, filter, button action을 모두 지배한다.
- Profile count label이 local file count와 Cloud completed doc count를 보여주지만, UI상 local-only/cloud-only 관계처럼 오해될 수 있다.

## 2. Intended ClipStorageState Model

명시적 상태 모델을 도입한다. 이 모델은 Firestore schema 변경 없이 앱 내부 derived state로 시작한다.

```dart
enum ClipStorageState {
  localOnly,
  pendingUpload,
  cloudSyncedLocal,
  cloudOnly,
  failedUpload,
  failedDownload,
}
```

상태 정의:

| State | Local file exists | Cloud metadata/object | Transfer state | 의미 |
| --- | --- | --- | --- | --- |
| `localOnly` | yes | no confirmed completed linkage | none | Standard에서 Cloud upload 가능 |
| `pendingUpload` | yes | queued/uploading may exist | pending upload | 신규 upload 진행 중 |
| `cloudSyncedLocal` | yes | confirmed completed Cloud linkage | none | 기기에도 있고 Cloud에도 있는 clip |
| `cloudOnly` | no | completed active Cloud metadata/object | none | Cloud 보관함에만 있으며 download/restore 가능 |
| `failedUpload` | yes | failed or no completed Cloud linkage | failed upload | upload 재시도 가능 후보 |
| `failedDownload` | no or incomplete local file | completed Cloud metadata/object may exist | failed download | download 재시도 가능 후보 |

중요 원칙:
- `기기 존재`와 `Cloud 존재`는 서로 배타적이지 않다.
- `localOnly`는 "기기에 있음"이 아니라 "기기에만 있음"이다.
- `cloudSyncedLocal`은 upload 대상이 아니다.
- `cloudOnly`는 upload 대상이 아니라 download/restore 대상이다.

## 3. Current Code Mapping

현재 로직 매핑:

| Current code | Current meaning | 문제 |
| --- | --- | --- |
| `recordedVideoPaths` | current album local `.mp4` + merged placeholders | local list와 cloud-only list가 같은 배열에 섞임 |
| `_cloudSyncedPaths` | synced local paths + `cloud_only://` placeholders | 서로 다른 상태를 한 set으로 관리 |
| `isClipCloudSynced(path)` | `_cloudSyncedPaths.contains(path)` | button/filter/badge의 과도한 단일 기준 |
| `cloud_only://...` | Cloud-only placeholder path | `_cloudSyncedPaths`에도 저장됨 |
| `getClipStatusBadge(path)` | placeholder, pending/failed, synced/local fallback | local file exists와 local-only를 구분하지 못함 |
| `isClipVisibleByStorageFilter(path, 'device')` | `!isClipCloudSynced && !cloud_only` | "기기"가 local-only 의미로 동작 |
| Profile `기기 CLIP` | local album `.mp4` count | local-only count가 아님 |
| Profile `Cloud CLIP` | Firestore completed count | cloud-only count가 아님 |

현재 코드의 보존해야 할 계약:
- local file path는 기존 로컬 데이터의 실제 위치다.
- `cloud_only://` placeholder는 Cloud metadata를 Library에 노출하기 위한 synthetic path다.
- `local_index_entries_v1`은 cloud metadata 필드를 이미 수용한다.
- Firestore `videos` 문서와 Storage object는 변경하지 않는다.

## 4. Proposed Derived State Algorithm

초기 구현은 새 영구 schema를 만들기보다 derived state helper를 추가하는 방식이 안전하다.

권장 API:

```dart
ClipStorageState getClipStorageState(String path);
bool isLocalFilePath(String path);
bool hasLocalFile(String path);
bool isCloudOnlyPlaceholder(String path);
VideoMetadata? getCloudMetadataForClipPath(String path);
bool hasCompletedCloudLink(String path);
```

Derived algorithm:

```text
if transferState == pendingUpload:
  return pendingUpload

if transferState == failedUpload:
  return failedUpload

if transferState == failedDownload:
  return failedDownload

if path starts with cloud_only://:
  return cloudOnly

localExists = File(path).existsSync()
cloudLink = hasCompletedCloudLink(path)

if localExists && cloudLink:
  return cloudSyncedLocal

if localExists && !cloudLink:
  return localOnly

if !localExists && cloudLink:
  return cloudOnly

return localOnly only if the path is a valid local clip path and exists;
otherwise exclude from visible clip model or mark as invalid/stale internally.
```

`hasCompletedCloudLink(path)`의 안전한 순서:
1. `_cloudMetadataByPath[path]` exists and metadata is active/completed.
2. local index entry for `pathOrKey == path` has `cloudVideoId` and active cloud state.
3. legacy `_cloudSyncedPaths.contains(path)` for real local path. This is compatibility fallback only.
4. Optional fallback lookup by Firestore `localPath == path`, if already available through cached metadata.
5. filename+size matching is only heuristic and should not silently mark local as synced unless the plan explicitly allows it.

`cloud_only://` placeholder state:
- Always `cloudOnly` unless a restore/download maps it to a real local path.
- Do not treat placeholder as a local file.
- Do not use placeholder membership in `_cloudSyncedPaths` to decide local clip uploadability.

## 5. Count Semantics

Counts must be explicitly named and derived from clear predicates.

| Count | Meaning | Source |
| --- | --- | --- |
| Device/local file count | local `.mp4` files present on device | album directories via `_updateAlbumClipCounts()` |
| Cloud active count | active completed Cloud docs | `CloudService.getCompletedVideoCount()` |
| Uploadable count | local file exists and state is `localOnly` or retryable `failedUpload` | derived state over local paths |
| Synced local count | local file exists and state is `cloudSyncedLocal` | derived state over local paths |
| Cloud-only count | state is `cloudOnly` | Cloud metadata placeholders not matched to local completed links |
| Pending upload count | state is `pendingUpload` | transfer state + sync queue/metadata |

Profile should avoid implying that Device and Cloud are disjoint sets.

Recommended labels:
- `기기 CLIP`: local files on this device
- `Cloud CLIP`: active Cloud clips
- optional diagnostic/debug label: `업로드 가능`
- optional diagnostic/debug label: `동기화됨`

If a production UI needs fewer labels, keep Profile as-is but update QA/debug reporting to include explicit derived counts.

## 6. Badge Semantics

Recommended badge mapping:

| State | Badge | Action hint |
| --- | --- | --- |
| `localOnly` | `기기` or `로컬만` | upload available for Standard |
| `pendingUpload` | `업로드 중` or `로딩중` | disabled/progress |
| `cloudSyncedLocal` | `동기화됨` | already in Cloud and on device |
| `cloudOnly` | `Cloud` | download/restore available |
| `failedUpload` | `업로드 실패` | retry upload |
| `failedDownload` | `복원 실패` | retry restore |

Preferred wording change:
- Keep `기기` only if it means "exists on device".
- Use `로컬만` for uploadable local-only.

This avoids the current ambiguity where `기기` filter means "not cloud synced", while Profile `기기 CLIP` means "local file count".

## 7. Library Filter Semantics

Current `기기` filter behaves like local-only. This conflicts with Profile `기기 CLIP`.

Recommended filter model:

| Filter | Predicate | User meaning |
| --- | --- | --- |
| `전체` | all valid local files + visible cloud-only placeholders | all library entries |
| `기기` | local file exists: `localOnly`, `pendingUpload`, `cloudSyncedLocal`, `failedUpload` | clips available on device |
| `로컬만` or `업로드 가능` | `localOnly` or retryable `failedUpload` | can upload to Cloud |
| `Cloud` | `cloudSyncedLocal` + `cloudOnly` + pending/failed Cloud-linked states | clips with Cloud presence |
| `Cloud만` optional | `cloudOnly` | needs restore for local playback |
| `하트만` | favorite overlay filter | independent of storage state |

Minimal safer change:
- Keep visible UI filters as `전체`, `기기`, `하트만`.
- Change `기기` to mean local file exists.
- Add hidden/debug or later visible `업로드 가능` filter for R3 QA.

If product wants `기기` to mean local-only, rename the Profile count or filter to remove ambiguity.

## 8. Transfer Button Semantics

Selection action should be based on derived states, not raw `isClipCloudSynced`.

Recommended selection reducer:

```text
states = selectedPaths.map(getClipStorageState)

if all states are localOnly:
  action = upload
  icon = cloud_upload_rounded
  enabled = signed-in && canStartNewCloudWrite

else if all states are failedUpload:
  action = retry upload
  icon = cloud_upload_rounded
  enabled = signed-in && canStartNewCloudWrite

else if all states are cloudOnly:
  action = download/restore
  icon = download_rounded
  enabled = signed-in && canReadExistingCloudClips

else if all states are cloudSyncedLocal:
  action = disabled or cloud management
  icon = cloud_done_rounded
  enabled = false

else if any pendingUpload:
  action = disabled
  icon = sync
  enabled = false

else if mixed localOnly + failedUpload:
  action = upload/retry upload
  icon = cloud_upload_rounded
  enabled = signed-in && canStartNewCloudWrite

else:
  action = disabled
  icon = download_for_offline_rounded or info
  enabled = false
```

Important behavior:
- `cloudSyncedLocal` must not show download as the primary transfer action, because the file is already on device.
- `cloudOnly` should show download/restore.
- `localOnly` should show upload.
- Mixed local/cloud selections should be disabled with an explanatory toast instead of silently using a misleading icon.

## 9. cloud_synced_paths Refactor Strategy

Goal: reduce `cloud_synced_paths` from a broad state source to a legacy compatibility input.

Recommended new internal concepts:

| Concept | Persistence | Notes |
| --- | --- | --- |
| `cloud_synced_local_paths` | optional SharedPreferences string list | real local paths confirmed to have completed Cloud upload |
| `cloud_only_placeholders` | preferably derived, not persisted | created from Cloud metadata pull |
| `local_index_entries_v1.cloudVideoId` | existing local index fields | use as stable local-to-cloud linkage |
| transfer UI state | memory or existing local queue metadata | pending/failed display |

Migration-safe strategy:
1. Keep reading existing `cloud_synced_paths`.
2. When loading legacy entries:
   - entries starting `cloud_only://` go to placeholder compatibility cache only.
   - entries with existing local file paths go to synced-local compatibility cache.
   - stale local paths are ignored, preserving current cleanup behavior.
3. Do not immediately delete `cloud_synced_paths`.
4. Write both old and new keys for one release if a new key is introduced.
5. After stabilization, stop writing placeholders to `cloud_synced_paths`.
6. Later, stop relying on `cloud_synced_paths` for derived state except as legacy fallback.

Do not run a destructive migration/backfill. Let app startup derive and lazily normalize state.

## 10. Backward Compatibility / Migration Safety

Safety rules:
- Never delete local media files as part of this refactor.
- Never delete Storage objects or Firestore docs as part of this refactor.
- Never change Firestore schema/rules/index for this phase.
- Do not clear `cloud_synced_paths` globally.
- Do not assume filename+size match proves identity without a fallback path for mistakes.

Compatibility behavior:
- Existing synced local paths continue to show `cloudSyncedLocal`.
- Existing `cloud_only://` placeholders continue to show `cloudOnly`.
- Existing restored clips with local index Cloud metadata remain synced.
- Existing local-only clips not in any Cloud marker remain uploadable.

Risk handling:
- If a legacy local path is in `cloud_synced_paths` but no Cloud metadata can be found, classify as `cloudSyncedLocalLegacy` internally or `cloudSyncedLocal` with a debug warning first. Do not downgrade to localOnly automatically without a deliberate repair plan, because that can trigger duplicate uploads.
- Add a non-destructive repair report before any cleanup:
  - legacy synced local count
  - legacy placeholder count
  - missing metadata linkage count
  - filename+size match count
  - stale marker count

## 11. R3 QA Fixture Recovery Plan

R3 QA should resume only with a verified local-only fixture.

Verified local-only fixture conditions:
- signed-in manual Google login state exists.
- active paid state is loaded in app memory.
- local file exists in a normal album, not Trash.
- path is not `cloud_only://`.
- path is not in legacy `cloud_synced_paths`.
- local index entry for the path has no `cloudVideoId`.
- no cached `_cloudMetadataByPath[path]`.
- no Firestore completed video doc is linked to the local path.
- filename+size heuristic does not match an active Cloud doc, or if it does, QA records it as not a safe fixture.
- badge/state resolves to `localOnly`.
- selecting only that clip yields upload action with `cloud_upload_rounded`.

Fixture creation options, in preferred order:
1. User records/imports a new clip while app is temporarily Free or Cloud write disabled, then returns to active Standard. This is closest to intended policy but requires careful state setup.
2. QA-only local media import into app normal album, with no `cloud_synced_paths` or local index Cloud metadata. No Cloud write should occur before verification.
3. If using an existing local file, first perform read-only evidence that it is absent from Cloud linkage. Do not mutate state to make it local-only unless explicitly approved.

R3 resume gate:
- derived count reports `uploadable_count >= 1`.
- selected fixture state is `localOnly`.
- upload button visible and mapped to upload action.
- app-controlled sensitive log gate remains clean.

## 12. Implementation Phases

### Phase 0: Read-only diagnostics

Deliverables:
- Add no product behavior changes.
- Add or run count-only diagnostics in QA docs:
  - local file count
  - active Cloud doc count
  - local-only derived count
  - synced local derived count
  - cloud-only placeholder count
  - pending/failed counts

Exit criteria:
- Current ambiguous 7/7 state can be explained by derived counts.

### Phase 1: Derived state helper

Deliverables:
- Add `ClipStorageState` enum.
- Add `getClipStorageState(path)` and helper predicates.
- Do not change UI behavior yet except optional debug logs/tests.

Exit criteria:
- Unit tests cover localOnly, cloudSyncedLocal, cloudOnly, pending/failed states.
- Legacy `cloud_synced_paths` behavior remains compatible.

### Phase 2: Badge/filter/button refactor

Deliverables:
- Convert badge logic to `ClipStorageState`.
- Convert Library filter predicates to explicit semantics.
- Convert transfer button reducer to derived state.
- Keep labels conservative if product copy is not finalized.

Exit criteria:
- localOnly selection shows upload.
- cloudOnly selection shows restore/download.
- cloudSyncedLocal selection does not masquerade as uploadable local-only.
- mixed selection is disabled with clear reason.

### Phase 3: Count semantics and Profile copy

Deliverables:
- Keep `기기 CLIP` as local file count or rename it.
- Keep `Cloud CLIP` as active Cloud doc count.
- Add optional uploadable/synced debug counts for QA.

Exit criteria:
- QA can distinguish local file count from uploadable count.
- Product text does not imply Device and Cloud counts are disjoint.

### Phase 4: Persistence split

Deliverables:
- Introduce new preference key only if needed.
- Stop writing `cloud_only://` placeholders into broad synced-local markers.
- Keep reading legacy key.

Exit criteria:
- No user data loss.
- No duplicate upload caused by marker migration.
- Stale markers are reported, not destructively removed beyond existing safe cleanup.

### Phase 5: R3 QA resume

Deliverables:
- Create verified local-only fixture.
- Run Cloud upload fixture capture.
- Collect Firestore/Storage before-after evidence.

Exit criteria:
- R3 upload path exercises `uploadVideoImmediate` or intended queue path.
- upload success changes fixture state from `localOnly` to `cloudSyncedLocal`.

## 13. Test Plan

### Unit tests

Add focused tests around state derivation:
- local file exists, no marker, no metadata => `localOnly`
- local file exists, legacy marker exists => `cloudSyncedLocal`
- path starts `cloud_only://`, metadata exists => `cloudOnly`
- pending upload transfer state wins over local-only/synced markers => `pendingUpload`
- failed upload transfer state => `failedUpload`
- failed download transfer state => `failedDownload`
- stale marker with no local file and not placeholder is ignored or reported
- placeholder is not counted as local file

### Widget/logic tests

Test Library selection reducer:
- all localOnly => upload icon/action
- all cloudOnly => download icon/action
- all cloudSyncedLocal => disabled/cloud done action
- mixed localOnly/cloudOnly => disabled
- pendingUpload selected => disabled/progress
- Standard false hides or disables Cloud transfer according to chosen UI contract
- Standard true + expired write gate shows blocked toast for uploadable state

### Integration/manual QA

Manual scenarios:
- Free import/record creates localOnly and no Cloud access.
- Standard import/record auto uploads and transitions pendingUpload -> cloudSyncedLocal.
- Existing localOnly under Standard can be manually uploaded.
- Cloud-only placeholder can be restored and transitions to cloudSyncedLocal.
- Expired within grace allows Cloud read/restore but blocks new upload.
- Expired after grace blocks Cloud read/restore and upload.

### Non-regression checks

Required checks:
- No local media deletion.
- No Storage deletion.
- No Firestore schema/rules/index changes.
- No duplicate Cloud upload for already synced local clips.
- Existing CloudBackupScreen download flow still works.
- Profile counts remain stable or copy change is documented.

## 14. Go/No-Go Criteria

### Go for implementation

GO if:
- Team accepts that `기기 CLIP` means local file count, not local-only count, or approves label/filter copy changes.
- Derived state helper can be added without Firestore schema/rules/index changes.
- Legacy `cloud_synced_paths` can be read as compatibility input without destructive migration.
- Tests can cover state derivation and transfer button reducer.

### No-Go for implementation

NO-GO if:
- Product requires destructive cleanup of existing `cloud_synced_paths` without a backup/repair report.
- Product requires Firestore schema or Storage path changes in the same phase.
- Existing synced local clips would be reclassified as localOnly and risk duplicate upload.
- R3 QA demands continuation against the current 7 clips without a verified local-only fixture.

### Go for R3 QA resume

GO only when:
- `uploadable_count >= 1`.
- fixture path is verified localOnly by derived state.
- selected fixture shows upload action.
- active paid state is loaded in app memory.
- app-controlled sensitive log gate remains clean.

Current verdict:
- NO-GO for R3 upload fixture QA against the current 7 clips.
- GO for a scoped implementation plan/review of derived `ClipStorageState` before any code changes.

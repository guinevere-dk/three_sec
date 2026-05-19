# Cloud Clip R4 Migration/Backfill Inventory Dry-run Report v1

## 1. 작업 범위와 금지선

R4 migration/backfill은 실제 보정이 아니라 운영자가 명시 실행하는 read-only inventory dry-run 도구와 보고서 작성으로만 수행했다. 이번 작업은 기존 `users`, `videos`, `vlog_projects`, 선택적 `vlog_folders` 문서의 field 분포를 익명 집계하고, 누락/legacy/비정상 상태를 reason code로 분류하며, 최소 backfill 후보를 “제안 목록”으로만 산출하는 범위에 한정한다.

금지선 준수:

- Firestore 문서 생성/수정/삭제 없음.
- batch update/backfill 실행 코드 없음.
- fallback 제거 없음.
- Firebase rules/index 변경 없음.
- Storage 객체 접근/삭제/경로 변경 없음.
- `videos`, `users`, `vlog_projects`, `vlog_folders` 컬렉션명 rename/change 없음.
- 실제 `uid`, document id, `storagePath`, fileName 원문을 report/manifest에 기록하지 않음.

## 2. 변경/생성 파일

| 파일 | 내용 |
|---|---|
| `functions/scripts/cloud_clip_r4_migration_backfill_inventory.js` | 운영자 명시 실행용 R4 read-only inventory dry-run 스크립트. Firestore 또는 fixture를 읽고 JSON report만 생성한다. |
| `functions/package.json` | `cloud-clip:r4-inventory-dry-run` npm script 추가. 의존성 및 lockfile 변경 없음. |
| `tools/cloud_clip_r4_migration_backfill_inventory_fixture.json` | 누락/legacy/비정상 상태 reason code 검증용 fixture. |
| `tools/cloud_clip_r4_migration_backfill_inventory_zero_fixture.json` | backfill 후보 0건 summary 검증용 fixture. |
| `plans/cloud_clip_r4_migration_backfill_inventory_report_v1.md` | 구현 방식, 실행 방법, schema, 후보 산출 방식, rollout/rollback, 검증 결과 보고서. |

## 3. 근거 파일 요약

| 근거 파일 | 반영한 기준 |
|---|---|
| `AGENTS.md` | 사용자 데이터 보존, 기존 기능 유지, 레거시 호환 우선. migration/backfill은 dry-run과 승인 gate 우선. |
| `CURRENT_PHASE.md` | DB migration/backfill은 승인 필요. 이번 작업은 inventory dry-run과 문서화로 제한. |
| `DATA_COMPATIBILITY.md` | `users`, `videos`, `vlog_projects`, Storage `users/{uid}/videos/{videoId}/{fileName}` 계약 유지. 필드 rename 금지. |
| `plans/cloud_clip_policy_decision_v1.md` | 기존 사용자 문서 mutation 금지, inventory dry-run 선행, staged rollout 전 fallback 유지. |
| `plans/cloud_clip_remaining_risk_resolution_plan_v1.md` | R4는 기존 `videos` field 분포 확인 후 read fallback으로 충분한 문서는 migration하지 않음. |
| `plans/cloud_clip_deferred_items_execution_guide_v1.md` | R4 대상 field, 익명 집계, 최소 backfill, staged rollout, rollback 원칙. |
| `plans/cloud_clip_r2_storage_delete_dry_run_inventory_report_v1.md` | 운영자 명시 실행 스크립트, fixture 검증, JSON manifest/report, 개인정보 최소화 구조를 재사용. |
| `functions/scripts/cloud_clip_delete_dry_run_inventory.js` | R2 dry-run의 no-mutation 안전 계약, CLI option, hash 중심 출력 방식 참고. |
| `functions/package.json` | Node 20와 `firebase-admin` 사용 가능. lockfile 변경 없이 npm script만 추가. |
| `lib/services/cloud_service.dart` | 실제 사용 field: `storagePath`, `lifecycleState`, `cloudState`, `originalStoragePath`, `originalStorageTier`, `storageTier`, upload/status/timestamp 및 `vlog_projects` metadata 확인. |
| `lib/models/vlog_project.dart` | project/folder 연결 field: `folderName`, `ownerAccountId`, `cloudProjectId`, `cloudSyncedAt` 확인. |
| `lib/services/local_index_service.dart` | local index cloud shadow field: `cloudStorageTier`, `cloudState`, `cloudFileName` 확인. |

## 4. 구현 방식

### 4.1 실행 형태

Cloud Functions endpoint를 추가하지 않고 `functions` 패키지의 운영 스크립트로 구현했다.

이유:

1. Flutter 앱이나 HTTP endpoint에서 자동 실행될 위험을 제거한다.
2. 운영자가 명시 실행할 때만 Firebase read가 발생한다.
3. fixture mode로 실제 Firebase 접근 없이 reason code와 summary를 검증할 수 있다.
4. mutation/backfill execute와 inventory dry-run을 물리적으로 분리한다.

### 4.2 실행 명령

도움말:

```bash
cd functions
npm run cloud-clip:r4-inventory-dry-run -- --help
```

로컬 fixture 검증:

```bash
cd functions
npm run cloud-clip:r4-inventory-dry-run -- --fixture ../tools/cloud_clip_r4_migration_backfill_inventory_fixture.json --include-folders --out-dir ../logs
```

후보 0건 fixture 검증:

```bash
cd functions
npm run cloud-clip:r4-inventory-dry-run -- --fixture ../tools/cloud_clip_r4_migration_backfill_inventory_zero_fixture.json --out-dir ../logs
```

운영 Firebase read-only inventory 예시:

```bash
cd functions
npm run cloud-clip:r4-inventory-dry-run -- --include-folders --out-dir ../logs
```

운영 샘플링 예시:

```bash
cd functions
npm run cloud-clip:r4-inventory-dry-run -- --include-folders --limit 1000 --out-dir ../logs
```

기본 report 출력 경로:

```text
logs/cloud_clip_r4_migration_backfill_inventory_<timestamp>_<random>.json
```

## 5. Inventory report schema

최상위 구조:

| 필드 | 설명 |
|---|---|
| `reportId` | `cloud_clip_r4_migration_backfill_inventory_*` 형식의 report 식별자. |
| `generatedAt` | 생성 시각. |
| `dryRun` | 항상 `true`. |
| `queryVersion` | inventory schema/query version. |
| `environment` | Node/platform, fixture mode, `includeFolders`, `limit`. |
| `policy` | mutation 금지와 write/batch/fallback/rename/path 변경 count 0 선언. |
| `summary` | collection별 scan count, 익명 uid/storagePath hash count, reason summary, candidate reason count. |
| `fieldDistribution` | collection별 field 존재/누락/null-or-empty/type/value 분포. |
| `fieldCombinationSummary` | `videos`의 `storagePath`/tier/lifecycle/cloud/trash 조합별 count. |
| `anomalies` | reason code가 있는 문서의 hash 중심 샘플. 최대 200개. |
| `backfillCandidateList` | 실제 수정 목록이 아닌 최소 field 제안 목록. |
| `stagedRolloutPlan` | future write 전 단계적 rollout 원칙. |
| `rollbackPlan` | 현재 dry-run no-op 및 future mutation 전 rollback 원칙. |

익명화 기준:

- `uid`는 `uidHash` 또는 count로만 기록한다.
- document id는 `documentIdHash`로만 기록한다.
- `storagePath`는 `storagePathHash`와 prefix 정합성 reason code로만 기록한다.
- fileName/localPath/downloadUrl 원문은 기록하지 않는다.

## 6. 집계 대상 field

### 6.1 `videos`

주요 field:

- `uid`, `videoId`, `fileName`, `storagePath`, `storageTier`.
- `lifecycleState`, `cloudState`, `originalStoragePath`, `originalStorageTier`.
- `localPath`, `albumName`, `isFavorite`, `fileSize`, `uploadStatus`, `uploadProgress`, `downloadUrl`.
- `createdAt`, `updatedAt`, `completedAt`, `trashed`, `trashedAt`, `trashedFromAlbumName`, `originalAlbumName`, `restoredAt`, `deleted`, `errorCode`, `errorCopy`.

### 6.2 `vlog_projects`

주요 field:

- `uid`, `localProjectId`, `title`, `clipPaths`, `clipCount`, `folderName`, `lockState`.
- `clientCreatedAt`, `clientUpdatedAt`, `lastSyncedAt`, `deleted`.
- 실제 코드에서 관찰되는 연결 후보 `cloudProjectId`, `ownerAccountId`도 분포만 집계한다.

### 6.3 `users`

주요 field:

- `subscriptionTier`, `storageUsage`, `lastUpdated`.
- 구독 전환 계열 후보 `nextTierEffectiveAt`, `nextUserTier`, `productId`, `purchaseDate`.

### 6.4 `vlog_folders`

현재 Dart/Firebase Cloud metadata 코드에서 원격 `vlog_folders` 사용은 확인되지 않았고, local directory명으로 사용된다. 다만 사용자 지시상 기존 계약 컬렉션 후보로 보수적으로 포함할 수 있도록 `--include-folders` 옵션을 제공한다.

주요 field:

- `uid`, `folderName`, `name`, `ownerAccountId`, `createdAt`, `updatedAt`, `deleted`.

## 7. Reason code 분류

| reason code | 의미 | backfill 후보 여부 |
|---|---|---|
| `missing_storage_tier_with_storage_path` | `storagePath`가 있으나 `storageTier`/`originalStorageTier`가 모두 없음. | 후보 |
| `missing_lifecycle_state` | `lifecycleState` 없음. | 후보 |
| `missing_cloud_state` | `cloudState` 없음. | 후보 |
| `legacy_local_only_without_cloud_state` | legacy local/cloud 상태를 보수적으로 판정해야 하는 문서. | 조건부 후보 아님, fallback 우선 |
| `storage_path_owner_mismatch` | `storagePath`의 uid와 metadata `uid` 불일치. | 후보 아님, 수동 조사 |
| `storage_path_video_id_mismatch` | `storagePath`의 videoId와 metadata videoId/doc id 불일치. | 후보 아님, 수동 조사 |
| `storage_path_invalid_prefix` | Storage path 계약 prefix 불일치. | 후보 아님, 수동 조사 |
| `trash_missing_original_storage_path` | trash/tombstone 상태에서 `originalStoragePath` 없음. | 후보 |
| `trash_missing_original_storage_tier` | trash/tombstone 상태에서 `originalStorageTier` 없음. | 후보 |
| `timestamp_missing` | 필수 timestamp 계열 없음. | 후보 아님, fallback/수동 판단 |
| `timestamp_invalid` | timestamp parse 불가. | 후보 아님, 수동 조사 |
| `unknown_cloud_state` | 알려진 `cloudState` set 밖의 값. | 후보 아님, 코드/데이터 조사 |
| `unknown_lifecycle_state` | 알려진 `lifecycleState` set 밖의 값. | 후보 아님, 코드/데이터 조사 |
| `file_size_invalid` | `fileSize`가 음수 또는 숫자로 해석 불가. | 후보 아님, Storage metadata 대조 필요 |
| `owner_uid_missing` | owner uid 없음. | 후보 아님, 자동 추론 금지 |
| `project_ref_missing` | project 연결에 필요한 `localProjectId` 없음. | 후보 |
| `folder_ref_missing` | `folderName` 또는 folder collection 참조 불명확. | 후보 |
| `clip_paths_missing_or_invalid` | `clipPaths` 배열 없음/비정상. | 후보 아님, 수동 조사 |
| `clip_count_missing_or_invalid` | `clipCount` 없음/비정상. | 후보 아님, 수동 조사 |
| `clip_count_mismatch` | `clipPaths.length`와 `clipCount` 불일치. | 후보 아님, 수동 조사 |
| `subscription_tier_missing` | user 구독 tier 없음. | R4 clip backfill 후보 아님 |
| `storage_usage_invalid` | user storage usage 음수/비정상. | R4 clip backfill 후보 아님 |

## 8. Backfill candidate list 산출 방식

`backfillCandidateList`는 “수정 실행 목록”이 아니라 reason summary 기반 “제안 목록”이다. 각 항목은 다음을 포함한다.

- `reasonCode`.
- `affectedAnonymousDocCount`.
- `proposedMinimalFields`.
- `rationale`.
- `risk`.
- `fallbackAvailable`.
- `stagedRolloutRequired`.
- `execution: proposal_only_no_write_code`.

최소 후보 원칙:

1. 기존 field를 덮어쓰지 않고 missing/null/empty field만 future 후보로 둔다.
2. Storage path, collection명, document id, uid 계약은 변경하지 않는다.
3. 추론 불확실 또는 mismatch reason은 backfill하지 않고 수동 조사로 분리한다.
4. read fallback으로 충분한 문서는 migration하지 않는다.
5. future write가 필요해도 별도 승인, export, feature flag, sample cohort, rollback manifest 없이는 실행하지 않는다.

현재 스크립트가 후보로 제안하는 최소 field:

| reason code | 최소 field | 위험도 | fallback 가능 |
|---|---|---|---|
| `missing_storage_tier_with_storage_path` | `storageTier` | medium | 가능 |
| `missing_lifecycle_state` | `lifecycleState` | medium | 가능 |
| `missing_cloud_state` | `cloudState` | medium | 가능 |
| `trash_missing_original_storage_path` | `originalStoragePath` | high | 제한적/불가 |
| `trash_missing_original_storage_tier` | `originalStorageTier` | high | 제한적/불가 |
| `project_ref_missing` | `localProjectId` | high | 가능하나 추론 주의 |
| `folder_ref_missing` | `folderName` | medium | 가능 |

## 9. Staged rollout plan

현재 단계는 dry-run only이므로 실제 rollout은 없다. future backfill이 별도 승인될 경우 권장 순서는 다음과 같다.

1. no-op/dry-run report만 리뷰한다.
2. fixture와 emulator/test project에서 write preview 이전 검증을 완료한다.
3. 운영 데이터는 anonymous hash bucket 기반 sample cohort만 먼저 선정한다.
4. write는 기본 disabled이며 명시 feature flag로만 열 수 있게 한다.
5. write 전 대상 문서와 변경 예정 field의 기존 값을 export한다.
6. 기존 non-empty field는 절대 overwrite하지 않고 missing/null/empty field만 후보로 둔다.
7. 작은 batch 단위로 실행하고 batch마다 Library placeholder, Trash/restore, usage count, old/new client read를 검증한다.
8. anomaly count가 증가하거나 mismatch reason이 발견되면 즉시 중단한다.
9. dual-read fallback은 전체 rollout과 rollback 검증 후에도 일정 기간 유지한다.

## 10. Rollback plan

현재 작업은 no-op/dry-run이므로 데이터 rollback이 필요 없다.

future mutation 전 rollback 기준:

1. 모든 변경 예정 문서의 기존 값과 없던 field 여부를 manifest/export에 기록한다.
2. 새로 추가한 optional field는 rollback 시 제거 가능해야 한다.
3. 기존 field를 덮어쓰는 방식은 금지한다. 덮어쓰기 발생 시 rollback 난이도가 급격히 증가한다.
4. feature flag를 즉시 disable하고 미실행 batch를 중단할 수 있어야 한다.
5. rollback 후 old/new client read, Library count, Cloud placeholder, Trash/restore, usage count를 검증한다.
6. fallback 제거는 rollback 완료와 별개로 금지하며, staged rollout 안정화 후 별도 승인 대상으로 둔다.

## 11. 검증 명령과 결과

실행한 검증:

```bash
cd functions && node --check scripts/cloud_clip_r4_migration_backfill_inventory.js
```

결과:

- Node 문법 검증 성공.
- Firestore write/batch update/fallback 제거 코드 없음.

```bash
cd functions && npm run cloud-clip:r4-inventory-dry-run -- --fixture ../tools/cloud_clip_r4_migration_backfill_inventory_fixture.json --include-folders --out-dir ../logs
```

결과:

- fixture 기반 report 생성 성공.
- scan count: `users=2`, `videos=5`, `vlog_projects=2`, `vlog_folders=1`.
- reason summary에 누락/legacy/비정상 상태가 분류됨.
- 주요 분류: `missing_storage_tier_with_storage_path=2`, `missing_lifecycle_state=1`, `missing_cloud_state=1`, `storage_path_owner_mismatch=1`, `trash_missing_original_storage_path=1`, `trash_missing_original_storage_tier=1`, `unknown_cloud_state=1`, `timestamp_invalid=3`, `project_ref_missing=1`, `folder_ref_missing=1`.
- backfill candidate reason count: `7`.
- 생성 report: `logs/cloud_clip_r4_migration_backfill_inventory_2026-05-15T10-24-59-220Z_738710e7.json`.

```bash
cd functions && npm run cloud-clip:r4-inventory-dry-run -- --fixture ../tools/cloud_clip_r4_migration_backfill_inventory_zero_fixture.json --out-dir ../logs
```

결과:

- 후보 0건 fixture report 생성 성공.
- scan count: `users=1`, `videos=1`, `vlog_projects=1`, `vlog_folders=0`.
- reason summary: `{}`.
- backfill candidate reason count: `0`.
- 생성 report: `logs/cloud_clip_r4_migration_backfill_inventory_2026-05-15T10-24-59-603Z_66c88b54.json`.

## 12. 미검증 사유

실제 Firebase 운영 프로젝트 접근은 수행하지 않았다. 현재 작업 지시는 실제 mutation 금지를 최우선으로 두고 있으며, 운영 Firebase Admin 자격증명과 운영 데이터 read 승인 범위가 제공되지 않았다. 따라서 fixture 기반 reason 분류, 후보 0건 summary, 문법 검증으로 대체했다.

## 13. 남은 리스크와 후속 승인 필요 항목

1. 운영 inventory 실행 전 Admin 자격증명의 read-only 운영 절차와 접근 통제를 확인해야 한다.
2. 운영 report는 hash 중심이지만, 운영자가 원본 대조를 수행할 경우 별도 안전 채널과 권한 통제가 필요하다.
3. `storage_path_owner_mismatch`, `storage_path_invalid_prefix`, `timestamp_invalid`, `unknown_cloud_state`, `file_size_invalid`는 자동 backfill 후보가 아니라 수동 조사 대상이다.
4. 실제 backfill write 도구는 이번 범위에 포함하지 않았으며, 별도 승인/계획/검증/rollback manifest 이후에만 설계할 수 있다.
5. `vlog_folders`는 현재 코드에서 원격 collection 사용이 명확하지 않아 기본 운영 실행에서는 옵션으로 분리했다. 실제 사용 여부가 확인되기 전 rename/change 없이 read-only 관찰만 허용한다.
6. fallback 제거는 이번 작업과 후속 backfill 모두에서 별도 승인 전까지 금지한다.

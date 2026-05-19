# Cloud Clip R2 Storage Delete Dry-run Inventory Report v1

## 1. 작업 범위

R2 Storage deletion은 실제 삭제가 아니라 운영자가 명시 실행하는 dry-run inventory로만 구현했다. 이번 작업은 Storage 객체와 Firestore `videos` metadata를 read-only로 대조하고, 삭제 후보 manifest를 로컬 `logs/` 디렉터리에 JSON 파일로 생성하는 범위에 한정한다.

금지선 준수:

- Storage `deleteObject` 또는 `delete()` 호출 없음.
- Firestore 문서 생성/수정/삭제 없음.
- `users/{uid}.storageUsage` 또는 `users/{uid}/usageEvents/{eventId}` mutation 없음.
- Firebase rules/index 변경 없음.
- Flutter 앱 자동 실행 경로에 연결하지 않음.

## 2. 변경/생성 파일

| 파일 | 내용 |
|---|---|
| `functions/scripts/cloud_clip_delete_dry_run_inventory.js` | 운영자 명시 실행용 dry-run inventory 스크립트. Storage 객체와 Firestore `videos` metadata를 읽고 manifest JSON만 생성한다. |
| `functions/package.json` | `cloud-clip:delete-dry-run` npm script 추가. 의존성 변경 없음. |
| `tools/cloud_clip_delete_dry_run_fixture.json` | 로컬 안전 검증용 fixture. 실제 Firebase 자격증명 없이 dry-run manifest 생성 확인 가능. |
| `plans/cloud_clip_r2_storage_delete_dry_run_inventory_report_v1.md` | 구현 방식, 실행 방법, manifest schema, 검증 결과 보고서. |

## 3. 근거 파일 요약

| 근거 파일 | 반영한 기준 |
|---|---|
| `AGENTS.md` | 사용자 데이터 보존, 기존 기능 유지, 레거시 호환 우선. 삭제/마이그레이션은 dry-run과 승인 gate 우선. |
| `CURRENT_PHASE.md` | Storage schema/path/rules, purge, 사용자 데이터 삭제는 승인 필요. 이번 작업은 운영 dry-run 도구로 제한. |
| `DATA_COMPATIBILITY.md` | `videos`, `users`, `users/{uid}/videos/{videoId}/{fileName}` 계약 유지. 삭제는 소유권 확인과 usage 차감 멱등성 검토 필요. |
| `plans/cloud_clip_policy_decision_v1.md` | 현재 단계 실제 삭제 금지, dry-run inventory만 허용, manifest에 object path/owner/project/reason/expected delta 포함. |
| `plans/cloud_clip_remaining_risk_resolution_plan_v1.md` | R2 safety gate: uid 소유권, Storage prefix, pending 제외, dry-run 후 수동 승인. |
| `plans/cloud_clip_deferred_items_execution_guide_v1.md` | R2 inventory query, manifest 필드, 개인정보 최소화, execute 분리 원칙. |
| `functions/index.js` | 기존 Functions는 social/IAP HTTP handler 중심. R2는 앱/HTTP 자동 실행 endpoint가 아니라 운영 스크립트 방식이 안전. |
| `functions/package.json` | Node 20, firebase-admin 사용 가능. lockfile 변경 없이 npm script만 추가. |
| `firebase/README.md` | 현재 Firebase Storage/Firestore 계약과 `videos` metadata 구조 확인. |

## 4. 구현 방식

### 4.1 실행 형태

Cloud Functions HTTP/callable endpoint를 추가하지 않고, `functions` 패키지의 운영 스크립트로 구현했다. 이유는 다음과 같다.

1. Flutter 앱 사용 중 자동 실행될 위험을 제거한다.
2. Cloud Functions 런타임 파일 시스템 영속성 제약을 피하고 저장소 로컬 `logs/` manifest 파일을 명확히 생성한다.
3. 실제 delete execute와 endpoint 노출을 이번 범위에서 분리한다.

### 4.2 실행 명령

실제 Firebase 자격증명이 있는 운영 환경:

```bash
cd functions
npm run cloud-clip:delete-dry-run -- --retention-days 90 --prefix users/
```

명시 bucket 사용:

```bash
cd functions
npm run cloud-clip:delete-dry-run -- --bucket your-bucket-name --retention-days 90 --prefix users/
```

로컬 fixture 검증:

```bash
cd functions
npm run cloud-clip:delete-dry-run -- --fixture ../tools/cloud_clip_delete_dry_run_fixture.json --cutoff 2026-03-01T00:00:00.000Z
```

도움말:

```bash
cd functions
npm run cloud-clip:delete-dry-run -- --help
```

기본 manifest 출력 경로:

```text
logs/cloud_clip_delete_dry_run_<timestamp>_<random>.json
```

## 5. Manifest schema

최상위 구조:

| 필드 | 설명 |
|---|---|
| `manifestId` | `cloud_clip_delete_dry_run_*` 형식의 manifest 식별자. |
| `generatedAt` | 생성 시각. |
| `dryRun` | 항상 `true`. |
| `queryVersion` | dry-run query/schema 버전. |
| `environment` | Node/platform, fixture mode, bucket, prefix. |
| `policy` | retention, cutoff, mutation 금지, delete/write 호출 수 0. |
| `approval` | execute 전 수동 승인 placeholder. 기본 null. |
| `summary` | 후보/검토/제외 count와 예상 usage 차감량 집계. |
| `candidates` | false positive 방지 조건을 모두 통과한 삭제 후보. |
| `needsReview` | 보수적으로 수동 검토로 분리한 항목. 예상 차감량 제외. |
| `excluded` | active/pending/retention 미도달/invalid prefix 등 제외 항목. |

후보 항목 주요 필드:

| 필드 | 설명 |
|---|---|
| `reasonCode` | 후보 사유. 현재 실제 후보는 `trash_retention_elapsed_with_metadata`. |
| `uidHash` | 실제 uid 대신 hash. |
| `videoIdHash` | 실제 videoId 대신 hash. |
| `storagePathHash` | 실제 Storage path 대신 hash. |
| `storagePathShape` | `users/{uid}/videos/{videoId}/{fileName}` 형태만 후보 허용. |
| `firestoreDocumentIdHash` | Firestore 문서 id hash. |
| `objectSizeBytes` | Storage 객체 크기. |
| `metadataFileSizeBytes` | Firestore `fileSize`. |
| `expectedUsageDeltaBytes` | 실제 반영하지 않는 예상 usage delta. 후보는 음수. |
| `uploadStatus`, `lifecycleState`, `cloudState`, `trashed` | read-only metadata 상태 요약. |
| `lifecycleMarkedAt` | retention 기준 timestamp. |

## 6. False positive 방지 검증

삭제 후보 `candidates`에 포함되려면 다음 조건을 모두 만족해야 한다.

1. Storage path가 `users/{uid}/videos/{videoId}/{fileName}` 정규식과 일치한다.
2. 동일 `storagePath`를 가진 Firestore `videos` metadata가 정확히 1개 존재한다.
3. metadata의 `uid`, `videoId`, `storagePath`가 Storage path에서 파싱한 값과 모두 일치한다.
4. metadata path가 `users/{uid}/videos/{videoId}/` prefix로 시작한다.
5. `uploadStatus`, `cloudState`, `lifecycleState`와 pending boolean이 upload/copy/restore pending 상태가 아니다.
6. `lifecycleState` 또는 `cloudState`가 `trash`/`tombstone`/`deleted`이거나 `trashed`/`deleted` boolean이 true다.
7. `trashedAt`, `deletedAt`, `tombstonedAt`, `updatedAt` 중 retention 기준 timestamp가 존재한다.
8. retention cutoff 이전에 trash/tombstone 처리됐다.
9. Storage object size와 Firestore `fileSize`가 모두 양수이며 서로 일치한다.

위 조건을 충족하지 못하면 다음처럼 분리한다.

| reason code | 분리 위치 | usage 예상 차감 포함 여부 |
|---|---|---|
| `invalid_prefix_excluded` | `excluded` | 제외 |
| `active_metadata_excluded` | `excluded` | 제외 |
| `active_or_pending_upload_excluded` | `excluded` | 제외 |
| `trash_retention_not_elapsed_excluded` | `excluded` | 제외 |
| `orphan_storage_object_metadata_missing` | 기본 `excluded`, `--include-orphans` 사용 시 `needsReview` | 제외 |
| `metadata_storage_path_mismatch` | `needsReview` | 제외 |
| `duplicate_metadata_storage_path_needs_review` | `needsReview` | 제외 |
| `metadata_required_field_missing_needs_review` | `needsReview` | 제외 |
| `trash_timestamp_missing_needs_review` | `needsReview` | 제외 |
| `file_size_missing_needs_review` | `needsReview` | 제외 |
| `file_size_mismatch_needs_review` | `needsReview` | 제외 |

## 7. 삭제 후보 0건 동작

후보가 0건이어도 manifest는 정상 생성된다.

예상 summary 형태:

```json
{
  "candidateCount": 0,
  "candidateObjectSizeBytes": 0,
  "expectedUsageDecrementBytes": 0,
  "candidatesByReasonCode": {},
  "candidates": []
}
```

## 8. 검증 명령과 결과

실행한 검증:

```bash
cd functions && npm run cloud-clip:delete-dry-run -- --help
```

결과:

- 도움말 출력 성공.
- Storage delete/Firestore write/usage write 동작 없음.

```bash
cd functions && node --check scripts/cloud_clip_delete_dry_run_inventory.js
```

결과:

- Node 문법 검증 성공.

```bash
cd functions && npm run cloud-clip:delete-dry-run -- --fixture ../tools/cloud_clip_delete_dry_run_fixture.json --cutoff 2026-03-01T00:00:00.000Z --out-dir ../logs
```

결과:

- fixture 기반 manifest 생성 성공.
- 후보 1건, expected usage decrement 2048 bytes.
- active metadata와 invalid prefix는 제외.
- metadata missing orphan은 기본 제외.
- 생성 manifest: `logs/cloud_clip_delete_dry_run_2026-05-14T13-40-34-692Z_93329913.json`.

```bash
cd functions && npm run cloud-clip:delete-dry-run -- --fixture ../tools/cloud_clip_delete_dry_run_fixture.json --cutoff 2025-01-01T00:00:00.000Z --out-dir ../logs
```

결과:

- 후보 0건이어도 manifest 생성 성공.
- expected usage decrement 0 bytes.
- `candidates` 빈 배열과 summary count가 정상 기록됨.
- 생성 manifest: `logs/cloud_clip_delete_dry_run_2026-05-14T13-40-56-614Z_d767a760.json`.

## 9. 미검증 사유

실제 Firebase 운영 프로젝트 접근은 수행하지 않았다. 현재 환경에는 운영 Firebase Admin 자격증명과 명시 bucket 접근 승인이 제공되지 않았고, 사용자 지시상 실제 데이터 mutation 금지가 최우선이므로 fixture와 문법/도움말 검증으로 대체했다.

## 10. 남은 리스크와 후속 승인 필요 항목

1. 실제 운영 실행 전 Admin 자격증명 범위와 bucket 이름을 운영자가 확인해야 한다.
2. 운영 manifest의 `needsReview` 항목은 실제 삭제 대상이 아니며 수동 검토 없이는 execute에 포함하면 안 된다.
3. 실제 delete execute 구현은 별도 승인, approved manifest, batch 재검증, usage decrement idempotency, rollback 한계 고지 후에만 가능하다.
4. 구독 만료 기반 삭제는 R3 정책 확정 전 자동 후보로 확장하지 않는다.
5. 개인정보 보호를 위해 manifest는 hash 중심이지만, 운영자가 원본 대조를 위해 별도 안전 채널과 접근 통제를 준비해야 한다.

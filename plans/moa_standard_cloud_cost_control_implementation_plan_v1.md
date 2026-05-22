# MOA Standard Cloud Cost Control Implementation Plan v1

## 1. Scope

Source prompt:

- `plans/moa_standard_cloud_cost_control_implementation_prompt.md`

Goal:

- Standard plan provides 50GB Cloud backup.
- Cloud is treated as backup/restore storage, not repeated streaming storage.
- Repeated playback/edit/export must prefer local cache.
- Upload, download, restore, cache, subscription expiry, and usage accounting must be controlled on both client and backend paths.

Non-goals for this plan:

- No implementation in this step.
- No Firebase deploy in this step.
- No Storage physical delete in this step.
- No migration/backfill execution in this step.
- No product id change.
- No Storage path rename from `users/{uid}/videos/{videoId}/{fileName}`.

Approval gates:

- Firebase rules/index/schema changes require separate approval.
- Cloud Functions endpoint changes require separate approval.
- Any migration/backfill/purge/physical delete requires dry-run, manifest, backup, rollback plan, and separate approval.

## 2. Current State Summary

Relevant current contracts:

- Firestore users: `users/{uid}` contains subscription/user state and `storageUsage`.
- Firestore usage events: `users/{uid}/usageEvents/{eventId}` already exists in rules.
- Firestore cloud assets: existing top-level `videos/{videoId}` is the effective Cloud asset metadata collection.
- Firestore projects: `vlog_projects/{projectId}` stores project metadata.
- Storage videos: `users/{uid}/videos/{videoId}/{fileName}`.
- Storage thumbnails: `users/{uid}/videos/{videoId}/thumbnails/poster.jpg`.
- IAP product ids remain `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual`.

Observed implementation pieces:

- `lib/services/cloud_service.dart`
  - Standard storage limit constant is already 50GB.
  - Premium dormant limit remains 200GB in code, but runtime permission is normalized elsewhere.
  - `_checkStorageLimit()` checks `users/{uid}.storageUsage` before upload.
  - `_updateStorageUsageIdempotent()` writes `users/{uid}.storageUsage` and `users/{uid}/usageEvents/{eventId}` in a Firestore transaction.
  - Upload success increments usage after Storage upload and metadata commit.
  - Download validates `storagePath` prefix and ignores untrusted legacy `downloadUrl` paths.
- `lib/services/cloud_clip_session_resolver.dart`
  - Cloud-only clips are materialized into `cloud_clip_session_cache/edit_session_cache` or `export_session_cache`.
  - Session cache TTL is 24 hours.
- `lib/screens/video_edit_screen.dart`
  - Cloud-only clips use edit/export materialization and do not persist session cache paths into projects.
- `lib/screens/profile_screen.dart`
  - Displays Cloud usage from `CloudStatsSnapshot`.
- `firebase/firestore.rules`
  - Allows owner-scoped access to `users`, `videos`, `vlog_projects`, and `users/{uid}/usageEvents`.
- `firebase/storage.rules`
  - Enforces owner path, video content type, and 500MB per object as a legacy/global safety cap.
  - Does not enforce aggregate 50GB usage.

Primary gaps:

1. 50GB limit is not finally enforced by a trusted server-side reservation/commit path.
2. Storage Rules cannot enforce aggregate per-user usage by themselves.
3. `storageUsage` can diverge from actual completed `videos.fileSize` sum and needs reconciliation semantics.
4. Upload/download events are not rich enough for monthly egress control and cost reporting.
5. Edit and export session caches can cause duplicate downloads of the same Cloud-only source.
6. Standard upload normalization policy is not centralized as a Cloud-specific preflight contract.
7. UI exposes basic Cloud usage but not monthly download/cache state.
8. Bulk restore/download throttling is not defined in code.

## 3. Design Principles

- Keep existing collections and paths. Use additive fields and helper services.
- Treat `videos/{videoId}` as the Cloud asset record instead of introducing a new `cloud_assets` collection in P0.
- Treat `users/{uid}.storageUsage` as the compatibility field for `cloud_used_bytes`.
- Use `users/{uid}/usageEvents/{eventId}` for all idempotent accounting.
- Treat `users/{uid}/usageEvents/{eventId}` as the source of truth for upload/download accounting.
- Treat `users/{uid}.monthlyDownloadBytes` as a denormalized summary for fast UI/reporting only. If it diverges from usage events, usage events win.
- Never persist local cache paths to Project JSON, Library local index, or Cloud project metadata.
- Never use Cloud download URL as the playback source for repeated video playback.
- Prefer canonical local video cache for playback/edit/export materialization.
- Use client precheck for fast UX, but server reservation/commit for authority.

## 4. P0 Scope Reduction

P0 must not attempt to complete every cost-control feature at once. P0 is the minimum safe launch layer that prevents the biggest cost and data-loss risks while collecting enough measurement data for stricter controls.

P0 hard requirements:

1. Server-side upload reservation and commit.
2. Standard 50GB quota cannot be bypassed.
3. Standard Cloud upload must use normalized MOA standard video, not raw original.
4. Cloud playback/edit/export must check canonical local cache first.
5. Repeated playback/export of the same Cloud clip must not create duplicate download traffic.
6. Subscription-expired users cannot start new uploads.
7. Pricing copy must match actual Store product details.

P0 measurement-only:

1. `monthlyDownloadBytes` summary derived from usage events
2. `cacheHit` / `cacheMiss`
3. daily cost report
4. bulk restore estimated bytes

P1 or feature-flagged:

1. hard monthly download block
2. bulk restore hard limit
3. physical orphan cleanup
4. automatic deletion after grace period

## 5. Data Contract Plan

### 5.1 `users/{uid}` additive fields

Keep:

- `subscriptionTier`
- `storageUsage`
- `lastUpdated`

Add lazily, no backfill required for P0:

- `cloudLimitBytes`: `53687091200` for Standard.
- `cloudUsedBytes`: optional alias for reporting; P0 canonical remains `storageUsage`.
- `monthlyDownloadBytes`: denormalized monthly summary for fast UI/reporting; not the accounting ledger.
- `monthlyUploadBytes`
- `billingPeriodStart`
- `billingPeriodEnd`
- `cloudUsageUpdatedAt`
- `cloudUsageVersion`: `1`
- `cloudReservedUploadBytes`
- `cloudDownloadSoftLimitBytes`: `53687091200`
- `cloudDownloadHardLimitBytes`: `107374182400`
- `bulkRestoreDailyLimitBytes`: proposed `10737418240`
- `cloudAccessState`: one of `active_standard`, `expired_grace_period`, `read_only_cloud`, `scheduled_for_cleanup`, `deleted`

Compatibility rule:

- Existing clients reading only `storageUsage` must continue to work.
- New code writes `storageUsage` and `cloudUsedBytes` together only after server commit.
- If `cloudUsedBytes` is missing, read fallback uses `storageUsage`.

### 5.2 `videos/{videoId}` additive fields

Keep existing required fields:

- `uid`
- `videoId`
- `fileName`
- `storagePath`
- `albumName`
- `isFavorite`
- `fileSize`
- `uploadStatus`

Add:

- `assetType`: `standard_video`
- `cloudState`: existing compatible states plus `reserved`, `active`, `trash`, `tombstone`, `deleted`
- `uploadRequestId`
- `uploadReservationId`
- `reservationExpiresAt`
- `usageCommitEventId`
- `sourceFileSize`
- `normalizedFileSize`
- `durationMs`
- `width`
- `height`
- `fps`
- `codec`
- `bitrate`
- `normalizedForStandard`: bool
- `storageVerifiedAt`
- `downloadCount`
- `lastDownloadedAt`
- `monthlyDownloadBytesAtLastEvent`

Compatibility rule:

- Existing documents without these fields are valid.
- Existing `fileSize` remains the usage size for completed Cloud video assets.

### 5.3 `users/{uid}/usageEvents/{eventId}` event schema

Current usage events are retained and extended.

Accounting authority:

- `users/{uid}/usageEvents/{eventId}` is the source of truth for usage accounting.
- `users/{uid}.monthlyDownloadBytes` and similar user-level counters are summaries.
- If a retry, multi-device race, or repair job creates divergence, reconciliation must trust `usageEvents` and repair summaries from events, not the reverse.

Fields:

- `uid`
- `videoId`
- `eventType`: `upload_reserve`, `upload_commit`, `upload_cancel`, `download`, `restore`, `delete_logical`, `usage_reconcile`
- `source`: `library_upload`, `background_sync`, `app_playback`, `edit_materialize`, `export_materialize`, `cloud_backup_restore`, `account_delete`
- `bytes`
- `storageDelta`
- `downloadDelta`
- `uploadDelta`
- `requestId`
- `periodKey`: `yyyy-MM`
- `status`: `reserved`, `committed`, `cancelled`, `failed`, `skipped_duplicate`
- `createdAt`
- `committedAt`
- `metadataVersion`: `1`

Event id rules:

- Upload commit: `upload_commit_{videoId}`.
- Download/materialize: `download_{videoId}_{purpose}_{yyyyMMdd}_{hash(cacheMissId)}`.
- Reconcile: `usage_reconcile_{yyyyMMdd}_{uidHash}`.
- Duplicate event ids must be no-op.

## 6. Server Authority Plan

### 6.1 Required Cloud Functions

Add callable Functions in `functions/index.js`:

1. `prepareCloudUpload`
   - Input: `requestId`, `fileName`, `fileSize`, `contentType`, `albumName`, `source`, optional normalized metadata.
   - Auth required.
   - Reject guest/unauthed users.
   - Verify active Standard or normalized Standard-compatible Premium.
   - Verify file size and content type.
   - Verify Standard normalized video object size is within the Standard per-object policy cap, suggested <= 50MB.
   - Verify `storageUsage + cloudReservedUploadBytes + fileSize <= 50GB`.
   - Create or reuse `videos/{videoId}` with `uploadStatus=reserved`.
   - Set `reservationExpiresAt`.
   - Reserve bytes in `users/{uid}.cloudReservedUploadBytes`.
   - Return `videoId`, `storagePath`, `thumbnailStoragePath`, `reservationId`.

2. `commitCloudUpload`
   - Input: `videoId`, `requestId`.
   - Auth required and owner match.
   - Verify `videos/{videoId}` is reserved/uploading for the same request.
   - Reject commit if `reservationExpiresAt` has passed.
   - Verify Storage object exists at `storagePath`.
   - Verify object size/contentType matches reservation.
   - Verify thumbnail object if required by current upload completion policy.
   - Transactionally:
     - mark `videos/{videoId}.uploadStatus=completed`;
     - set verified metadata;
     - decrement reserved bytes;
     - increment `storageUsage`/`cloudUsedBytes`;
     - write `usageEvents/upload_commit_{videoId}`.

3. `cancelCloudUpload`
   - Input: `videoId`, `requestId`, `reason`.
   - Auth required and owner match.
   - Release reservation.
   - Mark metadata `failed` or `cancelled`.
   - Do not increment usage.
   - Physical Storage delete is not part of P0 unless separately approved.

4. `recordCloudDownload`
   - Input: `videoId`, `source`, `bytes`, `cacheHit=false`.
   - Auth required and owner match.
   - If cache hit, record count-only local cache event or skip download byte increment.
   - If cache miss, record download bytes and evaluate soft warning policy.
   - P0 does not hard-block normal restore by default.
   - Hard block must be behind remote config or a feature flag.
   - Create a usage event and update `monthlyDownloadBytes` as a denormalized summary.

5. `reconcileCloudUsageDryRun`
   - Admin-only or local emulator-only first.
   - Calculates completed active `videos.fileSize` sum by user.
   - Reports difference from `users.storageUsage`.
   - Does not mutate in P0.

6. `dailyCloudCostReport`
   - Admin-only scheduled/report mode.
   - Emits aggregate counts only:
     - total standard users;
     - total/avg cloud used GB;
     - total/avg monthly download GB;
     - top storage users by masked uid;
     - top download users by masked uid;
     - estimated cost per user;
     - risk level.

### 6.2 Reservation Expiry

Every upload reservation must include `reservationExpiresAt`.

If upload is not committed before expiry:

- reservation can no longer be committed;
- reserved bytes must be released by cleanup job or next `prepareCloudUpload` / `commitCloudUpload` call;
- metadata remains `failed` or `expired`;
- local file must remain untouched.

`cloudReservedUploadBytes` must never permanently block the user because of abandoned uploads.

Implementation requirements:

- `prepareCloudUpload` opportunistically releases expired reservations for the current user before calculating quota.
- `commitCloudUpload` rejects expired reservations and releases the reservation in the same transaction when possible.
- A scheduled cleanup job marks expired reservation metadata and releases reserved bytes idempotently.
- Cleanup must be idempotent by reservation id and must not decrement committed `storageUsage`.
- Local cleanup after upload remains gated on successful commit, not on reservation creation or Storage upload completion.

Suggested defaults:

- Reservation TTL: 30 minutes for foreground upload.
- Queue upload may refresh/recreate reservation immediately before actual upload.
- Expired reservation status: `expired`.

Tests:

- Expired reservation cannot commit.
- Expired reservation releases reserved bytes exactly once.
- Abandoned reservations do not prevent later valid uploads.
- Expired reservation leaves local file and local index untouched.

### 6.3 Storage Rules

P0 preferred rule direction:

- Keep path `users/{uid}/videos/{videoId}/{fileName}`.
- Require owner auth.
- Require content type and max object size.
- Require matching reserved video metadata before write, if Storage Rules can safely read the Firestore document in this project.
- Ensure `request.resource.size <= reservedFileSize`.

Fallback if Firestore lookup in Storage Rules is not adopted:

- Client uploads only after `prepareCloudUpload`.
- `commitCloudUpload` is the only path that marks a video completed and increments usage.
- Any object without committed metadata is treated as orphan candidate and excluded from user-visible Cloud.
- Orphan cleanup remains dry-run/report until physical delete is approved.

Important:

- Storage Rules alone cannot enforce aggregate 50GB.
- The 500MB Storage Rule cap is only the legacy/global final safety wall. It is not the Standard product upload policy.
- Standard normalized Cloud video should be constrained by a lower per-object policy cap, suggested <= 50MB.
- Aggregate quota must be enforced in `prepareCloudUpload` and `commitCloudUpload`.

### 6.4 Firestore Rules

P0 rule direction:

- Preserve owner read/write behavior for current clients.
- Tighten `usageEvents` so client can create only safe event payloads if direct client events remain.
- Prefer moving quota-critical event writes to Functions only.
- Add validation for additive fields without breaking existing documents.

Implementation warning:

- Rules changes require separate approval and emulator tests.

## 7. Client Implementation Plan

### Phase P0-A. Cost Policy Constants

Files:

- Add `lib/utils/cloud_cost_policy.dart`.
- Add `test/cloud_cost_policy_test.dart`.

Contents:

- `kStandardCloudLimitBytes = 50 * 1024 * 1024 * 1024`
- `kMonthlyDownloadSoftLimitBytes = 50 * 1024 * 1024 * 1024`
- `kMonthlyDownloadHardLimitBytes = 100 * 1024 * 1024 * 1024`
- `kBulkRestoreDailyLimitBytes = 10 * 1024 * 1024 * 1024`
- `kCloudVideoCacheMaxBytes = 2 * 1024 * 1024 * 1024`
- `formatCloudBytes(bytes)`
- `cloudUsageRatio(used, limit)`
- `canUploadWithinLimit(used, reserved, incoming, limit)`

Acceptance:

- All UI and Cloud code reads limits from this policy file.
- No Standard/Premium magic numbers remain in UI code.

### Phase P0-B. Cloud Upload Preflight and Normalization Contract

Files:

- Add `lib/services/cloud_upload_preflight_service.dart`.
- Update `lib/services/cloud_service.dart`.
- Update `lib/managers/video_manager.dart` only where upload sources are prepared.
- Add `test/cloud_upload_preflight_service_test.dart`.

Rules:

- Standard Cloud upload accepts only MOA standard video:
  - duration near 2 seconds per existing clip duration contract;
  - max 1080p;
  - target 30fps;
  - H.264 preferred;
  - bitrate cap from policy.
  - per-object size cap far below the legacy/global 500MB Storage cap; suggested Standard cap <= 50MB.
- Nonconforming local/imported clip must be normalized before Cloud upload.
- Raw/original high-resolution imported file must not be directly uploaded as Standard backup.

Implementation approach:

- Use existing native `normalizeVideoDuration` path for nonconforming clips.
- Add a preflight result:
  - `readyOriginal`
  - `normalizedCopy`
  - `blocked`
  - `failed`
- Upload only the validated/normalized file.
- Store source vs normalized metadata on `videos/{videoId}`.

Acceptance:

- A 4K or long imported source is not uploaded directly.
- A valid 2-second 1080p clip uploads without extra normalization.
- A Standard normalized video object over the Standard per-object cap is blocked before Storage object creation.
- Failure leaves local source intact.

### Phase P0-C. Server Upload Reservation Integration

Files:

- Add `lib/services/cloud_usage_service.dart`.
- Update `lib/services/cloud_service.dart`.
- Update `functions/index.js`.
- Update `firebase/firestore.rules` and `firebase/storage.rules` only after approval.
- Add Functions emulator tests.

Client flow:

```text
CloudService.uploadVideoImmediate()
  -> cloudUploadPreflight()
  -> prepareCloudUpload()
  -> upload file to returned storagePath
  -> upload thumbnail
  -> commitCloudUpload()
  -> local cleanup only after commit success
```

Queue flow:

```text
enqueue upload task
  -> reserve before active upload
  -> upload only when reservation succeeds
  -> commit or cancel reservation
```

Required failure handling:

- `prepareCloudUpload` quota fail: no Storage object created.
- upload fail: call `cancelCloudUpload`; local source remains.
- thumbnail fail: do not commit completed metadata; local source remains.
- commit fail: keep retryable pending state; do not delete local source.
- duplicate retry: same `requestId` returns existing reservation/result.

Acceptance:

- Synthetic quota boundary: 49GB used + 500MB reserved upload succeeds only as a quota math test.
- Synthetic quota boundary: 49.8GB used + 500MB reserved upload is blocked before Storage object creation.
- Real Standard video object limit: Standard normalized video must satisfy the lower per-object cap, suggested <= 50MB.
- Client manipulation cannot complete an over-quota upload.
- Duplicate taps do not double-create metadata or double-increment usage.

### Phase P0-D. Canonical Local Video Cache

Files:

- Add `lib/services/cloud_video_cache_service.dart`.
- Update `lib/services/cloud_clip_session_resolver.dart`.
- Update `lib/screens/video_edit_screen.dart`.
- Update `lib/managers/video_manager.dart`.
- Add `test/cloud_video_cache_service_test.dart`.
- Extend `test/cloud_clip_session_resolver_test.dart`.

Current issue:

- `edit_session_cache` and `export_session_cache` are separate purpose directories.
- Preview then export may download the same Cloud source twice.

Target structure:

```text
app documents/
  cloud_video_cache/
    {videoId}/standard.mp4
  cloud_clip_session_cache/
    edit_session_cache/
    export_session_cache/
```

Resolution flow:

```text
resolveCloudSource(videoId, purpose)
  1. validate cloud_only placeholder
  2. read metadata from VideoManager/CloudService
  3. check cloud_video_cache/{videoId}
  4. if exists and file size matches, return local file and record cache hit
  5. if missing, assert download allowed
  6. download once into temp file
  7. verify size
  8. atomically move into cloud_video_cache
  9. record download event
  10. return local file for edit/export
```

Persistence guard:

- Expand guard naming from `isSessionCachePath` to `isNonPersistentCloudMaterializationPath`.
- Reject both:
  - `cloud_clip_session_cache`
  - `cloud_video_cache`
- Project JSON must still store only `cloud_only://...` or local permanent paths.
- Library local index must not register cache paths.

Cache policy:

- Max video cache size: 2GB default.
- Eviction: LRU by last access time.
- Protected paths: current edit/export active files.
- Never delete active session/export sources.
- Never delete local original clips.
- Never treat cache clear as Cloud delete.

Acceptance:

- First Cloud-only preview downloads once.
- Replaying the same clip uses local cache.
- Export after preview uses local cache, not another Cloud download.
- Cache clear removes only local cached copies.
- Project JSON and Cloud project metadata never contain cache paths.

### Phase P0-E. Download and Restore Throttling

Files:

- Update `lib/services/cloud_usage_service.dart`.
- Update `lib/services/cloud_service.dart`.
- Update `lib/screens/cloud_backup_screen.dart`.
- Add `test/cloud_download_policy_test.dart`.

Candidate thresholds:

- Monthly soft limit: 50GB.
- Monthly hard limit: 100GB.
- Bulk restore daily limit: 10GB/day.
- Cache hit does not consume download bytes.
- Cache miss consumes download bytes.
- P0 records usage and warns only; it does not hard-block normal restore by default.
- Hard monthly download block and bulk restore hard limit are P1 or feature-flagged.

UX:

- Soft limit warning:
  - "이번 달 Cloud 다운로드 사용량이 많습니다. 반복 재생은 로컬 캐시를 우선 사용합니다."
- Feature-flagged hard limit copy:
  - "이번 달 Cloud 다운로드 한도를 초과했습니다. 다음 달에 다시 이용하거나 구독 상태를 확인해 주세요."
- Bulk restore warning:
  - show estimated bytes before multi-select restore.

#### Download Limit Rollout

- P0 records download usage but does not hard-block normal user restore by default.
- Hard block must be behind remote config / feature flag.
- Initial enforcement:
  - cache miss records download bytes;
  - repeated cache hit records no bytes;
  - abnormal repeated download patterns may show warning;
  - bulk restore shows estimated size and staged restore suggestion.
- Hard limit activation requires:
  - at least 2 weeks of usage data;
  - no major restore complaint pattern;
  - support copy reviewed.

Acceptance:

- One missing Cloud clip download records one download event.
- Repeated playback from cache records no additional download bytes.
- Bulk restore shows estimated size and staged restore suggestion.
- Hard limit block is inactive unless the remote config / feature flag is explicitly enabled.

### Phase P0-F. UI Updates

Files:

- `lib/screens/profile_screen.dart`
- `lib/screens/cloud_backup_screen.dart`
- `lib/screens/paywall_screen.dart`
- `lib/screens/project_screen.dart` if Project upsell references Cloud benefits.

Profile Cloud section:

```text
Cloud 백업 공간
18.4GB / 50GB

이번 달 Cloud 다운로드
6.2GB
```

Paywall benefits:

- "50GB Cloud 백업"
- "Project 저장"
- "1080p 내보내기"
- "편집 기능"
- "기기 변경 시 복원"
- "최근 클립 자동 캐시"

Do not promise:

- unlimited streaming;
- original video unlimited backup;
- always play directly from Cloud.

Pricing:

- Product prices must come from Store product details when available.
- Static fallback copy may say:
  - monthly Standard: 6,900 KRW;
  - annual Standard: 69,000 KRW;
  - launch first-year promotion: 59,000 KRW.
- Product ids stay unchanged.

Acceptance:

- Free user sees no Cloud usage entitlement.
- Standard user sees 50GB usage.
- Expired grace user sees read/restore guidance, no new upload promise.

### Phase P0-G. Subscription Expiry Enforcement

Files:

- `lib/managers/user_status_manager.dart`
- `lib/services/cloud_service.dart`
- `lib/screens/cloud_backup_screen.dart`
- Functions entitlement checks.

Current policy to preserve:

- Active Standard can upload/read/download.
- Expired paid user can read/download during 30-day grace.
- Expired paid user cannot start new uploads.
- Never-paid Free cannot read old Cloud clips.

Add backend state mapping:

- `active_standard`
- `expired_grace_period`
- `read_only_cloud`
- `scheduled_for_cleanup`
- `deleted`

Acceptance:

- Scheduled cancellation remains Standard until expiry.
- After expiry, upload blocked, restore allowed only within grace.
- After grace, Cloud list/read/download blocked unless user re-subscribes.

## 8. Backend Reporting Plan

### Phase P1-A. Dry-run Usage Reconciliation

Files:

- Add `functions/scripts/cloud_usage_reconcile_dry_run.js`.
- Add report output under `logs/` only when explicitly run.

Report:

- uid hash only;
- `storageUsage`;
- completed active video sum;
- reserved bytes;
- missing fileSize count;
- missing storagePath count;
- orphan candidate count;
- suggested delta;
- no mutation.

Acceptance:

- Dry-run can run on emulator and staging.
- No user-identifying raw uid/storage path in report.

### Phase P1-B. Daily Cost Control Report

Files:

- Add callable/scheduled function in `functions/index.js`, or script first.

Metrics:

- total Standard users;
- total cloud used GB;
- avg cloud used GB/user;
- total monthly download GB;
- avg monthly download GB/user;
- top 10 storage users by masked uid/hash;
- top 10 download users by masked uid/hash;
- estimated storage cost;
- estimated download cost;
- estimated cost per Standard user;
- risk level:
  - GREEN <= 1,500 KRW/user/month;
  - YELLOW > 1,500 and <= 2,500;
  - RED > 2,500.

Acceptance:

- No secrets, raw uid, tokens, or raw storage paths in logs.
- Report can be generated without deploy in emulator/local dry-run first.

## 9. Physical Delete and Orphan Cleanup Policy

P0:

- No new automatic physical delete.
- Logical delete/tombstone remains separate from local cache clear.
- Orphan cleanup is report-only.

P1/P2, separate approval:

- Inventory dry-run.
- Candidate manifest.
- Per-object owner/path verification.
- Usage decrement idempotency.
- Batch size limits.
- Rollback plan for metadata and usage counters.
- Explicit approval before execution.

Acceptance before any physical delete:

- object exists and belongs to uid;
- matching `videos/{videoId}.storagePath`;
- not active, not in grace read-only active data, not referenced by project policy;
- usage decrement event idempotency verified.

## 10. Test Plan

### Dart unit tests

- `test/cloud_cost_policy_test.dart`
  - byte formatting;
  - 50GB boundaries;
  - soft/hard monthly download boundaries.
- `test/cloud_upload_preflight_service_test.dart`
  - valid Standard clip accepted;
  - oversized/original input requires normalization;
  - failed normalization blocks upload and preserves local source.
- `test/cloud_video_cache_service_test.dart`
  - cache hit returns local file;
  - cache miss downloads once;
  - corrupt size mismatch redownloads or fails;
  - LRU evicts oldest only;
  - protected active cache is not deleted.
- Extend `test/cloud_clip_session_resolver_test.dart`
  - edit then export same cloud clip causes one Cloud download;
  - project path remains `cloud_only://...`;
  - nonpersistent cache path guard rejects cache paths.
- Extend `test/video_manager_clip_storage_state_test.dart`
  - cache path is never local library asset;
  - cloud-only placeholder remains Cloud state.

### Functions tests

- Synthetic quota boundary: `prepareCloudUpload` allows 49GB used + 500MB reserved only as a quota math test.
- Synthetic quota boundary: `prepareCloudUpload` rejects 49.8GB used + 500MB reserved.
- Real Standard policy: `prepareCloudUpload` rejects a Standard normalized video object above the Standard per-object cap, suggested <= 50MB.
- `commitCloudUpload` rejects owner mismatch.
- `commitCloudUpload` rejects object size mismatch.
- duplicate `requestId` does not double reserve or double commit.
- `recordCloudDownload` creates usage events as the ledger and updates `monthlyDownloadBytes` only as a denormalized summary.
- `recordCloudDownload` increments summary download bytes only on cache miss.
- monthly hard limit only blocks cache-miss download when the remote config / feature flag is enabled.
- expired reservation cannot commit and releases reserved bytes idempotently.

### Rules tests

- owner can read own video object.
- other user cannot read/write.
- non-video content type rejected.
- oversized object rejected.
- reserved metadata mismatch rejected if reservation-based Storage rule is adopted.
- `usageEvents` cannot be deleted by client.

### Manual QA

1. Standard user uploads until near 50GB, then attempts over-limit upload.
2. Standard user previews same Cloud clip multiple times; log shows one cache miss then cache hits.
3. Standard user previews Cloud clip, then exports; no second download event for same cached clip.
4. Clear playback cache; next playback downloads once.
5. Bulk restore over daily threshold shows estimated size and staged restore suggestion.
6. Expired Standard within grace can restore existing Cloud clip but cannot upload.
7. Free never-paid user sees no Cloud restore/download entitlement.
8. Account delete/rejoin does not show stale Cloud clips.

## 11. Rollout Plan

### Step 1. Document and constants only

- Add central client policy constants.
- No backend behavior change.
- Run Flutter tests/analyze.

### Step 2. Client preflight and cache service behind feature flag

- Add local canonical cache.
- Keep existing session resolver fallback.
- Add logs with count-only cache hit/miss.
- No server rule change yet.

### Step 3. Functions reservation in emulator

- Add callable Functions.
- Add emulator tests.
- Client can be wired behind a remote/local feature flag.

### Step 4. Rules tightening in emulator

- Update Firestore/Storage rules.
- Run all rules tests.
- No production deploy until approved.

### Step 5. Staged release

- Internal track only.
- Monitor:
  - upload reservation failures;
  - expired reservation cleanup count;
  - reserved bytes released by cleanup;
  - commit failures;
  - cache hit rate;
  - monthly download bytes;
  - usage divergence.

### Step 6. Public rollout gate

- Usage divergence dry-run clean or accepted.
- Cache hit rate for Cloud playback/export is acceptable.
- No quota bypass found in emulator/QA.
- At least 2 weeks of download/cache data reviewed before enabling hard download blocks.
- Support copy and paywall copy reviewed.

## 12. Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Client-only quota bypass | Storage cost spike | Server reservation/commit required before public rollout |
| Duplicate downloads through edit/export caches | Egress cost spike | Canonical `cloud_video_cache` before session materialization |
| `storageUsage` divergence | Incorrect quota block/allow | Idempotent events plus dry-run reconciliation |
| Abandoned reservation blocks quota | User cannot upload despite available space | `reservationExpiresAt`, opportunistic release, scheduled cleanup |
| Commit succeeds but local cleanup runs too early | User data loss | Cleanup only after commit and thumbnail metadata success |
| Orphan Storage objects | Cost leak | Report-only inventory first, approved cleanup later |
| Hard download limit UX backlash | User trust issue | Soft warning first, hard block only for cache-miss downloads and with clear copy |
| Cache clear misunderstood as Cloud delete | User anxiety | Explicit UI copy: cache clear does not delete Cloud backup |
| Rules/index changes break old clients | Regression | Additive schema, emulator tests, staged rollout |

## 13. Completion Criteria

### P0-Dev Complete

P0-Dev Complete means the local/emulator implementation is ready for release gating, but production rollout is not yet approved.

Required:

- Standard upload quota is checked by client and authoritative server reservation.
- Over-50GB upload cannot be completed by client manipulation.
- Standard normalized video object is blocked above the Standard per-object cap, suggested <= 50MB.
- Upload usage is incremented exactly once.
- Cloud playback/edit/export checks local cache first.
- Repeated playback does not repeatedly download the same Cloud clip.
- Edit/export of the same Cloud source reuses canonical cache where valid.
- Download events are recorded for cache misses.
- Hard download block is not active by default in P0.
- Expired upload reservations cannot commit and cannot permanently reserve quota.
- Profile displays Cloud backup usage and monthly Cloud download usage.
- Expired Standard cannot upload new Cloud data.
- Grace read/download policy remains intact.
- Project JSON, Cloud project metadata, and Library local index never store cache paths.
- Flutter tests pass.
- Functions tests pass.
- Firebase emulator rules tests pass when rules are changed.
- No Firebase deploy, migration, backfill, or Storage physical delete is performed without explicit approval.

### P0-Release Ready

P0-Release Ready means production rollout is explicitly approved.

Required:

- Firebase Functions deploy approved.
- Firestore/Storage Rules deploy approved if rules changed.
- Internal track QA passed.
- Usage divergence dry-run reviewed.
- Rollback plan ready for Functions, client rollout, and additive metadata.
- Store product details verified against pricing copy.

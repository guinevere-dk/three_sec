# Cloud Clip Move Model QA Plan v1

## 1. Scope

This plan replaces sync-model Cloud Clip QA with move-model QA.

Policy source: `plans/cloud_clip_move_model_policy_v1.md`.

In scope:

- Device to Cloud move: `device/localOnly -> cloud/cloudOnly`.
- Cloud to device move: `cloud/cloudOnly -> device/localOnly`.
- Active state must be exactly one of `device` or `cloud`.
- `cloudSyncedLocal` is legacy/repair-needed only.
- Cloud removal means Firestore active metadata is changed to trash/tombstone.
- Storage object physical deletion is not part of R3/current scope and is a FAIL if observed.

Out of scope:

- Firebase rules/index/schema changes.
- Migration/backfill execution.
- Legacy data destructive cleanup.
- Storage object physical deletion.
- Deploy.

## 2. Global QA Rules

- Use only QA accounts and test clips.
- Do not record raw email, password, token, order id, provider value, or full uid.
- Mask uid if needed, for example `abcd...wxyz`.
- Do not mutate production user data.
- Do not manually delete Storage objects.
- Do not manually repair `cloud_synced_paths` or legacy `cloudSyncedLocal` data.
- Record before/after evidence for local file/index, Firestore active metadata state, and Storage object presence when available.

## 3. State Definitions

| State | Meaning | QA Classification |
| --- | --- | --- |
| `device` / `localOnly` | Local file and local index are active. Cloud active metadata is not considered active for the clip. | Normal active state |
| `cloud` / `cloudOnly` | Cloud active metadata exists; Library uses a `cloud_only://` placeholder. | Normal active state |
| `pendingUpload` | Device to Cloud move in progress. | Transitional |
| `failedUpload` | Upload failed and device copy remains. | Recoverable failure |
| `failedDownload` | Download/move-to-device failed and Cloud active metadata remains. | Recoverable failure |
| `cloudSyncedLocal` | Local file and Cloud linkage both appear active from legacy sync data. | Legacy/repair-needed, not normal |

## 4. Evidence Requirements

Each scenario should record:

- UI: Library badge/icon, transfer button state, snackbar/dialog.
- Local: count-only local file/index evidence. Raw paths are not required.
- Firestore: test `videos` document active/trash/tombstone state before/after.
- Storage: object presence before/after, with no physical delete.
- Logs: count-only/redacted app logs for move entry, gate block, failure, and sensitive log gate.
- Subscription state: active paid, grace, after grace, or free never paid.

## 5. Scenario Matrix

| ID | Scenario | Expected Active Result | Storage Physical Delete |
| --- | --- | --- | --- |
| MMQA-01 | Active paid upload move | Cloud only | Must not occur |
| MMQA-02 | Active paid download move | Device only | Must not occur |
| MMQA-03 | Grace upload blocked | Device remains | Must not occur |
| MMQA-04 | Grace download/move-to-device allowed | Device only | Must not occur |
| MMQA-05 | After grace download blocked | Cloud remains | Must not occur |
| MMQA-06 | Free never paid Cloud access blocked | Source state remains | Must not occur |
| MMQA-07 | Legacy cloudSyncedLocal no auto cleanup | Legacy state remains unless user-approved repair exists | Must not occur |
| MMQA-08 | Upload failure preserves local | Device remains | Must not occur |
| MMQA-09 | Download failure preserves Cloud active metadata | Cloud remains | Must not occur |

## 6. Detailed Scenarios

### MMQA-01 Active Paid Upload Move

Preconditions:

- Signed-in QA account.
- Active paid Standard/Premium state.
- One verified `device/localOnly` clip.

Steps:

1. Record local count/index before.
2. Record Firestore active metadata before.
3. Record Storage object before.
4. Select exactly one `device/localOnly` clip in Library.
5. Tap Cloud move/upload action.
6. Wait for completion.
7. Refresh Library and Cloud metadata.
8. Record local count/index, Firestore, Storage after.

Expected:

- Upload is allowed.
- Firestore active metadata is completed/active for the new Cloud clip.
- Storage object exists.
- Local file and local index for the moved clip are removed.
- Library shows the clip as `Cloud`.
- No `cloudSyncedLocal` is created for the new normal path.
- No Storage object physical deletion occurs.

PASS:

- Active state is Cloud only.

FAIL:

- Local file remains as active normal state.
- New normal state becomes `cloudSyncedLocal`.
- Storage object is physically deleted.
- Raw sensitive values appear in app-controlled logs.

### MMQA-02 Active Paid Download Move

Preconditions:

- Signed-in QA account.
- Active paid Standard/Premium state.
- One verified `cloud/cloudOnly` clip.

Steps:

1. Record Firestore active metadata before.
2. Record Storage object before.
3. Record local count/index before.
4. Select exactly one `cloud/cloudOnly` clip.
5. Tap device download/move-to-device action.
6. Wait for completion.
7. Refresh Library and Cloud metadata.
8. Record local count/index, Firestore, Storage after.

Expected:

- Download/move-to-device is allowed.
- Local file is created and local index is registered.
- Cloud active metadata is trash/tombstone.
- Cloud-only placeholder is removed from active Library view.
- Storage object still exists physically.
- Library shows the clip as `기기`.

PASS:

- Active state is device only.

FAIL:

- Cloud active metadata remains active after successful local registration.
- Local file is not created.
- Storage object is physically deleted.

### MMQA-03 Grace Upload Blocked

Preconditions:

- Signed-in QA account.
- Expired paid state within 30-day grace.
- One verified `device/localOnly` clip.

Steps:

1. Record Firestore/Storage before.
2. Attempt device to Cloud upload move.
3. Record gate message/log.
4. Record Firestore/Storage/local state after.

Expected:

- New upload/move-to-cloud is blocked.
- No new Cloud active metadata is created.
- No new Storage object is created.
- Device clip remains local.

PASS:

- Active state remains device only and write gate is enforced.

FAIL:

- New Cloud active metadata or Storage object appears.

### MMQA-04 Grace Download/Move-To-Device Allowed

Preconditions:

- Signed-in QA account.
- Expired paid state within 30-day grace.
- One existing `cloud/cloudOnly` clip.

Steps:

1. Record Firestore active metadata before.
2. Record Storage object before.
3. Record local count/index before.
4. Execute Cloud to device download/move.
5. Record local count/index, Firestore, Storage after.

Expected:

- Existing Cloud clip recovery is allowed during grace.
- Local file and local index are created.
- Cloud active metadata is trash/tombstone.
- Storage object is not physically deleted.

PASS:

- Active state becomes device only.

FAIL:

- Download is blocked during grace.
- Cloud active metadata remains active after successful local registration.
- Storage object is physically deleted.

### MMQA-05 After Grace Download Blocked

Preconditions:

- Signed-in QA account.
- Expired after 30-day grace.
- One existing `cloud/cloudOnly` clip.

Steps:

1. Record local/Firestore/Storage before.
2. Attempt Cloud download/move-to-device.
3. Record gate message/log.
4. Record local/Firestore/Storage after.

Expected:

- Cloud read/download/move-to-device is blocked.
- No local file is created.
- Cloud active metadata remains active.
- Storage object remains present.

PASS:

- Source Cloud state is preserved and access is blocked.

FAIL:

- Download succeeds after grace.
- Cloud active metadata is modified unexpectedly.
- Storage object is physically deleted.

### MMQA-06 Free Never Paid Cloud Access Blocked

Preconditions:

- Signed-in QA account.
- Free never paid state.
- Optional device clip and optional Cloud fixture from a prior paid state.

Steps:

1. Attempt device to Cloud upload move.
2. Attempt Cloud list/read/download if a Cloud fixture is visible.
3. Record gate messages/logs.
4. Record Firestore/Storage/local before/after.

Expected:

- Upload is blocked with tier-required or equivalent gate.
- Cloud read/download is blocked.
- No Cloud metadata/object is created.
- No local recovery file is created.

PASS:

- No Cloud access succeeds for free never paid state.

FAIL:

- Free never paid opens grace behavior.

### MMQA-07 Legacy cloudSyncedLocal No Auto Cleanup

Preconditions:

- Existing legacy `cloudSyncedLocal` fixture or count-only diagnostics showing `cloudSyncedLocalCount > 0`.

Steps:

1. Record count-only diagnostics before.
2. Open Library/Profile/Cloud surfaces without triggering repair.
3. Record diagnostics after.
4. Confirm no manual cleanup was performed.

Expected:

- Legacy state is classified as legacy/repair-needed.
- App does not automatically delete local files.
- App does not automatically trash/tombstone Cloud metadata.
- App does not destructively clean `cloud_synced_paths`.

PASS:

- No destructive automatic cleanup occurs.

FAIL:

- Legacy data is automatically deleted or modified without an approved repair plan.

### MMQA-08 Upload Failure Preserves Local

Preconditions:

- Signed-in QA account.
- Upload failure can be induced safely without Firebase schema/rules changes, or observed from a controlled network/API failure.
- One `device/localOnly` clip.

Steps:

1. Record local file/index before.
2. Attempt upload move under failure condition.
3. Record error/gate/log.
4. Record local file/index and Firestore/Storage after.

Expected:

- Local file and local index remain.
- State is `failedUpload` or returns to device/localOnly.
- No successful Cloud-only transition is shown.

PASS:

- Device copy remains active.

FAIL:

- Local file is removed before Cloud active completion.

### MMQA-09 Download Failure Preserves Cloud Active Metadata

Preconditions:

- Signed-in QA account with Cloud read permission.
- Download failure can be induced safely, or a controlled failure is observed.
- One `cloud/cloudOnly` clip.

Steps:

1. Record Firestore active metadata before.
2. Attempt download/move-to-device under failure condition.
3. Record error/gate/log.
4. Record local file/index, Firestore, Storage after.

Expected:

- Cloud active metadata remains active.
- Cloud-only placeholder remains or can be restored from metadata pull.
- No local-only success state is shown.
- Storage object remains present.

PASS:

- Cloud copy remains active.

FAIL:

- Cloud active metadata is trash/tombstone despite failed local recovery.
- Storage object is physically deleted.

## 7. Stop Conditions

Stop QA immediately if any of the following occurs:

- Storage object physical deletion is observed.
- Legacy `cloudSyncedLocal` data is automatically deleted or trash/tombstoned.
- Upload failure removes local files.
- Download failure removes Cloud active metadata.
- Grace upload creates new Cloud active metadata or Storage object.
- After-grace download creates a local file.
- Raw sensitive values appear in app-controlled logs.

## 8. Result Template

```md
## Move Model QA Result

- Date:
- Tester:
- Build/version:
- Device:
- Firebase environment:
- Account state:
- uid: masked or unavailable

### Scenario

- ID:
- Verdict: PASS / FAIL / BLOCKED / N/A
- Preconditions:
- Steps:
- Expected:
- Actual:
- Failure/block reason:

### Evidence

- UI:
- Local before/after:
- Firestore active metadata before/after:
- Storage object before/after:
- Logs:
- Sensitive log gate:
```

## 9. Go/No-Go Criteria

Go:

- MMQA-01 through MMQA-09 are PASS or explicitly approved BLOCKED where the failure condition cannot be safely induced.
- No Storage physical delete is observed.
- No legacy automatic cleanup is observed.
- UI badges expose only `기기` or `Cloud`.
- Grace behavior matches the move model: upload blocked, Cloud recovery allowed, after-grace read/download blocked.

No-Go:

- Any normal successful move ends in duplicate active device+Cloud state.
- Any failure path loses the only active copy.
- Any R3/current-scope path physically deletes Storage.
- Any QA step requires Firebase rules/index/schema changes or migration/backfill.

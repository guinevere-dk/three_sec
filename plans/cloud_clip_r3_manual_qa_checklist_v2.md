# Cloud Clip R3 Manual QA Checklist v2

## 1. Purpose

This checklist supersedes `plans/cloud_clip_r3_manual_qa_checklist_v1.md` for Cloud Clip storage QA.

R3 manual QA now follows the move model:

- A clip is active in exactly one storage tier: device or Cloud.
- Upload means `device/localOnly -> cloud/cloudOnly`.
- Download means `cloud/cloudOnly -> device/localOnly`.
- `cloudSyncedLocal` is legacy/repair-needed, not a passing normal state.
- Cloud removal means active metadata is trash/tombstone.
- Storage object physical deletion is not tested as expected behavior and is a FAIL if observed.

## 2. Common Restrictions

Do not perform:

- Code changes.
- Firebase rules/index/schema changes.
- Migration/backfill.
- Storage object physical deletion.
- Legacy data automatic cleanup or manual destructive repair.
- Deploy.
- Production user data access.
- Raw credential, token, order id, provider, email, or full uid recording.

## 3. Common Setup

Use:

- Signed-in QA account for signed-in scenarios.
- Masked uid only.
- QA clips only.
- Count-only local diagnostics where possible.
- Firestore/Storage before-after evidence scoped to the QA account and test clip.

Required baseline checks:

- App-controlled sensitive log gate: no raw email/password/token/order id/provider values.
- Clip badge vocabulary: only `기기` or `Cloud`.
- Active state vocabulary: `device/localOnly`, `cloud/cloudOnly`, or legacy/repair-needed `cloudSyncedLocal`.
- Storage physical delete event: must be absent.

## 4. Verdict Rules

| Verdict | Meaning |
| --- | --- |
| PASS | Preconditions are met, expected move-model result is observed, evidence is recorded. |
| FAIL | Policy is violated, including duplicate normal active state, wrong subscription gate, data loss, or Storage physical delete. |
| BLOCKED | Fixture, account, billing state, or safe failure induction is unavailable. |
| N/A | Scenario intentionally not applicable to the current environment. |

## 5. R3-MQA-01 Active Paid Upload Move

Preconditions:

- Signed-in manual QA account.
- Active paid Standard/Premium.
- One verified `device/localOnly` clip.

Steps:

1. Record local file/index count before.
2. Record Firestore active `videos` document state before.
3. Record Storage object state before.
4. Select the `기기` clip in Library.
5. Tap Cloud move/upload.
6. Wait for completion and refresh Library.
7. Record local, Firestore, Storage after.

Expected:

- Upload is allowed.
- Firestore active metadata is completed/active for the Cloud clip.
- Storage object exists.
- Local file and local index for the moved clip are removed.
- Library shows `Cloud`.
- New normal state is not `cloudSyncedLocal`.

PASS:

- Active state is Cloud only.

FAIL:

- Local active copy remains after successful move.
- New normal state is `cloudSyncedLocal`.
- Storage object physical delete occurs.

## 6. R3-MQA-02 Active Paid Download Move

Preconditions:

- Signed-in manual QA account.
- Active paid Standard/Premium.
- One verified `cloud/cloudOnly` clip.

Steps:

1. Record Firestore active metadata before.
2. Record Storage object before.
3. Record local file/index count before.
4. Select the `Cloud` clip in Library or Cloud surface.
5. Tap download/move-to-device.
6. Wait for completion and refresh Library.
7. Record local, Firestore, Storage after.

Expected:

- Download/move-to-device is allowed.
- Local file is created and local index is registered.
- Cloud active metadata becomes trash/tombstone.
- Cloud placeholder is removed from active view.
- Storage object remains physically present.
- Library shows `기기`.

PASS:

- Active state is device only.

FAIL:

- Cloud active metadata remains active after successful local registration.
- Local file is not created.
- Storage object physical delete occurs.

## 7. R3-MQA-03 Grace Upload Blocked

Preconditions:

- Signed-in manual QA account.
- Expired within 30-day grace.
- One `device/localOnly` clip.

Steps:

1. Record Firestore/Storage/local before.
2. Attempt upload/move-to-cloud.
3. Record snackbar/dialog/log gate.
4. Record Firestore/Storage/local after.

Expected:

- New upload is blocked.
- No new Cloud active metadata is created.
- No new Storage object is created.
- Device clip remains active.

PASS:

- Active state remains device only and `subscription_expired` or equivalent write gate is observed.

FAIL:

- New Cloud active metadata or Storage object is created.

## 8. R3-MQA-04 Grace Download/Move-To-Device Allowed

Preconditions:

- Signed-in manual QA account.
- Expired within 30-day grace.
- One existing `cloud/cloudOnly` clip.

Steps:

1. Record Firestore active metadata before.
2. Record Storage object before.
3. Record local file/index before.
4. Execute download/move-to-device.
5. Record local, Firestore, Storage after.

Expected:

- Existing Cloud clip can be recovered during grace.
- Local file and index are created.
- Cloud active metadata becomes trash/tombstone.
- Storage object remains physically present.

PASS:

- Active state becomes device only.

FAIL:

- Grace blocks recovery of an existing Cloud clip.
- Cloud active metadata remains active after successful local registration.
- Storage object physical delete occurs.

## 9. R3-MQA-05 After Grace Download Blocked

Preconditions:

- Signed-in manual QA account.
- Expired after 30-day grace.
- One existing `cloud/cloudOnly` clip.

Steps:

1. Record Firestore/Storage/local before.
2. Attempt download/move-to-device.
3. Record snackbar/dialog/log gate.
4. Record Firestore/Storage/local after.

Expected:

- Cloud read/download is blocked.
- No local file is created.
- Cloud active metadata remains active.
- Storage object remains physically present.

PASS:

- Source Cloud state is preserved and access is blocked.

FAIL:

- Download succeeds after grace.
- Cloud active metadata is changed.
- Storage object physical delete occurs.

## 10. R3-MQA-06 Free Never Paid Cloud Access Blocked

Preconditions:

- Signed-in manual QA account.
- Free never paid state.
- Device clip and/or existing Cloud fixture if available.

Steps:

1. Attempt upload/move-to-cloud from a device clip.
2. Attempt Cloud list/read/download if a Cloud fixture is visible.
3. Record gate messages/logs.
4. Record Firestore/Storage/local before-after.

Expected:

- Upload is blocked.
- Cloud read/download is blocked.
- No grace behavior opens.
- No new Cloud metadata/object or local recovery file is created.

PASS:

- No Cloud access succeeds.

FAIL:

- Free never paid receives grace access.

## 11. R3-MQA-07 Legacy cloudSyncedLocal Automatic Cleanup Does Not Run

Preconditions:

- Existing legacy `cloudSyncedLocal` fixture or count-only diagnostics showing `cloudSyncedLocalCount > 0`.

Steps:

1. Record count-only diagnostics before.
2. Open Library, Profile, and Cloud surfaces without repair/migration.
3. Record count-only diagnostics after.
4. Confirm no manual cleanup or migration was executed.

Expected:

- Legacy state is classified as legacy/repair-needed.
- App does not automatically delete local files.
- App does not automatically trash/tombstone Cloud metadata.
- App does not destructively clean `cloud_synced_paths`.

PASS:

- No automatic destructive cleanup occurs.

FAIL:

- Legacy local files or Cloud metadata are automatically deleted/modified without an approved repair plan.

## 12. R3-MQA-08 Upload Failure Preserves Local

Preconditions:

- Signed-in manual QA account.
- One `device/localOnly` clip.
- Safe upload failure can be induced or observed.

Steps:

1. Record local file/index before.
2. Attempt upload/move-to-cloud under failure.
3. Record failure gate/log.
4. Record local, Firestore, Storage after.

Expected:

- Local file remains.
- Local index remains.
- State is `failedUpload` or still device/localOnly.
- No Cloud-only success state is shown.

PASS:

- Device copy remains active.

FAIL:

- Local file is removed before Cloud active completion.

BLOCKED:

- Safe failure induction is not available.

## 13. R3-MQA-09 Download Failure Preserves Cloud Active Metadata

Preconditions:

- Signed-in manual QA account with Cloud read permission.
- One `cloud/cloudOnly` clip.
- Safe download failure can be induced or observed.

Steps:

1. Record Firestore active metadata before.
2. Attempt download/move-to-device under failure.
3. Record failure gate/log.
4. Record local, Firestore, Storage after.

Expected:

- Cloud active metadata remains active.
- Cloud placeholder remains or can be restored by metadata pull.
- No device-only success state is shown.
- Storage object remains physically present.

PASS:

- Cloud copy remains active.

FAIL:

- Cloud active metadata is trash/tombstone despite failed local recovery.
- Storage object physical delete occurs.

BLOCKED:

- Safe failure induction is not available.

## 14. Evidence Template

```md
## R3 Move Model Manual QA Result

- Date:
- Tester:
- App build/version:
- Device:
- Firebase environment:
- Account state:
- uid: masked or unavailable

### Scenario

- ID:
- Verdict: PASS / FAIL / BLOCKED / N/A
- Preconditions:
- Steps executed:
- Expected result:
- Actual result:
- FAIL/BLOCKED reason:

### Evidence

- UI screenshots:
- Local file/index before:
- Local file/index after:
- Firestore active metadata before:
- Firestore active metadata after:
- Storage object before:
- Storage object after:
- App-controlled sensitive log gate:
- Notes:
```

## 15. Release Gate

Required PASS:

- R3-MQA-01 Active paid upload move.
- R3-MQA-02 Active paid download move.
- R3-MQA-03 Grace upload blocked.
- R3-MQA-04 Grace download/move-to-device allowed.
- R3-MQA-05 After grace download blocked.
- R3-MQA-06 Free never paid Cloud access blocked.
- R3-MQA-07 Legacy cloudSyncedLocal automatic cleanup does not run.

Required PASS or approved BLOCKED:

- R3-MQA-08 Upload failure preserves local.
- R3-MQA-09 Download failure preserves Cloud active metadata.

Release gate FAIL:

- Any normal active clip ends as both device and Cloud.
- Any successful move leaves the source active state active.
- Any failure path loses the only active copy.
- Storage object physical deletion occurs.
- Grace upload creates Cloud active metadata or Storage object.
- Grace download/move-to-device is blocked for an existing Cloud clip.
- After-grace download/move-to-device succeeds.
- Free never paid state receives grace Cloud access.
- Legacy `cloudSyncedLocal` data is automatically cleaned without an approved repair plan.

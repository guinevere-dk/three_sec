# Cloud Clip R3 User Action Cloud Upload Log Capture v1

## 1. Scope

- Date: 2026-05-19
- App package: `com.dk.three_sec`
- Device: Android emulator `emulator-5554`
- Method: user-performed action log capture
- AI UI operation: not performed during the user action window
- Login state: existing user-performed manual Google login session

Prohibited values were not recorded in this document:

- raw email
- password
- token
- order id
- raw provider value
- `.env`
- `TEST_GOOGLE_ID`
- `TEST_GOOGLE_PW`

## 2. Action Window

The user did not send a separate `시작` message. Because logcat had been cleared immediately before the instruction, this report treats the window as:

| Item | Value |
|---|---|
| Window start | after `adb logcat -c`, before user action |
| Window end | user message `완료` |
| In-log CloudService activity window | `05-19 05:32:29` to `05-19 05:32:43` |

## 3. Pre-Action State Probe

Before the user action:

```text
prefs.user_id_present=True
prefs.masked_uid=tUny...b0l1
prefs.tier=UserTier.standard
prefs.product_id=3s_standard_monthly
prefs.purchase_date_present=True
prefs.auth_mode_guest=false
```

App-controlled sensitive log gate:

```text
app_pid_count=1
app_sensitive.email=0
app_sensitive.password=0
app_sensitive.token=0
app_sensitive.order_id=0
app_sensitive.raw_provider=0
category.app_dart_log=0
category.app_native_log=0
```

## 4. Post-Action State Probe

After the user action:

```text
prefs.user_id_present=True
prefs.masked_uid=tUny...b0l1
prefs.tier=UserTier.standard
prefs.product_id=3s_standard_monthly
prefs.purchase_date_present=True
prefs.auth_mode_guest=false
```

Local cloud marker probe:

```text
cloud_synced_paths_count=0
local_index_entries_present=True
cloud_only_marker_present=True
```

## 5. Count-Only Log Analysis

```text
app_pid_count=1
log_line_count=8931
cloud_keyword.CloudService=9
cloud_keyword.uploadVideo=0
cloud_keyword.uploadVideoImmediate=0
cloud_keyword.enqueue=0
cloud_keyword.upload_queue=0
cloud_keyword.executeUpload=0
cloud_keyword.storage_upload=4
cloud_keyword.firestore_metadata=0
cloud_keyword.cloud_synced_paths=0
cloud_keyword.canStartNewCloudWrite=0
cloud_keyword.subscription_expired=0
cloud_keyword.tier_required=1494
cloud_keyword.permission_denied=0
cloud_keyword.auth_uid_missing=0
app_sensitive.email=0
app_sensitive.password=0
app_sensitive.token=0
app_sensitive.order_id=0
app_sensitive.raw_provider=0
category.app_dart_log=0
category.app_native_log=0
```

Notes:

- `tier_required=1494` is not treated as a Cloud gate hit. It was caused by repeated Profile diagnostic lines containing the word `Standard`, not by a `tier_required` error.
- `storage_upload=4` is not sufficient evidence of Storage upload. The targeted CloudService-only extraction showed download flow, not upload flow.

## 6. CloudService Flow Classification

Targeted CloudService extraction found 9 related lines.

Classified flow:

| Flow | Count / Evidence | Classification |
|---|---:|---|
| Vlog metadata get start/ok | 2 | read/query, not upload |
| Upload queue restore status | 1 | queue empty |
| Cloud download request | 2 | download/read |
| Cloud download complete | 2 | download/read |
| Visual separator lines | 2 | non-action |

No raw matching log line is included here.

Important negative evidence:

| Expected upload signal | Count |
|---|---:|
| `uploadVideo` | 0 |
| `uploadVideoImmediate` | 0 |
| upload enqueue / queue insertion | 0 |
| `_executeUpload` | 0 |
| Firestore metadata create / `uploadStatus` create | 0 |
| `cloud_synced_paths` update | 0 |
| `canStartNewCloudWrite` block | 0 |
| `subscription_expired` | 0 |
| permission denied | 0 |
| auth uid missing | 0 |

## 7. Verdict

Cloud upload was not actually invoked during the captured user action window.

| Question | Verdict |
|---|---|
| Did CloudService upload entry run? | NO |
| Did `uploadVideoImmediate` run? | NO |
| Did upload queue enqueue? | NO |
| Was upload blocked by subscription gate? | NO evidence |
| Was upload blocked by auth uid missing? | NO evidence |
| Was upload blocked by permission denied? | NO evidence |
| Was Firestore metadata creation attempted? | NO evidence |
| Was Storage upload attempted? | NO evidence |
| Was Cloud download/read invoked? | YES |

Root classification:

```text
UI route / action mismatch: the user-performed action triggered existing Cloud read/download behavior, not Cloud upload.
```

## 8. Next Action

Recommended next step:

1. Use the current signed-in active paid state.
2. In the app, identify a local-only clip with no Cloud badge.
3. Enter multi-select mode on that local-only clip.
4. Trigger the cloud upload/move action specifically.
5. Re-run this capture.

If the UI route remains ambiguous or inaccessible, add a temporary QA-only trigger that calls the existing `CloudService.uploadVideoImmediate` path for one selected local clip. That would be a QA route fix, not a Cloud copy implementation.

Evidence collection can proceed only after one of these upload signals appears:

- `uploadVideoImmediate`
- `uploadVideo`
- upload queue enqueue
- Firestore metadata create with `uploadStatus`
- Storage path under `users/{maskedUid}/videos/{videoId}/{fileName}`

## 9. Prohibited Scope Confirmation

Confirmed not performed:

- `.env` read/output
- `TEST_GOOGLE_ID` output
- `TEST_GOOGLE_PW` output
- login automation
- password input
- raw email/token/order id/provider output in this document
- Firebase rules/index change
- Firestore schema change
- migration/backfill
- Storage deletion
- Cloud copy implementation
- deploy
- unrelated cleanup

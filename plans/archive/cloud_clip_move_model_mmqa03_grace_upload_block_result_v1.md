# Cloud Clip Move Model MMQA-03 Grace Upload Block Result v1

## Scenario

- ID: MMQA-03 / R3-MQA-03
- Scenario: Grace upload blocked
- Date: 2026-05-20
- Device: Android emulator
- App package: `com.dk.three_sec`
- Account: signed-in QA account
- Login method: user-performed manual Google login
- Verdict: BLOCKED

## Intended Preconditions

Required:

- expired within 30-day grace state
- one verified `device/localOnly` clip
- app-controlled sensitive log gate PASS or previously documented plugin/runtime WARN only
- Cloud upload/move-to-cloud attempt should occur while `can_start_new_cloud_write=false`

## Setup Performed

The app was fully stopped before SharedPreferences injection.

SharedPreferences backup files were created inside the app data sandbox:

- before injection backup: present
- after injection backup: present

Injected local grace state:

- local tier key removed so runtime tier loads as Free
- Standard monthly product history preserved
- purchase history set to a date whose inferred monthly expiry is within the 30-day grace window for 2026-05-20
- user id key preserved

No raw uid, local path, Storage path, file name, email, token, order id, or provider value is recorded here.

## Grace State Load Evidence

After app restart:

- runtime tier loaded as `UserTier.free`
- Standard product history loaded
- Cloud metadata pull was allowed, consistent with grace read behavior
- local mp4 count before action setup: `60`

At this point the intended MMQA-03 state appeared to be in place.

## Blocker

Before the upload attempt, the user opened Profile > subscription management and returned.

Observed effect:

- Profile/Library state refreshed from Free/grace to Standard.
- Cloud upload button appeared.
- The subsequent upload action ran with `can_start_new_cloud_write=true`.

Therefore the action window did not run under the intended expired-within-grace state.

This invalidates MMQA-03 as a grace upload block test.

Related issue recorded separately:

- `plans/cloud_clip_subscription_state_refresh_on_launch_issue_v1.md`

## Action Window Evidence

The user selected a device/local clip and pressed the Cloud upload button after the state had refreshed.

Count-only markers:

| Marker | Count |
| --- | ---: |
| `LibraryTransfer` | 7 |
| `resolved_action=upload` | 3 |
| `branch=upload_move` | 1 |
| `can_start_new_cloud_write=false` | 1 |
| `can_start_new_cloud_write=true` | 4 |
| `write_gate_blocked` | 0 |
| `subscription_expired` | 0 |
| `uploadVideoImmediate` | 4 |
| `ThumbnailUpload` | 1 |
| `thumbnail_upload_success` | 1 |
| `thumbnail_metadata_commit_success` | 1 |
| `local_cleanup_executed=true` | 1 |
| `permission_denied` | 0 |
| `StorageException` | 0 |
| Storage physical delete marker | 0 |

Interpretation:

- upload was not blocked by grace write gate
- upload path proceeded after the state refreshed to Standard
- this is not valid evidence for MMQA-03 PASS or FAIL because the precondition was lost

## Local / Cloud Evidence

Local:

- local mp4 count after action: `60`

Cloud/UI:

- Library active view showed Cloud cards after the action.
- Because the action ran under Standard, any Cloud active metadata/object changes are outside MMQA-03's intended grace-block validation window.

Storage:

- Storage physical delete marker: `0`
- `StorageException`: `0`
- `permission_denied`: `0`

## Sensitive Log Gate

Action/log window count-only scan:

| Category | Count |
| --- | ---: |
| app-controlled email-like hit | 0 |
| app-controlled path-like raw hit | 0 |
| app-controlled raw uid filter marker | 3 |
| app-controlled redacted path marker | 22 |

Raw values are not printed in this report.

Security note:

- app-controlled raw uid-like filter logging was observed in CloudService/vlog metadata diagnostics during this run.
- This should be treated as a separate sensitive-log follow-up before strict security gate PASS.

## PASS Criteria Check

| Requirement | Result |
| --- | --- |
| upload/move-to-cloud blocked in grace | BLOCKED, action did not remain in grace |
| `subscription_expired` or write gate observed | Not observed |
| local device clip preserved | Inconclusive for grace; upload action ran under Standard |
| Cloud active count increase absent | Not valid; action ran under Standard |
| thumbnailReadyCount increase absent | Not valid; action ran under Standard |
| Storage physical delete absent | PASS |
| sensitive app log gate PASS | FAIL, raw uid-like filter marker observed |

## FAIL Criteria Check

| Failure Condition | Observed |
| --- | --- |
| grace upload created Cloud metadata/object | Not proven; action state changed to Standard |
| local file deleted during grace block | Not proven |
| upload success toast under grace | Not proven |
| raw sensitive app log | Yes, raw uid-like filter marker count > 0 |

## Verdict

MMQA-03 / R3-MQA-03 Grace upload blocked: BLOCKED.

Reason:

- The intended expired-within-grace precondition was invalidated when subscription management refreshed the account to active Standard before the upload action.
- The upload action then ran with `can_start_new_cloud_write=true`, so it cannot validate grace upload blocking.
- A separate subscription state refresh issue has been recorded.
- Strict sensitive log gate also requires follow-up because app-controlled raw uid-like filter logging was observed.

## Required Next Step

Before rerunning MMQA-03:

1. Decide whether the test should use a QA account that is actually expired within grace, not locally injected over an active Standard account.
2. Or add a QA-only state lock/test harness that prevents subscription management/store refresh from overriding the injected grace state during the test window.
3. Redact CloudService/vlog metadata filter diagnostics so raw uid-like values are not logged.

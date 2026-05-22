# MMQA-01 / R3-MQA-01 Active Paid Upload Move Result v2

## Summary

- Scenario: MMQA-01 / R3-MQA-01 Active paid upload move rerun
- Date: 2026-05-19
- Runtime basis: clean rebuild/reinstall verified in `cloud_clip_move_model_runtime_build_verification_v1.md`
- Login: user-performed manual Google login
- Subscription state: active Standard injected and verified as `UserTier.standard`
- Fixture: new QA clip created while temporarily in signed-in free never paid state
- Sensitive log gate: PASS for app-controlled logs
- Verdict: FAIL

## User Correction / Addendum

After the initial result was written, the user clarified that an upload failure toast had appeared during the run.

This changes the interpretation:

- The user action was not a successful upload completion.
- The app surfaced an upload failure state under active Standard.
- MMQA-01 should be treated as an active paid upload move failure, not merely an inconclusive/no-action run.

No raw toast internals, uid, email, token, order id, provider value, or local path were recorded.

## Failure Summary

The rerun failed because active paid upload move did not complete.

After the user action:

- local mp4 count stayed `1 -> 1`
- `cloud_synced_paths` count evidence stayed unchanged
- `local_index_entries_v1` count evidence stayed unchanged
- `uploadVideoImmediate=0`
- `upload_completed=0`
- `removeLocalClipAfterCloudMove=0`
- `move_to_cloud=0`
- user reported an upload failure toast

The source device copy remained, which is the correct preservation behavior for upload failure. However, MMQA-01 requires active paid upload move success, so the scenario verdict is FAIL.

## Runtime Build Identity

From the prior runtime verification:

| Field | Value |
| --- | --- |
| Build | debug APK |
| App version | `1.3.6+136` |
| APK install time | `2026-05-19 07:49:20` |
| Source state | move-model cleanup calls present |
| Clean rebuild/reinstall | PASS |

## Login And Sensitive Log Gate

Login was completed manually by the user.

Signed-in storage evidence:

- Firebase Auth shared preference store files were present.
- No raw uid, email, token, password, order id, provider value, or local path was printed.

Initial log gate after login:

| Check | Result |
| --- | --- |
| Firebase Auth storage exists | PASS |
| App-controlled raw sensitive output | PASS after tag-only triage |
| System/non-app log hits | WARN only |

Tag-only triage found hits in system/non-app tags such as `AppsFilter`, `WindowManager`, `FlagStore`, `gmoe`, and `FlagRegistrar`. No raw matching lines were printed.

## State Injection

Active Standard was injected after login, then the app was restarted.

| Field | Result |
| --- | --- |
| `flutter.3s_user_tier` | `UserTier.standard` |
| Product value present | true |
| Purchase date value present | true |

For local-only fixture creation, the app was then temporarily changed to signed-in free never paid:

| Field | Result |
| --- | --- |
| `flutter.3s_user_tier` | `UserTier.free` |
| Product value present | false |
| Purchase date value present | false |

After fixture creation, active Standard was restored:

| Field | Result |
| --- | --- |
| `flutter.3s_user_tier` | `UserTier.standard` |
| Product value present | true |
| Purchase date value present | true |

## Fixture Evidence

The fixture was created after clean reinstall.

| Evidence | Before fixture | After fixture |
| --- | ---: | ---: |
| Local mp4 file count | 0 | 1 |

SharedPreferences count evidence after fixture creation in free state:

| Evidence | Count |
| --- | ---: |
| `cloud_synced_paths` length | 600 |
| `cloud_synced_paths` cloud-only marker count | 9 |
| `cloud_synced_paths` mp4 marker count | 9 |
| `local_index_entries_v1` length | 5191 |
| `local_index_entries_v1` cloud-only marker count | 18 |
| `local_index_entries_v1` mp4 marker count | 38 |

Interpretation:

- One local mp4 was created.
- Existing Cloud metadata placeholders were present after signed-in metadata pull.
- No raw local path was printed.

## Before Upload Evidence

Captured after restoring active Standard and before user upload action.

| Evidence | Before upload |
| --- | ---: |
| Local mp4 file count | 1 |
| `cloud_synced_paths` length | 600 |
| `cloud_synced_paths` cloud-only marker count | 9 |
| `cloud_synced_paths` mp4 marker count | 9 |
| `local_index_entries_v1` length | 5191 |
| `local_index_entries_v1` cloud-only marker count | 18 |
| `local_index_entries_v1` mp4 marker count | 38 |

Logcat was cleared before upload action.

## User Action

The user reported upload completion.

AI did not automate OAuth, password input, or arbitrary app UI navigation.

## After Upload Evidence

Captured after the user reported upload completion.

| Evidence | Before | After |
| --- | ---: | ---: |
| Local mp4 file count | 1 | 1 |
| `cloud_synced_paths` length | 600 | 600 |
| `cloud_synced_paths` cloud-only marker count | 9 | 9 |
| `cloud_synced_paths` mp4 marker count | 9 | 9 |
| `local_index_entries_v1` length | 5191 | 5191 |
| `local_index_entries_v1` cloud-only marker count | 18 | 18 |
| `local_index_entries_v1` mp4 marker count | 38 | 38 |

Interpretation:

- There was no count evidence of Cloud metadata/placeholder creation.
- There was no count evidence of local active file removal.
- The move-model upload path did not complete.

## Logcat Evidence

Raw matching values were not printed.

Keyword counts:

| Keyword | Count |
| --- | ---: |
| `uploadVideoImmediate` | 0 |
| `uploadVideo` | 0 |
| `CloudService` | 7 |
| `putFile` | 0 |
| `upload_completed` | 0 |
| `completed` | 4 |
| `removeLocalClipAfterCloudMove` | 0 |
| `move_to_cloud` | 0 |
| `metadata` | 3 |
| `Storage` | 0 |
| `permission denied` | 0 |
| `subscription_expired` | 0 |
| `tier_required` | 0 |
| `auth uid missing` | 0 |

Sensitive log gate:

| Check | Count | Result |
| --- | ---: | --- |
| App-controlled sensitive hits | 0 | PASS |
| App-controlled line count | 650 | informational |

## UI Evidence

UIAutomator text after the reported upload showed:

- Library album header: `일상 10 / 10 Clips`
- Storage filters: `전체`, `기기`
- Bottom navigation: `Camera`, `Library`, `Profile`

No accessible text confirmed that the selected fixture changed to `Cloud`.

The UI count includes existing Cloud placeholders plus the new local clip, so it is not enough by itself to prove a successful move.

## Firestore Evidence

Direct Firestore before/after evidence was not collected in this rerun without exposing raw document identifiers.

Since upload entry was not observed and local/marker counts did not change, this scenario did not reach the point where Firestore active metadata verification could be meaningfully performed.

## Storage Evidence

Direct Storage object listing was not collected in this rerun without exposing raw object paths.

Since upload entry was not observed and `Storage=0`, this scenario did not reach the point where Storage object existence could be meaningfully verified.

No Storage physical deletion evidence was observed.

## Verdict

FAIL.

Reason:

- Active paid upload move did not complete.
- The user reported an upload failure toast.
- `uploadVideoImmediate=0`, `upload_completed=0`, `Storage=0`.
- Local and Cloud marker/index counts were unchanged.

Positive safety observation:

- Local mp4 count stayed `1 -> 1`, so upload failure did not remove the only local copy.

## PASS Criteria Check

| Criterion | Result |
| --- | --- |
| Active state becomes `cloud/cloudOnly` | FAIL |
| Library shows `Cloud` badge | FAIL / not observed |
| Local active file/index removed | FAIL, upload did not complete |
| Firestore active metadata completed/active | FAIL / not observed |
| Storage object exists | FAIL / not observed |
| Storage object physical deletion absent | PASS, no evidence of deletion |
| New normal state not `cloudSyncedLocal` | PASS by absence of new Cloud state evidence |
| App-controlled sensitive log gate | PASS |
| Upload failure preserves local copy | PASS |

## Immediate Follow-Up

The next rerun should verify the UI route before the upload action:

1. In Library, tap `기기` filter.
2. Confirm exactly one visible local fixture is selected.
3. Long-select the local fixture.
4. Confirm the transfer icon is `cloud_upload_rounded`, not download/restore.
5. Clear logcat immediately before tapping.
6. Tap the transfer button.
7. Wait 20-30 seconds.
8. Capture:
   - `uploadVideoImmediate`
   - `upload_completed`
   - `removeLocalClipAfterCloudMove`
   - local mp4 count
   - marker/index count

If the upload icon appears but a failure toast appears again, capture only count/tag evidence and classify the failing gate:

- subscription/write gate
- auth missing
- Firebase permission denied
- Storage/Firestore upload failure
- UI selected path not localOnly
- unknown app failure

## Safety Notes

- No Firebase rules/index/schema changes were made.
- No migration/backfill was run.
- No Storage physical deletion was performed by AI.
- No legacy `cloudSyncedLocal` cleanup was performed.
- No deploy was performed.
- No raw uid/email/token/order id/provider/local path values were recorded.

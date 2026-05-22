# MMQA-01 / R3-MQA-01 Active Paid Upload Move Result v1

## Summary

- Scenario: MMQA-01 / R3-MQA-01 Active paid upload move
- Date: 2026-05-19
- Account: signed-in QA account
- Login: user-performed manual login state
- Subscription state: active Standard injected and verified as `UserTier.standard`
- Sensitive log gate: PASS for app-controlled logs
- Verdict: FAIL

## Policy Under Test

Expected move-model result:

- Source state: `device/localOnly`
- Target state after upload: `cloud/cloudOnly`
- Local active file/index removed after Cloud active upload completion
- Firestore active metadata completed/active
- Storage object exists
- Storage object physical deletion does not occur
- New normal state must not become `cloudSyncedLocal`

## Fixture Preparation

The existing legacy clips were not used as upload fixtures because prior diagnostics showed legacy Cloud markers. A new QA fixture was created while the app was temporarily set to free state so auto Cloud upload would not run.

Count-only fixture evidence:

| Evidence | Before fixture | After fixture |
| --- | ---: | ---: |
| Local mp4 file count | 8 | 9 |
| `cloud_synced_paths` cloud-only marker count | 7 | 7 |
| `cloud_synced_paths` mp4 marker count | 15 | 15 |

Interpretation:

- A new local mp4 was created.
- Cloud marker counts did not increase during fixture creation.
- The new fixture was treated as a `device/localOnly` candidate.

## Active Paid State Injection

The initial Standard reinjection used the wrong tier string and the upload button did not appear. The app was stopped, SharedPreferences was backed up, and the tier was corrected.

Verified state:

| Field | Result |
| --- | --- |
| `flutter.3s_user_tier` | `UserTier.standard` |
| Product value present | true |
| Purchase date value present | true |

No raw uid, email, token, order id, provider, or local path values were recorded.

## Before Evidence

Captured after active Standard reinjection and before the user tapped upload.

| Evidence | Before |
| --- | ---: |
| Local mp4 file count | 9 |
| `cloud_synced_paths` length | 1164 |
| `cloud_synced_paths` cloud-only marker count | 7 |
| `cloud_synced_paths` mp4 marker count | 15 |
| `local_index_entries_v1` length | 7467 |
| `local_index_entries_v1` cloud-only marker count | 14 |
| `local_index_entries_v1` mp4 marker count | 52 |

Firestore/Storage direct console evidence was not collected before the tap in a raw-safe automated way. The after verdict does not depend on direct Firestore/Storage inspection because the local-source removal criterion failed.

## User Action

The user selected one clip in Library and completed the Cloud upload action.

AI did not automate OAuth, password input, or arbitrary app UI navigation.

## After Evidence

Captured after the user reported upload completion.

| Evidence | Before | After |
| --- | ---: | ---: |
| Local mp4 file count | 9 | 9 |
| `cloud_synced_paths` length | 1164 | 1312 |
| `cloud_synced_paths` cloud-only marker count | 7 | 8 |
| `cloud_synced_paths` mp4 marker count | 15 | 17 |
| `local_index_entries_v1` length | 7467 | 8011 |
| `local_index_entries_v1` cloud-only marker count | 14 | 16 |
| `local_index_entries_v1` mp4 marker count | 52 | 56 |

Interpretation:

- Cloud-side local metadata/placeholder evidence increased.
- Local mp4 file count did not decrease.
- Local active copy removal was not verified and appears not to have happened.

## Logcat Evidence

Raw matching values were not printed.

Keyword counts after upload:

| Keyword | Count |
| --- | ---: |
| `CloudService` | 5 |
| `upload_completed` | 1 |
| `completed` | 1 |
| `metadata` | 4 |
| `Storage` | 5 |
| `permission denied` | 0 |
| `subscription_expired` | 0 |
| `tier_required` | 0 |
| `auth uid missing` | 0 |

Sensitive log gate:

| Check | Count | Result |
| --- | ---: | --- |
| Email-like total, all logcat sources | 2 | WARN, source not app-controlled |
| Sensitive-word total, all logcat sources | 4 | WARN, source not app-controlled |
| App-controlled sensitive hits | 0 | PASS |

## Firestore Evidence

Direct Firestore before/after document inspection was not completed in this run without exposing raw document identifiers.

Available app evidence:

- Upload completion log keyword count: `upload_completed=1`
- Metadata keyword count: `metadata=4`
- Cloud marker/placeholder count increased after upload.

This is enough to infer that the upload path likely reached Cloud metadata completion, but it is not sufficient for a standalone Firestore PASS. The scenario is already FAIL due local active copy retention.

## Storage Evidence

Direct Storage object listing was not completed in this run without exposing raw object paths.

Available app evidence:

- Storage keyword count after upload: `Storage=5`
- Upload completion keyword count: `upload_completed=1`
- No Storage physical delete evidence was observed in app-controlled logs.

This is not a direct Storage PASS. The scenario is already FAIL due local active copy retention.

## UI Evidence

UIAutomator dump after upload showed:

- Current album count: `9 Clips`
- Storage filter buttons include `전체` and `기기`
- Visible clip thumbnails: 9

The `Cloud` badge was not exposed in the UIAutomator text dump, so Library badge PASS was not verified from accessibility text.

## Verdict

FAIL.

Primary failure:

- Local active file count remained `9 -> 9` after upload completion.
- Move-model upload requires local active file/index removal after Cloud active upload completion.

Secondary concerns:

- `local_index_entries_v1` count-like evidence increased instead of showing source local index removal.
- Direct Firestore/Storage before-after evidence was not available in a raw-safe automated form for this run.
- UI `Cloud` badge was not verified via UIAutomator text.

## PASS Criteria Check

| Criterion | Result |
| --- | --- |
| Active state becomes `cloud/cloudOnly` | FAIL |
| Library shows `Cloud` badge | BLOCKED |
| Local active file/index removed | FAIL |
| Firestore active metadata completed/active | INFERRED, not direct PASS |
| Storage object exists | INFERRED, not direct PASS |
| Storage object physical deletion absent | No app evidence of deletion; direct audit unavailable |
| New normal state not `cloudSyncedLocal` | FAIL risk, because local active copy remained while Cloud marker/placeholder increased |

## Follow-Up

1. Ensure the emulator is running a build that includes the move-model implementation:
   - `LibraryScreen._moveSelectedLocalToCloudInBackground()` calls `removeLocalClipAfterCloudMove(...)`.
   - `CloudService.uploadVideoImmediate()` performs best-effort local cleanup after upload completion.
2. Re-run MMQA-01 after reinstalling or hot-restarting the updated app build.
3. Add a raw-safe QA diagnostic endpoint or log line for count-only state after move:
   - `localFileCount`
   - `localOnlyCount`
   - `cloudOnlyCount`
   - `cloudSyncedLocalCount`
   - `uploadableCount`
4. Add raw-safe Firestore/Storage evidence tooling for QA account scoped counts and state summaries.

## Safety Notes

- No Firebase rules/index/schema changes were made.
- No migration/backfill was run.
- No Storage object physical deletion was performed by AI.
- No legacy `cloudSyncedLocal` cleanup was performed.
- No deploy was performed.
- No raw uid/email/token/order id/provider/local path values were recorded.

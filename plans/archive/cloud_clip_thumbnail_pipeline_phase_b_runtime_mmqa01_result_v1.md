# Cloud Clip Thumbnail Pipeline Phase B Runtime MMQA-01 Result v1

## Verdict

FAIL

MMQA-01 active paid upload move was re-run with the latest Phase B APK installed. The immediate upload move route reached `uploadVideoImmediate()`, generated a thumbnail, then failed during thumbnail Storage upload. Local cleanup was not executed, so the failure safety rule was preserved.

The run still fails MMQA because:

- thumbnail upload failed, so no successful Cloud move occurred
- app-controlled sensitive log gate had raw uid/path-like candidate hits

## Runtime Setup

- Latest debug APK build: PASS
- APK installed with data-preserving reinstall: PASS
- signed-in QA account: assumed active from existing session
- active Standard state log: observed before action
- app data clear/uninstall/wipe: not performed
- logcat cleared immediately before the user upload action

## Before Evidence

Before the action window:

| Evidence | Count |
| --- | ---: |
| local mp4 count | 54 |
| Cloud active count | 11 |
| thumbnailReadyCount | 0 |
| thumbnailMissingCount | 11 |
| thumbnailFailedCount | 0 |

Selection/action route evidence during the action window:

| Event | selected | localOnly | cloudOnly | cloudSyncedLocal | pendingUpload | failedUpload | uploadable | action | branch |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| render | 1 | 1 | 0 | 0 | 0 | 0 | 1 | upload | render |
| tap_start | 1 | 1 | 0 | 0 | 0 | 0 | 1 | upload | upload_move |

This confirms the user-selected fixture was treated as localOnly/uploadable and the button route was upload move.

## Action Window Counters

Library upload move summary:

| Counter | Value |
| --- | ---: |
| uploadVideoImmediate_call_count | 1 |
| upload_success_count | 0 |
| upload_failure_count | 1 |
| skipped_count | 0 |
| final_toast_type | failure |

Phase B thumbnail pipeline summary:

| Counter | Value |
| --- | ---: |
| result | failure |
| thumbnail_generation_attempt_count | 1 |
| thumbnail_generation_success | 1 |
| thumbnail_generation_failure | 0 |
| thumbnail_upload_attempt_count | 1 |
| thumbnail_upload_success | 0 |
| thumbnail_upload_failure | 1 |
| thumbnail_metadata_commit_success | 0 |
| thumbnail_metadata_commit_failure | 0 |
| local_cleanup_executed | false |

Failure-related tag-only summary:

| Source Tag | Count |
| --- | ---: |
| E/StorageException | 61 |
| W/StorageUtil | 4 |
| I/flutter | 2 |

Raw-safe classifier:

- Primary failure category: Storage upload failure
- Permission-denied text count in Storage logs: 2
- `thumbnail_upload_failed` app code count: 2
- `thumbnail_generation_failed` count: 0
- `thumbnail_metadata_failed` count: 0

## After Evidence

After the failed upload attempt:

| Evidence | Result |
| --- | --- |
| local mp4 count | 56 |
| local mp4 count decreased | NO |
| local cleanup executed | false |
| Cloud active count after action | not refreshed in action-window logs |
| cloudOnly count increased | NO evidence |
| thumbnailReadyCount increased | NO |
| fallbackCloudCardCount increased | NO evidence |
| Cloud-only card thumbnail-ready | N/A, upload failed |
| Storage physical delete log count | 0 |

The local count did not decrease, which is consistent with the required failure safety behavior. Because the run failed before thumbnail upload completion and metadata commit, a successful Cloud-only thumbnail-ready card was not expected.

## Sensitive Log Gate

App-controlled sensitive log scan was count/tag-only. No raw values were printed.

| Category | Count | Tag Summary |
| --- | ---: | --- |
| email-like app log hit | 0 | N/A |
| token/order/provider app log hit | 0 | N/A |
| path/.mp4-like app log hit | 3 | I/flutter=3 |
| raw uid-like app log hit | 2 | I/flutter=2 |

Component-only classification:

| Category | CloudService | VideoManager | LibraryTransfer | UserStatusManager | Profile |
| --- | ---: | ---: | ---: | ---: | ---: |
| path/.mp4-like | 1 | 0 | 0 | 0 | 0 |
| uid-like | 2 | 0 | 0 | 0 | 0 |

Sensitive log gate verdict: FAIL.

## PASS Criteria Check

| Criterion | Result |
| --- | --- |
| `thumbnailStatus=completed` | FAIL |
| `thumbnailStoragePath` present | FAIL |
| `durationMs` present | FAIL |
| thumbnailReadyCount increased | FAIL |
| local file/index removed | FAIL, but correct for failed upload |
| resulting state is cloudOnly | FAIL |
| no cloudSyncedLocal normal success | PASS |
| no Storage physical delete | PASS |
| sensitive log gate PASS | FAIL |

## Failure Safety Check

| Safety Rule | Result |
| --- | --- |
| thumbnail failure must not delete local file/index | PASS |
| video-only upload must not be treated as move success | PASS |
| metadata missing must not trigger local cleanup | PASS |
| Storage physical delete must not occur | PASS |

## Root Cause Classification

Primary runtime blocker:

- `thumbnail_upload_failure=1`
- Storage logs include permission-denied text
- No Firestore metadata commit occurred
- local cleanup stayed disabled

Likely cause:

- Firebase Storage rules/path policy does not currently allow the new thumbnail child path, or the runtime request is otherwise denied by Storage authorization.

Secondary gate blocker:

- app-controlled sensitive log gate failed due to raw uid/path-like candidate hits from CloudService-related Flutter logs.

## Required Follow-Up

1. Fix app-controlled CloudService sensitive logging before another security-gated MMQA pass.
2. Triage thumbnail Storage upload permission for:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

3. Do not change Firebase rules/schema/index without a separate approved plan.
4. Re-run MMQA-01 after the logging fix and approved thumbnail Storage authorization plan.

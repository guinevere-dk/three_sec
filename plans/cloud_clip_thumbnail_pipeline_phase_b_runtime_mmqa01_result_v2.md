# Cloud Clip Thumbnail Pipeline Phase B Runtime MMQA-01 Result v2

## Verdict

FAIL on strict security gate.

Functional upload move path: PASS.

After deploying Storage thumbnail rules, the immediate upload move completed the expected Phase B sequence:

1. localOnly upload route selected
2. `uploadVideoImmediate()` called
3. thumbnail generation succeeded
4. thumbnail Storage upload succeeded
5. Firestore thumbnail metadata commit succeeded
6. local cleanup executed after Cloud completion

However, the strict sensitive log gate still found path-like raw candidates in `I/flutter` logs, so the overall MMQA verdict remains FAIL until those hits are classified or redacted.

## Deploy Evidence

Pre-deploy checks:

- `firebase use`: `fir-3s-8edb9`
- `git diff -- firebase/storage.rules`: thumbnail-only rule/helper change

Deploy command:

```text
firebase deploy --only storage
```

Result:

- PASS
- target project: `fir-3s-8edb9`
- deployed scope: `storage`
- `firebase/storage.rules` compiled successfully
- deploy complete

No Firestore rules/index, Functions, Hosting, migration/backfill, or Storage object delete was performed.

## Runtime Setup

- latest debug APK rebuilt: PASS
- APK installed with `adb install -r`: PASS
- app data/session preserved: PASS
- active Standard state logs observed before action
- logcat cleared immediately before user action
- user performed upload action manually

## Before Evidence

| Evidence | Count |
| --- | ---: |
| local mp4 count | 56 |
| Cloud active count | 10 |
| thumbnailReadyCount | 0 |
| thumbnailMissingCount | 10 |
| thumbnailFailedCount | 0 |

## Action Route Evidence

| Event | selected | localOnly | cloudOnly | cloudSyncedLocal | pendingUpload | failedUpload | uploadable | action | branch |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| render | 1 | 1 | 0 | 0 | 0 | 0 | 1 | upload | render |
| tap_start | 1 | 1 | 0 | 0 | 0 | 0 | 1 | upload | upload_move |

Upload move summary:

| Counter | Value |
| --- | ---: |
| uploadVideoImmediate_call_count | 1 |
| upload_success_count | 1 |
| upload_failure_count | 0 |
| skipped_count | 0 |
| final_toast_type | success |

## Phase B Thumbnail Counters

| Counter | Value |
| --- | ---: |
| result | success |
| thumbnail_generation_attempt_count | 1 |
| thumbnail_generation_success | 1 |
| thumbnail_generation_failure | 0 |
| thumbnail_upload_attempt_count | 1 |
| thumbnail_upload_success | 1 |
| thumbnail_upload_failure | 0 |
| thumbnail_metadata_commit_success | 1 |
| thumbnail_metadata_commit_failure | 0 |
| local_cleanup_executed | true |

Permission failure regression check:

| Signal | Count |
| --- | ---: |
| `thumbnail_upload_failed` | 0 |
| `permission_denied` | 0 |
| `StorageException` | 0 |

## After Evidence

| Evidence | Before | After | Result |
| --- | ---: | ---: | --- |
| local mp4 count | 56 | 55 | PASS |
| Cloud active count | 10 | 11 | PASS |
| thumbnailReadyCount | 0 | 1 | PASS |
| thumbnailMissingCount | 10 | 10 | PASS |
| thumbnailFailedCount | 0 | 0 | PASS |
| Storage physical delete log count | 0 | 0 | PASS |

Interpretation:

- local active copy was removed after all Cloud completion conditions.
- resulting Cloud metadata includes completed thumbnail evidence by count.
- no cloudSyncedLocal normal success was observed in action summary.
- no Storage physical delete signal was observed.

## Sensitive Log Gate

Raw values were not printed in this report. Scan was count/tag-only.

| Category | Count | Tag Summary |
| --- | ---: | --- |
| email-like app log hit | 0 | N/A |
| token/order/provider app log hit | 0 | N/A |
| raw uid-like app log hit | 0 | N/A |
| path/.mp4-like app log hit | 5 | I/flutter=5 |

Path-like hit classification:

| Component Marker | Count |
| --- | ---: |
| CloudService | 0 |
| VideoManager | 0 |
| LibraryTransfer | 0 |
| UserStatusManager | 0 |
| Profile | 0 |
| thumbnailLog | 0 |
| Firebase | 0 |
| Storage | 0 |
| I/flutter tag | 5 |

Additional marker scan:

- local data prefix marker count: 1
- Cloud Storage `users/` marker count: 0
- `video/mp4` marker count: 0
- known app component prefix count: 0

Sensitive log gate verdict: FAIL under strict policy because path-like candidates remain in `I/flutter`.

## PASS Criteria Check

| Criterion | Result |
| --- | --- |
| `thumbnailStatus=completed` | PASS by thumbnailReadyCount increase |
| `thumbnailStoragePath` present | PASS by thumbnailReadyCount increase |
| `durationMs` present | PASS by metadata commit success path |
| thumbnailReadyCount increased | PASS |
| local file/index removed | PASS |
| resulting state is cloudOnly | PASS by Cloud active count increase and local count decrease |
| no cloudSyncedLocal normal success | PASS |
| no Storage physical delete | PASS |
| sensitive log gate PASS | FAIL |

## Final Assessment

The Storage rules deploy fixed the prior thumbnail upload permission-denied blocker.

Phase B functional move model behavior is now verified for this run:

- video upload success
- thumbnail upload success
- metadata commit success
- local cleanup after completion

The remaining blocker is security/log hygiene:

- path-like `I/flutter` hits remain but were not attributable to CloudService, VideoManager, LibraryTransfer, UserStatusManager, Profile, Firebase, or Storage markers by count-only classification.
- A focused raw-safe source triage is required before declaring MMQA-01 fully PASS.

## Required Follow-Up

1. Perform count/tag-only source triage of the remaining `I/flutter` path-like hits.
2. Do not print raw matching lines.
3. If app-controlled, redact the source.
4. If Flutter/system/runtime-only and not app-controlled, document an explicit QA gate exception.

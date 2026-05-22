# Cloud Clip MMQA-03 CloudService Sensitive Log Redaction v1

## Scope

Redacted app-controlled CloudService vlog metadata diagnostics that could expose raw uid-like filter/query values.

Out of scope:

- Firebase rules/index/schema changes
- migration/backfill
- Storage physical delete
- deploy
- product behavior changes
- unrelated cleanup

## Changed Files

- `lib/services/cloud_service.dart`
- `plans/cloud_clip_mmqa03_cloudservice_sensitive_log_redaction_v1.md`

## Root Cause

MMQA-03 runtime logging showed app-controlled raw uid-like values from CloudService vlog metadata diagnostics.

The primary source was the vlog metadata query start log:

- `getUserVlogProjectMetadataMap()`
- query diagnostic included a raw uid in the filter description

Additional vlog metadata diagnostics also printed project identifiers directly. These were not the MMQA-03 blocker, but they are identifier-like values and were redacted in the same narrow diagnostic area.

## Implementation

Updated CloudService vlog metadata diagnostic output only.

Redacted fields:

- uid filter value
- auth uid
- target uid
- project document id
- local project id
- cloud project id
- Firebase error message text
- non-Firebase error text

Allowed output forms:

- masked uid: `abcd...wxyz`
- masked project id
- `<lookup>`
- `<redacted-error>`
- count/status-only fields such as collection name, doc count, deleted doc count, clip count, status code

No query behavior or Firestore writes were changed.

## Static Search

Checked for remaining direct vlog metadata diagnostic patterns:

```text
rg -n -F 'filters=uid==$uid' lib\services\cloud_service.dart
rg -n -F 'localProjectId=$localProjectId' lib\services\cloud_service.dart
rg -n -F 'cloudProjectId=$cloudProjectId' lib\services\cloud_service.dart
rg -n -F 'projectDocId=$projectDocId' lib\services\cloud_service.dart
```

Result: no remaining matches.

Follow-up search showed vlog metadata diagnostics now use `_maskUid(...)` / `_maskId(...)` for identifier output.

## Verification

Format:

```text
dart format lib\services\cloud_service.dart
```

Result: PASS.

Tests:

```text
flutter test test/user_status_manager_r3_test.dart test/video_manager_clip_storage_state_test.dart test/cloud_thumbnail_metadata_model_test.dart test/library_clip_transfer_action_test.dart test/media_widgets_cloud_only_renderer_test.dart
```

Result: PASS, 37 tests.

Build/install:

```text
flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Result: PASS.

Targeted analyzer:

```text
flutter analyze lib\services\cloud_service.dart
```

Result: FAIL due to existing lint debt in `cloud_service.dart`.

Observed categories:

- existing `avoid_print` info entries
- existing unused `_checkStandardOrAbove` warning

No compile or test failure was introduced.

## Runtime Recheck

After installing the rebuilt debug APK:

1. Cleared logcat.
2. Launched the app.
3. Let Profile/startup trigger vlog metadata diagnostics.
4. Scanned app-controlled logs count-only.

Results:

| Category | Count |
| --- | ---: |
| `vlogMeta` marker | 4 |
| raw uid filter marker | 0 |
| masked uid filter marker | 2 |
| app-controlled email-like hit | 0 |
| app-controlled raw path-like hit | 0 |
| raw project id marker | 0 |

The specific MMQA-03 upload-block action window was not rerun in this task because the prior MMQA-03 precondition was invalidated by subscription state refresh to active Standard. The redaction target was the CloudService/vlog metadata diagnostic source observed during that run, and the rebuilt runtime no longer emits the raw uid filter marker in the startup/vlog metadata window.

## Security Gate Status

CloudService/vlog metadata diagnostic redaction: PASS.

Remaining MMQA-03 blockers are separate:

- stable expired-within-grace test account or QA-only state lock is needed
- subscription state refresh-on-launch issue remains documented separately

## Forbidden Scope Check

Not performed:

- Firebase rules/index/schema changes
- migration/backfill
- Storage physical delete
- deploy
- Cloud copy
- unrelated cleanup

## Verdict

The app-controlled raw uid-like filter marker from CloudService/vlog metadata diagnostics has been redacted.

MMQA-03 can be retried after the grace-state precondition is made stable.

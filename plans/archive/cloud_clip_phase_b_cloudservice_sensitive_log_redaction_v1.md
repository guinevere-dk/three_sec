# Cloud Clip Phase B CloudService Sensitive Log Redaction v1

## Scope

Target file:

- `lib/services/cloud_service.dart`

Goal:

- Remove raw uid-like, local path, Storage path, file name, full video id, and raw exception message exposure from CloudService-controlled logs.
- Keep product behavior unchanged.

Out of scope:

- Firebase rules/index/schema
- Storage rules
- migration/backfill
- Storage physical delete
- deploy

## Changes

Added CloudService-local redaction helpers:

- `_maskUid(...)`
- `_maskId(...)`
- `_redactedPathCountLabel(...)`
- `_redactErrorForMetadata(...)`

Updated CloudService logs to avoid raw values in:

- queue restore diagnostics
- queue duplicate diagnostics
- storage usage lookup/update diagnostics
- immediate upload preparation and failure handling
- queued upload diagnostics
- download diagnostics
- metadata update/delete diagnostics
- purge diagnostics
- vlog project metadata diagnostics

Updated error handling:

- `_classifySyncError(...)` now uses a redacted error string for user-facing error copy generation.
- `_safeUpdateFailureMetadata(...)` continues to store sanitized `errorMessage`.
- queued sync job failure `errorMessage` now stores sanitized error text.

## Raw-Safe Search Result

Command:

```text
rg -n "uid=\$uid|authUid=\$authUid|targetUid=\$uid|message=\$\{e\.message\}|error=\$e|실패: \$e|videoId=\$videoId|URL: \$downloadUrl|event=\$eventId|localPath=\$localPath|storagePath=\$storagePath|fileName=|p\.basename\(videoFile\.path\)" lib\services\cloud_service.dart
```

Remaining hits:

- `final fileName = p.basename(videoFile.path)` in data construction only.
- No remaining raw log output candidate from that search.

Notes:

- Firestore/Storage contract fields such as `fileName` and `storagePath` are still written as required application data.
- Logging of those values was redacted.

## Verification

Format:

```text
dart format lib\services\cloud_service.dart
```

Result: PASS.

Tests:

```text
flutter test test\cloud_thumbnail_metadata_model_test.dart test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart test\media_widgets_cloud_only_renderer_test.dart
```

Result: PASS, 24 tests.

Analyzer:

```text
flutter analyze lib\services\cloud_service.dart test\cloud_thumbnail_metadata_model_test.dart
```

Result: FAIL due to existing lint debt:

- `avoid_print` info entries across `cloud_service.dart`
- existing unused private helper warning: `_checkStandardOrAbove`

No compile error was introduced by the targeted test run.

## Runtime Recheck Recommendation

Rebuild/reinstall latest APK, then rerun the same MMQA-01 upload action window with:

- `adb logcat -c` before click
- count/tag-only sensitive gate scan
- no raw log line output

Expected app-controlled sensitive gate after this patch:

- raw uid-like app log count: 0
- raw local path/.mp4-like app log count: 0
- email/token/order/provider app log count: 0

The previous thumbnail upload permission failure is not fixed by this redaction patch and should remain classified separately.

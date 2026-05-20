# Cloud Clip Upload Move Pending State Fix Report v1

Date: 2026-05-20

## Scope

Fixed the self-inflicted state mismatch where `_moveSelectedLocalToCloud()` set `pendingUpload` before dispatching the background worker, causing `_moveSelectedLocalToCloudInBackground()` to reject the same target as non-uploadable.

No Firebase rules/index/schema, migration/backfill, Storage physical delete, legacy cleanup, Cloud copy, or deploy changes were made.

## Files Changed

- `lib/screens/library_screen.dart`
- `test/library_clip_transfer_action_test.dart`

## Implementation

The fix captures each target's pre-pending `ClipStorageState` before calling `markClipTransferPendingUpload(path)`.

The background worker now receives:

- `targets`
- `prePendingStates`

Upload eligibility is evaluated from the pre-pending state snapshot:

- `localOnly`: allowed
- `failedUpload`: allowed
- `cloudOnly`: rejected
- `cloudSyncedLocal`: rejected
- `pendingUpload`: rejected
- `failedDownload`: rejected

This preserves global `pendingUpload` UI-state precedence while allowing a target that was `localOnly` before this dispatch to continue through upload after the UI marker is applied.

## Tests Added

Added coverage in `test/library_clip_transfer_action_test.dart`:

- pre-pending `localOnly` remains upload eligible after runtime UI marker becomes `pendingUpload`
- pre-pending `failedUpload` remains upload retry eligible
- pre-pending non-upload states are not upload eligible

## Verification

### Format

```powershell
dart format lib\screens\library_screen.dart test\library_clip_transfer_action_test.dart
```

Result: PASS

### Tests

```powershell
flutter test test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

Result: PASS

Total: 17 tests passed.

### Targeted Analyzer

```powershell
flutter analyze lib\screens\library_screen.dart test\library_clip_transfer_action_test.dart
```

Result: FAIL due to existing info-level lint debt.

Analyzer findings were limited to:

- `curly_braces_in_flow_control_structures`
- deprecated `withOpacity`

No compile error was introduced.

## Runtime MMQA-01 Recheck

The fixed debug APK was rebuilt and installed over the existing emulator app data.

Action window:

1. User selected the prepared fixture.
2. `adb logcat -c` was executed immediately before upload click.
3. User clicked upload.
4. Logs were collected count-only after completion.

## Runtime Results

Upload move route:

| Signal | Count / Result |
|---|---:|
| `_moveSelectedLocalToCloud_entry` | 1 |
| `_moveSelectedLocalToCloud_early_return` | 0 |
| `_moveSelectedLocalToCloud_background_dispatch` | 1 |
| `_moveSelectedLocalToCloudInBackground_entry` | 1 |
| `_moveSelectedLocalToCloudInBackground_summary` | 1 |
| `state_mismatch_count=0` | observed |
| `state_allowed_count=1` | observed |
| `local_file_exists_count=1` | observed |
| `local_file_missing_count=0` | observed |
| `uploadVideoImmediate_call_count=1` | observed |
| `upload_success_count=1` | observed |
| `upload_failure_count=0` | observed |
| `success_count=1` | observed |
| `failure_count=0` | observed |
| `skipped_count=0` | observed |
| `final_toast_type=success` | observed |

Downstream keyword counts:

| Keyword | Count |
|---|---:|
| `uploadVideoImmediate` | 4 |
| `CloudService` | 2 |
| `Firestore` | 1 |
| `Storage` | 5 |
| `putFile` | 0 |
| `permission denied` | 0 |
| `FirebaseException` | 4 |
| `StorageException` | 0 |
| `removeLocalClipAfterCloudMove` | 0 |
| `move_to_cloud` | 2 |

Interpretation:

- The pending state mismatch is fixed.
- The upload route now reaches the upload path.
- Runtime summary reported upload success.
- Firebase/Storage/Firestore keywords appeared, so the previous "CloudService not reached" blocker is resolved.

## Sensitive Log Gate

Count-only scan result:

| Pattern | Count |
|---|---:|
| raw uid | 0 |
| raw local path | 0 |
| email-like | 0 |
| token word | 0 |
| password word | 0 |
| order id word | 0 |
| provider raw pattern | 0 |
| raw `.mp4` path-like value | 2 |

Sensitive log gate verdict: **FAIL pending source classification**

The upload route fix itself worked, but the action-window scan still found two app-controlled `.mp4` path-like hits. A follow-up source classification command was not approved, so this report does not classify those hits by tag/source. Raw values were not printed.

## Verdict

Pending state fix: **PASS**

MMQA-01 upload route blocker status:

- Previous blocker `pendingUpload state mismatch before uploadVideoImmediate`: resolved.
- Upload now reaches upload flow and reports success.
- QA cannot be fully promoted to PASS until the two `.mp4` path-like app-controlled log hits are classified/redacted.

## Next Step

Run raw-safe source classification for the two `.mp4` path-like hits:

- tag/severity/count only
- no raw line output
- no raw path or filename output

If hits are app Dart logs, redact the source. If they are SDK/system and not app-controlled, document the exception and resume MMQA-01 move-model evidence collection.


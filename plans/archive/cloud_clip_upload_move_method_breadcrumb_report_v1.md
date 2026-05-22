# Cloud Clip Upload Move Method Breadcrumb Report v1

Date: 2026-05-20

## Scope

Added raw-safe breadcrumbs inside `_moveSelectedLocalToCloud()` and `_moveSelectedLocalToCloudInBackground()` to identify where the upload move path stops after the Library transfer button resolves to `upload_move`.

No product storage policy, Firebase rules/index/schema, migration/backfill, Storage physical delete, legacy cleanup, Cloud copy, or deploy changes were made.

## File Changed

- `lib/screens/library_screen.dart`

## Breadcrumbs Added

Tag:

- `[LibraryTransfer][UploadMove]`

Events:

- `_moveSelectedLocalToCloud_entry`
- `_moveSelectedLocalToCloud_early_return`
- `_moveSelectedLocalToCloud_background_dispatch`
- `_moveSelectedLocalToCloudInBackground_entry`
- `_moveSelectedLocalToCloudInBackground_summary`

Fields are count-only/raw-safe:

- `target_count`
- `selected_count`
- `is_guest`
- `can_start_new_cloud_write`
- `pending_upload_ui_set`
- `early_return_reason`
- `background_dispatch_invoked`
- `task_started`
- state counts
- `state_allowed_count`
- `state_mismatch_count`
- `local_file_exists_count`
- `local_file_missing_count`
- `uploadVideoImmediate_call_count`
- `upload_success_count`
- `upload_failure_count`
- `success_count`
- `failure_count`
- `skipped_count`
- `final_toast_type`

No raw uid, selected path, local filename, or `.mp4` path is logged.

## Verification

### Format

```powershell
dart format lib\screens\library_screen.dart
```

Result: PASS

### Tests

```powershell
flutter test test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

Result: PASS

Total: 14 tests passed.

### Targeted Analyzer

```powershell
flutter analyze lib\screens\library_screen.dart
```

Result: FAIL due to existing info-level lint debt.

Current analyzer output for this file contains only info-level issues:

- `curly_braces_in_flow_control_structures`
- deprecated `withOpacity`

No compile error was introduced.

## Runtime Capture

The instrumented debug APK was rebuilt and installed with app data retained. The user selected the fixture and clicked the upload button.

Sensitive log gate remained PASS:

| Pattern | Count |
|---|---:|
| raw uid | 0 |
| raw local path | 0 |
| raw `.mp4` path-like value | 0 |
| email-like | 0 |
| token word | 0 |
| password word | 0 |
| order id word | 0 |
| provider raw pattern | 0 |

## Runtime Breadcrumb Counts

| Keyword | Count |
|---|---:|
| `LibraryTransfer` | 5 |
| `UploadMove` | 4 |
| `_moveSelectedLocalToCloud_entry` | 1 |
| `_moveSelectedLocalToCloud_early_return` | 0 |
| `_moveSelectedLocalToCloud_background_dispatch` | 1 |
| `_moveSelectedLocalToCloudInBackground_entry` | 1 |
| `_moveSelectedLocalToCloudInBackground_summary` | 1 |
| `CloudService` | 0 |
| `putFile` | 0 |
| `Firestore` | 0 |
| `Storage` | 0 |

Important summary counts:

| Field | Observed |
|---|---:|
| `target_count=1` | 4 |
| `background_dispatch_invoked=true` | 1 |
| `task_started=true` | 1 |
| `state_mismatch_count=1` | 1 |
| `state_allowed_count=0` | 4 |
| `local_file_exists_count=0` | 4 |
| `local_file_missing_count=0` | 4 |
| `uploadVideoImmediate_call_count=0` | 4 |
| `upload_success_count=0` | 4 |
| `upload_failure_count=0` | 4 |
| `skipped_count=1` | 1 |
| `final_toast_type=failure` | 1 |

## Root Cause Classification

Root cause: **pending upload UI state causes background state mismatch before upload call**

Flow proven by breadcrumbs:

1. Transfer button resolved to `upload`.
2. `upload_move` branch handler was invoked.
3. `_moveSelectedLocalToCloud()` entered with `target_count=1`.
4. No early return happened.
5. Pending upload UI state was set.
6. Background dispatch was invoked.
7. `_moveSelectedLocalToCloudInBackground()` started.
8. Background state check saw the target as not allowed.
9. `state_mismatch_count=1`, `skipped_count=1`.
10. `uploadVideoImmediate_call_count=0`.
11. CloudService/Storage/Firestore were never reached.

The likely code-level cause is that `_moveSelectedLocalToCloud()` calls `markClipTransferPendingUpload(path)` before dispatching the background task, and `VideoManager.getClipStorageState(path)` gives transfer UI state priority. In the background loop, the allowed-state check only accepts `localOnly` or `failedUpload`, so the same target becomes `pendingUpload` and is skipped before the upload call.

## Verdict

MMQA-01 upload route failure is no longer UI route mismatch.

Current classification:

- **selected path state mismatch caused by pendingUpload UI state precedence**

This is not a Firebase permission, Storage upload, Firestore metadata, auth, or subscription gate failure.

## Recommended Fix

Keep product behavior unchanged and adjust the upload background eligibility check so the pending UI marker does not invalidate the target it just marked.

Low-risk options:

1. Capture pre-pending derived states before calling `markClipTransferPendingUpload()` and pass those into the background worker.
2. In `_moveSelectedLocalToCloudInBackground()`, treat `pendingUpload` as allowed when it was set by this upload dispatch and the local file exists.
3. Add a helper for upload eligibility that ignores the transfer UI state for this one in-flight target validation.

The safest implementation is option 1 because it preserves `ClipStorageState` precedence generally while avoiding this self-inflicted state transition in the upload worker.


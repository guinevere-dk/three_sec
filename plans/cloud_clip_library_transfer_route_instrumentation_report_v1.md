# Cloud Clip Library Transfer Route Instrumentation Report v1

Date: 2026-05-20

## Scope

Added raw-safe Library transfer breadcrumbs to identify which transfer action is resolved and which branch is invoked when the user taps the bottom transfer button.

No product storage policy, Firebase rules/index/schema, migration/backfill, Storage physical delete, Cloud copy, or deploy changes were made in this task.

## Files Changed

- `lib/screens/library_screen.dart`

Note: the working tree already contained prior move-model and redaction edits in related files. This task only added Library transfer route instrumentation.

## Instrumentation Added

Raw-safe breadcrumb tag:

- `[LibraryTransfer]`

Fields:

- `selected_count`
- `state_counts localOnly/cloudOnly/cloudSyncedLocal/pendingUpload/failedUpload/failedDownload/uploadable`
- `resolved_action`
- `show_transfer_button`
- `can_start_new_cloud_write`
- `can_read_existing_cloud_clips`
- `branch`
- `handler_invoked`

No selected path, uid, local filename, or `.mp4` path is logged.

## Runtime Result

After rebuilding and installing the instrumented debug APK, the user selected a fixture and tapped the upload button.

Action-window sensitive log gate remained PASS:

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

LibraryTransfer counts:

| Keyword | Count |
|---|---:|
| `LibraryTransfer` | 1 |
| `tap_start` | 1 |
| `selected_count` | 1 |
| `state_counts` | 1 |
| `resolved_action` | 1 |
| `show_transfer_button` | 1 |
| `can_start_new_cloud_write` | 1 |
| `can_read_existing_cloud_clips` | 1 |
| `branch=upload_move` | 1 |
| `branch=download_move` | 0 |
| `branch=cloud_done` | 0 |
| `branch=progress` | 0 |
| `branch=disabled` | 0 |
| `handler_invoked=true` | 1 |
| `handler_invoked=false` | 0 |

Resolved summary:

| Field | Count |
|---|---:|
| `resolved_action=upload` | 1 |
| `branch=upload_move` | 1 |
| `show_transfer_button=true` | 1 |
| `can_start_new_cloud_write=true` | 1 |
| `can_read_existing_cloud_clips=true` | 1 |
| `handler_invoked=true` | 1 |

Upload downstream counts after immediate and delayed checks:

| Keyword | Count |
|---|---:|
| `uploadVideoImmediate` | 0 |
| `_moveSelectedLocalToCloud` | 0 |
| `_moveSelectedLocalToCloudInBackground` | 0 |
| `CloudService` | 0 |
| `putFile` | 0 |
| `Firestore` | 0 |
| `Storage` | 0 |
| `lastImmediateUploadErrorCode` | 0 |
| `lastImmediateUploadUserMessage` | 0 |
| `permission denied` | 0 |
| `FirebaseException` | 0 |
| `StorageException` | 0 |

## Interpretation

The bottom transfer button route is no longer ambiguous:

- The selection resolved to `upload`.
- The visible transfer button was enabled.
- The write/read gates were true.
- The tap invoked the `upload_move` branch.

However, no downstream upload evidence appeared even after a delayed log check. This means the next failure point is after the transfer handler branch is selected but before CloudService upload logging appears.

Most likely next inspection area:

- `_moveSelectedLocalToCloud()` early return or target handling
- `_moveSelectedLocalToCloudInBackground()` entry
- per-target state/file existence branch before `uploadVideoImmediate()`

The current instrumentation proves this is no longer a button resolution problem and still not a Firebase/Storage/Firestore failure, because those services were not reached.

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
flutter analyze lib\screens\library_screen.dart lib\managers\video_manager.dart
```

Result: FAIL due to existing info-level lints.

Important detail:

- No compile error was introduced.
- Remaining analyzer output is info-level lint debt such as `avoid_print`, `curly_braces_in_flow_control_structures`, deprecated `withOpacity`, and local identifier naming.

## Next Step

Add one more raw-safe breadcrumb layer inside the upload move method:

- `_moveSelectedLocalToCloud` entry with target count
- early return reason count
- background enqueue invoked
- `_moveSelectedLocalToCloudInBackground` entry with target count
- per-target branch counts only:
  - state mismatch
  - local file missing
  - uploadVideoImmediate called
  - uploadVideoImmediate returned success/failure

Do not print raw path, uid, filename, `.mp4`, token, provider, order id, or email.


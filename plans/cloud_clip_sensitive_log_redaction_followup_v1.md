# Cloud Clip Sensitive Log Redaction Follow-up v1

Date: 2026-05-20

## Scope

Follow-up for MMQA-01 failure gate triage v2 where app-controlled sensitive log gate failed due to raw uid and path-like values in Flutter/Dart logs.

This change is limited to app log redaction. Product behavior, Firebase rules/index/schema, Storage behavior, migration/backfill, Cloud copy, and deploy were not changed.

## Files Changed

- `lib/screens/profile_screen.dart`
- `lib/managers/user_status_manager.dart`
- `lib/managers/video_manager.dart`
- `lib/screens/library_screen.dart`
- `lib/services/auth_service.dart`

## Redaction Changes

### uid

- Added local uid masking helpers in:
  - `ProfileScreen`
  - `UserStatusManager`
- Updated Profile diagnostic build log to print masked uid only.
- Updated UserStatusManager initialize and setUserId logs to print masked uid only.
- Updated AuthService session reset log to print masked uid only.

Mask format:

- empty: `<no-uid>`
- short: `<masked-uid>`
- normal: `abcd...wxyz`

### local path / `.mp4` path-like values

- Replaced Library thumbnail trace paths with `<redacted-path>`.
- Replaced thumbnail structured log `videoPath` values with `<redacted-path>`.
- Removed stack trace output from Library thumbnail/load trace points that could include local paths.
- Replaced VideoManager project/clip diagnostic path fields with `<redacted-path>`.
- Replaced export/recorded-clip queue source/output path fields with `<redacted-path>`.
- Added `_redactLogPayload()` for VideoManager JSON diagnostic payloads so keys containing `path` or `paths` are redacted before logging.

## Search Performed

Commands used:

```powershell
rg "uid|userId|path|localPath|\.mp4|print|debugPrint" lib
rg "redact|mask|masked|maskUid|redacted" lib test
rg -n "print\([^\n]*(uid|userId|path|Path|\.mp4)|debugPrint\([^\n]*(uid|userId|path|Path|\.mp4)" lib\screens\profile_screen.dart lib\managers\user_status_manager.dart lib\managers\video_manager.dart lib\screens\library_screen.dart lib\services\auth_service.dart
```

Remaining direct `uid=` matches in `AuthService` are masked through `_maskUid()` or masked variables. Remaining `path` log matches in the touched files use `<redacted-path>`, `<redacted-path-list:N>`, or `<redacted-storage-path>`.

## Verification

### Format

```powershell
dart format lib\screens\profile_screen.dart lib\managers\user_status_manager.dart lib\screens\library_screen.dart lib\managers\video_manager.dart lib\services\auth_service.dart
```

Result: PASS

### Tests

```powershell
flutter test test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

Result: PASS

Summary:

- `video_manager_clip_storage_state_test.dart`: 8 tests passed
- `library_clip_transfer_action_test.dart`: 6 tests passed
- Total: 14 passed

### Analyzer

```powershell
flutter analyze lib\screens\profile_screen.dart lib\managers\user_status_manager.dart lib\screens\library_screen.dart lib\managers\video_manager.dart lib\services\auth_service.dart
```

Result: FAIL due to existing info-level lints.

Important result:

- No new compile error remained after fixing the `stackTrace` reference in `LibraryScreen`.
- Analyzer still exits non-zero because the selected files contain many existing info-level lints such as `avoid_print`, `curly_braces_in_flow_control_structures`, deprecated `withOpacity`, and local helper naming style.

## Data Safety

- Raw uid was not added to logs.
- Raw local path was not added to logs.
- Email/password/token/order id/provider output was not added.
- Firebase rules/index/schema were not changed.
- Migration/backfill was not run.
- Storage physical delete was not performed.
- Cloud copy was not implemented.
- Deploy was not performed.

## Follow-up Needed

1. Rebuild/reinstall or `flutter run` the app so the redaction changes are present on emulator.
2. Re-run the MMQA-01 app-controlled sensitive log gate with:
   - `adb logcat -c`
   - upload action window
   - count-only scan for raw uid/email/token/order id/provider/local path
3. If app-controlled sensitive hit count is 0, resume MMQA-01 upload route triage.
4. If upload route still logs `uploadVideoImmediate=0`, fix/instrument the Library transfer tap route separately.


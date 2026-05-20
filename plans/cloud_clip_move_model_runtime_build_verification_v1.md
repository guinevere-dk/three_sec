# Cloud Clip Move Model Runtime Build Verification v1

## Summary

- Date: 2026-05-19
- Purpose: Verify that the emulator runtime is rebuilt/reinstalled from the current move-model source before re-running MMQA-01.
- Scope: Build/runtime verification only.
- Code changes: none in this task.
- Verdict: PASS for clean rebuild/reinstall verification; MMQA-01 rerun is BLOCKED pending user-performed manual login and fixture recreation.

## Source Verification

Command:

```powershell
rg -n "removeLocalClipAfterCloudMove|uploadVideoImmediate|delete\(|_removeLocalIndexByKey|cloudOnly|move_to_cloud" lib\screens\library_screen.dart lib\services\cloud_service.dart lib\managers\video_manager.dart
```

Confirmed source locations:

| File | Evidence |
| --- | --- |
| `lib/screens/library_screen.dart` | `_moveSelectedLocalToCloudInBackground()` calls `CloudService.uploadVideoImmediate(...)` and then `videoManager.removeLocalClipAfterCloudMove(...)`; after success it calls `syncCloudMetadataToLibrary(trigger: 'move_to_cloud')`. |
| `lib/services/cloud_service.dart` | `uploadVideoImmediate()` calls `VideoManager().removeLocalClipAfterCloudMove(...)` after upload completion as a best-effort cleanup path. |
| `lib/services/cloud_service.dart` | queued upload completion also calls `removeLocalClipAfterCloudMove(...)` with `trigger: 'queued_upload_move_to_cloud'`. |
| `lib/managers/video_manager.dart` | `removeLocalClipAfterCloudMove(...)` exists and deletes the local file, removes transfer state, removes local path from recorded list, removes ownership/local index/duration cache, persists `cloud_synced_paths`, updates album counts, and reloads current album when applicable. |

Current source contains move-model cleanup calls.

## Previous Emulator Runtime Identity

Before clean reinstall:

| Field | Value |
| --- | --- |
| `versionName` | `1.3.6` |
| `versionCode` | `136` |
| `firstInstallTime` | `2026-05-19 01:57:13` |
| `lastUpdateTime` | `2026-05-19 04:38:55` |

This timestamp did not prove the emulator was running the latest move-model source.

## Clean Rebuild

Commands executed:

```powershell
flutter clean
flutter pub get
flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true
```

Build result:

| Artifact | Value |
| --- | --- |
| APK | `build\app\outputs\flutter-apk\app-debug.apk` |
| Size | `170800280` bytes |
| Last write time | `2026-05-19 16:48:35` local time |

`flutter pub get` completed successfully. It reported available package updates but did not change dependency constraints.

## Reinstall

Commands executed:

```powershell
adb uninstall com.dk.three_sec
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Result:

- `adb uninstall`: `Success`
- `adb install`: `Success`

After reinstall:

| Field | Value |
| --- | --- |
| `versionName` | `1.3.6` |
| `versionCode` | `136` |
| `firstInstallTime` | `2026-05-19 07:49:20` |
| `lastUpdateTime` | `2026-05-19 07:49:20` |

Interpretation:

- The emulator app was cleanly reinstalled from the newly built APK.
- The install timestamp now postdates the clean build.

## Runtime State After Reinstall

The app was launched once after reinstall.

Observed state:

| Check | Result |
| --- | --- |
| `shared_prefs/FlutterSharedPreferences.xml` before first run | absent |
| Shared prefs after launch | minimal app/Firebase prefs only |
| Login screen visible | yes |
| UserStatusManager startup tier | `UserTier.free` |
| Manual Google login needed | yes |

UI evidence:

- Login screen shows `MOA`.
- `Continue with Google` is visible.
- Guest option is visible.

No OAuth automation, password entry, credential reading, or `.env` access was performed.

## Runtime Log Check

Raw values were not printed.

Relevant startup log evidence:

| Tag/Source | Result |
| --- | --- |
| `IAPService` startup product query | present |
| `UserStatusManager` startup | initialized as free after reinstall |
| Firebase startup | present |
| `removeLocalClipAfterCloudMove` execution | not expected yet; no upload performed after reinstall |
| `move_to_cloud` execution | not expected yet; no upload performed after reinstall |

Sensitive-value handling:

- No raw email, password, token, order id, provider value, full uid, or local path was recorded in this report.

## Test Verification

Command:

```powershell
flutter test test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

Result:

- PASS
- 14 tests passed

Covered:

- `ClipStorageState` derived state helpers.
- `localOnly` upload action reducer.
- `cloudOnly` download action reducer.
- two-value badge expectation: `기기` / `Cloud`.

## MMQA-01 Rerun Readiness

Current readiness:

| Requirement | Status |
| --- | --- |
| Latest move-model source present | PASS |
| Clean rebuild completed | PASS |
| Existing emulator app removed | PASS |
| New debug APK installed | PASS |
| Runtime install identity recorded | PASS |
| Signed-in QA account | BLOCKED, requires user-performed manual login |
| Active paid state | BLOCKED, must be reinjected after login/session setup |
| Verified `device/localOnly` fixture | BLOCKED, must be recreated after reinstall |
| MMQA-01 rerun | BLOCKED until the above are restored |

## Required Next Steps Before MMQA-01 Rerun

1. User performs manual Google login in the emulator.
2. AI confirms signed-in state without printing raw uid/email/token.
3. AI injects active Standard state using the correct SharedPreferences value format:
   - `flutter.3s_user_tier = UserTier.standard`
   - product/purchase fields present
4. App is fully restarted.
5. User creates a new QA-only `device/localOnly` clip.
6. AI records count-only before evidence.
7. User performs Library upload/move action.
8. AI records after evidence and reruns MMQA-01 verdict.

## Safety Notes

- No Firebase rules/index/schema changes were made.
- No migration/backfill was run.
- No Storage physical deletion was performed.
- No legacy `cloudSyncedLocal` cleanup was performed.
- No deploy was performed.
- Existing app data was intentionally cleared by `adb uninstall` as part of clean runtime verification.

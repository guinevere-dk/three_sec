# MMQA-01 Upload Failure Gate Triage v1

Date: 2026-05-20

## Scope

This run attempted to classify the active paid localOnly upload failure toast using count/tag-only evidence.

Sensitive value policy was maintained:

- Raw uid: not printed
- Raw email/token/order id/provider: not printed
- Raw local path: not printed
- Firebase rules/index/schema: not changed
- Migration/backfill: not run
- Storage physical delete: not performed
- Legacy cleanup: not performed
- Deploy: not performed

## Requested Failure Categories

1. selected path state mismatch
2. auth missing
3. write gate / subscription gate
4. Firebase permission denied
5. Storage upload failure
6. Firestore metadata failure
7. local file missing
8. UI route mismatch
9. unknown app failure

## Preflight Evidence

The following state was established before the runtime became unavailable:

| Check | Result | Notes |
|---|---:|---|
| Clean rebuild/reinstall identity | PASS | Recorded in `cloud_clip_move_model_runtime_build_verification_v1.md`. |
| Manual signed-in session | PASS before runtime block | User-performed manual login was completed. Current in-app verification is blocked because the app cannot launch. |
| Active Standard injection | PASS before runtime block | SharedPreferences was reinjected with Standard tier and non-empty purchase/product values. |
| Local QA fixture count | 1 | Count-only local mp4 evidence before the failed upload attempt. |
| Previous upload attempt result | FAIL | User reported upload failure toast. |
| Previous upload service entry | 0 hits | `uploadVideoImmediate`, `uploadVideo`, `putFile`, and `move_to_cloud` were not observed in the prior capture. |
| Previous local file count after failure | 1 | Local fixture remained present after failure toast. |
| Previous app-controlled sensitive log gate | 0 hits | No app-controlled raw sensitive hits observed in prior capture. |

## Current Capture Attempt

The requested fresh capture could not proceed to the user-action window.

| Step | Result |
|---|---|
| `adb devices` | PASS, emulator connected |
| App process check | No `com.dk.three_sec` pid |
| Non-destructive app stop/start recovery | BLOCKED |
| `adb shell am force-stop com.dk.three_sec` | Timed out |
| App launch for UI preflight | BLOCKED |
| UIAutomator dump after toast | Not available |
| Fresh post-toast logcat window | Not available |
| Fresh before/after local/index/marker count | Not available |

## Runtime Blocker Evidence

The emulator/system log repeatedly reports Android system binder failures:

| Source category | Tag | Severity | Count/Pattern |
|---|---|---:|---:|
| android_system_log | IPCThreadState | E | repeated binder transaction failures |
| android_system_log | ActivityManager | W/E | binder errors while handling frozen/system app state |
| android_system_log | ArtService | E | system service call failure |
| android_system_log | CameraManagerGlobal | E | camera service unavailable |
| android_system_log | GnssManager / biometric services | E | HAL/service recovery messages |

The binder failure error code was `-28`, reported by Android as no space left on device. Disk probe showed `/data` still had about `0.9G` available, while the root/system mount was full. This appears to be emulator/runtime system instability rather than a confirmed app upload failure path.

No app package process was active during this blocked state, so no valid app upload gate classification can be made from this run.

## Keyword Classification

Fresh action-window keyword counts are unavailable because the app could not be launched and the user could not perform the upload click inside a valid capture window.

| Keyword / Flow | Fresh Count | Classification |
|---|---:|---|
| `uploadVideoImmediate` | N/A | app not launched |
| `uploadVideo` | N/A | app not launched |
| `_moveSelectedLocalToCloud` | N/A | app not launched |
| `_moveSelectedLocalToCloudInBackground` | N/A | app not launched |
| `canStartNewCloudWrite` | N/A | app not launched |
| `lastImmediateUploadErrorCode` | N/A | app not launched |
| `lastImmediateUploadUserMessage` | N/A | app not launched |
| `auth uid` | N/A | app not launched |
| `permission denied` | N/A | app not launched |
| `FirebaseException` | N/A | app not launched |
| `StorageException` | N/A | app not launched |
| `Firestore` | N/A | app not launched |
| `putFile` | N/A | app not launched |
| `local file missing` | N/A | app not launched |
| `move_to_cloud` | N/A | app not launched |

## Failure Category Verdict

Verdict: **BLOCKED**

Reason: The requested failure source cannot be classified into categories 1-9 because the fresh upload attempt could not be executed. The emulator is connected, but the app process cannot be started or controlled reliably due to Android system-level binder failures. Classifying this as `unknown app failure` would be misleading because the upload path did not run during this triage attempt.

Current best classification:

- Primary: `BLOCKED: emulator/runtime launch failure before upload`
- Upload failure taxonomy: `N/A - no valid upload action window`

## Data Safety Result

| Guard | Result |
|---|---|
| Raw uid/email/token/order id/provider printed | PASS, not printed |
| Raw local path printed | PASS, not printed |
| Existing fixture modified manually | PASS, not modified |
| SharedPreferences destructive cleanup | PASS, not performed |
| Storage physical delete | PASS, not performed |
| Firebase rules/index/schema change | PASS, not performed |
| Migration/backfill | PASS, not performed |

## Next Action

Do not continue MMQA-01 failure-source triage on this emulator session until the Android runtime is recovered.

Recommended recovery path:

1. Cold boot or restart the emulator from the AVD manager.
2. Avoid `pm clear` or emulator wipe unless explicitly approved, because that can remove the current manual login/session and QA fixture.
3. After the app launches, rerun the required preflight:
   - signed-in check without raw uid/email/token output
   - active Standard state check
   - device filter selected
   - visible local fixture count
   - localOnly/failedUpload count-only diagnostic
   - transfer action is upload / cloud upload icon
4. Clear logcat immediately before the user clicks upload.
5. If the failure toast appears, collect UIAutomator and logcat immediately and classify using categories 1-9.


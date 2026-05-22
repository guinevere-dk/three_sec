# Cloud Clip Sensitive Log Runtime Recheck v1

Date: 2026-05-20

## Scope

Runtime recheck for the sensitive log redaction follow-up. The goal was to confirm the latest redaction changes were installed on the emulator and that the MMQA-01 upload action window no longer emits app-controlled raw sensitive values.

This run did not proceed to Firebase/Storage/Firestore root-cause analysis.

## Runtime Update

| Step | Result |
|---|---:|
| Debug APK rebuild with latest redaction changes | PASS |
| Install over existing app data with `adb install -r` | PASS |
| `pm clear` / wipe data | NOT RUN |
| App launch after reinstall | PASS |
| App process present | PASS |

Build command:

```powershell
flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true
```

Install result: `Success`

## Preflight

All preflight checks were raw-safe and count-only.

| Check | Result | Evidence |
|---|---:|---|
| signed-in persistence retained | PASS | auth persistence file count: `6` |
| active Standard state retained | PASS | tier key count: `1`, product key count: `1` |
| purchase date type | PASS | long count: `1`, string count: `0` |
| local fixture availability | PASS | local mp4 count: `55` |
| startup raw uid in Flutter logs | PASS | raw uid count: `0` |
| startup redacted uid marker | PASS | redacted uid marker count: `126` |
| startup raw local path / `.mp4` in Flutter logs | PASS | count: `0` |

Note: No raw uid, email, token, order id, provider, or local path value is included in this report.

## Action Window

Procedure:

1. User selected a local fixture and confirmed ready state.
2. `adb logcat -c` was executed immediately before click.
3. User clicked the upload button.
4. User reported completion after the failure/toast window.
5. UIAutomator dump and logcat were collected.
6. Counts were computed without printing raw matching lines.

## App-Controlled Sensitive Log Gate

App-controlled lines were defined as Flutter/Dart log lines or lines containing the app package.

| Pattern | Count |
|---|---:|
| app-controlled line count | 709 |
| app_dart raw uid count | 0 |
| app_dart redacted uid marker count | 704 |
| app_dart email-like count | 0 |
| app_dart token word count | 0 |
| app_dart password word count | 0 |
| app_dart order id word count | 0 |
| app_dart provider raw pattern count | 0 |
| app_dart raw local path count | 0 |
| app_dart raw `.mp4` path-like count | 0 |

Sensitive log gate verdict: **PASS**

## Upload Route Keyword Counts

| Keyword | Count |
|---|---:|
| `LibraryTransfer` | 0 |
| `selected_count` | 0 |
| `action` | 59 |
| `branch` | 0 |
| `uploadVideoImmediate` | 0 |
| `_moveSelectedLocalToCloud` | 0 |
| `CloudService` | 0 |
| `putFile` | 0 |
| `Firestore` | 0 |
| `Storage` | 0 |
| `uploadVideo` | 0 |
| `canStartNewCloudWrite` | 0 |
| `permission denied` | 0 |
| `FirebaseException` | 0 |
| `StorageException` | 0 |
| `lastImmediateUploadErrorCode` | 0 |
| `lastImmediateUploadUserMessage` | 0 |

Interpretation:

- Redaction runtime recheck passed.
- Upload route still did not enter the expected move/upload path in this action window.
- The generic `action` count is noisy and not sufficient evidence of Library transfer routing.
- There is still no evidence of Firebase permission, Storage upload, Firestore metadata, or CloudService failure because the upload route was not reached.

## Tag / Severity Summary

Top tag/severity counts:

| Tag | Severity | Count |
|---|---:|---:|
| EmulatedRequestProcessor | E | 2984 |
| flutter | I | 706 |
| IPCThreadState | W | 160 |
| EGL_emulation | D | 107 |
| AiAiEcho | I | 94 |
| BugleRcsEngine | I | 46 |
| TraceManagerImpl | E | 43 |
| system_server | W | 35 |
| SsBaseTemplateCard | D | 20 |
| `.gms.persistent` | W | 17 |

These are not evidence of app-controlled sensitive logging.

## Verdict

Runtime redaction recheck: **PASS**

MMQA-01 sensitive app log gate is clear to resume route triage:

- raw uid: `0`
- raw local path / `.mp4` path-like value: `0`
- email/password/token/order id/provider: `0`

Upload route triage remains open:

- `_moveSelectedLocalToCloud=0`
- `uploadVideoImmediate=0`
- `CloudService=0`
- `putFile=0`
- `Firestore=0`
- `Storage=0`

## Next Step

Resume Library transfer route triage before investigating Firebase/Storage/Firestore. Recommended next instrumentation should be raw-safe and count-only:

- selected clip count
- derived `ClipStorageState` counts
- resolved `LibraryClipTransferAction`
- transfer button tap handler branch
- write/read gate boolean results
- no raw uid/path/provider/token values


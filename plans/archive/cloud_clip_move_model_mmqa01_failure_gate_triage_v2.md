# MMQA-01 Upload Failure Gate Triage v2

Date: 2026-05-20

## Scope

This run retried MMQA-01 upload failure gate triage after emulator/runtime recovery.

No destructive recovery was performed:

- `pm clear`: not run
- Wipe data: not run
- Firebase rules/index/schema: not changed
- Migration/backfill: not run
- Storage physical delete: not performed
- Legacy cleanup: not performed
- Deploy: not performed

Sensitive value handling:

- Raw uid/email/token/order id/provider/local path values are not included in this report.
- Log analysis was performed with count/tag-only output.

## Emulator Recovery

| Check | Result | Evidence |
|---|---:|---|
| `adb devices` | PASS | Emulator connected. |
| App launch after prior runtime block | PASS | `am start` returned normally. |
| App process | PASS | App pid present. |
| App data reset avoided | PASS | No `pm clear`, no wipe data. |

## Preflight

| Check | Result | Evidence |
|---|---:|---|
| Manual signed-in session retained | PASS | Auth persistence file count: `6`. Raw uid/email not printed. |
| active Standard state | PASS | Tier/product keys present; `purchase_date` stored as `long`, not `string`. |
| App loaded Standard | PASS | App log showed Standard tier loaded; raw uid was not recorded here. |
| Device/local fixture present | PASS | Local mp4 file count: `55`. |
| User selected local fixture and saw upload icon | USER-CONFIRMED | User reported `준비` after selecting the fixture and confirming upload button state. |
| Logcat cleared before click | PASS | `adb logcat -c` executed immediately before user clicked upload. |

## Action Window

| Event | Result |
|---|---|
| User clicked upload button | USER-CONFIRMED |
| User reported completion/failure window | USER-CONFIRMED |
| UIAutomator dump collected after action | PASS |
| Logcat collected after action | PASS |
| Raw matching lines printed | PASS, none printed |

## Keyword Counts

Fresh post-click logcat keyword counts:

| Keyword / Flow | Count |
|---|---:|
| `uploadVideoImmediate` | 0 |
| `uploadVideo` | 0 |
| `_moveSelectedLocalToCloud` | 0 |
| `_moveSelectedLocalToCloudInBackground` | 0 |
| `selected path` | 0 |
| `localOnly` | 0 |
| `failedUpload` | 0 |
| `canStartNewCloudWrite` | 0 |
| `upload failed` | 0 |
| `lastImmediateUploadErrorCode` | 0 |
| `lastImmediateUploadUserMessage` | 0 |
| `auth uid` | 0 |
| `permission denied` | 0 |
| `FirebaseException` | 0 |
| `StorageException` | 0 |
| `Firestore` | 0 |
| `putFile` | 0 |
| `local file missing` | 0 |
| `source file` | 0 |
| `move_to_cloud` | 0 |
| `CloudService` | 0 |
| `Storage` | 0 |
| `metadata` | 11 |

Top tag/severity counts:

| Tag | Severity | Count |
|---|---:|---:|
| EmulatedRequestProcessor | E | 1301 |
| flutter | I | 354 in first capture, later 1158 total Flutter lines after continued runtime logging |
| AiAiEcho | I | 80 |
| IPCThreadState | W | 56 |
| EGL_emulation | D | 47 |
| BugleRcsEngine | I | 18 |
| SsBaseTemplateCard | D | 16 |
| `.gms.persistent` | W | 7 |
| NullBinder | I | 6 |
| WM-WorkConstraintsTrack | D | 6 |

## UI Dump Summary

| Check | Result |
|---|---:|
| UI dump collected | PASS |
| Relevant text count for upload/failure/cloud/device terms | 1 |
| Raw local path printed | PASS, none printed |

The UI dump did not provide a durable, specific failure reason through accessible text after the action window.

## Local / Marker Counts After Action

| Metric | Count |
|---|---:|
| Local mp4 file count | 55 |
| `cloud_only://` marker count | 27 |
| prefs `.mp4` marker count | 49 |
| `purchase_date` long count | 1 |
| `purchase_date` string count | 0 |

Because no upload service entry was observed, the unchanged local file count is expected and does not indicate a completed move attempt.

## App-Controlled Sensitive Log Gate

Fresh action-window app-controlled log scan found raw-sensitive patterns in Flutter logs. Values are intentionally not included.

| Pattern Class | Count |
|---|---:|
| Flutter line count | 1158 |
| Raw uid pattern | 1156 |
| Email-like pattern | 0 |
| Token word | 0 |
| Password word | 0 |
| Order id word | 0 |
| Provider pattern | 0 |
| Raw local path / `.mp4` pattern | 4 |

Security gate verdict: **FAIL**

Likely source category: `app_dart_log`

Observed behavior is consistent with a Profile/diagnostic log repeatedly printing raw uid and a small number of path-like values. Source lines were not printed to avoid leaking values. This must be redacted before continuing QA that depends on app-controlled sensitive log gate PASS.

## Failure Taxonomy

Primary upload failure classification: **8. UI route mismatch**

Reason:

- The user confirmed selecting the upload-looking action and clicking it.
- The action-window log was cleared before click.
- No upload route/function/service evidence appeared:
  - `uploadVideoImmediate=0`
  - `uploadVideo=0`
  - `_moveSelectedLocalToCloud=0`
  - `_moveSelectedLocalToCloudInBackground=0`
  - `CloudService=0`
  - `putFile=0`
  - `Firestore=0`
  - `Storage=0`
- No evidence supports auth missing, subscription gate, Firebase permission denied, Storage failure, Firestore failure, or local file missing in this action window.

Secondary blocking condition: **app-controlled sensitive log gate FAIL**

## Category Matrix

| Category | Verdict | Reason |
|---|---:|---|
| 1. selected path state mismatch | N/A | No selected path/state logs emitted in action window. |
| 2. auth missing | N/A | No auth-missing keyword hit. Signed-in persistence existed. |
| 3. write gate / subscription gate | N/A | No `canStartNewCloudWrite`, subscription, or tier gate hit. Standard state loaded. |
| 4. Firebase permission denied | N/A | No permission denied or FirebaseException hit. |
| 5. Storage upload failure | N/A | No Storage/putFile/upload entry hit. |
| 6. Firestore metadata failure | N/A | No Firestore failure hit. Generic `metadata` hits were not tied to upload flow. |
| 7. local file missing | N/A | No local-file-missing/source-file hit. |
| 8. UI route mismatch | FAIL | Upload-looking click did not enter upload route or CloudService upload flow. |
| 9. unknown app failure | N/A | Evidence is more specific than unknown: route did not enter upload flow. |

## Verdict

MMQA-01 upload failure gate triage v2: **FAIL**

Reasons:

1. Upload failure classification: `UI route mismatch`.
2. App-controlled sensitive log gate failed due to raw uid/path-like patterns in Flutter logs.

MMQA-01 upload move QA must remain stopped until:

1. app Dart logs redact raw uid/local path-like values, and
2. the Library selected upload control is instrumented/fixed so the click reliably reaches the move-to-cloud upload route.

## Recommended Next Steps

1. Redact app-controlled Profile/diagnostic logs that print raw uid and path-like values.
2. Add count-only breadcrumbs around Library selection transfer resolution and tap handler:
   - selected item count
   - derived action enum
   - storage state count summary
   - upload/download/disabled branch taken
   - no raw path/uid values
3. Re-run this triage after sensitive log gate returns to PASS.
4. If the upload route still shows 0 entry hits, inspect the selected floating panel button wiring rather than Firebase/Storage.


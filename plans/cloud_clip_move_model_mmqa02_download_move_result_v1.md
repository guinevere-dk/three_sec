# Cloud Clip Move Model MMQA-02 Download Move Result v1

## Scenario

- ID: MMQA-02 / R3-MQA-02
- Scenario: Active paid download move
- Date: 2026-05-20
- Device: Android emulator
- App package: `com.dk.three_sec`
- App version: `1.3.6` / versionCode `136`
- Account state: signed-in QA account, active Standard
- Login method: user-performed manual Google login
- uid: masked in app logs only
- Verdict: PASS

## Preconditions

Met:

- signed-in QA account
- active Standard state loaded
- thumbnail-ready `cloud/cloudOnly` clip visible in Library
- app-controlled sensitive log gate previously PASS, with only documented plugin/runtime WARN category allowed
- QA action used a single selected Cloud clip

No code change, Firebase rules/index/schema change, migration/backfill, deploy, Cloud copy, legacy cleanup, or Storage physical delete was performed.

## Before Evidence

Local:

- local mp4 count before: `57`

Library/UI:

- one Cloud clip was selected
- selection reducer log: `selected_count=1`
- selected state counts:
  - `localOnly=0`
  - `cloudOnly=1`
  - `cloudSyncedLocal=0`
  - `pendingUpload=0`
  - `failedUpload=0`
  - `failedDownload=0`
  - `uploadable=0`
- resolved action: `download`
- branch: `download_move`
- `can_start_new_cloud_write=true`
- `can_read_existing_cloud_clips=true`

Cloud thumbnail/UI:

- thumbnail-ready Cloud card was visible as an image card
- legacy/missing-thumbnail Cloud cards remained fallback Cloud cards

## Action

User performed the action manually:

1. Long-pressed one thumbnail-ready Cloud clip.
2. Confirmed the transfer action resolved to download/move-to-device.
3. Tapped the transfer button.

Action window was isolated with `adb logcat -c` before the tap.

## During Evidence

Action window count-only markers:

| Marker | Count |
| --- | ---: |
| `LibraryTransfer` | 1 |
| `resolved_action=download` | 1 |
| `branch=download_move` | 1 |
| `downloadVideo` inferred from download request marker | 1 |
| download complete marker | 1 |
| logical Cloud delete/tombstone request marker | 1 |
| tombstone complete marker | 1 |
| `StorageException` | 0 |
| `permission_denied` | 0 |
| Storage physical delete marker | 0 |
| redacted local path marker | 1 |

Observed sequence:

1. Library transfer branch resolved to `download_move`.
2. CloudService download request started with masked video id.
3. CloudService download completed with local path redacted.
4. CloudService logical delete/tombstone request started with masked video id.
5. CloudService tombstone completed.

## After Evidence

Local:

- local mp4 count after: `58`
- local mp4 delta: `+1`
- local file creation: PASS by count delta

Library/UI:

- album still shows `12 Clips` total.
- the moved item is now visible as a device/local image card with duration badge.
- Cloud fallback card content-desc count after: `11`
- effective active Cloud count decreased by one when the selected thumbnail-ready Cloud card moved to device.

Cloud metadata:

- logical tombstone call count: `1`
- tombstone complete marker count: `1`
- active Cloud placeholder count decreased by one in Library active view.

Storage:

- Storage physical delete marker count: `0`
- `StorageException`: `0`
- `permission_denied`: `0`

## Sensitive Log Gate

Raw values were not printed in this report.

Action window app-controlled count-only scan:

| Category | Count |
| --- | ---: |
| app-controlled email-like hit | 0 |
| app-controlled path-like raw hit | 0 |
| app-controlled raw uid-like hit | 0 |
| app-controlled redacted path marker | 10 |

Allowed:

- masked uid/video id forms
- `<redacted-path>` markers

Not observed:

- raw uid
- raw email
- raw token
- raw order id
- raw provider value
- raw local path
- raw Storage path
- raw file name

## PASS Criteria Check

| Requirement | Result |
| --- | --- |
| active paid download allowed | PASS |
| local file created | PASS |
| local index/register path reached | PASS, inferred from device card and local mp4 count increase |
| Cloud active metadata tombstone/trash | PASS |
| active state becomes device/localOnly | PASS |
| Library no longer shows the moved clip as Cloud | PASS |
| Storage physical delete absent | PASS |
| sensitive app log gate | PASS |

## Failure Criteria Check

| Failure Condition | Observed |
| --- | --- |
| local file creation failed | No |
| Cloud active metadata remained active after success | No evidence; tombstone completed and active Cloud view decreased |
| Storage physical delete occurred | No |
| download failed but Cloud metadata tombstoned | No |
| raw sensitive app log occurred | No |

## Notes

Direct Firestore document contents and Storage object names were not printed to avoid raw uid/path/storagePath/fileName exposure. Evidence uses app-controlled count-only logs, masked ids, local file count delta, and Library active-view state.

The current `deleteVideo(...)` path used by download move performs logical trash/tombstone metadata update. It does not perform Storage object physical deletion in this scenario.

## Verdict

MMQA-02 / R3-MQA-02 Active paid download move: PASS.

The thumbnail-ready Cloud-only clip moved to device/local active state. Local mp4 count increased, Cloud active UI count decreased, tombstone completed, and no Storage physical delete or app-controlled sensitive raw log was observed.

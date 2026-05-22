# Cloud Clip R3 Signed-In Local Manual QA Result v3

## 1. Scope

- Date: 2026-05-19
- App package: `com.dk.three_sec`
- Device: Android emulator `emulator-5554`
- Login method: user-performed manual Google login from the existing signed-in emulator session
- Credential handling: `.env`, `TEST_GOOGLE_ID`, and `TEST_GOOGLE_PW` were not read or printed.
- OAuth handling: AI did not automate login, enter a password, or operate OAuth screens.

## 2. References

- `AGENTS.md`
- `CURRENT_PHASE.md`
- `DATA_COMPATIBILITY.md`
- `plans/cloud_clip_r3_manual_qa_checklist_v1.md`
- `plans/cloud_clip_r3_local_qa_fixture_setup_plan_v1.md`
- `plans/cloud_clip_r3_logcat_redaction_source_triage_v1.md`

## 3. Logcat Source Gate

The v2 logcat blocker was reclassified by `plans/cloud_clip_r3_logcat_redaction_source_triage_v1.md`.

| Source category | Count | Gate |
|---|---:|---|
| `app_dart_log` | 0 | PASS |
| `app_native_log` | 0 | PASS |
| `firebase_sdk_log` | 0 | PASS |
| `google_signin_sdk_log` | 0 | PASS |
| `android_system_log` | 3 | WARN |

During this v3 resume, app-controlled sensitive log scans also stayed clean.

| Pattern | App-controlled count |
|---|---:|
| email | 0 |
| password marker | 0 |
| token marker | 0 |
| order id marker | 0 |
| raw provider marker | 0 |
| `app_dart_log` sensitive hits | 0 |
| `app_native_log` sensitive hits | 0 |

Raw matching values were not printed.

## 4. Signed-In State

Firebase/Auth state was checked through app-local preferences without printing raw auth payloads.

| Check | Result |
|---|---|
| `flutter.3s_user_id` | present |
| masked uid | `tUny...b0l1` |
| `flutter.3s_auth_mode_guest` | `false` after state injection |

The full uid was not printed.

## 5. Active Paid Injection

SharedPreferences file:

```text
/data/user/0/com.dk.three_sec/shared_prefs/FlutterSharedPreferences.xml
```

Injection helper:

```text
C:\tmp\r3_inject_prefs.ps1
```

Active paid state:

| Item | Before | After |
|---|---|---|
| remote backup | `shared_prefs/FlutterSharedPreferences.r3qa_active_20260519_140128.bak.xml` | same run |
| local before XML | `C:\tmp\r3qa_active_20260519_140128_before.xml` | N/A |
| local after XML | N/A | `C:\tmp\r3qa_active_20260519_140128_after.xml` |
| masked uid | `tUny...b0l1` | `tUny...b0l1` |
| `flutter.3s_user_tier` | `UserTier.standard` | `UserTier.standard` |
| `flutter.3s_product_id` | `3s_standard_monthly` | `3s_standard_monthly` |
| `flutter.3s_purchase_date` | present | present |

Post-restart probe:

```text
prefs.user_id_present=True
prefs.masked_uid=tUny...b0l1
prefs.tier=UserTier.standard
prefs.product_id=3s_standard_monthly
prefs.purchase_date_present=True
prefs.auth_mode_guest=false
```

Active paid load verdict:

- PASS for local SharedPreferences injection and reload.
- PASS for app-controlled sensitive log gate.

## 6. Local Test Clip

Camera permission and microphone permission were granted to the emulator test app.

Local test clips were recorded successfully. Redacted capture log evidence included:

```text
[Capture] recorded_clip_enqueued source=<app-private-path> quality=1080p ... aspectPreset=r9_16
```

The raw local path was not recorded.

## 7. Cloud Fixture Creation

Attempted method:

1. Opened Library.
2. Entered the test album.
3. Long-pressed a local 2s clip to enter selection mode.
4. Tapped the selection panel Cloud transfer button area.

Observed:

```text
cloud_synced_paths_count=0
local_index_entries_present=True
cloud_only_marker_present=True
```

No `CloudService` upload log was captured after the transfer tap. No new local cloud sync marker was created.

Fixture verdict:

- BLOCKED.
- A test Cloud clip fixture was not proven created.
- Because fixture creation was not proven, Firestore and Storage before-after evidence for the fixture could not be captured.

## 8. Firestore / Storage Evidence

Direct Firestore/Storage console or CLI evidence was not available in this local session.

| Evidence | Before | After | Verdict |
|---|---|---|---|
| Firestore `videos` document count | unavailable | unavailable | BLOCKED |
| Firestore fixture document | unavailable | unavailable | BLOCKED |
| Storage object path | unavailable | unavailable | BLOCKED |
| Storage object count | unavailable | unavailable | BLOCKED |
| Storage deletion check | no app evidence of deletion | no app evidence of deletion | BLOCKED for direct proof |

No Firebase rules/index changes, Firestore schema changes, migration/backfill, Storage deletion, deploy, or Cloud copy implementation were performed.

## 9. Expired Within 30-Day Grace Injection

Grace state:

| Item | Before | After |
|---|---|---|
| remote backup | `shared_prefs/FlutterSharedPreferences.r3qa_grace_20260519_141250.bak.xml` | same run |
| local before XML | `C:\tmp\r3qa_grace_20260519_141250_before.xml` | N/A |
| local after XML | N/A | `C:\tmp\r3qa_grace_20260519_141250_after.xml` |
| masked uid | `tUny...b0l1` | `tUny...b0l1` |
| `flutter.3s_user_tier` | `UserTier.standard` | absent |
| `flutter.3s_product_id` | `3s_standard_monthly` | `3s_standard_monthly` |
| `flutter.3s_purchase_date` | present | present |

Post-restart probe:

```text
prefs.user_id_present=True
prefs.masked_uid=tUny...b0l1
prefs.tier=<absent>
prefs.product_id=3s_standard_monthly
prefs.purchase_date_present=True
prefs.auth_mode_guest=false
```

Observed:

```text
cloud_synced_paths_count=0
```

Verdict:

- PASS for state injection persistence.
- PASS for no immediate Firestore overwrite to remove product/purchase history, based on SharedPreferences probe.
- BLOCKED for existing Cloud list/download/restore because no Cloud fixture was available.
- BLOCKED for proving new Storage object absence because direct Storage before-after was unavailable.

## 10. Expired After Grace Injection

Expired-after-grace state:

| Item | Before | After |
|---|---|---|
| remote backup | `shared_prefs/FlutterSharedPreferences.r3qa_expired_20260519_141316.bak.xml` | same run |
| local before XML | `C:\tmp\r3qa_expired_20260519_141316_before.xml` | N/A |
| local after XML | N/A | `C:\tmp\r3qa_expired_20260519_141316_after.xml` |
| masked uid | `tUny...b0l1` | `tUny...b0l1` |
| `flutter.3s_user_tier` | absent | absent |
| `flutter.3s_product_id` | `3s_standard_monthly` | `3s_standard_monthly` |
| `flutter.3s_purchase_date` | present | present |

Post-restart probe:

```text
prefs.user_id_present=True
prefs.masked_uid=tUny...b0l1
prefs.tier=<absent>
prefs.product_id=3s_standard_monthly
prefs.purchase_date_present=True
prefs.auth_mode_guest=false
```

Verdict:

- PASS for state injection persistence.
- BLOCKED for Cloud list/download/restore block verification because no Cloud fixture was available.
- BLOCKED for proving no Firestore purge/Storage deletion because direct Firestore/Storage before-after was unavailable.

## 11. Signed-In Free Never Paid Injection

Free never-paid state:

| Item | Before | After |
|---|---|---|
| remote backup | `shared_prefs/FlutterSharedPreferences.r3qa_free_20260519_141336.bak.xml` | same run |
| local before XML | `C:\tmp\r3qa_free_20260519_141336_before.xml` | N/A |
| local after XML | N/A | `C:\tmp\r3qa_free_20260519_141336_after.xml` |
| masked uid | `tUny...b0l1` | `tUny...b0l1` |
| `flutter.3s_user_tier` | absent | absent |
| `flutter.3s_product_id` | `3s_standard_monthly` | absent |
| `flutter.3s_purchase_date` | present | absent |

Post-restart probe:

```text
prefs.user_id_present=True
prefs.masked_uid=tUny...b0l1
prefs.tier=<absent>
prefs.product_id=<absent>
prefs.purchase_date_present=False
prefs.auth_mode_guest=false
```

Verdict:

- PASS for state injection persistence.
- BLOCKED for Cloud access block verification through fixture/list/download because no Cloud fixture was available and direct Firestore/Storage evidence was unavailable.

## 12. Scenario Verdicts

| Scenario | Verdict | Reason |
|---|---|---|
| R3-MQA-01 active Standard/Premium | BLOCKED | active paid state loaded and local clip recorded, but Cloud upload fixture was not proven created; no Firestore/Storage before-after |
| R3-MQA-02 expired within 30-day grace | BLOCKED | grace state persisted, but existing Cloud fixture/list/download/restore evidence unavailable |
| R3-MQA-03 expired after grace | BLOCKED | expired state persisted, but Cloud fixture/list/download/restore block and no-delete evidence unavailable |
| R3-MQA-04 signed-in free never paid | BLOCKED | free state persisted, but Cloud access block could not be proven with fixture or direct backend evidence |
| R3-MQA-06 grace Library upload/auto upload block | BLOCKED | `cloud_synced_paths_count=0`, but direct Storage before-after and reliable Cloud transfer execution evidence were unavailable |
| R3-MQA-07 grace CloudBackupScreen read-only notice | BLOCKED | no existing Cloud fixture available |
| R3-MQA-08 grace Cloud restore/download | BLOCKED | no existing Cloud fixture available |
| R3-MQA-09 grace metadata lifecycle write minimum | BLOCKED | Firestore before-after unavailable |
| R3-MQA-10 Profile Cloud stats matrix | BLOCKED | state matrix loaded locally, but Cloud stats behavior could not be validated without backend fixture/evidence |

FAIL count: 0 product behavior failures proven.

BLOCKED count: 9 scenarios.

## 13. Stop / Block Cause

The QA run did not hit a security stop in v3.

It is blocked by evidence/setup limitations:

```text
Active paid Cloud fixture creation was not proven from the app, and direct Firestore/Storage before-after evidence was unavailable.
```

## 14. Follow-Up Required

To complete R3 signed-in QA:

1. Provide a reliable way to trigger Cloud upload in the app UI, or add a temporary QA-only in-app trigger that calls the existing `CloudService.uploadVideoImmediate` path without changing production behavior.
2. Provide Firestore/Storage console access or a test-uid-limited read-only evidence script that emits only counts, masked uid paths, `videoId`, object existence, and object count.
3. Re-run active paid fixture creation first.
4. Re-run grace, expired-after-grace, and free states after fixture creation.
5. Continue to treat `app_dart_log` or `app_native_log` sensitive hits as stop-condition FAIL.

## 15. Prohibited Scope Confirmation

Confirmed not performed:

- `.env` read/output
- `TEST_GOOGLE_ID` output
- `TEST_GOOGLE_PW` output
- login automation
- password input
- operating user data access
- Firebase rules/index change
- Firestore schema change
- migration/backfill
- Storage deletion
- Cloud copy implementation
- npm audit fix
- deploy
- unrelated cleanup

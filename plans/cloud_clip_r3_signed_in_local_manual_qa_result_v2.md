# Cloud Clip R3 Signed-In Local Manual QA Result v2

## 1. Scope

- Date: 2026-05-19
- App package: `com.dk.three_sec`
- Platform/device: Android emulator `emulator-5554`
- Login method: user-performed manual Google login
- AI credential handling: no `.env` read/output, no `TEST_GOOGLE_ID` output, no `TEST_GOOGLE_PW` output, no password entry, no OAuth screen operation
- Output target: `plans/cloud_clip_r3_signed_in_local_manual_qa_result_v2.md`

## 2. Core References Reviewed

- `AGENTS.md`
- `CURRENT_PHASE.md`
- `DATA_COMPATIBILITY.md`
- `plans/cloud_clip_r3_manual_qa_checklist_v1.md`
- `plans/cloud_clip_r3_local_qa_fixture_setup_plan_v1.md`
- `plans/cloud_clip_r3_signed_in_local_manual_qa_result_v1.md`

## 3. Environment Actions

| Step | Result |
|---|---|
| Emulator discovery | `Pixel_9` available |
| Emulator launch | `emulator-5554` reached `device` state |
| App start before install | `com.dk.three_sec/.MainActivity` was not installed |
| App install/run | `flutter run -d emulator-5554 --no-resident` built and installed debug APK |
| Initial app state | App opened to camera permission-required state with bottom navigation available |
| Login | User completed Google login manually in emulator |

## 4. Firebase Auth Signed-In Check

Safe local inspection was limited to Android app private files and did not print raw auth store contents.

| Check | Result |
|---|---|
| Firebase Auth shared preference store | Present |
| Firebase user marker | Present |
| uid extraction | BLOCKED: safe parser could not extract a uid without risking raw auth payload output |
| uid recording | Not recorded; no full uid was printed |

Masked uid:

```text
unavailable
```

## 5. Logcat Redaction Check

Logcat was scanned through a helper script that outputs counts only and does not print matching values.

| Pattern | Count | Verdict |
|---|---:|---|
| email-like raw value | 3 | FAIL |
| password word/value marker | 0 | PASS |
| token word/value marker | 0 | PASS |
| order id marker | 0 | PASS |
| provider raw marker | 0 | PASS |

Result:

- The test account email is not recorded in this document.
- Raw matching log lines were not printed.
- Because email-like raw values were present in logcat after manual login, R3 signed-in QA stopped before subscription state injection.

## 6. SharedPreferences Evidence

SharedPreferences target:

```text
/data/user/0/com.dk.three_sec/shared_prefs/FlutterSharedPreferences.xml
```

Android Flutter SharedPreferences key prefix:

```text
flutter.
```

Required keys:

```text
flutter.3s_user_tier
flutter.3s_purchase_date
flutter.3s_product_id
flutter.3s_user_id
```

No state injection was performed.

| State | Before XML backup | After XML backup | Result |
|---|---|---|---|
| active paid | N/A | N/A | BLOCKED by logcat redaction failure |
| expired within 30-day grace | N/A | N/A | BLOCKED by logcat redaction failure |
| expired after grace | N/A | N/A | BLOCKED by logcat redaction failure |
| signed-in free never paid | N/A | N/A | BLOCKED by logcat redaction failure |

## 7. Firestore / Storage Evidence

No Firestore or Storage data was inspected or mutated after the redaction failure.

| Evidence | Before | After | Result |
|---|---|---|---|
| Firestore `videos` document count | N/A | N/A | BLOCKED |
| Firestore fixture document | N/A | N/A | BLOCKED |
| Storage object path | N/A | N/A | BLOCKED |
| Storage object count | N/A | N/A | BLOCKED |

Rationale:

- The safe uid could not be recorded.
- The logcat redaction gate failed before any paid/grace/free state injection.
- Operating user data access, schema changes, rules/index changes, migration/backfill, and Storage deletion were not performed.

## 8. Scenario Verdicts

| Scenario | Verdict | Reason |
|---|---|---|
| R3-MQA-01 active Standard/Premium | BLOCKED | logcat contains email-like raw values after user-performed manual login; active paid injection not performed |
| R3-MQA-02 expired within 30-day grace | BLOCKED | requires signed-in masked uid, active fixture, and clean redaction gate |
| R3-MQA-03 expired after grace | BLOCKED | requires signed-in masked uid, active fixture, and clean redaction gate |
| R3-MQA-04 signed-in free never paid | BLOCKED | requires clean redaction gate before state injection |
| R3-MQA-06 grace Library upload/auto upload block | BLOCKED | grace state injection and fixture were not created |
| R3-MQA-07 grace CloudBackupScreen read-only notice | BLOCKED | grace state injection and fixture were not created |
| R3-MQA-08 grace Cloud restore/download | BLOCKED | grace state injection and fixture were not created |
| R3-MQA-09 grace metadata lifecycle write minimum | BLOCKED | Firestore before/after was not captured |
| R3-MQA-10 Profile Cloud stats matrix | BLOCKED | active/grace/expired/free state matrix was not executed |

FAIL count: 1 redaction gate failure.

No Cloud policy product behavior was evaluated after the security stop.

## 9. Required Follow-Up

Before rerunning R3 signed-in local manual QA:

1. Use a QA build or logging configuration that redacts email-bearing auth diagnostics.
2. Confirm logcat has zero raw email/password/token/order id/provider values after manual login.
3. Add or use a safe signed-in status probe that reports only `signed_in=true` and `abcd...wxyz` masked uid.
4. Then rerun active paid injection, fixture creation, Firestore/Storage before-after capture, and R3-MQA-01~04 plus R3-MQA-06~10.

If Firestore later overwrites local paid/grace state to free, stop immediately and document whether a test-uid-limited Firestore subscription fixture is needed.

## 10. Prohibited Scope Confirmation

Confirmed not performed:

- `.env` read/output.
- `TEST_GOOGLE_ID` output.
- `TEST_GOOGLE_PW` output.
- Login automation.
- Password input.
- OAuth screen operation by AI.
- Personal/operating account use by AI.
- Operating user data access.
- Firebase rules/index change.
- Firestore schema change.
- migration/backfill.
- Storage object deletion.
- Cloud copy implementation.
- npm audit fix.
- deploy.
- unrelated cleanup.

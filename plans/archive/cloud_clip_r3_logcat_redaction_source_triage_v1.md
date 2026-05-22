# Cloud Clip R3 Logcat Redaction Source Triage v1

## 1. Scope

- Date: 2026-05-19
- App package: `com.dk.three_sec`
- Device: Android emulator `emulator-5554`
- Purpose: classify the R3 signed-in QA v2 `email-like` logcat hits without printing raw sensitive values.
- Login method: user-performed manual Google login.

Prohibited values were not printed:

- raw email
- `TEST_GOOGLE_ID`
- `TEST_GOOGLE_PW`
- password
- token
- order id
- raw provider value
- `.env` contents

## 2. References

- `plans/cloud_clip_r3_signed_in_local_manual_qa_result_v2.md`
- `plans/cloud_clip_r3_auth_log_redaction_report_v1.md`
- `lib/services/auth_service.dart`

Relevant code review result:

- `AuthService` Google login success logging uses `_redactedEmail(userCredential.user?.email)`.
- Targeted search did not show the prior raw `userCredential.user?.email` logging pattern.
- No app code patch was made in this triage because runtime hits were not from app logs.

## 3. Procedure

| Step | Result |
|---|---|
| Clear logcat | `adb logcat -c` completed |
| Stop app | `adb shell am force-stop com.dk.three_sec` completed |
| Start app | `adb shell am start -n com.dk.three_sec/.MainActivity` completed |
| Manual login | User performed Google login manually |
| Scan method | helper script parsed logcat and emitted only counts plus tag/process category metadata |
| Raw line output | Not performed |
| Raw matching value output | Not performed |

Helper:

```text
C:\tmp\r3_logcat_source_triage.ps1
```

## 4. Count-Only Result

```text
app_pid_count=1
email_like_hit_total=3
category.app_dart_log=0
category.app_native_log=0
category.firebase_sdk_log=0
category.google_signin_sdk_log=0
category.android_system_log=3
category.stale_or_unknown=0
hit_field.tag=0
hit_field.message=1
hit_field.tag_and_message=2
hit_field.unparsed=0
```

Breakdown:

| Count | Category | Hit field | Severity | Tag | Package |
|---:|---|---|---|---|---|
| 2 | `android_system_log` | `tag_and_message` | `D` | `android.hardware.audio@7.1-impl.ranchu` | `<non-app-process>` |
| 1 | `android_system_log` | `message` | `W` | `JobScheduler` | `<non-app-process>` |

No raw matching log message was printed or copied into this document.

## 5. Source Category Verdict

| Source category | Count | Verdict |
|---|---:|---|
| `app_dart_log` | 0 | PASS |
| `app_native_log` | 0 | PASS |
| `firebase_sdk_log` | 0 | PASS |
| `google_signin_sdk_log` | 0 | PASS |
| `android_system_log` | 3 | WARN |
| `stale_or_unknown` | 0 | PASS |

Classification:

- The hits were not emitted by the `com.dk.three_sec` process.
- The hits were not emitted by Flutter/Dart log tags.
- The hits were not classified as Firebase SDK or Google Sign-In SDK logs.
- Because logcat was cleared before app restart and manual login, the hits are not stale from the prior QA session.
- The two `android.hardware.audio@7.1-impl.ranchu` hits are email-pattern false positives caused by an Android system/HAL-style tag containing `@` and dotted suffix text, not app auth logging.
- The `JobScheduler` hit is from an Android system process. The raw message was not printed, so this triage only classifies it as non-app system log.

## 6. Code Redaction Decision

No app code redaction patch was applied.

Reason:

- `app_dart_log=0`
- `app_native_log=0`
- `com.dk.three_sec` process hits were not present in the count-only scan.
- The observed hits are outside app code control.

If a future scan reports `app_dart_log > 0` or `app_native_log > 0`, stop signed-in QA and patch the emitting app log site before continuing.

## 7. QA Gate Recommendation

Recommended gate adjustment:

1. Treat `app_dart_log` and `app_native_log` email-like hits as `FAIL`.
2. Treat `firebase_sdk_log` and `google_signin_sdk_log` email-like hits as `WARN` unless a raw value is known to be emitted by app-controlled logging.
3. Treat `android_system_log` hits as `WARN` when raw values are not printed and the app process count is zero.
4. Add a scanner distinction between `tag` hits and `message` hits, because Android system tags can match the email regex without containing an email address.
5. Signed-in QA may resume after this triage because app-controlled categories are zero.

Conservative caveat:

- If release policy requires zero email-like patterns across the entire device logcat, even from Android system processes, then the gate remains BLOCKED. That stricter policy is not fixable by app code alone.

## 8. Prohibited Scope Confirmation

Confirmed not performed:

- raw email output
- `TEST_GOOGLE_ID` output
- `TEST_GOOGLE_PW` output
- `.env` read/output
- password/token/order id output
- OAuth automation
- Firebase rules/index change
- Firestore schema change
- Storage deletion
- Cloud copy implementation
- deploy
- unrelated cleanup

# Cloud Clip R3 Signed-In Local Manual QA Result v1

## 1. Security Check

Date: 2026-05-19

Required checks:

```cmd
git status --short
git check-ignore .env
git ls-files .env
```

Results:

| Check | Result | Verdict |
|---|---|---|
| `git status --short` | `.env` not listed. `.gitignore` is modified. Existing R3 code/docs/test files are modified/untracked from prior work. | PASS for `.env` non-listing |
| `git check-ignore .env` | Output: `.env` | PASS |
| `git ls-files .env` | Empty output | PASS |

Conclusion:

- `.env` is ignored.
- `.env` is not tracked.
- `git rm --cached .env` is not required.
- `.env` contents were not printed.
- `TEST_GOOGLE_ID` and `TEST_GOOGLE_PW` were not printed.

## 2. Execution Decision

The signed-in R3 local manual QA was not executed.

Reason:

- The app's current Google login success path prints the signed-in user's email to runtime logs.
- `TEST_GOOGLE_ID` is a credential value.
- The user explicitly required that credential values must not appear in logs, reports, or screenshots.
- Proceeding with Google login would risk writing `TEST_GOOGLE_ID` to Android logcat.

Relevant code locations:

| File | Risk |
|---|---|
| `lib/services/auth_service.dart` | Google login success logs `userCredential.user?.email` |
| `lib/services/auth_service.dart` | Apple/Kakao/Naver and profile sync paths also include email-bearing diagnostics |

No credential-based login was attempted.

## 3. Environment State

Observed:

- Android emulator available: `emulator-5554`, Android 15 API 35.
- App package: `com.dk.three_sec`.
- `.firebaserc` default project: `fir-3s-8edb9`.
- `android/app/google-services.json` exists.

Actions performed:

- Cleared local emulator app data to remove prior guest session.
- Started app on emulator.
- Confirmed app foreground activity: `com.dk.three_sec/.MainActivity`.

Credential use:

- `.env` values were not read into output.
- No Google login form was filled.
- No password was typed.
- No screenshots/dumps containing credential values were captured.

## 4. SharedPreferences Evidence

Because login was stopped before credential use:

- No active paid state injection was performed.
- No grace state injection was performed.
- No expired state injection was performed.
- No signed-in free never paid state injection was performed.

Reason:

- R3 state injection must be applied only after a valid non-production Firebase Auth session exists.
- Injecting local paid/grace keys before a signed-in Firebase Auth session would not create a valid test uid and would invalidate Firestore/Storage evidence.

## 5. Firestore / Storage Evidence

Firestore before-after:

- BLOCKED.
- No non-production signed-in Firebase Auth uid was available.
- No `users/{testUid}/videos` path was inspected.
- No operating user data was accessed.

Storage before-after:

- BLOCKED.
- No test uid or fixture object path was available.
- No Storage path was inspected.
- No object was created, copied, moved, or deleted.

## 6. Scenario Verdicts

| Scenario | Verdict | Reason |
|---|---|---|
| R3-MQA-01 active Standard/Premium | BLOCKED | Signed-in QA login stopped due credential-in-log risk |
| R3-MQA-02 expired within 30-day grace | BLOCKED | Requires signed-in test uid and Cloud fixture |
| R3-MQA-03 expired after grace | BLOCKED | Requires signed-in test uid and Cloud fixture |
| R3-MQA-04 signed-in free never paid | BLOCKED | Requires signed-in test uid |
| R3-MQA-06 grace Library upload/auto upload block | BLOCKED | Requires signed-in grace state and fixture |
| R3-MQA-07 grace CloudBackupScreen read-only 안내 | BLOCKED | Requires signed-in grace state and fixture |
| R3-MQA-08 grace Cloud restore/download | BLOCKED | Requires signed-in grace state and fixture |
| R3-MQA-09 grace metadata lifecycle write minimum | BLOCKED | Requires signed-in grace state and Firestore before-after |
| R3-MQA-10 Profile Cloud stats matrix | BLOCKED | Requires signed-in active/grace/expired/free state matrix |

FAIL count: 0

No product behavior failure was observed. This is a security stop.

## 7. Stop Cause

Execution stopped before Google login.

Stop cause:

```text
Credential value would likely be written to app/runtime logs by the current auth diagnostics.
```

This conflicts with:

- `TEST_GOOGLE_PW` output prohibition.
- Credential value output prohibition.
- Credential values not appearing in logs/reports/screenshots.

## 8. Required Remediation Before Retrying

One of the following must happen before signed-in QA can proceed safely:

1. Temporarily run a QA build that redacts email-bearing auth diagnostics.
2. Change auth diagnostic logging so it never prints email or provider account identifiers.
3. Provide a login method that does not expose `TEST_GOOGLE_ID` to app logs or Android logcat.
4. Use an already signed-in emulator account only if logs are first proven not to print credential identifiers.

Minimum log redaction requirements:

- Do not print `userCredential.user?.email`.
- Do not print `user.email`.
- Do not print `socialEmail`.
- Do not print raw provider profile payloads.
- Mask uid in reports.

After remediation, rerun:

1. Sign in with the non-production QA account.
2. Confirm uid in memory/logs without printing email.
3. Inject active paid state for that uid.
4. Create test Cloud clip fixture.
5. Capture Firestore/Storage before-after for the test uid only.
6. Rerun R3-MQA-01~04 and R3-MQA-06~10.

## 9. Prohibited Scope Confirmation

Confirmed not performed:

- `TEST_GOOGLE_ID` output.
- `TEST_GOOGLE_PW` output.
- `.env` commit.
- Personal/operating account login.
- Operating user data access.
- Firebase rules/index change.
- Firestore schema change.
- migration/backfill.
- Storage object deletion.
- Cloud copy implementation.
- deploy.
- unrelated cleanup.

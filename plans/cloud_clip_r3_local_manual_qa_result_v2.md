# Cloud Clip R3 Local Manual QA Result v2

## 1. Summary

- Date: 2026-05-19
- App build/version: `1.3.6+136`
- Device: Android emulator `emulator-5554`, Android 15 API 35
- Firebase environment observed: `.firebaserc` default project `fir-3s-8edb9`
- App package: `com.dk.three_sec`
- Current account type: guest
- Test account: BLOCKED. No non-production signed-in Firebase Auth test account was available.
- Test Cloud clip fixture: BLOCKED. Could not create without a signed-in non-production account.
- SharedPreferences state injection: NOT PERFORMED. Injection into a guest session would not create a valid Firebase Auth user and could produce misleading QA results.
- Firestore before-after: BLOCKED. No test uid available.
- Storage before-after: BLOCKED. No test uid/object path available.
- Production user data: not used.
- Code/Firebase/deploy changes: none.

Overall verdict:

R3 local manual QA v2 remains BLOCKED. Execution stopped before fixture creation because the required non-production Firebase Auth test account was not available and the current app session is guest mode.

## 2. Execution Log

Environment checks executed:

```cmd
Get-Content .firebaserc
Get-ChildItem android\app -Recurse -Filter google-services.json
flutter devices --device-timeout 20
```

Observed:

- `.firebaserc` default project: `fir-3s-8edb9`.
- `android/app/google-services.json` exists.
- Android emulator connected: `sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64 • Android 15 (API 35)`.
- App foreground activity confirmed: `com.dk.three_sec/.MainActivity`.

Login path check:

- App login UI supports Google, Kakao, and guest.
- Email/password test login UI was not found.
- Existing session is guest.
- Google/Kakao login was not attempted because no non-production test credentials/account were provided, and using an arbitrary device account could violate the no production/personal data rule.

## 3. SharedPreferences Evidence

Target file:

```text
/data/user/0/com.dk.three_sec/shared_prefs/FlutterSharedPreferences.xml
```

Backup created inside app sandbox:

```text
/data/user/0/com.dk.three_sec/shared_prefs/FlutterSharedPreferences.r3qa_v2_before.xml
```

Observed shared_prefs listing:

```text
FlutterSharedPreferences.r3qa_v2_before.xml
FlutterSharedPreferences.xml
com.google.android.gms.appid.xml
com.google.firebase.messaging.xml
io.flutter.firebase.messaging.callback.xml
```

Before state summary:

| Key | Observed value |
|---|---|
| `flutter.3s_user_id` | `guest_..._...` masked guest id |
| `flutter.3s_auth_mode_guest` | `true` |
| `flutter.3s_user_tier` | absent |
| `flutter.3s_purchase_date` | absent |
| `flutter.3s_product_id` | absent |
| `flutter.3s_next_user_tier` | absent |
| `flutter.3s_next_tier_effective_at` | absent |

After state:

- Not changed.
- No active/grace/expired/free signed-in state was injected.

Reason:

- R3 fixture setup plan requires signing in through the app first.
- The current session is guest.
- Editing only `flutter.3s_user_id` and `flutter.3s_auth_mode_guest` would not create a valid Firebase Auth session.
- Proceeding would make Firestore/Storage evidence invalid and could mask real access behavior.

Evidence paths:

| Evidence | Path |
|---|---|
| Current UI dump | `C:\tmp\r3_mqa_v2_current_window.xml` |
| App internal backup | `shared_prefs/FlutterSharedPreferences.r3qa_v2_before.xml` |

## 4. Firestore Before-After Evidence

Result: BLOCKED.

Reason:

- No non-production signed-in Firebase Auth test uid was available.
- No test account path such as `users/{testUid}/videos` could be safely scoped.
- Firestore Console/CLI was not used to inspect operating user data.

Before:

- Not captured.

After:

- Not captured.

No Firestore schema changes, document edits, migrations, or deletes were performed.

## 5. Storage Before-After Evidence

Result: BLOCKED.

Reason:

- No test uid was available.
- No fixture object path such as `users/{testUid}/videos/{videoId}/{fileName}` existed for this QA run.
- Storage Console/CLI was not used to inspect operating user data.

Before:

- Not captured.

After:

- Not captured.

No Storage object was created, copied, moved, or deleted.

## 6. Scenario Results

### R3-MQA-01 Active Standard/Premium

- Account type: active Standard/Premium
- Preconditions: signed-in non-production Firebase Auth test account, active paid local state, test local clip, Firestore/Storage access scoped to test uid.
- Steps executed:
  - Verified emulator and app package.
  - Verified current app session is guest.
  - Checked login implementation; no email/password test login UI exists.
  - Did not attempt Google/Kakao login without explicit non-production test credentials.
- Expected result: Cloud upload succeeds, Firestore metadata and Storage object created, Cloud list/download and Profile stats work.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: SharedPreferences shows guest mode; no signed-in test uid.
- Follow-up action: provide or prepare a non-production signed-in test account and login method.

### R3-MQA-02 Expired Within 30-Day Grace

- Account type: expired within grace
- Preconditions: signed-in test account, existing Cloud clip fixture, preserved paid purchaseDate/productId history within grace.
- Steps executed:
  - Stopped before state injection because signed-in test account and Cloud fixture were missing.
- Expected result: Cloud read/download allowed, new upload blocked with `subscription_expired`, no new Storage object.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no test uid, no fixture path, no SharedPreferences injection performed.
- Follow-up action: complete R3-MQA-01 first to create fixture, then inject within-grace state.

### R3-MQA-03 Expired After Grace

- Account type: expired after grace
- Preconditions: signed-in test account, existing Cloud clip fixture, paid purchaseDate/productId history older than grace.
- Steps executed:
  - Stopped before state injection because signed-in test account and Cloud fixture were missing.
- Expected result: Cloud read/download blocked, new upload blocked, no Firestore/Storage delete.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no test uid, no fixture path, no SharedPreferences injection performed.
- Follow-up action: complete fixture creation, then inject after-grace state.

### R3-MQA-04 Signed-In Free Never Paid

- Account type: signed-in free never paid
- Preconditions: signed-in test account, no paid local history keys.
- Steps executed:
  - Current session was guest, not signed-in free.
  - No state injection performed.
- Expected result: upload blocked, Cloud read blocked, Profile Cloud stats inactive or `-`/0.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: SharedPreferences shows `flutter.3s_auth_mode_guest=true`.
- Follow-up action: sign in with a non-production account and remove paid keys only after login.

### R3-MQA-06 Grace Library Upload/Button/Auto Upload Block

- Account type: expired within grace
- Preconditions: signed-in test account, grace state, local clip, optional auto upload/queue setup.
- Steps executed:
  - Not executed because grace state could not be safely established.
- Expected result: upload/auto upload/queue upload blocked, no new Storage object.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no signed-in grace state.
- Follow-up action: rerun after R3-MQA-02 setup.

### R3-MQA-07 Grace CloudBackupScreen Read-Only 안내

- Account type: expired within grace
- Preconditions: signed-in test account, grace state, existing Cloud clip fixture.
- Steps executed:
  - Not executed.
- Expected result: existing Cloud clip visible with read-only/grace 안내 and no write CTA.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no Cloud fixture.
- Follow-up action: rerun after fixture creation and grace state injection.

### R3-MQA-08 Grace Cloud Restore/Download

- Account type: expired within grace
- Preconditions: signed-in test account, grace state, existing Cloud clip fixture.
- Steps executed:
  - Not executed.
- Expected result: restore/download succeeds locally, Cloud metadata/object not deleted.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no Cloud fixture and no Storage before-after scope.
- Follow-up action: rerun after fixture creation and before-after capture setup.

### R3-MQA-09 Grace Metadata Lifecycle Write Minimum

- Account type: expired within grace
- Preconditions: signed-in test account, grace state, existing Cloud clip fixture, Firestore before-after visibility.
- Steps executed:
  - Not executed.
- Expected result: restore/download allowed; unnecessary Cloud metadata lifecycle writes blocked or skipped.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: Firestore before-after could not be scoped to a test uid.
- Follow-up action: rerun after test uid and Firestore fixture path are available.

### R3-MQA-10 Profile Cloud Stats Matrix

- Account type: active paid / grace / expired / signed-in free never paid
- Preconditions: signed-in test account and all four local states.
- Steps executed:
  - Current guest profile was already covered in v1.
  - No signed-in state matrix was executed.
- Expected result: active/grace stats align with `canReadExistingCloudClips()`, expired/free inactive or `-`/0.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no signed-in state matrix.
- Follow-up action: rerun after account and state injection setup.

## 7. Failure / Stop Decision

No FAIL was observed because the policy-sensitive Cloud scenarios were not executed.

Execution was stopped before fixture creation and state injection.

Stop reason:

1. Required non-production Firebase Auth test account was not available.
2. Current app state is guest mode.
3. App does not expose email/password test login.
4. Google/Kakao login without explicit test credentials could use personal or production-linked account data.
5. SharedPreferences-only uid/auth-mode manipulation would not create a valid Firebase Auth session and would invalidate Firestore/Storage QA.

This is a safety stop, not a product behavior failure.

## 8. Required Inputs To Proceed

To rerun and close the blocked items, provide one of the following:

1. A non-production Google/Kakao test account available on the emulator, explicitly approved for QA.
2. A dev/staging Firebase project alias and config, if R3 QA must avoid the current default project.
3. An approved test-account creation/login path for Firebase Auth that does not require operating user credentials.

Also required:

- Confirmation that the test account may create a test Cloud clip.
- Firebase Console/tooling access scoped to the test uid for Firestore before-after.
- Storage Console/tooling access scoped to the test uid/object path for before-after.

## 9. Prohibited Scope Confirmation

Confirmed not performed:

- Operating user data access.
- Firebase rules/index change.
- Firestore schema change.
- migration/backfill.
- Storage object deletion.
- Cloud copy implementation.
- npm audit fix.
- deploy.
- unrelated cleanup.
- SharedPreferences paid/grace/free state injection.
- Firestore/Storage read against an unscoped production user path.

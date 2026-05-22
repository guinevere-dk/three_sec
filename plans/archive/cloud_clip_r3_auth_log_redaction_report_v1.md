# R3 Auth Log Redaction Report v1

Date: 2026-05-19

## Scope

- Target file: `lib/services/auth_service.dart`
- Purpose: unblock R3 signed-in local QA by removing email-bearing and full identifier-bearing auth logs.
- Not performed: Google login, password entry, `.env` read/output, Firebase rules/index/schema changes, deploy, migration, Storage deletion, Cloud copy work, npm audit fix.

## Changes

- Added local redaction helpers in `AuthService`:
  - `_maskUid(String?)`: keeps only first 4 and last 4 uid characters when available.
  - `_redactedEmail(String?)`: emits `d***@***`-style output without the email domain.
  - `_redactedUrl(String?)`: replaces profile/download URLs with `<redacted-url>`.
  - `_redactedAuthError(Object)`: logs auth error class/code metadata without exception details that can contain identifiers.
- Redacted Google, Apple, Kakao, and Naver login success logs:
  - raw email removed.
  - raw uid removed.
  - raw display name removed.
  - raw profile photo URL removed.
- Redacted social auth exchange diagnostics:
  - provider values replaced with `<redacted-provider>`.
  - `providerInfo` replaced with `<redacted-provider-info>`.
  - extracted email masked through `_redactedEmail`.
  - extracted profile/photo URL masked through `_redactedUrl`.
- Redacted login/session/sync/profile/delete diagnostics:
  - full uid replaced with masked uid in sign-in post-processing, Firestore tier sync, profile update, profile edit, and account deletion guard logs.
  - storage upload path and profile download URL redacted in profile edit diagnostics.
- Reduced Kakao token diagnostics:
  - retained only boolean token presence.
  - removed scope and expiry details from logs.
- Reduced social exchange token diagnostics:
  - retained only boolean token presence.
  - removed access/id token length output.

## Search Verification

Command:

```powershell
rg "userCredential.user?.email|email|TEST_GOOGLE|print" lib\services\auth_service.dart
```

Result:

- `TEST_GOOGLE`: no matches.
- `userCredential.user?.email`: only appears inside `_redactedEmail(...)` log calls.
- `email`: remaining matches are redaction helper code, Firestore/profile payload fields, Apple scope request, or `_redactedEmail(...)` output.
- `print`: existing logging remains by design; unrelated `avoid_print` cleanup was not performed.

Additional targeted check:

```powershell
rg -n 'uid=\$uid|uid=\$\{user\.uid\}|provider=\$provider|resolvedProvider=\$providerLabel|providerInfo=\$|email=\$socialEmail|email=\$\{user\.email\}|photoUrl=\$\{|photoURL=\$\{|accessToken=|idToken=|orderId|TEST_GOOGLE' lib\services\auth_service.dart
```

Result:

- No raw uid, raw provider, raw email, order id, or test credential matches.
- Remaining matches are `_redactedUrl(...)` output lines only.

## Analyzer Verification

Command:

```powershell
flutter analyze lib\services\auth_service.dart
```

Result:

- Exit code: 1
- Errors: 0
- Warnings: 0
- Infos: 151

Notes:

- Initial run found one compile error from a masked uid variable scope issue; it was fixed.
- Remaining analyzer issues are existing info-level debt such as `avoid_print`, `prefer_conditional_assignment`, and `deprecated_member_use`.
- Per task constraint, no broad print/style/deprecation cleanup was performed.

## Unit Test Verification

Command:

```powershell
flutter test test\user_status_manager_r3_test.dart
```

Result:

- PASS
- `5` tests passed.

## QA Resume Verdict

R3 signed-in local manual QA can resume.

The original blocker, email-bearing Google sign-in logging, is removed. The AuthService auth/login/sync diagnostics no longer intentionally print raw email, full uid, provider identifiers, credential identifiers, token values, order ids, or `TEST_GOOGLE_*` values.

## Remaining Risks

- `AuthService` still uses many `print` calls. They are retained intentionally to avoid unrelated cleanup, but should be replaced with a structured redacting logger in a separate task.
- Stack traces are still printed for failures. They do not intentionally include credentials, but a future central logger should apply a final redaction pass before output.
- Firestore/profile payloads still store email where the current app contract requires it; this report only changes logging behavior, not data schema or persistence.

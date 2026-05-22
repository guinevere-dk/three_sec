# Google Play Promo Code Redeem QA Report v1

Date: 2026-05-22
Status: local implementation QA complete, real Google Play redemption pending

## Scope

Implemented Profile-based Google Play code registration handoff for Android Free/Guest users.

This implementation does not validate, store, or grant entitlement from the entered code. Standard entitlement is still granted only by the existing Google Play Billing entitlement refresh pipeline.

## Changed Files

- `lib/services/promo_code_redeem_service.dart`
- `lib/screens/profile_screen.dart`
- `test/promo_code_redeem_service_test.dart`
- `plans/promo_code_google_play_redeem_implementation_plan_v1.md`

## Local QA Results

| Check | Result | Notes |
| --- | --- | --- |
| Code normalization | Pass | trims whitespace, removes spaces, uppercases |
| Format validation | Pass | allows A-Z, 0-9, hyphen; rejects invalid characters |
| Android-only launch gate | Pass | injected platform test blocks non-Android launch |
| Google Play redeem URI build | Pass | service builds encoded Play redeem URI |
| Guest launch block | Pass by code review | Guest card routes to login transition instead of opening Play redeem |
| Standard/Premium hidden | Pass by code review | Profile card is hidden for current Standard/Premium tier |
| Entitlement source of truth | Pass by code review | app-return path refreshes existing Store entitlement state; no direct grant from code |
| Duplicate refresh control | Pass by code review | app resume waits for global resume refresh before Profile re-read; manual refresh has 3 second debounce |
| Sensitive app logs | Pass by scan | app logs code length and tier state only; no raw code/full redeem URL/token/order/email/full uid |

## Commands

```powershell
dart format lib\services\promo_code_redeem_service.dart test\promo_code_redeem_service_test.dart lib\screens\profile_screen.dart
flutter test test\promo_code_redeem_service_test.dart
flutter analyze --no-fatal-infos
```

## Command Results

- `dart format`: pass
- `flutter test test\promo_code_redeem_service_test.dart`: pass, 6 tests
- `flutter analyze --no-fatal-infos`: pass with existing info-level lint output only

## Not Yet Verified

These require a real Android device or emulator connected to a Google Play test account and Play Console promo campaigns.

| Scenario | Required Test |
| --- | --- |
| Profile handoff custom launch code | Profile -> Google Play code registration -> app return -> Standard sync |
| Purchase sheet custom launch code | Paywall -> Google Play purchase sheet -> code use -> app return -> Standard sync |
| One-time friends code | Profile handoff using generated one-time code without recording the raw code |
| Wrong/expired/used code | Google Play rejects; app remains Free |
| Multi-account device | UI warning is shown; entitlement appears only when Play account and MOA account alignment succeeds |

## Release Risk

The main remaining risk is Google Play behavior for custom codes. If Profile URL handoff is unreliable but purchase-sheet redeem works, keep Profile copy conservative and rely on the purchase sheet path for launch support.


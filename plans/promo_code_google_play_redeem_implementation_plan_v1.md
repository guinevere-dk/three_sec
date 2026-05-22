# MOA Google Play Promo Code Redeem Implementation Plan v1

Status: implementation plan only  
Source prompt: `plans/promotion.md`  
Target area: Profile subscription card  
Date: 2026-05-22  

## 1. Decision

Implement promo code input as a Google Play redeem handoff, not as an in-app coupon system.

The app must never grant Standard from a typed code. The app only:

1. receives a code from the user;
2. normalizes and format-validates it locally;
3. opens the Google Play redeem URL;
4. refreshes Store entitlement after app return;
5. grants Standard only when Google Play active subscription verification succeeds through the existing IAP entitlement pipeline.

The trusted source of truth is the verified active Standard subscription, not the promo code string.

## 2. Campaigns

Existing Google Play Console campaigns from `plans/promotion.md`:

| Campaign | Purpose | Benefit | Code Type |
| --- | --- | --- | --- |
| `moa-standard-1m-launch` | launch trial | Standard 1 month free trial | representative custom code: `MOAWELCOME` |
| `moa-standard-90d-friends` | friends/family/core feedback users | Standard 90 days free trial | Google Play generated one-time codes |

The app must not hard-code campaign names or code-specific benefits into entitlement logic. Campaign names may appear only in QA docs or operator notes.

## 3. Current Code Inventory

Relevant current implementation:

| Area | Current state |
| --- | --- |
| Profile entry | `lib/screens/profile_screen.dart` shows a subscription menu item and opens `SubscriptionManagementScreen` via `_openStandardSubscriptionEntry()`. |
| Subscription management | `lib/screens/subscription_management_screen.dart` observes app lifecycle and calls `_refreshSubscriptionState(reason: 'app_resumed')` on resume. |
| Global app resume | `lib/main.dart` calls `IAPService().refreshEntitlementsFromStore(reason: 'app_resumed')` on `AppLifecycleState.resumed`. |
| Store entitlement refresh | `lib/services/iap_service.dart` has `refreshEntitlementsFromStore()` and Android `queryPastPurchases()` based verification through `_retryRestoreVerificationFromStore()`. |
| Manual restore | `IAPService.restorePurchases()` exists, but Paywall RESTORE was intentionally removed. Subscription management still owns subscription state actions. |
| Tier policy | `UserStatusManager` and `IAPEntitlementPolicy` already map `3s_standard_monthly` / `3s_standard_annual` to Standard. |

This means Phase 1 should avoid a new entitlement system. It should reuse `IAPService.refreshEntitlementsFromStore()` and existing Firestore sync side effects.

## 4. Scope

### In Scope

- Android-only Profile subscription card Google Play code registration handoff.
- Google Play redeem URL launch:
  - `https://play.google.com/redeem?code={encodedCode}`
- Local format validation only.
- Pending redeem state for app-return messaging and targeted refresh.
- App-return entitlement sync using existing IAP service.
- Safe diagnostics without raw code, token, order id, email, or full uid.
- Manual "구독 상태 다시 확인" action after redeem return.
- Tap-through QA with `MOAWELCOME` and at least one generated one-time code.

### Out of Scope

- App-side coupon validation.
- Server-side promo code validation.
- Firestore promo code collection.
- Storing raw promo codes.
- Granting Standard directly from any code value.
- Firebase rules, Functions schema, product id, package id, bundle id changes.
- iOS App Store offer code implementation.
- Play Console campaign creation or modification.
- New backend entitlement contract.

## 5. Platform Policy

### Android

Show the Google Play code registration section to eligible Android users. Open Google Play redeem with the encoded code. After the user returns, call or observe the existing Store entitlement refresh.

Google Play documentation supports directing users to:

```text
https://play.google.com/redeem?code=promo_code
```

Google also notes that promo code redemption can happen outside the app and the app must correctly process such purchases through Play Billing purchase fetching/processing. MOA already has Android `queryPastPurchases()` based refresh in `IAPService.refreshEntitlementsFromStore()`.

### iOS

Do not implement iOS code input in this phase.

Apple has a separate offer code system with App Store redemption URLs and StoreKit APIs. That must be planned separately if needed. For this phase, hide the section on iOS.

## 6. UX Design

### 6.1 Free User

Recommended location:

```text
Profile
-> Subscription card/menu group
-> below Standard upsell row or inside a compact expanded section
```

Copy:

```text
Google Play 코드 등록
Google Play에 로그인된 계정이 MOA 구독에 사용할 계정과 같은지 확인해 주세요.

[코드 입력] [코드 등록하러 가기]
```

After button tap:

```text
Google Play에서 코드 등록을 완료한 뒤 앱으로 돌아오면 구독 상태를 다시 확인합니다.
```

Avoid wording that implies MOA applies or validates the code directly. Preferred feature name is "Google Play 코드 등록", not "프로모션 코드 적용".

### 6.2 Standard User

Default: hide promo code input.

Reason: a current active Standard user usually cannot benefit from another new-subscriber launch code, and showing it creates confusion.

Optional future enhancement: collapsed "코드가 있나요?" secondary link, but not in Phase 1.

### 6.3 Expired / Grace User

Show promo code input if current local tier is Free or Cloud read-only grace. This helps previously paid users recover or restart through a Store-approved offer, if Google Play allows the code based on campaign eligibility.

### 6.4 Guest User

Do not allow redeem flow without an authenticated account.

Show:

```text
프로모션 코드는 구독 권한을 계정에 연결하기 위해 로그인이 필요합니다.
```

Action:

```text
[로그인하고 코드 사용]
```

Rationale: existing paid flow requires login before purchase so entitlement is safely linked to the app account.

Hard rule:

```text
Guest 상태에서는 코드 등록 화면을 열지 않는다.
먼저 MOA에 로그인한 뒤, 같은 Google Play 계정으로 코드 등록을 진행하도록 안내한다.
```

Reason: if a Guest user redeems a code in Google Play before signing in to MOA, the Store subscription may be tied to a Play account while the app has no authenticated MOA account to link or sync against. This is one of the most likely support issues: "I used the code but Standard is not shown in the app."

## 7. Input Policy

Normalize:

```dart
final normalizedCode = rawInput.trim().replaceAll(' ', '').toUpperCase();
```

Allowed characters:

```text
A-Z
0-9
-
```

Validation:

| Rule | Plan |
| --- | --- |
| Empty | button disabled |
| Too short | reject below 4 chars |
| Too long | reject above 64 chars |
| Invalid chars | show local format error |
| Spaces | remove spaces during normalization |
| Case | uppercase automatically |

Do not check whether the code is `MOAWELCOME`. Do not check whether a one-time code exists. Google Play owns final validity.

## 8. State Model

Use short-lived local UI state in `ProfileScreen`.

Suggested fields:

```dart
final TextEditingController _promoCodeController = TextEditingController();
bool _isPromoRedeemLaunching = false;
bool _promoRedeemPending = false;
DateTime? _promoRedeemStartedAt;
String? _promoCodeFormatError;
```

Persistence:

- Phase 1: in-memory only is acceptable because global app resume already refreshes Store entitlements.
- Optional Phase 2: persist a boolean/timestamp if the app process is killed after opening Play Store. If persisted, use a new key only after explicit review because SharedPreferences keys are approval-sensitive in `DATA_COMPATIBILITY.md`.

## 9. Launch Flow

```text
User enters code
-> normalize and format validate
-> set promoRedeemPending=true
-> launch external URL: https://play.google.com/redeem?code={encodedCode}
-> user completes or cancels in Google Play
-> app resumes
-> refresh entitlement from Store
-> refresh UserStatusManager/Profile UI
-> show result based on Standard active after refresh
```

Implementation detail:

```dart
final encodedCode = Uri.encodeComponent(normalizedCode);
final redeemUrl = Uri.parse('https://play.google.com/redeem?code=$encodedCode');
await launchUrl(redeemUrl, mode: LaunchMode.externalApplication);
```

Fallback copy if launch fails:

```text
Google Play 코드 등록 화면을 열 수 없습니다.
Play Store 앱에서 프로필 > 결제 및 정기 결제 > 코드 사용으로 등록해 주세요.
```

Pre-launch reminder copy:

```text
Google Play에 로그인된 계정이 MOA 구독에 사용할 Google 계정과 같은지 확인해 주세요.
계정이 다르면 코드가 등록되어도 앱에서 구독이 보이지 않을 수 있습니다.
```

## 10. Return Sync and Debounce

Reuse existing:

```dart
await IAPService().refreshEntitlementsFromStore(reason: 'promo_redeem_return');
await IAPService().syncCancellationStateFromStore(reason: 'promo_redeem_return');
await UserStatusManager().initialize();
await _refreshProfile();
```

Expected result:

- If Google Play generated an active Standard subscription, existing verification should apply Standard and sync to Firestore.
- If code is invalid, expired, already used, or not completed, no Standard entitlement is granted.

UI result copy:

Success:

```text
Standard 구독이 활성화되었습니다.
이제 Cloud 백업, 편집 기능, 1080p 내보내기를 사용할 수 있습니다.
```

Not yet active:

```text
아직 활성 구독을 확인하지 못했습니다.
Google Play에서 코드 적용을 완료했는지 확인한 뒤 다시 시도해 주세요.
```

Manual action:

```text
구독 상태 다시 확인
```

This manual action should call the same refresh method with reason `promo_redeem_manual_refresh`.

### 10.1 Duplicate Refresh Control

`main.dart` already calls `IAPService().refreshEntitlementsFromStore(reason: 'app_resumed')` on global app resume. If Profile also observes resume after a redeem handoff, duplicate Play Billing queries can occur.

Required plan:

- Profile targeted refresh is primarily for user feedback and immediate UI state.
- It must not blindly duplicate global app resume refresh.
- Add a 1-3 second debounce window before calling Store refresh from Profile.
- If the global resume refresh has just run, Profile should wait briefly, re-read `UserStatusManager`, and update the UI/message without a second Store query.

Preferred implementation options:

1. Local Profile debounce:
   - track `_lastPromoRedeemRefreshAt`;
   - if app resumed within 1-3 seconds of the global resume refresh, delay or skip direct Store query;
   - call `_refreshProfile()` after the global flow has had time to apply.
2. Shared service debounce:
   - add a small time-window guard inside `IAPService.refreshEntitlementsFromStore()`;
   - key by reason group such as `app_resumed` / `promo_redeem_return`;
   - return the latest known result when a duplicate call arrives too soon.

For Phase 1, prefer local Profile debounce to avoid changing the billing service contract more than necessary. If QA shows duplicate queries or double UI messages, move the debounce into `IAPService` as Phase 1 hardening.

## 11. Logging Policy

Allowed logs:

- Google Play code registration button clicked
- normalized code length
- platform
- launch success/fail
- entitlement refresh started/completed
- before/after tier
- active Standard true/false

Forbidden logs:

- raw promo code
- purchase token
- order id
- email
- full uid
- full redeem URL containing code

Example safe marker:

```text
[PromoRedeem] launch requested platform=android codeLength=10 validFormat=true
[PromoRedeem] return sync done beforeTier=free afterTier=standard activeStandard=true
```

## 12. File-Level Plan

### Phase P1-A. Inventory and UI Placement

Files:

- `lib/screens/profile_screen.dart`

Tasks:

1. Identify the subscription card/menu group final placement.
2. Add a compact Android-only "Google Play 코드 등록" section for Free and Grace users.
3. Hide section for Standard/Premium users by default.
4. Gate guest users with login-required copy.

No entitlement changes in this phase.

### Phase P1-B. Redeem Link Service

Preferred file:

- `lib/services/promo_code_redeem_service.dart`

Responsibilities:

1. Normalize code.
2. Validate format.
3. Build Google Play redeem URI.
4. Launch external application via `url_launcher`.
5. Return a typed result:
   - `launched`
   - `invalidFormat`
   - `unsupportedPlatform`
   - `launchFailed`

Service must not store or log raw code.

### Phase P1-C. Profile Return Sync

Files:

- `lib/screens/profile_screen.dart`
- existing `lib/services/iap_service.dart` only if a public helper is needed

Tasks:

1. Add `WidgetsBindingObserver` to Profile only if needed for targeted pending-flow UI.
2. On `resumed` with `_promoRedeemPending == true`, run the local debounce decision.
3. If not debounced, call Store refresh.
4. If debounced, wait briefly and re-read local entitlement state.
5. Compare before/after `UserTier`.
6. Show success/not-yet-active copy.
7. Clear pending state.

Important: `main.dart` already refreshes IAP on global app resume. Profile's targeted refresh is for user feedback and immediate UI update, not a separate entitlement path. It must avoid 1-3 second duplicate Store queries.

### Phase P1-D. Manual Refresh Button

Files:

- `lib/screens/profile_screen.dart`

Tasks:

1. Add "구독 상태 다시 확인" after a redeem attempt.
2. Call existing IAP refresh path.
3. Disable while refreshing.
4. Show result without raw Store identifiers.

### Phase P1-E. QA and Diagnostics

Files:

- `plans/promo_code_google_play_redeem_qa_report_v1.md`

Tasks:

1. Emulator/device tap-through with wrong code.
2. Real Play test with `MOAWELCOME`.
3. Real Play test with one `moa-standard-90d-friends` one-time code.
4. App-outside redeem then app start refresh.
5. Sensitive log scan.

## 13. QA Matrix

| ID | Scenario | Expected |
| --- | --- | --- |
| PR-QA-01 | Free Android enters `MOAWELCOME` from Profile | Play redeem URL opens with code prefilled |
| PR-QA-02 | Free Android applies valid 1-month code through Profile -> Play redeem URL | App return sync grants Standard |
| PR-QA-03 | Free Android applies `MOAWELCOME` through Paywall Google Play purchase sheet -> Redeem code | Store applies code and app sync grants Standard |
| PR-QA-04 | Free Android applies valid 90-day one-time code through Profile -> Play redeem URL | App return sync grants Standard and expected expiry is visible where supported |
| PR-QA-05 | Wrong code | Google Play rejects; app return does not grant Standard |
| PR-QA-06 | Already used code | Google Play rejects; app return does not grant Standard |
| PR-QA-07 | App killed after redeem | On next startup existing IAP warmup refresh can apply entitlement |
| PR-QA-08 | Play Store launch failure | fallback copy is shown |
| PR-QA-09 | iOS | section hidden |
| PR-QA-10 | Guest | stronger login-required copy, no redeem launch until authenticated |
| PR-QA-11 | Standard user | Google Play code registration section hidden by default |
| PR-QA-12 | App-outside redeem | app startup/profile refresh applies Standard |
| PR-QA-13 | Multiple Google accounts on device | UI warns to use the same Google Play account intended for MOA subscription |
| PR-QA-14 | Resume after redeem | no duplicate Store refresh within 1-3 seconds; UI message shown once |
| PR-QA-15 | Sensitive logs | raw code/token/order/email/full uid absent |

### 13.1 Required `MOAWELCOME` Dual Path Test

The launch custom code must be tested in both paths:

A. Profile handoff path:

```text
Profile -> Google Play 코드 등록 -> play.google.com/redeem?code=MOAWELCOME -> apply -> app return -> Standard sync
```

B. Purchase sheet path:

```text
Paywall -> Standard purchase button -> Google Play purchase sheet -> Redeem code -> MOAWELCOME -> apply -> app return -> Standard sync
```

If A is unreliable but B is reliable, keep Profile copy conservative:

```text
Google Play 코드 등록 화면으로 이동합니다.
코드가 등록되지 않으면 Standard 구매 화면의 결제창에서 '코드 사용'을 선택해 입력해 주세요.
```

In that case, add a small Paywall helper copy that Google Play purchase sheet also supports code redemption. Do not implement app-side validation as a workaround.

## 14. Test Data Handling

Do not commit real one-time promo codes to the repo.

QA reports may record:

- code type: `custom_launch` or `one_time_friends`
- code length
- last 0 characters of code; preferably no partial code at all
- redemption result
- Store entitlement result

QA reports must not record the raw promo code.

## 15. Completion Criteria

P1 implementation is complete when:

- Android Free/Grace users can enter a promo code from Profile.
- Valid-format code opens Google Play redeem URL.
- UI copy says "Google Play 코드 등록" / "코드 등록하러 가기", not app-side code application.
- iOS hides this Google Play-only feature.
- Guest users cannot open redeem and are told to sign in first with the Google Play account they intend to use.
- Users are warned to confirm the Google Play account before redeeming.
- App return triggers Store entitlement refresh and Profile UI update.
- App return refresh avoids duplicate Store queries within a 1-3 second window.
- Standard is granted only through verified active Store entitlement.
- Invalid/unused/incomplete redemption does not grant Standard.
- Manual "구독 상태 다시 확인" works.
- `MOAWELCOME` passes both Profile deep link and Google Play purchase sheet redeem tests, or the plan documents which path is reliable before release.
- Raw promo code is never stored in Firestore, server logs, local prefs, app logs, or QA docs.
- No product ids, Firebase schema, Storage paths, package ids, or billing verification contracts are changed.

## 16. Risks and Controls

| Risk | Control |
| --- | --- |
| Custom code requires in-app Play Billing purchase flow rather than only external redeem | Validate with `MOAWELCOME` on a Play test account before wide release. Keep entitlement based on Store verification. |
| `purchaseStream` event not delivered after app return | Existing `refreshEntitlementsFromStore()` uses Android `queryPastPurchases()` and server verification. |
| User enters code while Guest | Block redeem launch and ask login first. |
| User redeems with the wrong Google Play account | Pre-launch copy tells the user to confirm the Google Play account matches the intended MOA subscription account. |
| Duplicate entitlement refresh on app resume | Local Profile debounce or IAPService time-window debounce. |
| Raw one-time code leaks in logs | Log only code length and result flags. Never log the full URL. |
| User expects immediate Standard before completing Play flow | Copy says Play must complete code registration first. |
| iOS parity confusion | Hide Google Play promo input on iOS; plan App Store offer codes separately. |

## 17. References

- Google Play Billing promo codes: `https://developer.android.com/google/play/billing/promo`
- Apple App Store Connect subscription offer codes: `https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/`
- Apple auto-renewable subscription offer code redemption overview: `https://developer.apple.com/app-store/subscriptions/`

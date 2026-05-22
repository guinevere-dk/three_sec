# MOA Google Play Standard Annual Launch Offer Implementation Plan v1

## 1. Scope

Source prompt:

- `plans/MOA_Google_Play_Standard_Annual_Launch_Offer_Integration_Prompt.md`

Goal:

- Google Play Console에 설정된 Standard annual launch offer를 앱에서 조회한다.
- `3s_standard_annual` annual subscription product 안의 `launch` offer tag를 가진 offer를 찾는다.
- Paywall에는 Store가 내려준 launch offer가 있을 때만 첫해 혜택 가격을 표시한다.
- Standard annual launch offer 구매 시작 시 Google Play Billing purchase param에 해당 `offerToken`을 포함한다.
- 구매 완료 후 권한 부여는 기존 Standard annual entitlement 검증 경로를 그대로 사용한다.

Non-goals:

- 새 one-time product를 만들지 않는다.
- `3s_standard_annual` product id를 변경하지 않는다.
- 월간 Standard 사용자를 연간으로 유도하는 upgrade offer를 이 작업에서 처리하지 않는다.
- Firebase Functions 검증 계약, Firestore schema, Storage path, IAP product id를 변경하지 않는다.
- iOS 구매 흐름을 launch offer용으로 변경하지 않는다.
- 가격을 하드코딩해서 표시하지 않는다.

Approval gates:

- `pubspec.yaml` / `pubspec.lock` dependency 변경은 별도 승인 후 진행한다.
- Google Play Console offer 설정, base plan/offer activation, license tester 계정 준비는 앱 코드 구현 전 운영 승인 항목이다.
- server-side purchase verification contract 변경이 필요하다고 판정되면 별도 계획과 승인이 필요하다.

## 2. Current State Summary

Current IAP contracts:

- Flutter package uses `in_app_purchase` in `pubspec.yaml`.
- `IAPService` imports Android-specific IAP APIs from `in_app_purchase_android`.
- Product ids are currently defined in `lib/services/iap_service.dart`:
  - `3s_standard_monthly`
  - `3s_standard_annual`
  - `3s_premium_monthly`
  - `3s_premium_annual`
- `functions/index.js` allows the same four product ids in `ALLOWED_IAP_PRODUCT_IDS`.
- `IAPService.purchase(productId)` currently receives only a product id.
- Android purchase param currently uses `GooglePlayPurchaseParam(productDetails: product)` and does not inject an offer token for new purchases.
- Paywall currently shows Standard monthly and annual cards only.
- Paywall price display currently uses `ProductDetails.price` when available, then static fallback prices:
  - `3s_standard_monthly`: `₩6,900`
  - `3s_standard_annual`: `₩69,000`
- Purchase completion and entitlement sync already depend on existing product id verification and Standard tier mapping.

Immediate implications:

- Creating the offer in Google Play Console is not enough. The app must select the offer from Store product details and pass its `offerToken`.
- If Paywall continues to call `purchase('3s_standard_annual')` without an offer token, eligible users may be sent to regular annual purchase rather than launch offer purchase.
- Static display of `₩59,000` is forbidden because eligibility is decided by Google Play and can differ by account.
- Static annual fallback should not be used for a buyable paid UI if Store product details are unavailable. Loading/error UI with disabled CTA is safer.

## 3. Product And Offer Contract

Keep:

- Standard annual product id: `3s_standard_annual`
- Existing entitlement tier: `standard`
- Existing purchase verification product id allowlist

Add app-side constants only:

- Launch offer tag: `launch`
- Launch offer id for diagnostics/documentation only: `standard-annual-launch-offer`

Selection rule:

- Primary selector: `subscriptionOfferDetails.offerTags.contains('launch')`.
- Do not rely on offer id unless the current Billing wrapper exposes it safely.
- Do not infer launch eligibility locally from account history.
- If Google Play does not return the launch offer, the app treats the user as ineligible or Store not ready and hides first-year benefit copy.

Pricing rule:

- `launchOfferPriceText` must come from the launch offer pricing phase formatted price.
- `basePlanPriceText` / renewal price must come from regular annual base plan pricing phase or Store product formatted price.
- No hardcoded `₩59,000`, `₩69,000`, or `₩6,900` in the launch offer display path.
- If product details are loading, show loading/skeleton and disable purchase.
- If product details fail, show retry and disable purchase.

## 4. Proposed Data Model

Add a small view model close to the IAP service or a dedicated policy file.

Suggested file:

- `lib/services/standard_annual_offer_service.dart`

Suggested models:

```dart
enum StandardAnnualOfferPurchaseMode {
  regularAnnual,
  launchOffer,
  unavailable,
}

class StandardAnnualOfferViewModel {
  final String productId;
  final String? basePlanPriceText;
  final String? launchOfferPriceText;
  final String? launchOfferToken;
  final bool hasLaunchOffer;
  final bool canPurchase;
  final StandardAnnualOfferPurchaseMode purchaseMode;
  final String? diagnosticReason;

  const StandardAnnualOfferViewModel({
    required this.productId,
    required this.basePlanPriceText,
    required this.launchOfferPriceText,
    required this.launchOfferToken,
    required this.hasLaunchOffer,
    required this.canPurchase,
    required this.purchaseMode,
    required this.diagnosticReason,
  });
}
```

Rules:

- `hasLaunchOffer == true` requires a non-empty launch offer token and launch offer formatted price.
- `purchaseMode == launchOffer` requires `launchOfferToken != null`.
- `purchaseMode == regularAnnual` must not show first-year launch offer copy.
- `purchaseMode == unavailable` disables purchase CTA.

## 5. Implementation Phases

### Phase A. Billing API Inventory

Status:

- Completed in `plans/moa_google_play_standard_annual_launch_offer_phase_a_inventory_report_v1.md`.
- No code, dependency, lockfile, Firebase, or Store contract changes were made in Phase A.

Files to inspect:

- `pubspec.yaml`
- `lib/services/iap_service.dart`
- local package API for `in_app_purchase_android`

Tasks:

1. Confirm the installed `in_app_purchase_android` API names for:
   - `GooglePlayProductDetails`
   - `subscriptionOfferDetails`
   - offer tags
   - pricing phases
   - `GooglePlayPurchaseParam.offerToken`
2. Confirm whether `in_app_purchase_android` must be added as a direct dependency to remove analyzer dependency warnings.
3. Confirm how regular annual base plan token is represented by the package.
4. Document whether regular annual purchase on Android needs an offer/base-plan token as well.

Acceptance:

- Implementation uses package APIs that match the current dependency version.
- No dependency or lockfile change is made unless separately approved.

### Phase B. Offer Extraction Service

Status:

- Completed in code via `lib/services/standard_annual_offer_service.dart`.
- Covered by `test/standard_annual_offer_service_test.dart`.
- Phase B does not start purchases or change Paywall behavior yet.

Files:

- Add `lib/services/standard_annual_offer_service.dart`
- Add `test/standard_annual_offer_service_test.dart`

Tasks:

1. Build a pure extraction layer that accepts normalized Store product/offer data.
2. Add an adapter from current `ProductDetails` / `GooglePlayProductDetails` to the normalized model.
3. Select launch offer by `offerTags.contains('launch')`.
4. Extract:
   - launch offer token
   - launch first pricing phase formatted price
   - annual regular/base plan formatted price
5. Return `unavailable` if product details are missing or malformed.
6. Return `regularAnnual` if the product is available but no launch offer is returned.

Important:

- Keep most logic testable without constructing plugin platform classes directly.
- Do not log raw offer token. Log only `launchOfferTokenExists=true/false`.

Acceptance:

- Launch offer present: model has `hasLaunchOffer=true`, launch price, renewal/base price, token.
- Launch offer absent: model has `hasLaunchOffer=false`, no launch price, no launch token.
- Missing token: launch purchase is unavailable even if price/tag exists.
- Non-Android: annual product can still produce regular annual display; launch offer stays absent.

### Phase C. IAP Purchase API Extension

Status:

- Completed in `lib/services/iap_service.dart`.
- Added `IAPPurchaseIntent` guard/normalization coverage in `test/iap_purchase_intent_test.dart`.
- Purchase callers remain backward compatible because `offerToken`, `requireOfferToken`, and `purchaseContext` are optional named parameters.

Files:

- Update `lib/services/iap_service.dart`
- Extend tests around IAP purchase param construction if an existing test seam is available.

Tasks:

1. Extend purchase call to accept optional purchase intent:
   - product id
   - optional offer token
   - purchase mode
2. For Android Standard annual launch offer:
   - require non-empty offer token
   - build `GooglePlayPurchaseParam` with the selected launch offer token
3. For Android regular annual:
   - use regular/base plan token if required by current package API
   - otherwise preserve existing regular purchase behavior
4. For iOS:
   - ignore launch offer token and keep existing purchase flow
5. Preserve existing plan change/downgrade behavior.
6. Do not automatically fall back from launch offer purchase failure to regular annual purchase without explicit user action.

Suggested API direction:

```dart
Future<bool> purchase(
  String productId, {
  String? offerToken,
  bool requireOfferToken = false,
  String purchaseContext = 'regular',
})
```

Launch offer guard:

```dart
if (requireOfferToken && (offerToken == null || offerToken.isEmpty)) {
  return false;
}
```

Acceptance:

- Annual launch CTA calls purchase with `requireOfferToken=true`.
- If offer token is absent, launch purchase does not start.
- Logs include product id, purchase context, token existence boolean, but never the token value.
- Existing monthly purchase path remains unchanged.
- Existing Standard annual entitlement mapping remains unchanged.

### Phase D. Paywall View Model Integration

Status:

- Completed in `lib/screens/paywall_screen.dart`.
- Paywall now builds annual price/copy from `StandardAnnualOfferViewModel`.
- Launch annual purchase calls `IAPService.purchase` with `requireOfferToken=true`.
- Static paid price fallback was removed from Paywall buyable UI.

Files:

- Update `lib/screens/paywall_screen.dart`
- Optional: add widget tests if current Paywall has stable test seams.

Tasks:

1. Build monthly and annual UI from Store-backed view models.
2. Replace annual card price with:
   - Launch offer exists: `첫해 {launchOfferPriceText}` plus `이후 {basePlanPriceText}/년`
   - Launch offer absent: `{basePlanPriceText}/년`
3. Hide launch offer copy when `hasLaunchOffer=false`.
4. Disable CTA while product details are loading or missing.
5. Replace static paid price fallback with loading/error/retry for buyable UI.
6. When annual card with launch offer is selected, call IAP purchase with launch offer token.
7. When annual card has no launch offer, call regular annual purchase path.

UX copy:

- Launch offer present:
  - `Standard 연간`
  - `첫해 {launchOfferPriceText}`
  - `이후 {basePlanPriceText}/년`
  - `출시 기념 첫해 혜택`
- Launch offer absent:
  - `Standard 연간`
  - `{basePlanPriceText}/년`
- Product loading:
  - `가격 정보를 불러오는 중...`
  - CTA disabled
- Product error:
  - `가격 정보를 불러오지 못했습니다. 다시 시도해주세요.`
  - Retry button

Acceptance:

- First-year launch offer copy appears only when Store returns the launch offer.
- Annual purchase button does not start a launch purchase without a launch offer token.
- Monthly card remains based on monthly product details.
- Premium product ids remain hidden from Paywall purchase UI.

### Phase E. Verification And Entitlement Safety

Status:

- Completed in `lib/services/iap_service.dart` and `lib/screens/paywall_screen.dart`.
- Documented in `plans/moa_google_play_standard_annual_launch_offer_phase_e_entitlement_safety_report_v1.md`.
- No Firebase Functions verification contract change was required because launch-offer purchases still verify as `3s_standard_annual`.

Files:

- `lib/services/iap_service.dart`
- `functions/index.js` only if investigation proves current verification rejects valid launch-offer purchases.

Tasks:

1. Confirm purchase result still uses `productId == 3s_standard_annual`.
2. Confirm server verification accepts `3s_standard_annual` regardless of launch offer.
3. Confirm entitlement sync maps launch purchase to Standard, not a separate tier.
4. Confirm renewal after first year remains Standard annual entitlement.

Expected:

- No server change should be necessary because the product id remains `3s_standard_annual`.
- If Google verification payload exposes base plan/offer id and existing server code ignores it, keep ignoring it for entitlement.
- If server code validates fields that would reject launch offer, stop and create a separate backend plan.

Acceptance:

- Launch offer purchase grants Standard.
- Restore purchase grants Standard.
- Renewal does not downgrade or create a separate tier.
- Premium dormant compatibility remains unchanged.

### Phase F. Logging And Diagnostics

Status:

- Completed in `lib/services/standard_annual_offer_service.dart` and `lib/screens/paywall_screen.dart`.
- Documented in `plans/moa_google_play_standard_annual_launch_offer_phase_f_logging_diagnostics_report_v1.md`.
- Logs expose only counts, booleans, product ids, purchase context, purchase mode, and diagnostic reason. Raw offer tokens and purchase tokens are not logged.

Files:

- `lib/services/iap_service.dart`
- `lib/screens/paywall_screen.dart`

Required logs:

- queried product ids
- annual product found/not found
- Android offer details count
- launch tag offer found true/false
- selected offer token exists true/false
- displayed annual base price available true/false
- displayed launch price available true/false
- purchase started with launch offer true/false

Forbidden logs:

- purchase token
- offer token value
- raw user id
- payment token
- server verification token payload

Acceptance:

- Logs are useful for QA but do not expose sensitive purchase credentials.

## 6. Test Plan

### Unit Tests

Add tests for offer extraction:

- annual product with `launch` tag returns launch offer view model.
- annual product without `launch` tag returns regular annual view model.
- launch offer with missing token returns unavailable for launch purchase.
- launch price and base plan renewal price are separated.
- unknown offer tags are ignored.
- product details missing returns unavailable.
- static price fallback is not used for launch offer UI.

Add tests for purchase guard if feasible:

- launch annual purchase requires offer token.
- regular annual purchase does not use launch offer token.
- Android purchase param receives token only for launch purchase.
- iOS purchase flow ignores Android token and preserves existing behavior.

### Widget Tests

Paywall tests:

- Launch offer present: annual card shows `첫해 {price}` and `이후 {price}/년`.
- Launch offer absent: annual card shows only regular annual price.
- Product loading: CTA disabled.
- Product error: retry shown and CTA disabled.
- Monthly card still shows monthly Store price.

### Manual QA

Google Play license tester scenarios:

1. Fresh tester account enters Paywall.
2. Standard annual card shows first-year launch offer only if Google Play returns it.
3. Google Play purchase sheet shows the same first-year price as Paywall.
4. Complete purchase and verify Standard entitlement.
5. Relaunch app and verify entitlement persists.
6. Re-enter Paywall with same account and verify launch eligibility behavior.
7. Existing monthly subscriber account does not see new-customer launch offer.
8. Logs show token existence but not token value.
9. iOS purchase path still works or remains unchanged in sandbox.

## 7. Rollout Plan

### Dev Complete

Required:

- Offer extraction unit tests pass.
- IAP purchase guard tests pass where test seams allow.
- Paywall widget tests pass.
- `flutter test` passes.
- `flutter analyze --no-fatal-infos` has no new errors.
- No Firebase deploy.
- No product id change.
- No server verification contract change unless separately approved.

### Internal QA Ready

Required:

- Google Play Console launch offer is active for `3s_standard_annual`.
- Offer tag is exactly `launch`.
- License tester fresh account receives offer in purchase sheet.
- Ineligible account does not see launch offer copy.
- Paywall price matches Google Play purchase sheet.
- Purchase grants existing Standard entitlement.

### Release Ready

Required:

- Internal track QA passed on Android.
- iOS regression smoke test passed.
- Store product details pricing copy reviewed.
- Support copy reviewed for first-year pricing and renewal pricing.
- Rollback plan documented.

## 8. Rollback Plan

Fast rollback:

- Hide launch offer UI by feature flag or code path guard.
- Fall back to regular annual Store product display only.
- Keep existing Standard annual product id and entitlement logic.

Operational rollback:

- Disable or deactivate the launch offer in Google Play Console if purchase sheet pricing is wrong.
- Ship app hotfix that ignores launch offer details and uses regular annual path.

Data rollback:

- No data migration is planned.
- No entitlement schema change is planned.
- Existing purchases remain valid Standard annual subscriptions.

## 9. Risks And Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Offer exists in Console but not returned by Store | Paywall does not show launch price | Treat as regular annual; no first-year copy |
| Offer token omitted during purchase | User may buy regular annual | Launch CTA requires non-empty token |
| Paywall price differs from purchase sheet | User trust issue | Use Store formatted prices only and QA purchase sheet |
| Existing monthly user sees new-customer offer | Incorrect promotion UX | Do not infer eligibility locally; only display Store-returned offer |
| Android API shape differs by package version | Build failure | Phase A API inventory before implementation |
| Server verification rejects launch offer purchase | Purchase entitlement failure | Verify product id contract before release; backend change requires separate plan |
| Static fallback price shown to ineligible user | Misleading pricing | Disable paid CTA until Store details are loaded |

## 10. Completion Criteria

- `3s_standard_annual` product details are queried successfully.
- Android annual product offer details are parsed.
- `launch` offer tag is detected when Google Play returns it.
- Launch offer price and regular renewal price are displayed separately.
- Launch offer purchase includes the selected offer token.
- Launch offer purchase is never started without an offer token.
- Launch offer absent path shows regular annual only.
- All displayed paid prices come from Store product details.
- Purchase completion grants existing Standard entitlement.
- iOS path is unchanged or verified not to regress.
- Logs omit raw offer token and purchase token.

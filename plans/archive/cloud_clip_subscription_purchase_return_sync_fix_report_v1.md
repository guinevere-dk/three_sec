# Cloud Clip Subscription Purchase Return Sync Fix Report v1

## Summary

Implemented a focused subscription state sync fix for the case where a user purchases Standard and returns to Subscription Management.

The expected behavior is now:

- purchase completion is not treated as successful until local tier sync is observed,
- Paywall triggers a store entitlement refresh if the purchase stream event arrives before local tier has updated,
- Subscription Management runs store entitlement refresh immediately on screen init, app resume, and return from Paywall,
- local/Profile state can update to Standard without requiring a separate manual navigation step.

## Changed Files

- `lib/screens/paywall_screen.dart`
- `lib/screens/subscription_management_screen.dart`
- `plans/cloud_clip_subscription_purchase_return_sync_fix_report_v1.md`

## Implementation Details

### Paywall Purchase Completion

`PaywallScreen._handlePurchaseCompleted(...)` now:

1. waits for local tier sync,
2. if not synced, calls:

   ```dart
   IAPService().refreshEntitlementsFromStore(reason: 'return_from_paywall')
   ```

3. waits for local tier sync again,
4. only shows success and pops when the target tier/product is actually reflected locally,
5. otherwise leaves the user on Paywall and shows a "still confirming" message.

This prevents a false-success flow where the UI returns to Subscription Management while local tier is still Free.

### Subscription Management Return / Resume

`SubscriptionManagementScreen._refreshSubscriptionState(...)` now runs:

```dart
_iapService.refreshEntitlementsFromStore(reason: reason)
```

before cancellation sync, local cache reload, and Firestore reconciliation.

This makes `return_from_paywall` and `app_resumed` perform the same store entitlement recovery used at app startup.

## Expected Runtime Markers

On successful purchase return:

- `trigger=return_from_paywall source=store_query ... reason_code=verification_active`
- `trigger=return_from_paywall source=server_verify ... reason_code=verification_active`
- Subscription Management build marker should move from `free` to `standard`

If the purchase is still pending or verification is delayed:

- Paywall does not pop as a confirmed success.
- User sees a confirmation-in-progress message.
- Subscription Management can still recover on app resume or re-entry through store entitlement refresh.

## Restrictions Observed

- No purchase state was changed directly.
- No Firestore rules/index/schema change.
- No deploy.
- No raw uid/email/token/order id/provider/purchase token logging added.
- No folder count logic changed.
- No MMQA-03 grace logic changed.

## Validation

### Format

PASS

```powershell
dart format lib\screens\subscription_management_screen.dart lib\screens\paywall_screen.dart
```

### Tests

PASS, 11 tests.

```powershell
flutter test test\user_status_manager_r3_test.dart test\auth_service_qa_subscription_lock_test.dart
```

### Debug Build

PASS

```powershell
flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true
```

### Analyzer

NON-BLOCKING FAIL due existing `avoid_print` diagnostics in `SubscriptionManagementScreen`.

```powershell
flutter analyze lib\screens\subscription_management_screen.dart lib\screens\paywall_screen.dart
```

Result:

- 6 info-level `avoid_print` issues in `lib/screens/subscription_management_screen.dart`.
- No compile-stopping error from this change.

## Runtime Verification Needed

Recommended next runtime check:

1. Use a normal debug build without `R3_QA_SUBSCRIPTION_LOCK=true`.
2. Keep signed-in QA account.
3. Open Profile -> Subscription Management -> Paywall.
4. Purchase Standard.
5. Confirm return path markers:
   - `source=store_query reason_code=verification_active`
   - `source=server_verify reason_code=verification_active`
6. Confirm Subscription Management/Profile shows Standard immediately after return.
7. Confirm app-controlled sensitive log gate remains PASS.

## Verdict

Implementation Verdict: PASS

Runtime purchase-return verification is still required.

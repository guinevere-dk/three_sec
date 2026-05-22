# Cloud Clip Subscription Entitlement Refresh Instrumentation Report v1

## Summary

Implemented raw-safe `[EntitlementRefresh]` instrumentation for the subscription entitlement investigation plan.

The marker records only count/status fields and tier transitions. It does not log raw uid, email, token, order id, provider, purchase token, local path, Storage path, or filename.

## Changed Files

- `lib/main.dart`
- `lib/screens/profile_screen.dart`
- `lib/screens/subscription_management_screen.dart`
- `lib/services/iap_service.dart`
- `lib/services/auth_service.dart`
- `plans/cloud_clip_subscription_entitlement_refresh_instrumentation_report_v1.md`

## Instrumented Flows

### App Startup

`lib/main.dart`

- Logs `source=local_cache` around `UserStatusManager.initialize()`.
- Logs `source=expiry_eval` around `evaluateAndAutoDowngradeIfExpired(reason: startup_warmup)`.
- Existing `IAPService.refreshEntitlementsFromStore(reason: startup_warmup)` now logs store/server entitlement markers.

### App Resume

`lib/main.dart` already calls `IAPService.refreshEntitlementsFromStore(reason: app_resumed)`.

`lib/services/iap_service.dart` now emits `[EntitlementRefresh]` for that path with:

- `source=store_query`
- `source=server_verify` when a verified active purchase is applied
- candidate and verification counters

### Profile Initialization / Refresh

`lib/screens/profile_screen.dart`

- Logs `trigger=profile_init source=local_cache`.
- Logs `trigger=profile_init source=expiry_eval`.
- Logs `trigger=profile_refresh source=local_cache`.
- Logs `trigger=profile_refresh source=expiry_eval`.

Profile still does not force a store or Firestore entitlement refresh in this change.

### Subscription Management

`lib/screens/subscription_management_screen.dart`

- Logs local cache reload after cancellation-store sync.
- Existing calls to `IAPService.syncCancellationStateFromStore(...)` and `AuthService.syncCurrentUserSubscriptionFromFirestore(...)` now produce raw-safe entitlement markers.

### Firestore Entitlement Cache

`lib/services/auth_service.dart`

- `syncCurrentUserSubscriptionFromFirestore(...)` now passes its refresh reason into the internal Firestore sync.
- Firestore sync emits `source=firestore_cache` markers for:
  - missing/invalid Firestore payload preserved
  - Firestore free applied
  - local grace preserved
  - local paid tier preserved
  - Firestore paid applied
  - expired downgrade after Firestore sync
  - sync failure

### Store / Server Verification

`lib/services/iap_service.dart`

- `refreshEntitlementsFromStore(...)` logs store query before/after tier and counters.
- `_retryRestoreVerificationFromStore(...)` now returns count-only stats:
  - `candidate_count`
  - `verified_active_count`
  - `verified_inactive_count`
  - `verification_failed_count`
- `_applyActiveSubscriptionToUserStatus(...)` logs `source=server_verify` when verified active entitlement is applied.
- `syncCancellationStateFromStore(...)` logs raw-safe store query results for management screen entry/resume paths.

## Raw-Safe Fields

All new `[EntitlementRefresh]` markers use only:

- `trigger`
- `source`
- `before_tier`
- `after_tier`
- `result`
- `reason_code`
- `candidate_count`
- `verified_active_count`
- `verified_inactive_count`
- `verification_failed_count`
- `duration_ms`

## Redaction Follow-Up Included

While validating the new markers, existing IAP logs were found to print order-id-like values in the same entitlement path. To keep this investigation usable under the strict sensitive log gate:

- `_safePurchaseOrderId(...)` now returns `<redacted-order-id>` instead of raw order/purchase/transaction identifiers.
- verification log keys use `_logSafePurchaseVerificationKey(...)`, which redacts the order-id component.
- verification payloads are not changed; only log output is redacted.

## Validation

### Format

PASS

Command:

```powershell
dart format lib\main.dart lib\screens\profile_screen.dart lib\screens\subscription_management_screen.dart lib\services\iap_service.dart lib\services\auth_service.dart
```

### Tests

PASS, 28 tests.

Command:

```powershell
flutter test test\user_status_manager_r3_test.dart test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

### Diff Check

PASS

Command:

```powershell
git diff --check -- lib\main.dart lib\screens\profile_screen.dart lib\screens\subscription_management_screen.dart lib\services\iap_service.dart lib\services\auth_service.dart
```

### Analyzer

NON-BLOCKING FAIL due existing analyzer debt in the targeted files.

Command:

```powershell
flutter analyze lib\main.dart lib\screens\profile_screen.dart lib\screens\subscription_management_screen.dart lib\services\iap_service.dart lib\services\auth_service.dart
```

Result:

- No new compile-stopping error was reported.
- Analyzer still reports existing warnings/infos, mainly `avoid_print`, unused imports in `main.dart`, referenced-package lints in `iap_service.dart`, and pre-existing style/deprecation issues.

## Runtime Use

For the next runtime investigation, filter logcat by:

```text
[EntitlementRefresh]
```

Expected interpretation:

- `trigger=startup_warmup source=local_cache` shows launch local state load.
- `trigger=startup_warmup source=store_query` shows whether Google Play candidates were found on launch.
- `source=server_verify reason_code=verification_active` shows a verified active entitlement applying Standard/Premium.
- `source=firestore_cache reason_code=firestore_paid` shows Firestore restoring paid state.
- `source=firestore_cache reason_code=local_grace_preserved` shows QA grace preserved.
- `source=store_query/server_verify after_tier=standard` after injected grace indicates the store/server path overwrote the QA fixture.

## Restrictions Observed

- No purchase/subscription state was changed intentionally.
- No Firebase rules/index/schema changes.
- No deploy.
- No MMQA-03 retry.
- No raw uid/email/token/order id/provider/purchase token was added to the new entitlement markers.

## Next Step

Run a raw-safe runtime capture across:

1. cold launch,
2. Profile open,
3. Subscription Management entry/return,
4. injected grace launch and management navigation.

Then document the root cause in `plans/cloud_clip_subscription_entitlement_refresh_root_cause_v1.md`.

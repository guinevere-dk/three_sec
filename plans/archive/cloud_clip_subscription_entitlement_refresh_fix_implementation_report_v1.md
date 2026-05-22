# Cloud Clip Subscription Entitlement Refresh Fix Implementation Report v1

## Summary

Implemented Phase 1~2 launch/Profile Firestore entitlement reconciliation.

The fix reduces the previous asymmetry where Firestore paid entitlement was applied only after entering Subscription Management. Signed-in active paid users whose local cache is Free/stale can now recover Standard/Premium entitlement from Firestore during startup and Profile init/refresh.

Debug-only QA entitlement lock was not implemented. MMQA-03 grace tests must use the selected strategy: do not enter Subscription Management and assert tier immediately before action.

## Changed Files

- `lib/services/auth_service.dart`
- `lib/main.dart`
- `lib/screens/profile_screen.dart`
- `plans/cloud_clip_subscription_entitlement_refresh_fix_implementation_report_v1.md`

## Implementation Details

### Entitlement Reconciliation Entry Point

Added `AuthService.reconcileCurrentUserEntitlement({required String reason})`.

Behavior:

- Skips guest or non-authenticated sessions.
- Calls `syncCurrentUserSubscriptionFromFirestore(...)`.
- Uses `preserveLocalPaidTier: true`.
- Reloads `UserStatusManager` after sync.
- Keeps existing raw-safe `[EntitlementRefresh] source=firestore_cache` markers.

No purchase state is changed directly.

### Startup Integration

`_warmUpStartupServices()` now runs Firestore entitlement reconciliation after:

1. local cache load,
2. expiry evaluation,
3. IAP initialization,
4. store entitlement refresh.

This keeps store/server verification ahead of Firestore cache reconciliation.

### Profile Integration

Profile initialization and manual refresh now run Firestore entitlement reconciliation after:

1. local cache reload,
2. expiry evaluation,
3. optional local auto-downgrade sync.

After reconciliation, Profile reloads `UserStatusManager` before loading Cloud stats and rendering updated tier state.

### Subscription Management

No behavior change.

Existing Subscription Management refresh remains intact.

## Expected Runtime Markers

Local Free/stale + Firestore paid:

- `trigger=startup_warmup source=firestore_cache before_tier=free after_tier=standard result=applied reason_code=firestore_paid`
- or `trigger=profile_init/profile_refresh source=firestore_cache before_tier=free after_tier=standard result=applied reason_code=firestore_paid`

Firestore Free + local paid:

- `source=firestore_cache result=preserved reason_code=local_paid_preserved`

Local grace + Firestore Free:

- `source=firestore_cache result=preserved reason_code=local_grace_preserved`

## QA Grace Strategy

Implemented strategy:

- No debug-only entitlement lock.
- MMQA-03 must not navigate to Subscription Management.
- MMQA-03 must assert intended tier immediately before upload action.
- If any marker shows Firestore paid overwrite before the action, mark the scenario BLOCKED and recreate/adjust fixture.

Note:

- Because production launch/Profile reconciliation is now active, a paid QA account with Firestore paid state can overwrite injected grace during launch/Profile as designed. This is controlled by the pre-action assertion strategy, not by a runtime lock.

## Validation

### Format

PASS

Command:

```powershell
dart format lib\main.dart lib\screens\profile_screen.dart lib\services\auth_service.dart
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
git diff --check -- lib\main.dart lib\screens\profile_screen.dart lib\services\auth_service.dart
```

### Analyzer

NON-BLOCKING FAIL due existing analyzer debt.

Command:

```powershell
flutter analyze lib\main.dart lib\screens\profile_screen.dart lib\services\auth_service.dart
```

Result:

- No compile-stopping errors from this change.
- Existing warnings/infos remain, including unused imports in `main.dart`, `avoid_print`, existing style lints, and deprecated API warnings.

## Restrictions Observed

- No debug-only QA entitlement lock.
- No purchase/subscription state mutation.
- No Firebase rules/index/schema change.
- No deploy.
- No raw uid/email/token/order id/provider/purchase token added.
- No unrelated cleanup.

## Follow-Up Runtime QA

Recommended next runtime checks:

1. Inject local Free/stale with active paid Firestore state.
2. Cold launch.
3. Confirm `startup_warmup source=firestore_cache before_tier=free after_tier=standard reason_code=firestore_paid`.
4. Repeat via Profile init/refresh.
5. Confirm Subscription Management is no longer the first path that restores paid entitlement.
6. For MMQA-03, assert grace/free immediately before upload and mark BLOCKED if Firestore paid overwrite appears.

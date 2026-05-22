# Cloud Clip R3 QA Subscription Lock Implementation Report v1

## Summary

Implemented the debug-only R3 QA subscription lock described in `plans/cloud_clip_r3_qa_subscription_lock_plan_v1.md`.

The lock protects MMQA-03 local injected expired-within-grace fixtures from being overwritten by Firestore paid entitlement reconciliation during the controlled action window.

Production entitlement refresh remains active:

- lock defaults to false,
- release builds force the lock off with `kReleaseMode`,
- Firestore paid still restores Standard/Premium when the lock is off,
- Firestore paid still restores Standard/Premium when the lock is on but no local grace history exists,
- store/server verification precedence is not changed.

## Changed Files

- `lib/services/auth_service.dart`
- `test/auth_service_qa_subscription_lock_test.dart`
- `plans/cloud_clip_r3_qa_subscription_lock_implementation_report_v1.md`

## Implementation Details

### Dart Define

Added:

```dart
static const bool r3QaSubscriptionLockRequested = bool.fromEnvironment(
  'R3_QA_SUBSCRIPTION_LOCK',
  defaultValue: false,
);
```

Runtime enabled predicate:

```dart
!kReleaseMode && r3QaSubscriptionLockRequested
```

This keeps the lock unavailable in release builds even if the dart-define is accidentally supplied.

### Guard Helper

Added `AuthService.shouldSkipFirestorePaidForQaLock(...)`.

The helper returns true only when all conditions are true:

- QA lock requested,
- build is not release,
- signed-in user,
- local tier is Free,
- local grace history is present,
- Firestore candidate tier is Standard or Premium.

The helper is pure and `@visibleForTesting`.

### Firestore Sync Integration

The guard runs immediately before Firestore paid state is applied to local state.

If the guard returns true:

- local Free/grace state is preserved,
- Firestore paid apply is skipped,
- no Firestore user profile write is added,
- `[EntitlementRefresh]` marker is emitted:

```text
source=firestore_cache before_tier=free after_tier=free result=skipped reason_code=qa_lock_applied
```

The existing Firestore paid apply path is unchanged when the guard is false.

## Safety Properties

Preserved:

- production launch/Profile entitlement recovery,
- Subscription Management refresh behavior,
- store/server verification precedence,
- Firestore Free downgrade guard behavior,
- local paid preservation behavior,
- local grace preservation behavior.

Not changed:

- purchase state,
- Firestore user profile schema or data contract,
- Firebase rules/index/schema,
- Storage behavior,
- release build entitlement behavior.

## Tests

Added `test/auth_service_qa_subscription_lock_test.dart`.

Covered cases:

- lock off: Firestore paid restore is not skipped,
- lock on + local grace: Firestore paid overwrite is skipped,
- lock on without grace history: Firestore paid restore is not skipped,
- release guard: lock is forced disabled,
- Firestore Free candidate is not affected,
- signed-in user requirement is enforced.

## Validation

### Format

PASS

```powershell
dart format lib\services\auth_service.dart test\auth_service_qa_subscription_lock_test.dart
```

### Tests

PASS, 34 tests.

```powershell
flutter test test\auth_service_qa_subscription_lock_test.dart test\user_status_manager_r3_test.dart test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart
```

### Debug Build

PASS

```powershell
flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true --dart-define=R3_QA_SUBSCRIPTION_LOCK=true
```

### Analyzer

NON-BLOCKING FAIL due existing analyzer debt in `lib/services/auth_service.dart`.

```powershell
flutter analyze lib\services\auth_service.dart test\auth_service_qa_subscription_lock_test.dart
```

Result:

- 153 info-level issues.
- Existing categories include `avoid_print`, `prefer_conditional_assignment`, and deprecated `updateEmail`.
- No compile-stopping error from the QA lock implementation.

## Raw-Safe Logging

The QA lock uses the existing `[EntitlementRefresh]` status/count marker shape.

No raw uid, email, token, order id, provider, or purchase token output was added.

## Runtime Verification Plan

Recommended next runtime check:

1. Build/run debug with `R3_QA_SUBSCRIPTION_LOCK=true`.
2. Inject expired-within-grace local state.
3. Keep Firestore paid state unchanged.
4. Cold launch.
5. Confirm:
   - `source=firestore_cache`
   - `before_tier=free`
   - `after_tier=free`
   - `result=skipped`
   - `reason_code=qa_lock_applied`
6. Confirm MMQA-03 upload action remains in grace/free state before tap.
7. Confirm raw-sensitive app log gate remains PASS.

Control check:

1. Build/run without `R3_QA_SUBSCRIPTION_LOCK=true`.
2. Inject local Free/stale without grace history.
3. Confirm Firestore paid still restores Standard.

## Restrictions Observed

- No purchase state change.
- No Firestore user profile write behavior added.
- No Firebase rules/index/schema change.
- No deploy.
- No raw uid/email/token/order id/provider/purchase token added.
- Production entitlement refresh fix was not removed.
- No unrelated cleanup.

## Verdict

Implementation Verdict: PASS

Runtime MMQA-03 lock verification is ready.

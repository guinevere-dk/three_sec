# Cloud Clip Subscription State Refresh On Launch Issue v1

## Summary

During MMQA-03 setup, the emulator app launched with local `UserTier.free` even though the signed-in QA account is expected to have an active Standard subscription.

After the user opened Profile > subscription management and returned, the app state refreshed to Standard and the Library Cloud upload button appeared.

This suggests a subscription entitlement refresh gap on normal app launch/profile initialization.

## Observed Behavior

Observed on 2026-05-20:

1. App was launched after local SharedPreferences state injection for MMQA-03.
2. Profile showed Free.
3. App logs loaded:
   - `tier=UserTier.free`
   - preserved Standard product history
4. Cloud read metadata pull still ran because local grace history existed.
5. User entered subscription management and returned.
6. Profile/Library state refreshed to Standard.
7. Cloud upload button reappeared.

Raw uid/email/token/path values are intentionally not recorded in this document.

## Expected Behavior

For a signed-in active Standard account:

- app launch should refresh or reconcile entitlement state without requiring manual subscription management navigation.
- Profile should not remain Free if the active entitlement can be restored from store/server state.
- Library Cloud upload button visibility should be consistent with the resolved entitlement state.

For a deliberately injected grace QA state:

- QA needs a way to keep the local grace fixture stable, or to clearly detect when store/server entitlement refresh has overridden it.

## Impact

MMQA-03 / R3-MQA-03 Grace upload blocked runtime QA was invalidated:

- initial state was local free/grace
- user navigation caused state to become active Standard
- upload action then ran under active Standard, not grace
- the observed upload path cannot prove grace upload blocking

User-visible risk:

- active subscribers may see Free until entering subscription management.
- Cloud upload UI may be hidden until manual subscription refresh/navigation.

QA risk:

- subscription-state tests can be invalidated mid-run if store/server refresh happens through UI navigation.
- result documents must record whether the action window was still in the intended subscription state.

## Evidence

Count/status-only evidence:

- startup state: Free with Standard product history
- post-subscription-management state: Standard
- upload action window included `can_start_new_cloud_write=true`
- upload path proceeded instead of write-gate blocking

No Firebase rules/index/schema change, migration/backfill, deploy, Storage delete, or Cloud copy was performed.

## Suspected Areas

Candidate code areas for later investigation:

- `AuthService` sign-in/profile subscription sync
- `IAPService` restore/query current purchase flow
- Profile subscription management refresh path
- app startup ordering between `UserStatusManager.initialize()`, Firebase user profile sync, and store entitlement refresh
- local SharedPreferences vs Firestore/store entitlement precedence

## Required Follow-Up

Create a separate implementation plan before code changes.

Recommended checks:

1. Identify the code path that runs when entering subscription management.
2. Compare it with normal app launch/profile initialization.
3. Confirm whether active purchase restore/query is skipped on launch.
4. Define source-of-truth precedence for:
   - local SharedPreferences
   - Firestore user profile
   - Google Play purchase state
   - server verification result
5. Add a raw-safe diagnostic marker that records entitlement refresh source and result without uid/email/token/order id/provider values.

## Verdict

Issue recorded for later work.

Do not fix as part of MMQA-03. This should be handled in a dedicated subscription entitlement refresh task.

# Cloud Clip Subscription Entitlement Refresh Investigation Plan v1

## 1. Purpose

This document defines the investigation plan for the subscription entitlement refresh gap recorded in `plans/cloud_clip_subscription_state_refresh_on_launch_issue_v1.md`.

Observed behavior:

- A signed-in QA account expected to be active Standard appeared as Free after app launch.
- Entering Profile > subscription management and returning refreshed the app state to Standard.
- MMQA-03 grace upload-block QA was invalidated because the intended grace fixture became active Standard before the upload action window.

No code change is included in this phase.

## 2. Scope

In scope:

- App startup subscription initialization flow.
- Profile initialization and manual refresh flow.
- Subscription management screen refresh flow.
- `SharedPreferences`, Firestore user profile, Google Play purchase state, and server verification precedence.
- Raw-safe diagnostics design for future implementation.

Out of scope:

- Changing purchase state.
- Changing Firebase rules, indexes, or schemas.
- Deploying Firebase resources.
- Adding production code in this investigation step.
- Logging raw uid, email, token, order id, provider, local path, Storage path, or filename.

## 3. Current Evidence From Code

### App Startup

`lib/main.dart` startup warmup currently performs this sequence:

1. `UserStatusManager().initialize()`
2. `evaluateAndAutoDowngradeIfExpired(reason: 'startup_warmup')`
3. `AuthService().syncFreeTierToFirestore(...)` only if local auto-downgrade occurred
4. `IAPService().initialize()`
5. `IAPService().refreshEntitlementsFromStore(reason: 'startup_warmup')`

The app also calls `IAPService().refreshEntitlementsFromStore(reason: 'app_resumed')` on lifecycle resume.

Investigation question: startup has a store refresh hook, but the runtime symptom suggests one of the following:

- refresh is skipped because IAP is not initialized/available yet,
- `queryPastPurchases()` does not return an active candidate during launch,
- server verification does not apply the entitlement during launch,
- a later Firestore/local initialization overwrites the restored tier,
- Profile renders before the asynchronous entitlement refresh has completed and does not subscribe to the later result,
- the QA injected free/grace state is intentionally overwritten by store/server refresh, but only after a management route triggers the needed sequence.

### Profile Initialization

`lib/screens/profile_screen.dart` profile initialization and refresh perform:

1. `UserStatusManager.initialize()`
2. `evaluateAndAutoDowngradeIfExpired(...)`
3. `AuthService.syncFreeTierToFirestore(...)` only if local auto-downgrade occurred
4. cloud stats refresh if Cloud read is allowed

Profile initialization does not appear to directly call `IAPService.refreshEntitlementsFromStore()` or `AuthService.syncCurrentUserSubscriptionFromFirestore(...)`.

Investigation question: Profile may re-read the local cache but not force the same store/server or Firestore entitlement reconciliation that subscription management runs.

### Subscription Management

`lib/screens/subscription_management_screen.dart` runs `_refreshSubscriptionState(...)` on:

- screen init,
- app resume while the screen is active,
- return from paywall,
- return from Play cancellation flow.

The refresh sequence is:

1. `IAPService.syncCancellationStateFromStore(reason: ...)`
2. `UserStatusManager.initialize()`
3. if authenticated: `AuthService.syncCurrentUserSubscriptionFromFirestore(preserveLocalPaidTier: true, reason: ...)`
4. `UserStatusManager.initialize()` again

This differs from Profile because it explicitly combines store cancellation sync, local reload, and Firestore sync with paid-tier preservation.

Investigation question: entering subscription management may recover Standard through `syncCancellationStateFromStore`, through Firestore sync with `preserveLocalPaidTier: true`, or through both.

### AuthService Firestore Sync

`lib/services/auth_service.dart` sign-in success path:

- may call `resetToFree()` when the previous local uid/tier cannot be preserved,
- sets the signed-in uid in `UserStatusManager`,
- calls Firestore subscription sync with retry.

Firestore sync behavior to investigate:

- If Firestore tier is paid, it calls `UserStatusManager.setTier(...)`.
- If Firestore tier is Free, it can reset local tier to Free.
- If Firestore is Free but local state is grace, it can preserve local Cloud read grace.
- If `preserveLocalPaidTier=true` and local tier is paid, it can avoid immediate local paid downgrade when Firestore says Free.

Investigation question: active Standard can start as Free if the local cache is Free and Profile does not call the management-screen preserve/refresh path. Conversely, QA injected grace can be overwritten if a store/server refresh later confirms active paid entitlement.

### IAPService Store Refresh

`lib/services/iap_service.dart` contains:

- `initialize()`: store availability/product/listener setup.
- `refreshEntitlementsFromStore(reason: ...)`: calls Android past purchase verification and pending verification retry, then reloads `UserStatusManager`.
- `_retryRestoreVerificationFromStore(...)`: uses Android `queryPastPurchases()` and applies verified results through the normal delivery path.
- `restorePurchases()`: store restore plus restore verification and pending verification retry.
- `syncCancellationStateFromStore(...)`: subscription management-oriented store sync path.

Investigation question: startup uses `refreshEntitlementsFromStore`, while subscription management uses `syncCancellationStateFromStore` plus Firestore sync. We need to isolate which call changes Free to Standard.

## 4. Source-of-Truth Precedence to Validate

Proposed precedence for active entitlement decisions:

1. Server verification result for a current store purchase.
2. Google Play purchase state as a candidate input that must be verified by the server.
3. Firestore user profile as remote cached entitlement and cross-device continuity state.
4. Local `SharedPreferences` as local cache/offline fallback and QA injection surface.

Proposed rules:

- A verified active server result should be allowed to restore Standard/Premium and update local cache and Firestore.
- An unverified store candidate should not grant paid entitlement by itself.
- Firestore paid state can restore local paid cache when server/store refresh is unavailable, subject to expiry evaluation.
- Firestore Free should not blindly override a locally verified active entitlement.
- QA injected grace state is not a production source of truth; it needs an explicit QA guard or a documented action-window check so store/server refresh does not silently invalidate grace tests.

## 5. Required Investigation Questions

1. After `UserStatusManager.initialize()` at app launch, does any completed subscription sync update UI-visible state before Profile renders?
2. Does startup `IAPService.refreshEntitlementsFromStore(reason: 'startup_warmup')` run to completion on the affected emulator?
3. Does startup `refreshEntitlementsFromStore` find a matching past purchase, verify it, and call the entitlement apply path?
4. Does `AuthService` sign-in/profile sync apply Firestore `subscriptionTier` at launch, or only during explicit sign-in and subscription-management refresh?
5. Does Profile initialization miss a needed Firestore/store refresh call?
6. Which subscription-management step changes Free to Standard: store cancellation sync, Firestore sync with preservation, or local reload after an async IAP update?
7. Under what exact conditions does an active Standard account appear as Free after launch?
8. Under what exact conditions does a QA injected grace/free state get overwritten by store/server refresh?
9. Which diagnostics can prove the above without logging raw uid, email, token, order id, provider, path, Storage path, or filename?

## 6. Investigation Procedure

### Static Trace

1. Trace startup order in `lib/main.dart`.
2. Trace Profile initialization and pull-to-refresh in `lib/screens/profile_screen.dart`.
3. Trace subscription management `_refreshSubscriptionState(...)`.
4. Trace `IAPService.refreshEntitlementsFromStore(...)`, `_retryRestoreVerificationFromStore(...)`, and `syncCancellationStateFromStore(...)`.
5. Trace `AuthService.syncCurrentUserSubscriptionFromFirestore(...)` and the preserve flags.
6. Trace `UserStatusManager.initialize()`, `setTier()`, `resetToFree()`, and expiry downgrade behavior.

### Runtime Trace, Raw-Safe

Use a signed-in QA account and do not print raw identifiers.

Scenario A: cold launch active Standard

- Clear logcat.
- Launch app.
- Record count/status-only markers:
  - startup user status load count
  - startup entitlement refresh requested/completed count
  - past purchase candidate count
  - verification active/inactive/failed count
  - local tier before/after
  - Profile first-render tier

Scenario B: Profile only

- From launched app, open Profile without entering subscription management.
- Record whether only local initialization occurs or whether store/Firestore refresh occurs.
- Record whether Profile remains Free or updates to Standard.

Scenario C: subscription management entry/return

- Clear logcat.
- Enter subscription management.
- Record count/status-only markers for:
  - `syncCancellationStateFromStore`
  - Firestore sync with `preserveLocalPaidTier=true`
  - local reload after sync
  - before/after tier
- Identify which marker first changes tier from Free to Standard.

Scenario D: injected grace state

- Inject grace/free local state with app stopped and XML backups.
- Launch app and record whether startup store/server refresh overwrites it.
- Enter Profile and subscription management separately to identify invalidation triggers.
- Do not use the result for MMQA-03 unless the action window still shows grace write-block state immediately before upload.

## 7. Raw-Safe Diagnostic Design

Future diagnostics should use a single component marker such as `[EntitlementRefresh]` and only count/status fields.

Allowed fields:

- `trigger=startup_warmup|app_resumed|profile_init|profile_refresh|subscription_management_init|return_from_paywall`
- `source=local_cache|firestore_cache|store_query|server_verify|expiry_eval`
- `before_tier=free|standard|premium`
- `after_tier=free|standard|premium`
- `result=applied|preserved|skipped|failed`
- `reason_code=not_initialized|store_unavailable|no_candidate|verification_active|verification_inactive|firestore_paid|firestore_free|local_grace_preserved|local_paid_preserved|expired_downgrade`
- `candidate_count=N`
- `verified_active_count=N`
- `verified_inactive_count=N`
- `verification_failed_count=N`
- `duration_ms=N`

Disallowed fields:

- raw uid
- email
- token
- order id
- provider raw value
- purchase token
- transaction id
- local path
- Storage path
- file name

If an identifier is required for correlation, use an internal action-window sequence number, not a user or purchase identifier.

## 8. Expected Findings to Confirm or Reject

Hypothesis 1: startup refresh runs too late for Profile first render.

- Evidence: startup entitlement refresh completes after Profile first displays Free.
- Likely fix later: expose refresh completion to UI or run entitlement reconciliation before Profile state is considered ready.

Hypothesis 2: startup refresh does not apply active purchase, but subscription management does.

- Evidence: startup has no verified active apply marker; subscription management does.
- Likely fix later: use the same verified entitlement refresh path at launch/profile initialization.

Hypothesis 3: Firestore Free overwrites local paid/grace before store verification restores Standard.

- Evidence: Firestore sync/reset marker before later store apply marker.
- Likely fix later: centralize precedence so verified store/server state wins and Firestore Free cannot prematurely downgrade active paid.

Hypothesis 4: QA grace is correctly overwritten by real active store entitlement.

- Evidence: verified active store/server result after injected grace state.
- Likely fix later: MMQA grace tests need a QA account without active store entitlement, a QA entitlement override guard, or a pre-action state assertion that fails fast when active paid is restored.

## 9. Decision Criteria for Later Implementation

Implement launch/profile refresh only after investigation confirms the refresh source.

Go for implementation when:

- the Standard recovery path is identified,
- the same path can be invoked at launch/profile without changing purchase state,
- raw-safe diagnostics can prove ordering,
- QA injected grace invalidation behavior is documented.

No-go until redesigned when:

- source-of-truth precedence remains ambiguous,
- launch refresh would make QA grace impossible to test without a separate fixture strategy,
- adding refresh on launch risks downgrading active users incorrectly,
- diagnostics would require raw purchase/user identifiers.

## 10. Follow-Up Deliverables

After this investigation:

1. `plans/cloud_clip_subscription_entitlement_refresh_root_cause_v1.md`
2. `plans/cloud_clip_subscription_entitlement_refresh_fix_plan_v1.md`
3. Optional raw-safe instrumentation implementation report if diagnostics are needed before the fix.
4. Updated MMQA-03 plan defining how grace fixtures remain stable during action windows.

## 11. Go/No-Go Verdict

Current verdict: GO for investigation only.

Implementation is NO-GO until the exact recovery path and overwrite conditions are confirmed with raw-safe runtime evidence.

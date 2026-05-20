# Cloud Clip Subscription Entitlement Refresh Fix Plan v1

## 1. Root Cause Summary

Runtime capture in `plans/cloud_clip_subscription_entitlement_refresh_root_cause_v1.md` confirmed an asymmetric entitlement refresh path.

Current behavior:

- Launch/Profile:
  - load local `SharedPreferences`
  - run expiry evaluation
  - launch also runs store query
  - does not run Firestore paid entitlement sync
- Subscription Management:
  - runs store cancellation sync
  - reloads local cache
  - runs Firestore entitlement sync
  - reloads local cache again

Observed root cause:

- When local cache is Free/stale/grace, launch/Profile preserve Free.
- Store query can return `candidate_count=0`, so store/server verification may not recover Standard at launch.
- Firestore paid state is only applied when Subscription Management runs `source=firestore_cache reason_code=firestore_paid`.

## 2. Production Risk

Risk:

- Active paid users can see Free after launch if local cache is Free or stale.
- Cloud upload UI can remain hidden even though Firestore has active Standard/Premium entitlement.
- Users may need to enter Subscription Management to recover their paid state.

Impact:

- Paid-user trust issue.
- Incorrect Cloud write/read gating until entitlement is reconciled.
- Inconsistent Profile and Library state after cold launch.

## 3. QA Risk

Risk:

- MMQA-03 grace/free fixture can be overwritten by Firestore paid sync.
- Subscription Management navigation during grace tests invalidates the intended state.
- Test evidence can become ambiguous if tier is not asserted immediately before action.

Observed overwrite marker:

- `trigger=subscription_management_init`
- `source=firestore_cache`
- `before_tier=free`
- `after_tier=standard`
- `result=applied`
- `reason_code=firestore_paid`

## 4. Source-of-Truth Precedence

Production precedence:

1. Server verification result for current store purchase.
2. Google Play purchase state as candidate input, only after server verification.
3. Firestore user profile as remote entitlement cache and cross-device continuity state.
4. Local `SharedPreferences` as local cache/offline fallback.

Rules:

- Verified active server result wins over Firestore and local cache.
- Verified inactive terminal result can downgrade only through existing expiry/grace-safe rules.
- Firestore paid can restore local Free/stale cache when no current server/store result is available.
- Firestore Free must not blindly downgrade a locally verified active paid tier.
- Local QA injection is not a production source of truth and must be protected by QA procedure or debug-only lock.

## 5. Proposed Launch/Profile Reconciliation

Add a narrow signed-in entitlement reconciliation step outside Subscription Management.

Proposed triggers:

- `startup_warmup` after Firebase/Auth session is available.
- `profile_init` after `UserStatusManager.initialize()`.
- `profile_refresh` on manual profile refresh.
- Optional `app_resumed` after existing store entitlement refresh.

Recommended order for signed-in authenticated accounts:

1. Load local cache.
2. Run expiry evaluation.
3. Run store/server refresh if available.
4. If store query has no active verified result, run Firestore entitlement sync with preserve guards.
5. Reload local cache and update UI.

Implementation shape:

- Introduce a single orchestration helper, for example `EntitlementRefreshCoordinator` or a small method on an existing service.
- Avoid duplicating Subscription Management logic in multiple screens.
- Keep `[EntitlementRefresh]` markers.
- Do not mutate purchase state directly.

## 6. Firestore Paid Sync Conditions

Firestore paid sync may restore local entitlement when all conditions are met:

- User is signed in with an authenticated account.
- Not guest mode.
- Firestore user document exists.
- Firestore `subscriptionTier` resolves to Standard/Premium.
- Product id/purchase date payload is acceptable for current existing logic.
- No verified inactive terminal server result has just been applied.
- No QA entitlement lock is active.

Expected result:

- Local Free/stale becomes Standard/Premium.
- UI gates re-evaluate after local cache reload.
- Marker:
  - `source=firestore_cache`
  - `result=applied`
  - `reason_code=firestore_paid`

## 7. Firestore Free Downgrade Guard

Keep and formalize `preserveLocalPaidTier` behavior.

Firestore Free should not downgrade local paid when:

- local tier is Standard/Premium and still within inferred active period,
- a verified active store/server result exists in the current session,
- preserveLocalPaidTier is true for launch/profile reconciliation,
- local state is in an explicit syncing/pending state.

Firestore Free can apply when:

- local tier is Free and no grace applies,
- verified inactive terminal result has been applied,
- local paid state is expired and expiry/grace rules intentionally downgrade,
- account/user transition requires clearing stale paid state.

Expected marker cases:

- Preserve paid:
  - `source=firestore_cache`
  - `result=preserved`
  - `reason_code=local_paid_preserved`
- Preserve grace:
  - `source=firestore_cache`
  - `result=preserved`
  - `reason_code=local_grace_preserved`
- Apply free:
  - `source=firestore_cache`
  - `result=applied`
  - `reason_code=firestore_free`

## 8. Store/Server Verification Precedence

Store/server verification remains the highest authority.

Required behavior:

- If store query returns a purchase candidate and server verification returns active, apply Standard/Premium before Firestore cache decisions.
- If server verification returns terminal inactive, apply existing expiry/grace-safe downgrade logic before Firestore cache decisions.
- If store query returns no candidate, Firestore cache can be used to recover paid state.
- If server verification is recoverable failure, preserve existing local paid state and avoid destructive downgrade.

Do not:

- Grant paid entitlement from unverified store candidate alone.
- Log purchase token/order id/provider raw values.
- Use Firestore paid to override a verified inactive terminal server result in the same refresh window.

## 9. QA Grace Fixture Strategy

Minimum required QA procedure:

- Do not enter Subscription Management during MMQA-03 grace upload-block tests.
- Assert tier immediately before the upload action:
  - `before_tier=free`
  - `source=local_cache` preserved
  - no `source=firestore_cache reason_code=firestore_paid` after injection
- If a paid overwrite marker appears, mark the QA scenario BLOCKED and recreate fixture.

Recommended implementation option:

- Add debug-only QA entitlement refresh lock/bypass.
- The lock should be unavailable in release builds.
- It should prevent launch/profile/subscription-management Firestore paid sync from overwriting an explicitly injected QA grace/free fixture.
- It should emit raw-safe marker:
  - `source=firestore_cache`
  - `result=skipped`
  - `reason_code=local_grace_preserved`

Alternative without code:

- Use a QA account whose Firestore profile does not contain active paid entitlement for grace tests.
- This is operationally cleaner but requires careful account fixture management.

## 10. Implementation Phases

Phase 1: Coordinator Design

- Define one entitlement reconciliation entry point.
- Decide owner service.
- Define trigger inputs and raw-safe marker behavior.
- No UI behavior change yet.

Phase 2: Launch/Profile Firestore Sync

- Add signed-in Firestore entitlement sync after local/expiry and store query.
- Use `preserveLocalPaidTier=true`.
- Ensure Profile UI reloads after reconciliation.

Phase 3: QA Grace Guard

- Implement either:
  - debug-only QA entitlement lock, or
  - documented no-navigation plus pre-action assertion only.
- Update MMQA-03 checklist.

Phase 4: Regression Hardening

- Add tests for:
  - local Free + Firestore paid restores Standard,
  - Firestore Free preserves local paid when guard applies,
  - local grace is preserved when QA lock applies,
  - store/server active result wins,
  - terminal inactive result is not overwritten by Firestore paid in same window.

Phase 5: Runtime Validation

- Re-run cold launch active paid.
- Re-run Profile open only.
- Re-run injected grace with and without Subscription Management according to chosen QA strategy.

## 11. Test Plan

Unit tests:

- Firestore paid sync restores Standard from local Free/stale.
- Firestore Free with `preserveLocalPaidTier=true` preserves local paid.
- Local grace preserved when Firestore Free is received.
- Expired paid auto-downgrade still preserves R3 grace history.
- Debug-only QA lock prevents Firestore paid overwrite.

Widget/manual tests:

- Profile first render eventually shows Standard after launch reconciliation.
- Library Cloud upload button appears for active Standard after reconciliation.
- Profile refresh does not require Subscription Management to recover Standard.

Runtime QA:

- A. Active Standard cold launch with stale local Free:
  - expect `firestore_cache before_tier=free after_tier=standard reason_code=firestore_paid`.
- B. Profile open only:
  - expect entitlement recovery without Subscription Management.
- C. Subscription Management:
  - should no longer be the first place where paid entitlement is recovered.
- D. Injected grace:
  - no Subscription Management navigation, pre-action assertion passes.
  - with QA lock, Firestore paid overwrite is skipped.

Security checks:

- `[EntitlementRefresh]` markers contain only allowed fields.
- No raw uid/email/token/order id/provider/purchase token in app-controlled logs.

## 12. Go/No-Go Criteria

Go for implementation when:

- The coordinator owner and trigger order are approved.
- Firestore paid restore conditions are accepted.
- Firestore Free downgrade guard is accepted.
- QA grace strategy is selected.
- Raw-safe diagnostics remain mandatory.

No-go when:

- The fix would require Firebase rules/index/schema changes.
- The fix would mutate purchase state directly.
- QA grace protection is undefined.
- Store/server precedence is weakened.
- Any raw uid/email/token/order id/provider/purchase token logging is introduced.

Current verdict:

- GO for implementation planning.
- NO-GO for code changes until this plan is approved.

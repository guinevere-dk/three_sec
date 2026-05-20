# Cloud Clip Subscription Entitlement Refresh Root Cause v1

## Summary

Runtime capture confirms the subscription entitlement inconsistency is caused by different refresh paths across launch/Profile and Subscription Management.

Root cause:

- App launch and Profile initialization only reload local cache and run expiry evaluation.
- Launch also runs store query, but in this runtime it returned no purchase candidates.
- Launch/Profile do not run Firestore paid entitlement sync.
- Subscription Management runs Firestore entitlement sync and applies the active Standard tier from Firestore.

Therefore, if local SharedPreferences is Free or QA injected grace/free, the app can remain Free on launch/Profile until Subscription Management is opened. Subscription Management then applies Firestore paid state and overwrites the local grace/free fixture.

Raw uid, email, token, order id, provider, and purchase token values are not recorded.

## Build / Runtime Setup

- Debug APK rebuilt with raw-safe `[EntitlementRefresh]` instrumentation.
- Installed with data-preserving reinstall.
- No `pm clear`, uninstall, wipe data, Firebase deploy, rules/index/schema change, or purchase-state mutation was performed.

## Scenario A: Cold Launch Active Standard

Procedure:

1. Cleared logcat.
2. Force-stopped app.
3. Cold-launched app.
4. Collected `[EntitlementRefresh]` markers only.

Observed marker order:

1. `trigger=profile_init source=local_cache before_tier=free after_tier=standard result=applied reason_code=no_candidate candidate_count=0 verified_active_count=0 verified_inactive_count=0 verification_failed_count=0`
2. `trigger=startup_warmup source=local_cache before_tier=free after_tier=standard result=applied reason_code=no_candidate candidate_count=0 verified_active_count=0 verified_inactive_count=0 verification_failed_count=0`
3. `trigger=profile_init source=expiry_eval before_tier=standard after_tier=standard result=skipped reason_code=no_candidate`
4. `trigger=startup_warmup source=expiry_eval before_tier=standard after_tier=standard result=skipped reason_code=no_candidate`
5. `trigger=startup_warmup source=store_query before_tier=standard after_tier=standard result=skipped reason_code=no_candidate candidate_count=0 verified_active_count=0 verified_inactive_count=0 verification_failed_count=0`

Interpretation:

- Standard was restored from local cache in this active state.
- Store query did not find a candidate in this capture.
- No Firestore cache sync marker ran during launch.
- No server verification apply marker ran during launch.

Verdict:

- Active Standard cold launch did not reproduce the Free-visible issue when local cache already contained Standard.
- This means the earlier Free-visible state depends on local cache being Free/grace or stale.

## Scenario B: Profile Open / Refresh Only

Procedure:

1. Opened Profile.
2. Triggered Profile refresh.
3. Collected `[EntitlementRefresh]` markers only.

Observed markers:

1. `trigger=profile_refresh source=local_cache before_tier=standard after_tier=standard result=preserved reason_code=no_candidate`
2. `trigger=profile_refresh source=expiry_eval before_tier=standard after_tier=standard result=skipped reason_code=no_candidate`

Interpretation:

- Profile refresh only reloads local cache and evaluates expiry.
- No `store_query` marker.
- No `server_verify` marker.
- No `firestore_cache` marker.

Verdict:

- Profile alone cannot restore paid entitlement if local cache is Free/stale.

## Scenario C: Subscription Management Entry

Procedure:

1. Cleared logcat.
2. Entered Subscription Management from Profile.
3. Collected `[EntitlementRefresh]` markers only.

Observed markers while local state was already Standard:

1. `trigger=subscription_management_init source=store_query before_tier=standard after_tier=standard result=skipped reason_code=no_candidate candidate_count=0`
2. `trigger=subscription_management_init source=local_cache before_tier=standard after_tier=standard result=preserved reason_code=no_candidate`
3. `trigger=subscription_management_init source=firestore_cache before_tier=standard after_tier=standard result=applied reason_code=firestore_paid`

Interpretation:

- Subscription Management always ran the Firestore entitlement sync path.
- In this already-Standard state, Firestore confirmed paid state but did not cause a visible tier transition.

Verdict:

- Subscription Management includes a refresh path that Profile does not run.

## Scenario D: Injected Grace / Free State

Procedure:

1. Force-stopped app.
2. Injected local Free + within-grace paid history state in SharedPreferences.
3. Created before/after XML backups.
4. Cold-launched app.
5. Opened/refreshed Profile.
6. Entered Subscription Management.
7. Returned to Profile.

### D1: Launch After Grace Injection

Observed markers:

1. `trigger=profile_init source=local_cache before_tier=free after_tier=free result=preserved reason_code=no_candidate`
2. `trigger=startup_warmup source=local_cache before_tier=free after_tier=free result=preserved reason_code=no_candidate`
3. `trigger=profile_init source=expiry_eval before_tier=free after_tier=free result=skipped reason_code=no_candidate`
4. `trigger=startup_warmup source=expiry_eval before_tier=free after_tier=free result=skipped reason_code=no_candidate`
5. `trigger=startup_warmup source=store_query before_tier=free after_tier=free result=skipped reason_code=no_candidate candidate_count=0`

Interpretation:

- Injected grace/free state survived launch.
- Store query found no candidate and did not overwrite grace/free.
- No Firestore paid sync ran during launch.

### D2: Profile Refresh After Grace Injection

Observed markers:

1. `trigger=profile_refresh source=local_cache before_tier=free after_tier=free result=preserved reason_code=no_candidate`
2. `trigger=profile_refresh source=expiry_eval before_tier=free after_tier=free result=skipped reason_code=no_candidate`

Interpretation:

- Profile refresh preserved injected grace/free.
- No store/server/Firestore entitlement recovery ran.

### D3: Subscription Management After Grace Injection

Observed markers:

1. `trigger=subscription_management_init source=store_query before_tier=free after_tier=free result=skipped reason_code=no_candidate candidate_count=0`
2. `trigger=subscription_management_init source=local_cache before_tier=free after_tier=free result=preserved reason_code=no_candidate`
3. `trigger=subscription_management_init source=firestore_cache before_tier=free after_tier=standard result=applied reason_code=firestore_paid`

Interpretation:

- Store query did not overwrite the fixture.
- Firestore cache sync overwrote injected grace/free with active Standard.
- This is the exact trigger/source that invalidated MMQA-03 when the user entered Subscription Management before upload.

### D4: Return From Subscription Management

Observed markers:

1. `trigger=profile_refresh source=local_cache before_tier=standard after_tier=standard result=preserved reason_code=no_candidate`
2. `trigger=profile_refresh source=expiry_eval before_tier=standard after_tier=standard result=skipped reason_code=no_candidate`

Interpretation:

- On return, Profile simply reloaded the already-overwritten Standard local cache.

## Root Cause

The app has asymmetric entitlement refresh behavior:

- Launch/Profile:
  - local cache reload
  - expiry evaluation
  - launch store query
  - no Firestore entitlement sync

- Subscription Management:
  - store cancellation sync
  - local cache reload
  - Firestore entitlement sync with paid-state preservation
  - local cache reload

In the captured environment, Google Play store query returned `candidate_count=0`, so launch could not recover Standard through store/server verification. Firestore had paid entitlement state and restored Standard only when Subscription Management called Firestore sync.

## Why Active Standard Can Appear As Free On Launch

If the local cache is Free, stale, or QA-injected grace/free:

1. Launch local cache preserves Free.
2. Launch expiry evaluation skips downgrade because it is already Free.
3. Launch store query may return no candidate.
4. Launch does not call Firestore paid sync.
5. Profile only reloads local cache and expiry evaluation.
6. Result: Profile shows Free.

The account becomes Standard only after a path runs Firestore entitlement sync, currently Subscription Management.

## Why QA Grace Is Overwritten

Injected grace/free is stable through:

- launch local cache reload,
- launch expiry evaluation,
- launch store query with no candidate,
- Profile refresh.

It is overwritten by:

- `trigger=subscription_management_init`
- `source=firestore_cache`
- `reason_code=firestore_paid`
- `before_tier=free`
- `after_tier=standard`

## Security / Redaction Result

The recorded evidence uses only allowed `[EntitlementRefresh]` fields:

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

Raw uid, email, token, order id, provider, and purchase token values are not recorded.

## Product Implication

For production active Standard users:

- If local cache is intact and Standard, launch displays Standard.
- If local cache is Free/stale but Firestore contains paid state, Profile may show Free until Subscription Management is opened.
- If store query returns no candidate, launch has no current path to recover paid state from Firestore.

For QA:

- MMQA-03 grace upload-block cannot include Subscription Management navigation unless the test intentionally expects Firestore paid overwrite.
- A valid grace test must assert `before_tier=free` immediately before upload and avoid Subscription Management.

## Recommended Fix Direction

Do not implement in this report.

Recommended next plan:

1. Add a launch/profile entitlement reconciliation step that can run Firestore paid sync for signed-in accounts.
2. Keep raw-safe `[EntitlementRefresh]` diagnostics.
3. Define QA behavior for injected grace:
   - either a QA-only entitlement refresh bypass,
   - or a documented rule that grace tests must not navigate to Subscription Management.
4. Ensure Firestore Free does not incorrectly downgrade a locally verified active paid entitlement.
5. Keep server/store verification as highest authority when candidates are available.

## Verdict

Root cause confirmed.

Overall: PASS for runtime capture.

Issue classification:

- Production risk: active paid users with stale/local Free cache can see Free until Subscription Management triggers Firestore sync.
- QA risk: injected grace/free fixtures are overwritten by Subscription Management Firestore paid sync.

No MMQA-03 retry was performed.

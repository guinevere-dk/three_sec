# Cloud Clip R3 QA Subscription Lock Plan v1

## 1. Purpose

MMQA-03 requires a signed-in QA account to stay in an injected expired-within-grace or Free fixture during the upload action window.

The production entitlement refresh fix is correct and must remain active:

- launch/Profile Firestore reconciliation restores active paid users from local Free/stale state,
- Subscription Management is no longer required for first recovery,
- store/server verification remains higher precedence than Firestore cache.

The remaining QA problem is narrower: for paid QA accounts, production Firestore paid reconciliation can overwrite a locally injected grace/free fixture before MMQA-03 can verify that new upload is blocked.

This plan adds a debug-only QA entitlement lock to protect intentionally injected MMQA fixtures without weakening production behavior.

No code change is included in this document.

## 2. Dart Define Contract

Flag:

```text
R3_QA_SUBSCRIPTION_LOCK=true
```

Default:

```text
R3_QA_SUBSCRIPTION_LOCK=false
```

Build scope:

- Enabled only for debug/profile builds.
- Forced disabled in release builds.
- Release builds must behave as if the flag is false even if the dart-define is accidentally supplied.

Recommended runtime predicate:

```dart
const bool qaSubscriptionLockRequested =
    bool.fromEnvironment('R3_QA_SUBSCRIPTION_LOCK');

final bool qaSubscriptionLockEnabled =
    !kReleaseMode && qaSubscriptionLockRequested;
```

Release behavior:

- `kReleaseMode == true` always disables the lock.
- Optional debug/profile assertion can verify that release-only code paths never observe an active lock.

## 3. Intended Behavior

The lock applies only immediately before applying Firestore paid entitlement from `source=firestore_cache`.

When all conditions are true:

- QA lock is enabled.
- Current build is not release.
- User is signed in.
- Local tier is `free`.
- Local state has grace history or an explicit subscription-expired-within-grace marker.
- Firestore candidate is paid: Standard or Premium.
- Refresh trigger is one of the app entitlement reconciliation triggers, such as:
  - `startup_warmup`
  - `profile_init`
  - `profile_refresh`
  - `app_resumed`
  - `subscription_management_init`

Then:

- Skip applying Firestore paid entitlement.
- Preserve local injected grace/free state.
- Emit raw-safe `[EntitlementRefresh]` marker:
  - `source=firestore_cache`
  - `result=skipped`
  - `reason_code=qa_lock_applied`

If the implementation reuses existing grace preservation reason codes, this is also acceptable:

- `reason_code=local_grace_preserved`

The preferred reason code for QA lock-specific evidence is:

- `qa_lock_applied`

## 4. Non-Goals

The QA lock must not:

- grant Standard/Premium entitlement,
- bypass store/server verification,
- change purchase state,
- change Firestore user profile data,
- write Firebase rules/index/schema,
- affect release builds,
- hide expired production subscriptions,
- turn arbitrary Free users into paid users,
- suppress Firestore Free downgrade guards outside the explicit QA fixture case.

## 5. Source-of-Truth Precedence

Production precedence remains unchanged:

1. Server verification result for current store purchase.
2. Google Play purchase state as candidate input after server verification.
3. Firestore user profile as remote entitlement cache.
4. Local `SharedPreferences` as local cache/offline fallback.

QA lock behavior is an overlay only for debug/profile builds:

- It can prevent Firestore paid cache from overwriting an injected local grace/free fixture.
- It must not override a verified active or verified inactive server result.
- It must not mutate the source-of-truth data.

If a store/server verification result is available in the same refresh window:

- verified active result remains authoritative,
- verified inactive result remains authoritative,
- QA lock should not convert or reinterpret the verification result.

## 6. Firestore Paid Sync Integration

Recommended insertion point:

- Inside the existing Firestore entitlement sync path, immediately before local state is updated from Firestore paid data.
- The check should be shared by all triggers that call Firestore entitlement reconciliation.

Expected flow:

1. Read local tier and grace markers from `UserStatusManager` or equivalent local status object.
2. Read Firestore candidate tier.
3. If candidate is not paid, continue existing logic.
4. If candidate is paid, call the QA lock guard.
5. If the guard returns locked, emit skipped marker and return without applying Firestore paid state.
6. If the guard returns unlocked, continue existing production Firestore paid apply path.

Pseudo decision:

```text
if firestore_candidate in standard/premium:
  if qa_lock_enabled
     and local_tier == free
     and local_grace_history_present:
       skip Firestore paid apply
       log qa_lock_applied
  else:
       apply Firestore paid as production behavior
```

## 7. Grace History Detection

The lock must require concrete local grace evidence.

Acceptable evidence examples:

- local expiry date exists and is within the 30-day grace window,
- local expired subscription history exists,
- `UserStatusManager` reports an expired-within-grace state,
- existing R3 subscription state helpers classify the user as grace-eligible.

Not sufficient:

- local tier is simply `free`,
- missing purchase date,
- missing product id,
- arbitrary QA flag without grace history,
- stale Free state with no subscription history.

This prevents the QA lock from blocking legitimate Firestore paid recovery for ordinary local Free/stale states.

## 8. Diagnostics

Marker:

```text
[EntitlementRefresh]
```

Allowed fields:

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
- optional `qa_lock_enabled=true|false`
- optional `qa_lock_candidate_count`

Required lock marker:

```text
trigger=<trigger> source=firestore_cache before_tier=free after_tier=free result=skipped reason_code=qa_lock_applied
```

Raw values remain forbidden:

- raw uid,
- email,
- token,
- order id,
- provider,
- purchase token.

## 9. UI / Status Exposure

The lock should not create production-facing UI.

Allowed debug/profile exposure:

- count/status-only marker in logcat,
- optional debug-only Profile diagnostics line if such diagnostics already exist,
- no raw identifiers.

Recommended wording if surfaced in debug diagnostics:

```text
QA subscription lock: active
```

Release builds:

- no visible lock indicator,
- no active lock behavior,
- no release-only user-facing text.

## 10. Safety Guards

Required guards:

- `kReleaseMode` disables the lock unconditionally.
- The lock can only skip Firestore paid apply when local grace history is present.
- The lock cannot apply or synthesize paid status.
- The lock cannot change Firestore or store purchase state.
- The lock emits raw-safe evidence when it skips.
- The lock must not hide verified server/store results.

Recommended code-level structure:

- One helper function, for example:
  - `shouldSkipFirestorePaidForQaLock(...)`
- Inputs should be enum/status values and booleans only.
- Return should include:
  - `skip: true|false`
  - `reasonCode: qa_lock_applied|none`

## 11. Test Plan

Unit tests:

1. QA lock off: local Free/stale + Firestore paid restores Standard.
2. QA lock on + local grace history + Firestore paid preserves local Free/grace.
3. QA lock on + no grace history + Firestore paid restores Standard.
4. QA lock on + local paid + Firestore Free preserves local paid through existing `preserveLocalPaidTier` behavior.
5. QA lock on + Firestore Free + local grace preserves local grace through existing grace guard.
6. Release guard: simulated release predicate forces lock disabled.
7. Raw-safe diagnostics: marker fields contain only tier/status/count/reason values.

Runtime tests:

1. Build debug with:

   ```powershell
   flutter run -d emulator-5554 --debug --dart-define=GUEST_LOGIN_ENABLED=true --dart-define=R3_QA_SUBSCRIPTION_LOCK=true
   ```

2. Inject expired-within-grace local state.
3. Keep Firestore paid state unchanged.
4. Cold launch.
5. Confirm:
   - `source=firestore_cache`
   - `before_tier=free`
   - `after_tier=free`
   - `result=skipped`
   - `reason_code=qa_lock_applied`
6. Confirm MMQA-03 upload action sees grace/free state.
7. Confirm no raw sensitive logs.

Control runtime test:

1. Build debug without `R3_QA_SUBSCRIPTION_LOCK=true`.
2. Inject local Free/stale with no grace history.
3. Confirm Firestore paid restores Standard as verified in `plans/cloud_clip_subscription_entitlement_refresh_fix_runtime_verification_v1.md`.

## 12. MMQA-03 Procedure Update

For MMQA-03 grace upload blocked QA:

1. Use a debug/profile build with `R3_QA_SUBSCRIPTION_LOCK=true`.
2. Inject expired-within-30-day grace local state.
3. Do not enter Subscription Management during the action window.
4. Cold launch or resume app.
5. Assert pre-action entitlement:
   - local tier remains Free/grace,
   - Firestore paid sync was skipped by QA lock,
   - no raw sensitive logs.
6. Attempt device/localOnly upload.
7. Expected outcome:
   - upload blocked by subscription write gate,
   - local clip remains,
   - no new Cloud active metadata/object,
   - no Storage physical delete.

If QA lock is off or not observed:

- MMQA-03 must keep the existing pre-action assertion rule.
- If Firestore paid overwrite appears before action, mark the scenario BLOCKED.

## 13. Implementation Phases

Phase 1: Guard Helper

- Add debug/profile-only flag read.
- Add release guard.
- Add local grace history predicate.
- Add Firestore paid skip predicate.

Phase 2: Firestore Sync Integration

- Insert predicate before applying Firestore paid state.
- Keep existing `preserveLocalPaidTier` and `local_grace_preserved` behavior.
- Emit `[EntitlementRefresh]` skipped marker.

Phase 3: Tests

- Add focused unit tests for lock on/off and grace-history requirements.
- Add release guard test or documented compile-mode guard if direct release-mode unit testing is not practical.

Phase 4: Runtime Verification

- Rebuild debug with `R3_QA_SUBSCRIPTION_LOCK=true`.
- Run injected grace preservation capture.
- Confirm raw-safe marker.
- Re-run MMQA-03.

## 14. Go / No-Go Criteria

Go when:

- Lock is debug/profile-only.
- Release builds cannot activate it.
- Lock requires local grace history.
- Firestore paid recovery still works when lock is off.
- Firestore paid recovery still works when lock is on but no grace history exists.
- Raw-safe diagnostics are in place.
- Store/server precedence is unchanged.

No-go when:

- Release build can activate the lock.
- Lock blocks Firestore paid recovery for ordinary Free/stale users with no grace history.
- Lock changes purchase state or Firestore data.
- Lock hides server/store verification results.
- Raw uid/email/token/order id/provider/purchase token logging is introduced.
- Firebase rules/index/schema changes are required.

## 15. Verdict

Recommended verdict: GO for implementation after approval.

This is a QA-only guard for MMQA-03 fixture stability. It preserves the production entitlement refresh fix and prevents Firestore paid cache from invalidating the local injected grace state during the controlled action window.

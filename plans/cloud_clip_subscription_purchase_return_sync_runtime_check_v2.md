# Cloud Clip Subscription Purchase Return Sync Runtime Check v2

## Summary

Follow-up emulator verification after `plans/cloud_clip_subscription_purchase_return_sync_fix_report_v1.md`.

User attempted to start the purchase-return test, but at step 2 the Subscription Management/Profile flow already showed Standard as applied. Therefore no new purchase was executed in this window.

Raw uid, email, token, order id, provider, purchase token, local path, storage path, and file name values are not recorded.

## Build / Runtime Context

- Build: debug APK.
- Dart defines:
  - `GUEST_LOGIN_ENABLED=true`
  - `R3_QA_SUBSCRIPTION_LOCK` not set.
- Install method: `adb install -r`, data preserved.
- QA lock marker count: `0`.

## Evidence

User-visible result:

- User reported Standard was already applied at the Subscription Management step.

Local status probe:

- `local_tier_standard_present=True`
- `local_tier_free_present=False`
- `local_product_key_present=True`
- `local_purchase_date_key_present=True`
- `local_next_tier_key_present=True`

Logcat window:

- `email_like_raw_hit_count=0`
- `token_assignment_raw_hit_count=0`
- no IAP purchase/update markers captured in this window because no purchase was attempted,
- no `[EntitlementRefresh]` markers captured in this short post-clear window.

Previous v1 runtime evidence from the same normal debug build showed:

```text
qa_lock_marker_count=0
trigger=profile_init source=firestore_cache before_tier=free after_tier=standard result=applied reason_code=firestore_paid
trigger=startup_warmup source=firestore_cache before_tier=free after_tier=standard result=applied reason_code=firestore_paid
```

## Verdict

Subscription state visible as Standard before purchase retry: PASS

The original user-facing blocker, "Profile/Subscription Management remains Free after Standard subscription," is not reproducible in the current normal debug runtime. Local SharedPreferences also contains Standard state.

Live purchase-return store verification path: N/A in this run

No new purchase was performed because the app already showed Standard. Therefore this run cannot prove a new `purchase update -> verify -> setTier -> syncSubscriptionToFirestore -> completePurchase` sequence.

## Remaining Notes

- The current state includes a pending next-tier key. This may be a legitimate cancellation/downgrade reservation or leftover QA state and should be interpreted separately before future subscription QA.
- If the issue reappears, the next capture should begin before tapping the purchase button and continue until Paywall returns.

## Restrictions Observed

- No purchase state changed by AI.
- No Firestore user profile modified by AI.
- No Firebase rules/index/schema change.
- No deploy.
- No raw sensitive values recorded.

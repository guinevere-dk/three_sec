# Cloud Clip Subscription Purchase Return Sync Runtime Check v1

## Summary

Ran emulator verification after implementing `plans/cloud_clip_subscription_purchase_return_sync_fix_report_v1.md`.

Build used:

```text
debug
GUEST_LOGIN_ENABLED=true
R3_QA_SUBSCRIPTION_LOCK not set
```

No purchase state, Firestore user profile, Firebase rules/index/schema, or deploy action was changed by AI.

Raw uid, email, token, order id, provider, purchase token, local path, storage path, and file name values are not recorded.

## Actions

1. Built debug APK without QA subscription lock.
2. Installed with `adb install -r` to preserve app data/session.
3. Force-stopped app.
4. Cleared logcat.
5. Cold-launched app.
6. Collected count/status-only IAP and `[EntitlementRefresh]` markers.
7. Checked current UI text count-only via UIAutomator dump.

## Evidence

Runtime counters:

- `qa_lock_marker_count=0`
- `entitlement_marker_count=9`
- `store_verification_active_count=0`
- `server_verification_active_count=0`
- `firestore_paid_count=2`
- `store_no_candidate_count=1`
- `standard_ui_marker_count=25`
- `free_ui_marker_count=27`
- `iap_marker_count=16`
- `token_assignment_raw_hit_count=0`

Observed key markers:

```text
trigger=startup_warmup source=store_query before_tier=free after_tier=free result=skipped reason_code=no_candidate
trigger=profile_init source=firestore_cache before_tier=free after_tier=standard result=applied reason_code=firestore_paid
trigger=startup_warmup source=firestore_cache before_tier=free after_tier=standard result=applied reason_code=firestore_paid
```

IAP store query:

- product details loaded successfully,
- store refresh executed,
- no matching past purchase candidate was found in the current emulator store query,
- no pending app verification item was found.

UIAutomator count-only probe:

- `ui_standard_or_subscription_text_count=0`
- `ui_free_text_count=0`

The UI dump did not expose the relevant Profile/Subscription Management text at the current screen. Runtime Flutter markers did show final Standard build markers after Firestore reconciliation.

## Result

Cold launch entitlement recovery: PASS

- QA subscription lock was not active.
- Firestore paid state restored Standard.
- Product runtime did not stay locked in injected Free/grace.

Purchase-return store verification path: NOT FULLY VERIFIED

- The new `return_from_paywall` store refresh code compiled and is present in the installed APK.
- However, the current emulator store query returned no matching purchase candidate.
- Therefore `source=store_query reason_code=verification_active` and `source=server_verify reason_code=verification_active` were not observed in this run.

## Interpretation

The app can now recover Standard outside Subscription Management through Firestore paid reconciliation.

The specific user requirement, "after Standard purchase exits back to Subscription Management, state should sync immediately," still needs a live purchase-return window where Google Play returns a matching purchase candidate. Current emulator evidence suggests the existing purchase is not visible to `queryPastPurchases()` in this run, despite Firestore paid data being present.

## Recommended Next Runtime Step

Run a focused purchase-return capture:

1. Use this normal debug build without `R3_QA_SUBSCRIPTION_LOCK=true`.
2. Clear logcat immediately before tapping purchase.
3. User performs the Standard purchase flow.
4. Capture from purchase tap through Paywall return.
5. Required markers:
   - purchase update status count,
   - `_verifyPurchase` attempt count,
   - `source=server_verify reason_code=verification_active`,
   - `source=store_query reason_code=verification_active`,
   - `completePurchase` executed or deferred reason,
   - Subscription Management final tier Standard.

## Verdict

Overall runtime check: PARTIAL PASS

- PASS: normal debug build, QA lock off, Firestore paid recovery to Standard.
- BLOCKED: live purchase-return store verification could not be proven because current emulator store query had no matching purchase candidate.

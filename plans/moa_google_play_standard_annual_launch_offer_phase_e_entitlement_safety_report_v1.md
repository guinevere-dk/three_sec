# MOA Standard Annual Launch Offer Phase E Entitlement Safety Report v1

## Scope

Phase E verified and tightened the entitlement path after a Standard annual launch-offer purchase.

Implemented:

- Centralized IAP product-id entitlement policy in `IAPEntitlementPolicy`.
- Standard annual product id `3s_standard_annual` maps to existing `UserTier.standard`.
- Purchase product id and server verification product id must match after normalization before entitlement is granted.
- Unsupported product ids no longer fall through to a Premium entitlement in the active-delivery path.
- Paywall local tier wait now refuses unsupported purchase product ids instead of assuming Premium.

Not changed:

- No product id change.
- No Firebase Functions verification contract change.
- No Firestore schema/rules/index change.
- No Google Play offer/base-plan server-side field validation added.

## Server Verification Finding

`functions/index.js` currently validates IAP purchases by normalized product id allowlist:

- `3s_standard_monthly`
- `3s_standard_annual`
- `3s_premium_monthly`
- `3s_premium_annual`

The current `/iap/verify` handler does not reject by launch offer id, base plan id, or offer token. Because the launch offer remains under `3s_standard_annual`, no backend change is required for Phase E.

If a future server verifier starts validating Google Play base plan or offer fields, that must be handled in a separate backend plan before release.

## Entitlement Rule

Launch offer purchase, restore, and renewal must all resolve as:

```text
productId = 3s_standard_annual
entitlement = UserTier.standard
```

The app now uses a canonical check:

```text
normalize(purchase.productID) == normalize(server.data.productId)
```

If either product id is unsupported or the two ids differ, entitlement delivery is skipped.

## QA Coverage

Added tests in `test/iap_purchase_intent_test.dart`:

- Standard annual launch purchase maps to Standard.
- Uppercase/whitespace product ids normalize to `3s_standard_annual`.
- Mismatched purchase and verification product ids do not grant entitlement.
- Unsupported product ids do not default to Premium.

## Manual QA Still Required

Google Play internal-track QA is still required to confirm:

- Play purchase result product id is `3s_standard_annual` for the launch offer.
- Purchase sheet completes and grants Standard.
- Restore after launch purchase grants Standard.
- Renewal continues as Standard annual.

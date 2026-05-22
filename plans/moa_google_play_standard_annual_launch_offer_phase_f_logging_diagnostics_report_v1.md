# MOA Standard Annual Launch Offer Phase F Logging Diagnostics Report v1

## Scope

Phase F added safe diagnostics for Google Play Standard annual launch-offer QA.

Implemented:

- Annual offer extraction now exposes non-sensitive diagnostic fields:
  - `annualProductCount`
  - `androidOfferDetailsCount`
  - `launchTagOfferFound`
  - `annualProductFound`
  - `launchOfferTokenExists`
  - `regularAnnualOfferTokenExists`
- Paywall logs annual-offer diagnostics after Store catalog load.
- Paywall logs purchase-start diagnostics before calling `IAPService.purchase`.
- Logs only product ids, purchase context, counts, booleans, purchase mode, and diagnostic reason.

## Required Log Coverage

Covered by existing or new logs:

- Queried product ids: existing `IAPService._loadProducts()` query log.
- Annual product found/not found: new Paywall annual diagnostics.
- Android offer details count: new Paywall annual diagnostics.
- Launch tag offer found true/false: new Paywall annual diagnostics.
- Selected offer token exists true/false: new Paywall annual diagnostics and purchase-start diagnostics.
- Displayed annual base price available true/false: new Paywall annual diagnostics.
- Displayed launch price available true/false: new Paywall annual diagnostics.
- Purchase started with launch offer true/false: new Paywall purchase-start diagnostics.

## Sensitive Data Guard

The new logs do not print:

- raw offer token
- purchase token
- payment token
- server verification payload
- raw user id

Token diagnostics are limited to boolean existence fields.

## Example Log Shapes

```text
[Paywall][StandardAnnualOffer] trigger=catalog_loaded annualProductFound=true annualProductCount=1 androidOfferDetailsCount=2 launchTagOfferFound=true selectedOfferTokenExists=true displayedAnnualBasePriceAvailable=true displayedLaunchPriceAvailable=true canPurchase=true purchaseMode=launchOffer diagnosticReason=launch_offer_available
```

```text
[Paywall][StandardAnnualOffer] purchaseStarted=true productId=3s_standard_annual purchaseContext=standard_annual_launch purchaseStartedWithLaunchOffer=true selectedOfferTokenExists=true requireOfferToken=true
```

## QA Notes

These logs are intended for internal-track Google Play QA:

- Eligible account should show `launchTagOfferFound=true`, `purchaseMode=launchOffer`, and `purchaseStartedWithLaunchOffer=true`.
- Ineligible account should show `launchTagOfferFound=false` and `purchaseMode=regularAnnual` or an unavailable diagnostic reason if Store details are incomplete.
- If `launchTagOfferFound=true` but `selectedOfferTokenExists=false`, purchase should remain blocked by the Phase C guard.

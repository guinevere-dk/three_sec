# MOA Google Play Standard Annual Launch Offer Phase A Inventory Report v1

## 1. Scope

Phase A는 Google Play Standard annual launch offer 구현 전 Billing API와 기존 구매 경로를 고정하는 인벤토리 단계다.

이번 단계에서는 코드, 의존성, Firebase Functions, Store 설정을 변경하지 않는다.

대상 문서:

- `plans/MOA_Google_Play_Standard_Annual_Launch_Offer_Integration_Prompt.md`
- `plans/moa_google_play_standard_annual_launch_offer_implementation_plan_v1.md`

대상 코드:

- `pubspec.yaml`
- `pubspec.lock`
- `lib/services/iap_service.dart`
- `lib/screens/paywall_screen.dart`
- `functions/index.js`
- local pub-cache `in_app_purchase_android-0.4.0+8`

## 2. Dependency Inventory

현재 직접 의존성:

- `pubspec.yaml`: `in_app_purchase: ^3.2.0`

현재 lock 상태:

- `in_app_purchase`: `3.2.3`, direct main
- `in_app_purchase_android`: `0.4.0+8`, transitive
- `in_app_purchase_platform_interface`: `1.4.0`, transitive
- `in_app_purchase_storekit`: `0.4.7`, transitive

중요한 점:

- `lib/services/iap_service.dart`는 이미 `in_app_purchase_android`와 `in_app_purchase_storekit`을 직접 import한다.
- 하지만 두 패키지는 현재 `pubspec.yaml`의 직접 의존성이 아니다.
- 따라서 analyzer의 `depend_on_referenced_packages` 정보성 경고가 발생할 수 있다.
- 이 경고를 정리하려면 이후 별도 승인 하에 `pubspec.yaml` / `pubspec.lock` 변경이 필요하다.
- Phase A에서는 lockfile 변경 금지 원칙에 따라 의존성을 변경하지 않았다.

## 3. Android Billing API Shape

확인한 패키지:

- `C:\Users\Guiny\AppData\Local\Pub\Cache\hosted\pub.dev\in_app_purchase_android-0.4.0+8`

확인 결과:

- `GooglePlayPurchaseParam` 생성자는 `offerToken` 파라미터를 지원한다.
- `GooglePlayProductDetails`는 `ProductDetailsWrapper productDetails`와 `int? subscriptionIndex`를 가진다.
- Android subscription 상품은 `ProductDetailsWrapper.subscriptionOfferDetails`의 각 항목이 별도 `GooglePlayProductDetails`로 펼쳐진다.
- 즉 같은 `productId == 3s_standard_annual`인 `ProductDetails`가 여러 개 반환될 수 있다.
- `GooglePlayProductDetails.offerToken` getter는 현재 `subscriptionIndex`에 해당하는 `SubscriptionOfferDetailsWrapper.offerIdToken`을 반환한다.
- `SubscriptionOfferDetailsWrapper`에는 다음 필드가 있다.
  - `basePlanId`
  - `offerId`
  - `offerTags`
  - `offerIdToken`
  - `pricingPhases`
- `PricingPhaseWrapper`에는 다음 필드가 있다.
  - `billingCycleCount`
  - `billingPeriod`
  - `formattedPrice`
  - `priceAmountMicros`
  - `priceCurrencyCode`
  - `recurrenceMode`
- `InAppPurchaseAndroidPlatform.buyNonConsumable`은 다음 순서로 token을 결정한다.
  - `GooglePlayPurchaseParam.offerToken`이 있으면 사용한다.
  - 없고 `productDetails is GooglePlayProductDetails`이면 `GooglePlayProductDetails.offerToken`을 fallback으로 사용한다.
  - 결정된 token을 `BillingClient.launchBillingFlow(offerToken: ...)`에 전달한다.

## 4. Existing Product And Entitlement Contract

Flutter product ids:

- `IAPService.standardMonthly = 3s_standard_monthly`
- `IAPService.standardAnnual = 3s_standard_annual`
- `IAPService.premiumMonthly = 3s_premium_monthly`
- `IAPService.premiumAnnual = 3s_premium_annual`

Server allowlist:

- `functions/index.js`의 `ALLOWED_IAP_PRODUCT_IDS`는 위 네 product id를 허용한다.
- `3s_standard_annual`은 이미 허용되어 있다.

Entitlement implication:

- launch offer는 별도 product가 아니다.
- 구매 완료 후 entitlement는 기존 `3s_standard_annual -> Standard` 경로를 그대로 사용해야 한다.
- Phase A 기준으로 server verification 계약 변경 필요성은 발견되지 않았다.

## 5. Existing Purchase Flow Inventory

현재 구매 시작 경로:

- Paywall CTA는 `_iapService.purchase(selectedProductId)`만 호출한다.
- `IAPService.purchase(String productId)`는 product id만 받는다.
- 상품 선택은 `_products.firstWhere((p) => p.id == productId)`로 수행한다.
- Android 구매 param은 `_buildAndroidPurchaseParam(...)`에서 만든다.
- 신규 구매 또는 동일 tier 구매는 `GooglePlayPurchaseParam(productDetails: product)`만 사용한다.
- 명시적인 launch `offerToken` 주입 경로는 없다.

중요한 충돌 지점:

- Android 구독 offer는 같은 product id로 여러 `GooglePlayProductDetails`가 반환될 수 있다.
- 현재 `firstWhere(id == 3s_standard_annual)`는 regular annual base plan과 launch offer 중 어떤 항목이 선택되는지 명확히 보장하지 않는다.
- 명시적 launch offer 구매를 하려면 product id만으로는 부족하다.
- Phase B 이후에는 product id 선택이 아니라 offer-aware selection이 필요하다.

## 6. Paywall Inventory

현재 Paywall:

- Standard monthly / annual 카드만 표시한다.
- Annual 카드 가격은 `_getPrice(_currentAnnualProductId)`를 사용한다.
- `_getPrice`는 `_products.firstWhere((p) => p.id == productId).price`를 사용한다.
- Store product가 없으면 fallback 가격을 사용한다.
  - monthly fallback: `₩6,900`
  - annual fallback: `₩69,000`
- 구매 CTA는 선택된 product id만 넘긴다.

launch offer 관점의 문제:

- annual product가 여러 offer로 반환되면 Paywall 가격도 `firstWhere` 결과에 좌우된다.
- launch offer eligibility가 없는 사용자에게 launch copy를 보여주면 안 된다.
- Store details 미조회 상태에서 paid CTA에 fallback 가격을 쓰면 실제 purchase sheet 가격과 불일치할 수 있다.
- Phase D에서는 buyable paid UI의 정적 가격 fallback을 loading/error/retry 상태로 대체해야 한다.

## 7. Regular Annual Token Decision

현재 패키지 구현상 Android subscription purchase에는 offer token이 필요하다.

다만 앱 코드가 명시적으로 `offerToken`을 넣지 않아도, 선택된 `GooglePlayProductDetails`가 subscription 항목이면 plugin이 `GooglePlayProductDetails.offerToken`을 fallback으로 `launchBillingFlow`에 전달한다.

따라서 regular annual 구매의 안정적인 조건은 다음과 같다.

- regular/base plan에 해당하는 `GooglePlayProductDetails`를 명확히 선택한다.
- 해당 항목의 `offerId == null` 또는 `offerTags`에 `launch`가 없는 것을 확인한다.
- 가능하면 base plan의 `offerIdToken`을 명시적으로 전달하거나, 최소한 선택된 `GooglePlayProductDetails.offerToken` fallback을 의도적으로 사용한다.

launch offer 구매의 조건은 더 엄격해야 한다.

- `offerTags.contains('launch')`인 offer를 찾는다.
- `offerIdToken`이 비어 있지 않아야 한다.
- 구매 시작 시 `GooglePlayPurchaseParam(offerToken: selectedOffer.offerIdToken)`을 명시적으로 전달한다.
- token 값은 로그에 남기지 않고 존재 여부만 기록한다.

## 8. Phase B Requirements

Phase B는 다음 전제 위에서 구현해야 한다.

1. `3s_standard_annual` product id를 변경하지 않는다.
2. launch offer 선택 기준은 `offerTags.contains('launch')`이다.
3. 같은 product id의 여러 `GooglePlayProductDetails`를 정상 입력으로 다룬다.
4. product id만 받는 기존 purchase API는 launch offer를 표현하기에 부족하다.
5. regular annual과 launch offer는 동일 product id지만 서로 다른 offer token을 가질 수 있다.
6. UI 가격은 Store에서 받은 `formattedPrice`만 사용한다.
7. static fallback price는 buyable paid UI에서 사용하지 않는다.

권장 구현 순서:

1. pure Dart normalized model을 먼저 만든다.
2. Android adapter에서 `GooglePlayProductDetails.productDetails.subscriptionOfferDetails`와 `subscriptionIndex`를 읽어 normalized offer로 변환한다.
3. launch offer selector를 unit test로 고정한다.
4. regular annual selector도 unit test로 고정한다.
5. Paywall과 purchase API는 selector가 안정화된 뒤 연결한다.

## 9. Risks

확인된 위험:

- 현재 `firstWhere(productId)` 경로는 동일 product id의 여러 offer를 구분하지 못한다.
- `in_app_purchase_android`와 `in_app_purchase_storekit`은 직접 import 중이지만 transitive dependency 상태다.
- Google Play Console에서 launch offer가 활성화되어도 Store가 eligibility 때문에 offer를 반환하지 않을 수 있다.
- local unit test만으로 실제 Store eligibility와 purchase sheet 가격 일치는 검증할 수 없다.
- fallback 가격이 남아 있으면 Store 가격과 Paywall 가격이 불일치할 수 있다.

금지 유지:

- product id 변경 금지
- Firebase Functions verification contract 변경 금지
- Firestore schema 변경 금지
- Storage path 변경 금지
- `pubspec.lock` 변경 금지
- raw offer token 로그 금지

## 10. Phase A Result

완료:

- 현재 IAP dependency version 확인
- Android Billing wrapper API shape 확인
- launch offer token 전달 가능성 확인
- subscription offer details 구조 확인
- regular annual/base plan token 처리 방식 확인
- 기존 Paywall/IAPService 충돌 지점 확인
- backend allowlist에서 `3s_standard_annual` 유지 확인

변경하지 않음:

- Dart/Flutter 코드
- Firebase Functions 코드
- Firebase rules/index/schema
- `pubspec.yaml`
- `pubspec.lock`
- Store product id
- user data

Phase A acceptance:

- 현재 dependency version에서 사용할 API 이름이 확인되었다.
- 다음 단계 구현은 current package API에 맞춰 진행 가능하다.
- dependency 또는 lockfile 변경은 별도 승인 전까지 하지 않는다.

## 0. 목적

Google Play Console에서 Standard 연간 구독 base plan 아래에 첫해 출시 혜택 Offer를 추가했다.

콘솔 설정:

- Subscription product: Standard
- Existing product id may remain: `3s_standard_annual`
- Offer ID: `standard-annual-launch-offer`
- Eligibility: 신규 고객 확보
- Eligibility condition: 구독한 적 없음
- Offer tag: `launch`
- Offer intent:
  - 신규 고객에게 첫해 연간 구독을 할인 제공
  - 첫해 가격: 59,000원
  - 이후 갱신: 연간 정가 69,000원

앱 코드에서는 Standard annual product를 조회한 뒤, `subscriptionOfferDetails` 안에서 `launch` 태그가 붙은 offer를 찾아 해당 `offerToken`으로 결제를 시작해야 한다.

중요:

- Offer를 콘솔에 만들었다고 자동으로 적용되는 것이 아니다.
- 앱에서 offerToken 없이 결제하면 정가 연간 base plan으로 결제될 수 있다.
- Paywall에 첫해 59,000원을 표시하려면 실제 Store product details에서 해당 offer가 조회될 때만 표시해야 한다.
- Store에서 offer가 내려오지 않으면 정가 annual plan만 표시하거나 fallback UI를 사용한다.

---

## 1. 핵심 요구사항

앱 결제 로직은 다음 흐름을 따라야 한다.


1. Google Play Billing에서 Standard annual product 조회
2. ProductDetails.subscriptionOfferDetails 확인
3. offerTags 안에 `launch`가 있는 offer 탐색
4. 해당 offer의 offerToken 확보
5. Paywall에는 launch offer 가격을 첫해 가격으로 표시
6. 결제 시작 시 BillingFlowParams에 offerToken 포함
7. 구매 완료 후 기존 subscription entitlement 검증 로직으로 Standard 권한 부여
`

---

## 2. 절대 하면 안 되는 것

다음 구현은 금지한다.


- annual product만 조회하고 offerToken 없이 결제 시작
- 앱에 59,000원 가격을 하드코딩해서 항상 표시
- launch offer가 없는 사용자인데도 첫해 혜택 문구 표시
- 월간 구독자에게 신규 고객 launch offer를 강제로 노출
- 일회성 product로 첫해 혜택 처리
- 자체 서버만 믿고 Google Play 구매 상태 검증 없이 Standard 권한 부여


---

## 3. Product / Offer 식별 정책

### 3.1 Product ID

현재 기존 product id를 유지한다.


standard annual product id:
3s_standard_annual


기존 코드에서 annual Standard product id가 다르면 현재 프로젝트의 실제 상수를 우선 확인한다.

### 3.2 Offer Tag

Google Play Console에서 설정한 offer tag:


launch


앱 코드에서는 이 tag를 기준으로 launch offer를 찾는다.

### 3.3 Offer ID

Console offer ID:


standard-annual-launch-offer


주의:

* 앱 코드에서 offer ID를 직접 받을 수 있는지 Billing 라이브러리 구조를 확인한다.
* 일반적으로 앱에서는 `subscriptionOfferDetails`, `offerTags`, `offerToken`, pricing phases를 사용한다.
* 안정적인 식별 기준은 `offerTags.contains('launch')`로 둔다.

---

## 4. Paywall 표시 정책

### 4.1 launch offer가 조회되는 신규 고객

Paywall에는 다음처럼 표시한다.


Standard Annual
첫해 59,000원
이후 연 69,000원

50GB Cloud 백업
1080p 내보내기
편집 기능
프로젝트 저장
기기 변경 시 복원


단, 실제 문구의 가격은 반드시 Store product details에서 받은 formatted price를 사용한다.

예:


첫해 {introPrice}
이후 {renewalPrice}/년


### 4.2 launch offer가 조회되지 않는 사용자

예를 들어 이미 구독 이력이 있거나, Google Play가 신규 고객으로 판단하지 않는 경우에는 launch offer가 내려오지 않을 수 있다.

이 경우:


Standard Annual
연 69,000원


또는 실제 Store에서 받은 annual base plan price를 표시한다.

금지:


사용 자격이 없는 사용자에게 첫해 59,000원 표시


### 4.3 월간 Standard 사용자

현재 launch offer는 “구독한 적 없음” 신규 고객용이다.

따라서 월간 Standard 사용자가 연간으로 변경하려는 경우:


- launch offer를 보여주지 않는다.
- annual base plan 정가를 보여준다.
- 추후 별도 upgrade offer가 만들어지면 그때 업그레이드 전용 offer를 처리한다.


---

## 5. 구현 대상 파일 조사

작업 전 아래 파일/구조를 먼저 찾는다.


- Google Play Billing / in_app_purchase 초기화 코드
- product id 상수 파일
- paywall screen
- subscription manager
- purchase service
- user entitlement / user status manager
- receipt / purchase verification flow
- Standard monthly / annual 상품 조회 코드


예상 후보:


lib/screens/paywall_screen.dart
lib/services/purchase_service.dart
lib/services/billing_service.dart
lib/managers/user_status_manager.dart
lib/constants/product_ids.dart
lib/services/subscription_service.dart


실제 파일명은 현재 코드베이스 기준으로 확인한다.

---

## 6. 데이터 모델 제안

앱 내부에서 Paywall에 넘길 수 있는 모델을 만든다.

예시:

dart
class StandardAnnualOfferViewModel {
  final String productId;
  final String basePlanPriceText;
  final String? launchOfferPriceText;
  final String? launchOfferToken;
  final bool hasLaunchOffer;
  final String renewalText;

  const StandardAnnualOfferViewModel({
    required this.productId,
    required this.basePlanPriceText,
    required this.launchOfferPriceText,
    required this.launchOfferToken,
    required this.hasLaunchOffer,
    required this.renewalText,
  });
}


중요:


hasLaunchOffer == true 인 경우에만 첫해 59,000원 UI를 표시한다.
launchOfferToken이 null이면 launch offer 결제를 시작하면 안 된다.


---

## 7. Offer 조회 로직

Google Play Billing에서 annual product를 조회한 뒤 다음 순서로 처리한다.

pseudo
productDetails = findProductDetails('3s_standard_annual')

annualBasePlan = productDetails.subscriptionOfferDetails
  .findRegularAnnualBasePlanOrDefault()

launchOffer = productDetails.subscriptionOfferDetails
  .firstWhere(
    offer.offerTags contains 'launch'
  )

if launchOffer exists:
  offerToken = launchOffer.offerToken
  launchPrice = first pricing phase formatted price
  renewalPrice = base plan pricing phase formatted price
else:
  offerToken = null
  launchPrice = null
  renewalPrice = productDetails.price or annual base plan price


주의:

* Billing 라이브러리 버전에 따라 `ProductDetails`, `SubscriptionOfferDetails`, `PricingPhase` 구조가 다를 수 있다.
* 현재 프로젝트가 Flutter `in_app_purchase` 패키지를 쓰는지, 직접 Play Billing wrapper를 쓰는지 확인한다.
* Flutter `in_app_purchase_android` 사용 시 GooglePlayProductDetails / GooglePlayPurchaseParam 등 Android 전용 객체가 필요할 수 있다.

---

## 8. 결제 시작 로직

### 8.1 launch offer 결제

launch offer가 있는 경우:

pseudo
startStandardAnnualLaunchPurchase() {
  final offer = findLaunchOffer(productId: '3s_standard_annual', tag: 'launch');

  if (offer == null || offer.offerToken == null) {
    fallbackToRegularAnnualPurchase();
    return;
  }

  startPurchase(
    productId: '3s_standard_annual',
    offerToken: offer.offerToken,
  );
}


### 8.2 정가 annual 결제

launch offer가 없는 경우:

pseudo
startStandardAnnualRegularPurchase() {
  startPurchase(
    productId: '3s_standard_annual',
    offerToken: null or regular base plan token depending on Billing API,
  );
}


주의:

* Android Billing v5+ 구독 결제에서는 offerToken이 필요할 수 있다.
* 정가 base plan에도 offerToken처럼 전달해야 하는 값이 있는지 현재 라이브러리 구현을 확인한다.
* launch offerToken과 base plan token을 혼동하지 말 것.

---

## 9. Flutter in_app_purchase 사용 시 구현 방향

현재 프로젝트가 Flutter `in_app_purchase` 및 `in_app_purchase_android`를 사용한다면 Android 전용 purchase param을 사용해야 할 수 있다.

개념 예시:

dart
final productDetails = ... // 3s_standard_annual
final googlePlayDetails = productDetails as GooglePlayProductDetails;

final offerDetails = googlePlayDetails.productDetails.subscriptionOfferDetails;

final launchOffer = offerDetails?.firstWhereOrNull(
  (offer) => offer.offerTags.contains('launch'),
);

final purchaseParam = GooglePlayPurchaseParam(
  productDetails: googlePlayDetails,
  offerToken: launchOffer?.offerToken,
);

await InAppPurchase.instance.buyNonConsumable(
  purchaseParam: purchaseParam,
);


주의:

* 실제 클래스명과 필드는 현재 사용 중인 패키지 버전에 맞춰 확인한다.
* `buyNonConsumable` / `buyConsumable` 중 현재 구독 구매에 사용 중인 메서드를 확인하고 기존 패턴을 유지한다.
* iOS와 공통 코드가 있다면 Android에서만 offerToken을 주입하고 iOS는 기존 흐름을 유지한다.

---

## 10. Paywall UI 요구사항

### 10.1 launch offer 있음


Standard 연간
첫해 {launchOfferPrice}/년
이후 {basePlanPrice}/년

출시 기념 첫해 혜택


예:


첫해 ₩59,000
이후 ₩69,000/년


### 10.2 launch offer 없음


Standard 연간
{basePlanPrice}/년


예:


연 ₩69,000


### 10.3 월간 상품

월간 상품은 기존 monthly product details를 그대로 사용한다.


월 {monthlyPrice}


예:


월 ₩6,900


또는 USD base인 경우 Store product details의 현지 가격 표시를 사용한다.

---

## 11. 가격 표시 원칙

가격은 절대 하드코딩하지 않는다.

금지:

dart
Text('첫해 ₩59,000')
Text('연 ₩69,000')
Text('월 ₩6,900')


허용:

dart
Text('첫해 ${offerPriceText}')
Text('이후 ${basePlanPriceText}/년')
Text('월 ${monthlyProduct.price}')


단, Store product details를 아직 불러오지 못한 loading 상태에서는 가격 영역에 skeleton/loading 표시를 사용한다.

---

## 12. 구매 검증 / 권한 부여

결제 완료 후 권한 부여는 기존 Standard annual 구독과 동일하게 처리한다.

구매 결과에서 확인해야 할 것:


- productId == 3s_standard_annual
- purchase status == purchased/restored
- purchase token valid
- server-side verification if currently implemented
- subscription active
- entitlement == Standard


중요:

* launch offer로 구매했는지 여부는 가격/프로모션 판정용이지, 권한은 동일한 Standard Annual이다.
* 첫해 할인으로 구매해도 사용자는 Standard 권한을 받아야 한다.
* 갱신 시 정가 annual로 갱신되어도 entitlement는 동일하다.

---

## 13. 실패 / 예외 처리

### 13.1 offer가 없음


상황:
- 사용자가 신규 고객이 아님
- Google Play가 offer eligibility를 만족하지 않는다고 판단
- Console 설정이 아직 배포되지 않음
- 앱 캐시 또는 Billing 응답 지연

처리:
- 첫해 혜택 UI 숨김
- 정가 annual 상품 표시
- launch offer 결제 버튼 비활성 또는 정가 결제로 fallback


### 13.2 offerToken 결제 실패


처리:
- 에러 로깅
- 사용자를 정가 결제로 즉시 보내지 말 것
- "혜택 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요." 표시


정가 fallback은 사용자가 명확히 이해할 수 있게 해야 한다.
첫해 59,000원을 눌렀는데 갑자기 69,000원 결제로 넘어가면 안 된다.

### 13.3 Store product details 미조회


처리:
- Paywall 가격 표시 loading
- 구매 버튼 disabled
- retry 제공


---

## 14. 테스트 요구사항

### 14.1 Unit tests


- annual product에서 launch tag offer를 찾는다.
- launch offer가 없으면 hasLaunchOffer=false가 된다.
- offerToken이 없으면 launch purchase를 시작하지 않는다.
- launch offer price와 base plan price를 분리해서 표시한다.
- 가격 문자열을 하드코딩하지 않는다.


### 14.2 Widget tests


- launch offer 있음: "첫해 {price}"와 "이후 {price}/년" 표시
- launch offer 없음: 정가 annual만 표시
- product loading 중: 구매 버튼 비활성
- product error 시: retry 표시


### 14.3 Manual QA

Google Play license tester로 확인:


1. 신규 테스트 계정으로 Paywall 진입
2. Standard annual에 첫해 launch offer가 표시되는지 확인
3. 결제 화면에서 첫해 가격이 59,000원으로 표시되는지 확인
4. 구매 완료 후 Standard 권한 부여 확인
5. 동일 계정으로 재진입 시 offer eligibility가 어떻게 표시되는지 확인
6. 이미 월간 구독한 계정에서 launch offer가 표시되지 않는지 확인
7. offerToken 없이 결제되는 경로가 없는지 로그 확인
8. 한국/미국 가격 표시가 Store product details와 일치하는지 확인


---

## 15. 로그 요구사항

디버그 로그에는 다음을 남긴다.


- queried product ids
- annual product found/not found
- number of subscriptionOfferDetails
- launch tag offer found/not found
- selected offerToken exists true/false
- displayed annual price 
- displayed launch price 
- purchase started with launch offer true/false


주의:

* purchase token, user id, payment token 등 민감 정보는 로그에 남기지 않는다.
* offerToken 자체도 운영 로그에는 남기지 않는 것이 안전하다. 존재 여부만 기록한다.

---

## 16. 완료 기준

완료 조건:


- `3s_standard_annual` product details를 정상 조회한다.
- annual subscriptionOfferDetails에서 `launch` tag offer를 찾는다.
- launch offer가 있으면 첫해 가격과 이후 갱신 가격을 분리 표시한다.
- launch offer 구매 시 해당 offerToken을 BillingFlowParams에 포함한다.
- launch offer가 없으면 첫해 혜택 UI를 숨기고 정가 annual만 표시한다.
- 가격은 Store product details의 formatted price를 사용한다.
- offerToken 없이 launch offer 결제가 시작되지 않는다.
- 구매 완료 후 기존 Standard annual entitlement가 정상 부여된다.
- iOS 결제 흐름은 깨지지 않는다.
- 테스트 계정으로 실제 Google Play 결제 화면에서 59,000원 첫해 가격이 표시됨을 확인한다.


---

## 17. 최종 원칙

첫해 혜택은 별도 일회성 상품이 아니다.


Standard annual subscription base plan
  + launch offer
  + offerToken purchase flow


앱은 Store가 내려준 offer만 표시하고, Store가 내려준 offerToken으로만 결제를 시작해야 한다.

가격 표시와 실제 결제 화면의 가격이 다르면 안 된다.



마지막으로, 지금 Console 화면에서는 **“구독한 적 없음” 선택이 맞습니다.**  
단, 월간 사용자를 연간으로 유도하는 할인은 이 offer로 해결하려고 하지 마세요. 그건 나중에 **업그레이드 전용 Offer**를 따로 만드는 게 맞습니다.


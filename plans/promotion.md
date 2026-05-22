좋습니다. 방향은 맞습니다.
다만 **앱 안에서 프로모션 코드를 직접 검증/적용하는 구조로 가면 안 됩니다.**

프로필 구독카드에 넣을 기능은 정확히 이렇게 정의해야 합니다.

> 사용자가 앱에 코드를 입력한다 → 앱이 Google Play redeem 화면으로 보낸다 → 사용자가 Play에서 코드 적용 → 앱 복귀 후 구독 상태를 다시 동기화한다.

즉, 앱은 `MOAWELCOME` 같은 코드를 자체 처리하지 않고, **Google Play 구독 상태만 최종 신뢰**해야 합니다.

아래 지시서를 그대로 개발 AI에게 주면 됩니다.

`md
# MOA Profile Subscription Card Promo Code Input Implementation Prompt

## 0. 목적

MOA 앱의 Profile 구독 카드에 Google Play 프로모션 코드 입력 기능을 추가한다.

현재 Google Play Console에 다음 프로모션 코드 캠페인이 생성되어 있다.

1. `moa-standard-1m-launch`
   - 목적: 출시 초기 체험용
   - 혜택: Standard 1개월 무료 체험
   - 대표 안내 코드: `MOAWELCOME`

2. `moa-standard-90d-friends`
   - 목적: 친구/친인척/핵심 피드백 유저용
   - 혜택: Standard 90일 무료 체험
   - 코드 형태: Google Play에서 생성한 프로모션 코드

이번 구현 목표는 앱 Profile 화면의 구독 카드에서 사용자가 프로모션 코드를 입력하고, Google Play 코드 등록 화면으로 이동한 뒤, 앱 복귀 시 Standard 구독 권한을 다시 동기화하는 것이다.

중요 원칙:

- 앱은 프로모션 코드를 자체 검증하지 않는다.
- 앱 서버나 Firestore에 프로모션 코드 문자열을 저장하지 않는다.
- 프로모션 코드 적용 여부는 Google Play 구독 상태로만 판단한다.
- 코드가 적용되면 Google Play active subscription으로 확인되어야 하며, 그 결과 Standard 권한을 부여한다.
- 앱은 `MOAWELCOME`, friends code 등을 별도 권한 시스템으로 처리하지 않는다.

---

## 1. 기능 위치

대상 화면:


Profile Screen
→ Subscription Card
→ Promo Code Input Section
`

예상 파일:


lib/screens/profile_screen.dart
lib/services/purchase_service.dart
lib/services/billing_service.dart
lib/services/subscription_service.dart
lib/managers/user_status_manager.dart


실제 파일명은 현재 프로젝트 기준으로 조사 후 적용한다.

---

## 2. UI 요구사항

Profile 구독 카드 하단에 작은 프로모션 코드 입력 섹션을 추가한다.

### 2.1 기본 UI


프로모션 코드가 있나요?

[ 코드 입력하기 ]

코드를 입력하면 Google Play 코드 등록 화면으로 이동합니다.


또는 공간이 충분하면:


프로모션 코드

[ MOAWELCOME 또는 받은 코드 입력 ]

[코드 사용하기]


### 2.2 입력 필드

입력 필드 조건:


- 대문자 자동 변환
- 앞뒤 공백 제거
- 중간 공백 제거 또는 사용자에게 안내
- 최소 길이 검증
- 특수문자 과도 입력 방지
- 비어 있으면 버튼 비활성화


예시:

dart
final normalizedCode = input.trim().replaceAll(' ', '').toUpperCase();


주의:

* Google Play one-time use code가 하이픈을 포함할 수 있다면 하이픈은 허용한다.
* `MOAWELCOME` 같은 custom code는 대문자로 처리해도 문제 없다.

허용 문자 예시:


A-Z
0-9
-


### 2.3 버튼

버튼명:


코드 사용하기


영문:


Redeem Code


버튼 클릭 시:


1. 입력값 normalize
2. Google Play redeem deep link 생성
3. 외부 브라우저 또는 Play Store로 이동
4. 앱 복귀 시 구독 상태 재동기화


---

## 3. Google Play Redeem Deep Link

Android에서는 입력된 코드를 사용하여 다음 URL을 연다.


https://play.google.com/redeem?code={PROMO_CODE}


예시:


https://play.google.com/redeem?code=MOAWELCOME


구현:

dart
final redeemUrl = Uri.parse(
  'https://play.google.com/redeem?code=$encodedCode',
);

await launchUrl(
  redeemUrl,
  mode: LaunchMode.externalApplication,
);


주의:

* `url_launcher` 또는 현재 프로젝트의 외부 URL 오픈 유틸을 사용한다.
* URL encoding을 반드시 적용한다.
* Android에서만 표시하거나 동작하게 한다.
* iOS에서는 Google Play promo code를 사용할 수 없으므로 해당 섹션을 숨기거나 “Android에서만 사용 가능”으로 처리한다.

---

## 4. 앱 복귀 후 구독 동기화

사용자가 Google Play redeem 화면에서 코드를 등록하고 앱으로 돌아왔을 때, 앱은 구독 상태를 다시 조회해야 한다.

동기화 시점:


1. 앱 resume
2. Profile 화면 재진입
3. 코드 사용하기 버튼 클릭 후 앱으로 돌아온 경우
4. 사용자가 “구매 복원” 버튼을 누른 경우


구현 흐름:

pseudo
onAppResume() {
  if (promoRedeemFlowStartedRecently) {
    syncSubscriptionEntitlement()
    promoRedeemFlowStartedRecently = false
  }
}


또는 Profile 화면에서:

pseudo
onProfileScreenVisible() {
  billingService.syncActivePurchases()
  userStatusManager.refresh()
}


권장:

* 코드 사용 버튼 클릭 시 `promoRedeemPending = true`로 저장
* 앱 resume 시 `promoRedeemPending == true`면 구독 상태 재조회
* 성공/실패 결과를 사용자에게 안내

---

## 5. 구독 권한 동기화 로직

Promo code는 Google Play에서 active subscription으로 반영된다.

권한 판정:


Standard active if:
- active Google Play subscription exists for Standard_monthly
OR
- active Google Play subscription exists for Standard_annual


상품 ID 후보:


3s_standard_monthly
3s_standard_annual


또는 현재 코드베이스의 실제 product id 상수를 사용한다.

권한 적용:

pseudo
syncSubscriptionEntitlement() async {
  await billingService.initializeIfNeeded();

  final purchases = await billingService.queryActivePurchases();

  final entitlement = entitlementResolver.resolveStandardEntitlement(
    purchases,
    standardProductIds: [
      standardMonthlyProductId,
      standardAnnualProductId,
    ],
  );

  await userStatusManager.applyEntitlement(entitlement);

  await cloudService.refreshCloudAccessState();

  return entitlement;
}


Promo code로 등록했는지 여부를 따로 구분하지 않는다.

---

## 6. 사용자 안내 문구

### 6.1 입력 전 안내


Google Play 프로모션 코드를 입력하면 코드 등록 화면으로 이동합니다.
코드 적용 후 앱으로 돌아오면 구독 상태가 자동으로 갱신됩니다.


### 6.2 코드 등록 후 앱 복귀 시

동기화 성공:


Standard 구독이 활성화되었습니다.
이제 Cloud 백업, 편집 기능, 1080p 내보내기를 사용할 수 있습니다.


동기화 실패:


아직 활성 구독을 확인하지 못했습니다.
Google Play에서 코드 적용을 완료했는지 확인한 뒤 다시 시도해 주세요.


수동 버튼:


구매 복원


복원 성공:


구독 정보가 복원되었습니다.


복원 실패:


활성 구독을 찾을 수 없습니다.


---

## 7. Profile 구독 카드 상태별 UI

### 7.1 Free 사용자

표시:


현재 플랜: Free

Standard로 업그레이드하면 Cloud 백업, 편집 기능, 1080p 내보내기를 사용할 수 있습니다.

[Standard 보기]
[프로모션 코드 입력]


### 7.2 Standard 사용자

표시:


현재 플랜: Standard
갱신 또는 만료 예정일: {date}

[구독 관리]
[구매 복원]


Standard 사용자는 이미 활성 구독이 있으므로 프로모션 코드 입력 섹션은 숨기거나 접힌 상태로 둔다.

추천:


이미 Standard를 사용 중이면 프로모션 코드 입력을 기본 숨김 처리


### 7.3 Expired / Grace 사용자

표시:


구독이 만료되었습니다.
유예 기간 동안 기존 Cloud 데이터를 복원할 수 있습니다.

[구독 다시 시작]
[프로모션 코드 입력]
[구매 복원]


---

## 8. iOS / 비Android 처리

이 기능은 Google Play 프로모션 코드용이다.

iOS에서는 다음 중 하나로 처리한다.

권장:


iOS에서는 이 섹션을 숨긴다.


또는:


프로모션 코드는 Android Google Play에서만 사용할 수 있습니다.


주의:

* iOS App Store offer code는 별도 구조이므로 이번 작업 범위에 포함하지 않는다.
* iOS 결제 흐름을 건드리지 않는다.

---

## 9. 코드 입력 검증

앱에서 하는 검증은 “형식 검증”까지만 한다.

해야 하는 것:


- 빈 값 차단
- 너무 짧은 값 차단
- 너무 긴 값 차단
- 허용 문자 외 입력 차단
- 대문자 normalize


하지 말아야 하는 것:


- MOAWELCOME인지 직접 검증
- friends code인지 직접 검증
- Firestore에서 코드 목록 조회
- 앱 서버에서 코드 사용 처리
- 코드별 Standard 권한 직접 부여


최종 유효성은 Google Play가 판단한다.

---

## 10. 보안 / 개인정보 / 로그

로그에 남겨도 되는 것:


- promo redeem button clicked
- normalized code length
- redeem URL launch success/fail
- subscription sync started
- standard entitlement active true/false


로그에 남기면 안 되는 것:


- 프로모션 코드 원문
- purchase token 원문
- order id 원문
- 이메일 원문
- Firebase UID 원문


주의:

* 친구용 one-time code는 유출되면 1회 사용될 수 있으므로 앱 로그에 원문을 남기지 않는다.
* `MOAWELCOME`도 운영 로그에 굳이 남기지 않는다.

---

## 11. 예외 처리

### 11.1 Play Store URL 열기 실패

문구:


Google Play 코드 등록 화면을 열 수 없습니다.
Play Store 앱에서 직접 코드를 등록해 주세요.


보조 안내:


Google Play Store → 프로필 → 결제 및 정기 결제 → 코드 사용


### 11.2 코드 적용 후 권한 미반영

문구:


구독 정보가 아직 반영되지 않았습니다.
잠시 후 구매 복원을 눌러 다시 확인해 주세요.


### 11.3 이미 사용된 코드

앱이 직접 알 수 없다. Google Play에서 안내한다.

앱 문구:


코드 적용 여부는 Google Play 화면에서 확인해 주세요.


### 11.4 사용 불가능한 코드

앱이 직접 알 수 없다. Google Play에서 안내한다.

앱 문구:


코드가 적용되지 않았다면 코드가 만료되었거나 이미 사용되었을 수 있습니다.


---

## 12. 테스트 요구사항

### 12.1 MOAWELCOME 1개월 코드 테스트


1. Free 테스트 계정으로 앱 실행
2. Profile 구독 카드 진입
3. 프로모션 코드 입력에 MOAWELCOME 입력
4. 코드 사용하기 클릭
5. Google Play redeem 화면 열림 확인
6. 코드 적용
7. 앱 복귀
8. 구독 상태 sync 실행 확인
9. Standard 권한 활성화 확인
10. Cloud 50GB 표시 확인
11. 편집화면 접근 가능 확인
12. 1080p 내보내기 가능 확인


### 12.2 90일 friends one-time code 테스트


1. Google Play Console에서 moa-standard-90d-friends 코드 1개 확보
2. Free 테스트 계정으로 앱 실행
3. Profile 구독 카드에서 해당 코드 입력
4. Google Play redeem 화면 이동 확인
5. 코드 적용
6. 앱 복귀
7. Standard 권한 활성화 확인
8. 만료/갱신 예정일 확인


### 12.3 앱 밖 redeem 테스트


1. Play Store에서 직접 코드 등록
2. 앱 실행
3. 앱 시작 동기화 또는 구매 복원 실행
4. Standard 권한 활성화 확인


### 12.4 잘못된 코드 테스트


1. 임의의 잘못된 코드 입력
2. Google Play에서 오류 안내 확인
3. 앱 복귀 후 Standard 권한이 부여되지 않는지 확인


### 12.5 이미 Standard 사용자인 경우


1. Standard 활성 계정으로 Profile 진입
2. 프로모션 코드 입력 섹션이 숨김 또는 보조 위치에 있는지 확인
3. 기존 Standard 권한에 영향 없는지 확인


---

## 13. 완료 기준

완료 조건:


- Profile 구독 카드에서 프로모션 코드 입력 UI가 표시된다.
- 입력한 코드를 Google Play redeem deep link로 전달한다.
- Android에서 Play Store/Google Play redeem 화면이 열린다.
- iOS에서는 해당 기능이 숨김 또는 비활성 처리된다.
- 앱 복귀 후 active subscription sync가 실행된다.
- Promo code 적용 후 Standard 권한이 정상 부여된다.
- Promo code 적용 실패 시 Standard 권한이 부여되지 않는다.
- 구매 복원 버튼으로 앱 밖 redeem 상태도 반영된다.
- 프로모션 코드 원문, purchase token, order id가 로그에 남지 않는다.
- `MOAWELCOME` 1개월 코드와 `moa-standard-90d-friends` one-time code가 실제 테스트 계정에서 검증된다.


---

## 14. 최종 원칙

프로모션 코드 입력 기능은 자체 쿠폰 시스템이 아니다.


앱 코드 입력
→ Google Play redeem 화면 이동
→ Google Play가 코드 검증
→ active subscription 생성
→ MOA가 구독 상태 sync
→ Standard 권한 부여


앱이 믿어야 하는 것은 사용자가 입력한 코드 문자열이 아니라 Google Play에서 확인되는 active Standard subscription 상태다.



주의할 점 하나만 더 말하면, **프로필 카드에 코드 입력창을 넣는 건 괜찮지만, 실제 검증은 절대 앱에서 하지 마세요.**  
앱은 Google Play redeem 화면으로 보내고, 돌아왔을 때 active subscription만 확인하면 됩니다.


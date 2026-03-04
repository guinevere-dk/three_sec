# Subscription Auto-Downgrade QA Checklist (KST)

## 정책 요약
- 기준: `purchaseDate + 주기(monthly/annual)`를 만료시각으로 계산
- 강등 시각: 만료 **다음날 00:00 (KST)** 이후
- 동기화: 로컬 강등 시 Firestore `subscriptionTier=free` 정합화

## 시나리오

### 1) 만료 직전 (강등되면 안 됨)
1. 테스트 계정에 월간 또는 연간 구독 상태를 세팅한다.
2. 현재 시각을 `autoDowngradeAt` 직전으로 맞춘다.
3. 앱 시작, 로그인 동기화, 프로필 진입/새로고침을 각각 수행한다.
4. 기대 결과:
   - `currentTier` 유지 (`standard`/`premium`)
   - Cloud/편집 권한 유지
   - Firestore tier 변경 없음

### 2) 만료 당일 (강등되면 안 됨)
1. 만료시각이 지난 상태이되, KST 기준 다음날 00:00 이전으로 맞춘다.
2. 앱 시작, 로그인 동기화, 프로필 진입/새로고침을 각각 수행한다.
3. 기대 결과:
   - 아직 Free 강등되지 않음
   - `evaluateAndAutoDowngradeIfExpired` 로그에 `shouldDowngrade=false`

### 3) 만료 다음날 00:00 이후 (강등되어야 함)
1. 현재 시각을 `autoDowngradeAt` 이후로 맞춘다.
2. 앱 시작 또는 프로필 진입/새로고침을 수행한다.
3. 기대 결과:
   - 로컬 `currentTier=free`
   - Cloud/편집 권한 제한 반영
   - Firestore `subscriptionTier=free`, `productId=null`, `purchaseDate=null`

### 4) 복원/재구매
1. 강등 후 스토어에서 복원 또는 재구매를 수행한다.
2. 기대 결과:
   - IAP 처리 후 tier가 다시 상향 반영
   - Firestore가 상향 등급으로 다시 동기화

### 5) 경계조건
- `productId` 미식별: 월간 fallback으로 계산되는지 확인
- `purchaseDate` 누락: 강등 스킵 및 안전 로그 확인
- 오프라인: 로컬 강등은 수행, Firestore 정합화는 실패해도 앱 동작 유지


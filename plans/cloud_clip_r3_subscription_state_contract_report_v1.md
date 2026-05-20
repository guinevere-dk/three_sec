# Cloud Clip R3 구독 상태 판단 계약 조사 보고서 v1

## 0. 조사 범위

본 문서는 R3 구독 만료 Cloud 접근 정책 구현 전, 현재 앱이 Cloud 접근 권한을 어떤 상태값과 레이어에서 판단하는지 정리한다.

금지 범위:

- 코드 변경 없음.
- Firebase rules/index 변경 없음.
- migration/backfill 없음.
- Storage 삭제 없음.
- Cloud copy 구현 없음.
- deploy 없음.

조사 기준 파일:

- [AGENTS.md](../AGENTS.md)
- [CURRENT_PHASE.md](../CURRENT_PHASE.md)
- [DATA_COMPATIBILITY.md](../DATA_COMPATIBILITY.md)
- [plans/cloud_clip_r3_subscription_expiry_implementation_plan_v1.md](cloud_clip_r3_subscription_expiry_implementation_plan_v1.md)
- [lib/managers/user_status_manager.dart](../lib/managers/user_status_manager.dart)
- [lib/services/auth_service.dart](../lib/services/auth_service.dart)
- [lib/services/iap_service.dart](../lib/services/iap_service.dart)
- [lib/services/cloud_service.dart](../lib/services/cloud_service.dart)
- [lib/managers/video_manager.dart](../lib/managers/video_manager.dart)
- [lib/screens/cloud_backup_screen.dart](../lib/screens/cloud_backup_screen.dart)
- [lib/screens/library_screen.dart](../lib/screens/library_screen.dart)
- [lib/screens/profile_screen.dart](../lib/screens/profile_screen.dart)
- [lib/screens/subscription_management_screen.dart](../lib/screens/subscription_management_screen.dart)
- [lib/screens/paywall_screen.dart](../lib/screens/paywall_screen.dart)

## 1. Current subscription source of truth

현재 앱에는 단일 원격 source of truth 하나만 있는 구조가 아니다. 구독 권한은 다음 입력들이 순서와 상황에 따라 합쳐진다.

| 레이어 | 역할 | 현재 계약 |
|---|---|---|
| Store/IAP purchase stream | 구매/복원 이벤트 원천 | `IAPService`가 `PurchaseDetails`를 받고 서버 검증을 수행한다. |
| IAP server verification result | 유효/활성 entitlement 판정 | `IapServerVerificationResult.valid`와 `active`가 true일 때만 로컬 tier를 반영한다. |
| `UserStatusManager` | 앱 런타임의 실질 권한 source | CloudService와 UI 대부분은 `UserStatusManager.currentTier`, `isStandardOrAbove()`, R3 helper를 읽는다. |
| SharedPreferences | 로컬 캐시와 앱 재시작 복구 | `3s_user_tier`, `3s_purchase_date`, `3s_product_id`, `3s_user_id`, pending tier key를 저장한다. |
| Firestore `users/{uid}` | 로그인 후 서버 동기화 입력/백업 | `AuthService`가 `subscriptionTier`, `productId`, `purchaseDate`, pending tier fields를 읽고 로컬에 반영한다. |

실제 Cloud 접근 분기의 현재 중심은 `UserStatusManager`다. Firestore `users/{uid}`는 로그인/수동 refresh/구매 후 동기화에 사용되지만, CloudService가 매번 Firestore user profile을 조회해 권한을 판단하지는 않는다.

현재 결론:

- Store/IAP 검증 결과가 가장 강한 entitlement 입력이다.
- Firestore `users/{uid}`는 로그인 시 로컬 상태를 복원/정합화하는 원격 캐시다.
- Cloud 접근 실행 시점의 직접 판정은 `UserStatusManager` 로컬 상태다.

## 2. Current cached/local state

`UserStatusManager`는 singleton이며 SharedPreferences를 로컬 캐시로 사용한다.

| key | 의미 | R3 관련성 |
|---|---|---|
| `3s_user_tier` | 현재 local tier | Standard/Premium 여부 판단의 기본값 |
| `3s_purchase_date` | 구매 또는 검증된 transaction 기준 시각 | 만료 추정과 grace 계산 기준 |
| `3s_product_id` | 구매 product id | 월간/연간 만료 기간 추정 기준 |
| `3s_user_id` | Firebase uid | 사용자 전환 시 로컬 tier 보존 여부 판단 |
| `3s_next_user_tier` | 예약된 다음 tier | 해지/다운그레이드 예약 UI와 상태 표시 |
| `3s_next_tier_effective_at` | 예약 tier 적용 시각 | 해지 후 만료 시점 안내 |

현재 helper:

| helper | 의미 |
|---|---|
| `currentTier` | 현재 로컬 tier |
| `isStandardOrAbove()` | 기존 Cloud 가능 tier 판정의 기본 helper |
| `estimatedExpiryAt` | 현재 유료 tier의 `purchaseDate + productId cycle` 기반 추정 만료 시각 |
| `lastKnownPaidExpiryAt` | Free로 강등된 뒤에도 남아 있는 purchase/product 기반 만료 시각 |
| `cloudReadGraceEndsAt` | `lastKnownPaidExpiryAt + 30일` |
| `canStartNewCloudWrite()` | 신규 Cloud upload/copy 가능 여부 |
| `canReadExistingCloudClips()` | 기존 Cloud list/read/download 가능 여부 |
| `isInCloudReadGrace()` | Free 상태에서 grace read-only UI 표시 여부 |

주의점:

- `resetToFree()`는 `3s_purchase_date`, `3s_product_id`를 제거한다.
- `_downgradeExpiredSubscriptionToFree()`는 R3 grace 판단을 위해 tier만 free로 낮추고 purchase/product는 보존한다.
- `syncFreeTierToFirestore()`는 Firestore의 `purchaseDate`, `productId`를 null로 정합화한다. 이후 다른 기기/재로그인에서 grace 복원이 필요한지 별도 정책 판단이 필요하다.

## 3. Firestore user profile fields involved

`AuthService`는 `users/{uid}` 문서에서 canonical 필드와 legacy snake_case 필드를 모두 읽는다.

| Firestore field | legacy field | 의미 |
|---|---|---|
| `subscriptionTier` | `subscription_tier` | `free`, `standard`, `premium` |
| `productId` | `product_id` | IAP product id |
| `purchaseDate` | `purchase_date` | 구매/transaction 시각 milliseconds 또는 Timestamp |
| `nextTier` | `next_tier` | 예약 변경 tier |
| `nextProductId` | `next_product_id` | 예약 변경 product id |
| `nextTierEffectiveAt` | `next_tier_effective_at` | 예약 변경 적용 시각 |
| `updatedAt` | `updated_at` | 동기화 시각 |
| `subscriptionDowngradeReason` | `subscription_change_reason` 등 | 자동/수동 downgrade 사유 |

동기화 흐름:

- 로그인 성공 후 `AuthService._onSignInSuccess()`가 `UserStatusManager.setUserId(uid)` 후 Firestore에서 구독 상태를 동기화한다.
- Firestore tier가 `free`이면 기본적으로 `UserStatusManager.resetToFree()`로 로컬을 free 정합화한다.
- 단, 결제 직후 Firestore 반영 지연을 고려해 `preserveLocalPaidTier` 옵션이 true이고 로컬이 paid이면 일시적으로 로컬 paid tier를 보존할 수 있다.
- paid tier를 읽으면 `UserStatusManager.setTier(tier, productId, purchaseDate)`로 로컬 cache를 갱신한다.
- 이후 canonical camelCase 필드를 Firestore에 merge해 snake_case와 정합성을 맞춘다.
- 로컬 만료 평가에서 자동 강등되면 `syncFreeTierToFirestore()`를 호출해 Firestore도 free로 정합화한다.

R3 관점의 핵심 리스크:

- Firestore free 정합화는 원격 `purchaseDate/productId`를 null로 만들기 때문에, 다른 기기 또는 재로그인 후 grace 근거가 사라질 수 있다.
- migration/backfill 없이 R3를 구현하려면 grace는 현재 기기의 보존된 SharedPreferences를 우선 사용하고, Firestore 기반 cross-device grace는 별도 정책으로 보류하는 것이 안전하다.

## 4. IAP/restore purchase flow involved

IAP 관련 흐름은 `IAPService`가 담당한다.

주요 product id:

- `3s_standard_monthly`
- `3s_standard_annual`
- `3s_premium_monthly`
- `3s_premium_annual`

구매/복원 흐름:

1. `IAPService.initialize()`가 purchase stream을 구독한다.
2. purchase stream에서 `purchased` 또는 `restored` 상태가 오면 `_verifyPurchase()`로 서버 검증을 수행한다.
3. 검증 결과가 `valid && active`이면 `_deliverProduct()` → `_applyActiveSubscriptionToUserStatus()`로 이어진다.
4. `_applyActiveSubscriptionToUserStatus()`는 product id로 `UserTier.standard` 또는 `UserTier.premium`을 결정한다.
5. `UserStatusManager.setTier()`로 로컬 SharedPreferences와 메모리 상태를 갱신한다.
6. `AuthService.syncSubscriptionToFirestore()`가 `users/{uid}`에 tier/product/purchaseDate를 merge한다.
7. `UserStatusManager.initialize()`로 저장 결과를 다시 로드한다.

복원 흐름:

- `restorePurchases()` 이후 Android에서는 `queryPastPurchases()` 기반 `_retryRestoreVerificationFromStore()`가 과거 구매를 찾아 다시 검증한다.
- 검증된 restore purchase도 동일하게 `_deliverProduct()`를 거쳐 로컬 tier와 Firestore를 갱신한다.

해지/만료 관련 흐름:

- `syncCancellationStateFromStore()`는 Google Play의 `isAutoRenewing`을 확인한다.
- auto-renew off이면 즉시 free로 낮추지 않고 `nextTier=free`, `nextTierEffectiveAt=estimatedExpiryAt` 예약을 저장한다.
- 실제 자동 free 강등은 `UserStatusManager.evaluateAndAutoDowngradeIfExpired()`에서 KST 기준 만료 다음날 00:00 이후 처리한다.
- terminal inactive status(`EXPIRED`, `CANCELLED`, `REVOKED`, `REFUNDED`, `CHARGEBACK` 등)가 검증 결과로 오면 `_applyInactiveSubscriptionToFree()`가 `resetToFree()`와 `syncFreeTierToFirestore()`를 수행한다.

R3 주의점:

- inactive purchase 처리의 `resetToFree()`는 purchase/product를 제거하므로 grace 근거가 사라진다.
- 자동 만료 강등 경로는 purchase/product를 보존하지만, IAP inactive 경로는 보존하지 않는다.
- R3 구현 전 어느 만료 경로에서 grace를 인정할지 정책 결정이 필요하다.

## 5. Cloud upload gating points

현재 신규 Cloud write는 `CloudService`에서 집중적으로 gate된다.

| 위치 | 현재 gate | 상태값 |
|---|---|---|
| `CloudService.uploadVideo()` | `_ensureNotGuestForCloud()` → `_getCurrentUserId()` → `_checkStandardOrAbove()` → `_canStartNewCloudWrite()` → `_checkStorageLimit()` | auth, `currentTier`, `canStartNewCloudWrite()`, `storageUsage` |
| `CloudService.uploadVideoImmediate()` | guest/auth/tier/write gate 후 Firestore metadata create 및 Storage upload | auth, `currentTier`, `canStartNewCloudWrite()` |
| `CloudService._processUploadQueue()` | queue 처리 전 `_canStartNewCloudWrite()` | `canStartNewCloudWrite()` |
| `CloudService._executeUpload()` | 실제 upload 직전 `_canStartNewCloudWrite()` 재확인 | `canStartNewCloudWrite()` |
| `CloudService.enqueuePendingLocalUploads()` | auto upload 시작 전 `_canStartNewCloudWrite()` | `canStartNewCloudWrite()` |
| `VideoManager._enqueueAutoCloudUploadAfterLocalSave()` | 최종 upload는 `CloudService.uploadVideo()`에 위임 | CloudService gate 재사용 |
| `LibraryScreen._moveSelectedLocalToCloudInBackground()` | `uploadVideoImmediate()` 결과와 error code/copy를 UI에 표시 | CloudService gate 재사용 |

현재 upload gate는 R3 구현 위치로 적절하다. Storage upload 또는 Firestore metadata create 전에 차단되는 경로가 있어야 하며, 이 책임은 `CloudService`에 두는 것이 맞다.

주의:

- `uploadVideo()`는 queued metadata를 먼저 만들기 전에 `_canStartNewCloudWrite()`를 확인한다.
- `uploadVideoImmediate()`도 metadata create 전에 확인한다.
- queue는 생성 후 만료될 수 있으므로 `_processUploadQueue()`와 `_executeUpload()`의 재확인이 필요하다.

## 6. Cloud read/download/restore gating points

기존 Cloud clip read/download는 현재 일부 경로에서 `canReadExistingCloudClips()`를 사용하고, 일부 metadata update 경로는 guest/auth/owner만 확인한다.

| 위치 | 현재 gate | R3 판단 |
|---|---|---|
| `CloudService.getCompletedUserVideos()` | guest/auth + `_canReadExistingCloudClips()` | Cloud 보관함/placeholder read gate로 적절 |
| `CloudService.downloadVideo()` | guest/auth + `_canReadExistingCloudClips()` + doc uid + storagePath prefix 검증 | grace download/restore gate로 적절 |
| `VideoManager.syncCloudMetadataToLibrary()` | `AuthService.isGuest`와 `UserStatusManager.canReadExistingCloudClips()` | Library placeholder pull gate로 적절 |
| `VideoManager._mergeCloudOnlyPlaceholdersForCurrentAlbum()` | `canReadExistingCloudClips()` | album placeholder 표시 gate로 적절 |
| `CloudBackupScreen._isAllowed` | not guest + `canReadExistingCloudClips()` | Cloud 보관함 UI gate로 적절 |
| `LibraryScreen._removeSelectedCloudBackupInBackground()` | placeholder면 `downloadVideo()` 호출 | 최종 download gate는 CloudService가 담당 |
| `CloudService.getUserVideos()` stream | guest/auth only, read grace gate 없음 | R3 적용 시 검토 필요 |
| `CloudService.findUserVideoByLocalPath()` | guest/auth only, read grace gate 없음 | Trash/metadata update 보조 조회라 정책 구분 필요 |
| `CloudService.getUserVlogProjectMetadataMap()` | guest/auth only | Vlog project metadata는 R3 Cloud clip read 정책과 별도인지 결정 필요 |

R3 구현을 단순하게 유지하려면 사용자에게 Cloud clip을 노출하거나 다운로드하는 경로는 `canReadExistingCloudClips()`로 통일한다. 내부 metadata update 보조 조회는 지나치게 막으면 trash/restore 정합성이 깨질 수 있으므로 read-only grace와 별도 write policy를 나누는 것이 좋다.

## 7. Trash/restore implications

현재 trash/restore는 삭제보다 metadata tombstone/active 전환 중심이다.

| 흐름 | 현재 동작 | R3 영향 |
|---|---|---|
| `VideoManager.moveClipToTrash()` cloud-only placeholder | local placeholder를 휴지통 placeholder로 이동하고 `CloudService.markVideoInTrash()` 호출 | Firestore metadata write가 발생한다. 만료 후에도 허용할지 정책 필요 |
| local cloud-synced clip trash | 로컬 파일을 휴지통으로 이동하고 `markVideoInTrashByLocalPath()` 호출 | metadata write 발생 |
| `VideoManager.restoreClip()` cloud-only placeholder | placeholder를 원래 album으로 되돌리고 `CloudService.restoreVideoFromTrash()` 호출 | metadata write 발생 |
| `CloudService.deleteVideo()` | 실제 Storage 삭제가 아니라 `lifecycleState/cloudState=trash` set | R3 삭제 금지에는 부합하지만 write성 작업 |
| `CloudBackupScreen._downloadSelected()` | `downloadVideo()` 후 `registerCloudRestoredClip()` 및 metadata update | grace 중 read/download로 볼 수 있으나 `markVideoMovedToAlbum()` write가 뒤따를 수 있음 |

중요한 정책 분기:

- R3 목표는 "기존 Cloud clip은 grace 기간 동안 read/download만 허용"이다.
- 그런데 현재 restore 구현은 로컬 파일 생성 후 `markVideoMovedToAlbum()` 같은 metadata write를 수행할 수 있다.
- 엄밀한 read-only grace를 적용하려면 grace 중 restore 후 Cloud metadata write를 생략하거나, "복원 기록/album localPath update는 허용되는 보존성 metadata write"로 예외 정의해야 한다.

권장:

- R3 v1에서는 Storage 삭제는 하지 않는다.
- grace 중 사용자 가치를 위해 download/restore는 허용하되, Cloud metadata lifecycle 변경은 최소화한다.
- trash/restore metadata write는 active paid 상태에서만 허용하거나, grace 중에는 로컬 복원만 하고 Cloud metadata는 보존하는 분리를 검토한다.
- 계정 삭제 purge 흐름은 R3와 무관하게 별도 R2/R7 승인 대상으로 유지한다.

## 8. Recommended helper/API contract

helper는 `UserStatusManager`에 두고, 실행 gate는 `CloudService`에 둔다.

권장 API:

```dart
enum CloudAccessOperation {
  upload,
  copy,
  listExisting,
  downloadExisting,
  restoreExisting,
  metadataMove,
  trash,
  storageUsage,
}

class CloudAccessDecision {
  final bool allowed;
  final String reasonCode;
  final String userMessage;
  final DateTime? expiryAt;
  final DateTime? graceEndsAt;
  final bool readOnlyGrace;
}
```

최소 구현안:

| helper | 위치 | 의미 |
|---|---|---|
| `canStartNewCloudWrite({DateTime? now})` | `UserStatusManager` | 신규 upload/copy/auto upload 차단 |
| `canReadExistingCloudClips({DateTime? now})` | `UserStatusManager` | list/download/restore 허용 |
| `isInCloudReadGrace({DateTime? now})` | `UserStatusManager` | UI read-only 배너 |
| `cloudReadGraceEndsAt` | `UserStatusManager` | grace 종료 표시 |
| `_canStartNewCloudWrite(operation)` | `CloudService` | metric/error copy 포함 실행 gate |
| `_canReadExistingCloudClips(operation)` | `CloudService` | metric/error copy 포함 실행 gate |

레이어 책임:

- `UserStatusManager`: 구독 상태 계산만 담당한다.
- `CloudService`: Cloud 작업별 allow/deny와 error code/copy를 담당한다.
- UI: helper를 직접 쓰더라도 최종 권한은 CloudService 결과를 신뢰한다.
- `AuthService`: Firestore user profile 동기화만 담당한다.
- `IAPService`: 검증된 purchase/restore 결과를 `UserStatusManager`와 Firestore에 반영한다.

추천 reason code:

- `guest_mode`
- `auth_required`
- `tier_required`
- `subscription_expired`
- `subscription_expired_or_grace_ended`
- `subscription_state_unknown`
- `storage_limit_exceeded`

## 9. Edge cases

| Edge case | 현재 위험 | 권장 처리 |
|---|---|---|
| Firestore free가 먼저 내려오지만 결제 직후 로컬 paid | 즉시 free 강등으로 구매 직후 Cloud 차단 가능 | 기존 `preserveLocalPaidTier` 유지 |
| Firestore user doc 없음 | 신규 사용자로 보고 free 정합화 가능 | 동일 uid 재로그인 시 preserveLocalOnFailure 유지 |
| Store inactive result | `resetToFree()`가 purchase/product를 제거해 grace 불가 | R3에서 inactive 만료와 환불/취소를 구분할지 결정 필요 |
| 자동 만료 downgrade | purchase/product 보존됨 | R3 grace 계산에 적합 |
| 다른 기기에서 grace 필요 | Firestore free 정합화 후 purchase/product null이면 grace 근거 없음 | cross-device grace는 R3 v1 범위 밖 또는 별도 remote field 필요 |
| product id 미상 | 만료 cycle 추정 불가 | 보수적으로 월간 또는 차단. 현재 코드는 미식별 상품을 월간으로 간주 |
| pending downgrade | `nextTier=free`만으로 즉시 Cloud 차단하면 안 됨 | effectiveAt 전에는 현재 tier 유지 |
| grace 중 restore | 로컬 복원은 read/download지만 metadata write가 뒤따를 수 있음 | metadata write 예외 여부 결정 필요 |
| Profile Cloud stats | 현재 `isStandardOrAbove()` 기준이라 grace 중 `-`/미지원 표시 가능 | grace read-only UX와 맞추려면 `canReadExistingCloudClips()` 기준 검토 |
| `getUserVideos()` stream | read grace gate 없음 | 노출 경로가 있다면 gate 추가 검토 |
| Storage usage limit | `currentTier` 기준 limit 계산 | grace 중 신규 write 차단이 우선이므로 usage limit 계산은 upload gate 뒤에서만 의미 있음 |
| guest mode | Cloud 전체 차단 | 유지 |
| Cloud copy | 현재 cloud-only copy skip/local-only 정책 | R3에서 구현 금지 |
| purgeCurrentUserCloudData | 계정 삭제 흐름의 실제 삭제 가능성 | R3 범위 밖, 별도 승인/dry-run 필요 |

## 10. Implementation go/no-go verdict

판정: 조건부 GO.

구현 가능 근거:

- 현재 앱은 이미 `UserStatusManager`를 중심으로 Cloud 권한을 판단하는 구조다.
- `CloudService`에 upload/read gate가 집중되어 있어 신규 Cloud write 차단과 기존 Cloud read/download grace 적용 위치가 명확하다.
- `AuthService`와 `IAPService`는 구매/복원/Firestore 동기화 책임이 분리되어 있어, R3 helper를 추가해도 Firebase rules/index나 migration이 필요하지 않다.
- Storage path, collection name, SharedPreferences key, IAP product id를 바꾸지 않아도 구현 가능하다.

GO 전 결정 필요:

1. grace 기준은 로컬 SharedPreferences purchase/product만 사용할지, Firestore free 이후 cross-device grace도 지원할지.
2. IAP inactive result에서 `resetToFree()`로 purchase/product를 지우는 경로에 grace를 부여할지.
3. grace 중 restore 후 Cloud metadata write를 허용할지, 로컬 복원만 하고 Cloud metadata는 보존할지.
4. Profile Cloud stats와 Cloud 보관함 진입 기준을 `isStandardOrAbove()`에서 `canReadExistingCloudClips()`로 맞출지.

NO-GO 조건:

- Firebase rules/index 변경이 필요하다는 전제가 생기는 경우.
- Storage object 삭제 또는 purge를 R3에 포함하려는 경우.
- Firestore schema migration/backfill 없이는 grace를 지원할 수 없다고 판단하는 경우.
- Cloud copy 구현을 R3에 포함하려는 경우.
- 구독 만료 시 기존 Cloud metadata/object를 삭제하거나 초기화하려는 경우.

최종 권장:

- R3 helper는 `UserStatusManager`에 둔다.
- Cloud 실행 gate는 `CloudService`에 둔다.
- UI는 안내와 버튼 노출에만 helper를 사용하고, 실제 권한은 CloudService 결과를 최종으로 본다.
- R3 v1은 로컬 캐시 기반 grace로 제한하고, cross-device grace나 server-side entitlement field는 별도 계획으로 분리한다.

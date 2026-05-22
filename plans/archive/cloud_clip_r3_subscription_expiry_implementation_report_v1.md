# Cloud Clip R3 구독 만료 Cloud 접근 정책 구현 보고서 v1

## 1. 구현 범위와 결론

R3 v1 구독 만료 Cloud 접근 정책을 Flutter 클라이언트 중심으로 구현했다.

확정 정책 반영:

- R3 v1 grace는 로컬 SharedPreferences의 `3s_purchase_date`, `3s_product_id` 기반으로만 계산한다.
- cross-device grace는 구현하지 않았다.
- 신규 Cloud write는 active Standard/Premium에서만 허용한다.
- expired/free grace 상태에서도 upload, auto upload, queue upload, copy는 차단한다.
- 기존 Cloud clip list/read/download/restore는 active 또는 30일 grace 기간에만 허용한다.
- grace 종료 후 Cloud 접근은 차단한다.
- refund/revoked/chargeback류 inactive 상태는 grace 없이 차단한다.
- cancelled는 expiry 전까지 paid 상태를 유지하고, expiry 후에는 단순 만료로 grace를 적용한다.
- grace 중 Cloud metadata lifecycle write는 최소화하고, 로컬 restore 중심으로 처리한다.

명시적 미수행:

- Firebase rules/index 변경 없음.
- Firestore schema 변경 없음.
- migration/backfill 없음.
- Storage object 삭제 없음.
- Cloud copy 구현 없음.
- npm audit fix 없음.
- deploy 없음.
- unrelated cleanup 없음.

## 2. 변경 파일 목록

| 파일 | 변경 내용 |
|---|---|
| [lib/managers/user_status_manager.dart](../lib/managers/user_status_manager.dart) | R3 helper 유지/정리. 만료 강등 시 purchase/product 이력을 보존하는 public helper 추가. |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) | 신규 Cloud write gate 통일, read gate 보강, metadata lifecycle write를 active write 권한으로 제한, reason code/message 정리. |
| [lib/services/iap_service.dart](../lib/services/iap_service.dart) | `CANCELLED`는 expiry 전 paid 유지, `EXPIRED/CANCELLED`는 이력 보존 free 강등, refund/revoked/chargeback류는 grace 없이 reset. |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) | Firestore `free` 동기화가 이미 로컬 grace 상태인 SharedPreferences 이력을 지우지 않도록 보존. |
| [lib/managers/video_manager.dart](../lib/managers/video_manager.dart) | grace restore 후 Cloud metadata move write를 생략하고 로컬 restore 중심으로 유지. |
| [lib/screens/library_screen.dart](../lib/screens/library_screen.dart) | Cloud upload 버튼/실행 진입을 `canStartNewCloudWrite()` 기준으로 차단하고 안내 메시지 표시. |
| [lib/screens/profile_screen.dart](../lib/screens/profile_screen.dart) | Profile Cloud stats 노출 기준을 `canReadExistingCloudClips()`로 조정. |
| [test/user_status_manager_r3_test.dart](../test/user_status_manager_r3_test.dart) | active paid, grace, grace 종료, free never paid, refund-like reset 상태 단위 테스트 추가. |
| [plans/cloud_clip_r3_subscription_expiry_implementation_report_v1.md](cloud_clip_r3_subscription_expiry_implementation_report_v1.md) | 본 구현 결과 보고서 갱신. |

## 3. 핵심 구현 요약

### 3.1 UserStatusManager

구독 상태 계산 helper는 `UserStatusManager`에 둔다.

확인/구현된 계약:

- `canStartNewCloudWrite({DateTime? now})`
  - Standard/Premium이 아니면 false.
  - Standard/Premium이어도 추정 만료 시각 이후면 false.
  - active paid 상태에서만 true.
- `canReadExistingCloudClips({DateTime? now})`
  - active paid면 true.
  - paid tier가 이미 만료됐지만 grace 안이면 true.
  - Free로 강등된 경우에도 보존된 purchase/product 기반 만료 후 30일 이내면 true.
  - purchase/product 이력이 없으면 false.
- `isInCloudReadGrace({DateTime? now})`
  - Free 상태이면서 read grace가 유효할 때 true.
- `cloudReadGraceEndsAt`
  - `lastKnownPaidExpiryAt + 30일`.
- `downgradeExpiredSubscriptionToFreePreservingHistory()`
  - tier와 pending tier만 정리하고 `3s_purchase_date`, `3s_product_id`는 보존한다.

### 3.2 CloudService

실행 gate와 error code/user message는 `CloudService`에 둔다.

신규 write gate 적용:

- `uploadVideo()`
- `uploadVideoImmediate()`
- `_processUploadQueue()`
- `_executeUpload()`
- `enqueuePendingLocalUploads()`
- metadata lifecycle write 계열:
  - `updateVideoMetadata()`
  - `markVideoMovedToAlbum()`
  - `markVideoInTrash()`
  - `restoreVideoFromTrash()`
  - `deleteVideo()`

read/download gate 적용:

- `getCompletedUserVideos()`
- `downloadVideo()`
- `getUserVideos()`
- `refreshCloudStatsSnapshot()`

reason code 정리:

- `tier_required`: never-paid Free처럼 Cloud write/read 권한 자체가 없는 상태.
- `subscription_expired`: paid 이력이 있으나 신규 Cloud write가 만료 정책으로 차단된 상태.
- `subscription_expired_or_grace_ended`: 기존 Cloud read/download grace가 종료되었거나 read 권한이 없는 상태.

### 3.3 IAP/Auth 동기화

- `CANCELLED` inactive가 expiry 전 들어오면 `nextTier=free` 예약만 유지하고 현재 paid tier는 expiry까지 유지한다.
- `EXPIRED` 또는 expiry 이후 `CANCELLED`는 로컬 purchase/product 이력을 보존한 free 강등으로 처리해 30일 grace를 열 수 있게 했다.
- `REVOKED`, `REFUNDED`, `CHARGEBACK`, `FRAUD` 등 refund-like 상태는 `resetToFree()`로 purchase/product를 제거해 grace 없이 차단한다.
- Firestore `users/{uid}`가 `free`로 내려와도 이미 로컬 grace 상태라면 SharedPreferences 이력을 지우지 않는다.
- cross-device grace는 추가하지 않았다. Firestore schema도 변경하지 않았다.

### 3.4 UI

- `CloudBackupScreen`은 `canReadExistingCloudClips()` 기준으로 진입/목록 표시를 판단하고 grace 중 read-only 배너를 표시한다.
- `LibraryScreen`은 upload 버튼/실행 진입을 `canStartNewCloudWrite()` 기준으로 차단한다.
- `ProfileScreen` Cloud stats는 `canReadExistingCloudClips()` 기준으로 표시한다.
- UI는 안내/버튼 노출에 helper를 사용하지만, 최종 권한은 `CloudService` 실행 결과가 결정한다.

## 4. 변경 전/후 동작

| 시나리오 | 변경 전 | 변경 후 |
|---|---|---|
| active Standard/Premium 신규 upload | Standard 이상이면 허용 | active Standard/Premium이고 만료 전일 때만 허용 |
| expired paid 신규 upload | tier 상태에 따라 허용될 수 있음 | `subscription_expired`로 차단 |
| Free grace 신규 upload | tier_required 또는 불명확 | `subscription_expired`로 차단, 기존 Cloud read/download만 허용 |
| Free never paid 신규 upload | Standard 이상 필요 | `tier_required`로 차단 |
| queue upload 중 만료 | queue 실행 시점 정책 불명확 | `_processUploadQueue()`와 `_executeUpload()`에서 재확인 후 failed 보존 |
| active/grace Cloud list | 일부 경로만 read gate | 사용자 노출 list/read 경로를 `canReadExistingCloudClips()` 기준으로 정렬 |
| grace Cloud download/restore | download는 가능하나 metadata write가 뒤따를 수 있음 | download/local restore는 허용, Cloud metadata lifecycle write는 active write 권한일 때만 수행 |
| grace 종료 후 Cloud 접근 | 일부 경로에서 접근 가능성 | read/download/list 차단 |
| CANCELLED | terminal inactive로 reset 가능 | expiry 전 paid 유지, expiry 후 grace 적용 |
| EXPIRED | reset 시 grace 이력 손실 가능 | purchase/product 보존 free 강등으로 grace 적용 |
| REFUNDED/REVOKED/CHARGEBACK | reset | reset 유지, grace 없음 |
| Profile Cloud stats | Standard 이상 기준 | active 또는 grace read 가능 기준 |
| Firebase rules/index | 변경 가능성 없음 | 변경 없음 |
| Storage 삭제 | R3 범위 밖 | 구현 없음 |
| Cloud copy | 미구현 | 계속 미구현/차단 |

## 5. QA matrix

| ID | 상태 | 절차 | 기대 결과 | 현재 상태 |
|---|---|---|---|---|
| R3-QA-01 | active paid | Standard/Premium에서 Cloud upload | upload 허용 | 단위 helper 테스트 완료, 수동 QA 필요 |
| R3-QA-02 | active paid | 자동 upload/queue upload | queue/upload 허용 | 수동 QA 필요 |
| R3-QA-03 | expired within grace | 신규 Cloud upload | `subscription_expired` 차단, 로컬 원본 보존 | helper 테스트 완료, 수동 QA 필요 |
| R3-QA-04 | expired within grace | Cloud 보관함 list/read | 목록 표시 허용 | helper 테스트 완료, 수동 QA 필요 |
| R3-QA-05 | expired within grace | Cloud download/restore | 로컬 restore 허용, Cloud metadata lifecycle write 최소화 | 수동 QA 필요 |
| R3-QA-06 | expired after grace | Cloud 보관함/download | 접근 차단 | helper 테스트 완료, 수동 QA 필요 |
| R3-QA-07 | free never paid | Cloud upload/read | `tier_required` 또는 read 차단 | helper 테스트 완료 |
| R3-QA-08 | guest | Cloud upload/read | guest 차단 | 수동 QA 필요 |
| R3-QA-09 | refund/revoked/chargeback | Cloud upload/read | grace 없이 차단 | reset helper 테스트로 유사 검증, store sandbox QA 필요 |
| R3-QA-10 | cancelled before expiry | entitlement refresh | expiry 전 paid 유지, pending free 예약 | sandbox QA 필요 |
| R3-QA-11 | cancelled/expired after expiry | entitlement refresh | free + 30일 grace | sandbox QA 필요 |
| R3-QA-12 | grace 종료 후 | Storage/Firestore 삭제 여부 | 삭제 없음 | 코드 리뷰 기준 확인, 수동 로그 QA 필요 |
| R3-QA-13 | Cloud copy | Cloud-only 일반 복사 | Cloud copy 생성 없음 | 수동 QA 필요 |

## 6. 실행한 검증 명령과 결과

### 6.1 단위 테스트

```cmd
flutter test test\user_status_manager_r3_test.dart
```

결과:

- PASS.
- `00:00 +5: All tests passed!`

검증 범위:

- active paid write/read 허용.
- expired paid grace 중 write 차단/read 허용.
- expired free 강등 후 purchase/product 이력 보존.
- grace 종료 후 read 차단.
- free never-paid read/write 차단.
- refund-like reset 후 grace 없음.

### 6.2 변경 파일 대상 analyze

```cmd
flutter analyze lib\managers\user_status_manager.dart lib\services\cloud_service.dart lib\services\iap_service.dart lib\services\auth_service.dart lib\managers\video_manager.dart lib\screens\library_screen.dart lib\screens\cloud_backup_screen.dart lib\screens\profile_screen.dart test\user_status_manager_r3_test.dart
```

결과:

- exit code 1.
- `453 issues found`.
- 출력은 기존 성격의 `avoid_print`, `curly_braces_in_flow_control_structures`, deprecated/info, IAP package dependency info, 기존 IAP nullability warning 위주다.
- 이번 R3 변경으로 인한 compile error는 출력에서 확인되지 않았다.

## 7. 금지 범위 준수 확인

- Firebase rules/index 변경 없음.
- Firestore schema 변경 없음.
- migration/backfill 없음.
- Storage object 삭제 구현 없음.
- Cloud copy 구현 없음.
- npm audit fix 없음.
- deploy 실행 없음.
- Storage path, collection name, SharedPreferences key, IAP product id 변경 없음.
- 계정 삭제 purge 흐름 변경 없음.

## 8. 남은 리스크

| 리스크 | 설명 | 후속 조치 |
|---|---|---|
| Store sandbox 상태 전파 | cancelled/expired/refund/revoked/chargeback은 실제 store 검증 결과가 필요 | Android/iOS sandbox QA |
| Firestore free 동기화와 local grace | 현재는 local grace 상태를 보존하지만 cross-device grace는 없음 | R3 v1 정책상 허용. cross-device는 별도 계획 |
| grace restore metadata write | grace 중 restore는 로컬 중심으로 처리하지만 일부 다른 lifecycle 경로는 사용 시나리오 QA 필요 | CloudBackup/Library restore 수동 QA |
| Profile stats in grace | `canReadExistingCloudClips()` 기준으로 표시하지만 limit은 Free면 0GB일 수 있음 | UX 확인 필요 |
| analyze 부채 | 기존 453개 이슈 때문에 신규 회귀 탐지가 어렵다 | R6 정적 분석 부채 작업으로 분리 |
| 수동 QA 미완료 | 실제 upload/download/queue/guest/profile UI는 기기 검증 필요 | QA matrix 수행 |

## 9. 최종 판정

R3 v1 구현은 코드 레벨에서 완료했다.

릴리스 전에는 다음 수동 QA를 완료해야 한다.

1. active Standard/Premium upload, auto upload, queue upload.
2. expired within grace Cloud list/download/restore.
3. expired after grace Cloud 접근 차단.
4. guest Cloud 접근 차단.
5. store sandbox cancelled/expired/refund/revoked/chargeback.
6. Cloud copy 미구현/차단 유지.
7. Storage object 삭제가 발생하지 않는지 로그/콘솔 확인.

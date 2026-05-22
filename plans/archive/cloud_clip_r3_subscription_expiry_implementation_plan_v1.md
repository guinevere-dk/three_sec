# Cloud Clip R3 구독 만료 Cloud 접근 정책 구현 계획 v1

## 0. 작업 범위와 결론

본 문서는 R5 Firebase rules/index validation을 PASS로 닫은 뒤 진행할 R3 구독 만료 Cloud 접근 정책의 구현 계획이다.

목표는 구독 만료 시 신규 Cloud write를 차단하고, 기존 Cloud clip은 grace 기간 동안 read/download만 허용한 뒤, grace 종료 후 Cloud 접근을 차단하는 것이다.

이번 R3 계획의 명시적 제외 범위:

- Storage object 삭제 구현 없음.
- Firebase rules/index 변경 없음.
- Firestore schema migration/backfill 없음.
- Cloud copy 구현 없음.
- Functions 변경 없음.
- Storage path, collection name, SharedPreferences key, IAP product id 변경 없음.

## 1. 기준 문서와 결정 원칙

| 기준 파일 | R3 적용 |
|---|---|
| [AGENTS.md](../AGENTS.md) | 사용자 데이터 보존, 기존 기능 유지, 레거시 호환을 우선한다. |
| [CURRENT_PHASE.md](../CURRENT_PHASE.md) | Cloud 안정화와 구독 tier 유지 범위 안에서 작은 단위로 진행한다. |
| [DATA_COMPATIBILITY.md](../DATA_COMPATIBILITY.md) | `videos`, `users`, Storage prefix, `3s_*` key, IAP product id를 변경하지 않는다. |
| [plans/cloud_clip_remaining_risk_resolution_plan_v1.md](cloud_clip_remaining_risk_resolution_plan_v1.md) | R3는 삭제보다 읽기전용 grace와 신규 Cloud 작업 차단을 먼저 확정한다. |
| [plans/cloud_clip_r5_firebase_rules_index_validation_report_v1.md](cloud_clip_r5_firebase_rules_index_validation_report_v1.md) | R5는 PASS로 닫고, R3에서는 rules/index 변경을 하지 않는다. |

정책 우선순위:

1. 기존 Cloud metadata와 Storage object를 삭제하지 않는다.
2. 만료 후 신규 Cloud 비용을 만드는 작업은 차단한다.
3. grace 기간에는 기존 Cloud clip을 사용자가 로컬로 회수할 수 있게 한다.
4. grace 종료 후에는 Cloud 접근을 차단하되, 삭제는 별도 R2/운영 정책으로 분리한다.
5. 서버 rules가 아니라 Flutter 클라이언트 분기로 먼저 적용한다.

## 2. 정책 정의

| 상태 | 신규 Cloud upload | Cloud copy | 기존 Cloud 목록/read | 기존 Cloud download/restore | Storage 삭제 |
|---|---:|---:|---:|---:|---:|
| 활성 Standard/Premium | 허용 | 미구현 | 허용 | 허용 | 없음 |
| 만료 직후 grace 기간 | 차단 | 미구현/차단 | 허용 | 허용 | 없음 |
| grace 종료 후 | 차단 | 미구현/차단 | 차단 | 차단 | 없음 |
| Free 신규 사용자 | 차단 | 미구현/차단 | 차단 | 차단 | 없음 |
| restore purchase/재구독 후 | 허용 | 미구현 | 허용 | 허용 | 없음 |

기본 grace 정책:

- 만료 후 30일 동안 기존 Cloud clip read/download/restore를 허용한다.
- grace 기준 시각은 기존 구독 purchase/product 정보로 추정한다.
- purchase timestamp 또는 product id가 없어 만료 시각을 추정할 수 없으면 보수적으로 grace를 열지 않는다.
- 이 경우에도 Cloud metadata/object는 삭제하지 않는다.

## 3. 필요한 상태값

새 저장 key를 만들지 않고 기존 값을 사용한다.

| 상태값/helper | 위치 | 목적 |
|---|---|---|
| `currentTier` | `lib/managers/user_status_manager.dart` | 현재 Free/Standard/Premium 판정 |
| `purchaseDate` | `lib/managers/user_status_manager.dart`, SharedPreferences `3s_purchase_date` | 구독 만료 추정 기준 |
| `productId` | `lib/managers/user_status_manager.dart`, SharedPreferences `3s_product_id` | 월간/연간 만료 추정 기준 |
| `estimatedExpiryAt` | `lib/managers/user_status_manager.dart` | 활성 구독이어도 만료 시각이 지났는지 판단 |
| `lastKnownPaidExpiryAt` | `lib/managers/user_status_manager.dart` | Free 강등 후 grace 계산 기준 |
| `cloudReadGraceEndsAt` | `lib/managers/user_status_manager.dart` | grace 종료 시각 |
| `canStartNewCloudWrite()` | `lib/managers/user_status_manager.dart` | 신규 Cloud upload/copy 차단 gate |
| `canReadExistingCloudClips()` | `lib/managers/user_status_manager.dart` | 기존 Cloud list/read/download 허용 gate |
| `isInCloudReadGrace()` | `lib/managers/user_status_manager.dart` | UX 배너/문구 분기 |

상태 보존 원칙:

- 자동 만료 강등 시 `3s_purchase_date`, `3s_product_id`는 grace 판단을 위해 보존한다.
- 신규 구매 또는 restore purchase가 성공하면 기존 `setTier()` 흐름으로 최신 purchase/product 값이 덮어써지게 한다.
- `3s_*` key 이름은 변경하지 않는다.
- Firestore `users/{uid}` schema에 새 field를 추가하지 않는다.

## 4. 필요한 분기 위치

### 4.1 신규 Cloud upload/copy 차단

| 위치 | 필요한 분기 | 기대 동작 |
|---|---|---|
| `lib/services/cloud_service.dart` `uploadVideo()` | `_canStartNewCloudWrite('클라우드 이동')` | 만료 후 Storage upload와 Firestore metadata 생성 전 차단 |
| `lib/services/cloud_service.dart` `uploadVideoImmediate()` | `_canStartNewCloudWrite('클라우드 이동')` | Library Cloud 이동 즉시 차단, 로컬 원본 보존 |
| `lib/services/cloud_service.dart` queue 처리 | `_canStartNewCloudWrite('백그라운드 업로드')` | queue job은 삭제하지 않고 실패 상태/오류 코드로 보존 |
| `lib/managers/video_manager.dart` auto upload enqueue | CloudService upload gate 재사용 | 촬영/저장 완료 후 만료 상태면 Cloud 업로드만 차단, 로컬 저장은 유지 |
| `lib/managers/video_manager.dart` 일반 copy 경로 | Cloud-only copy는 계속 skip | Cloud copy는 구현하지 않고 기존 local-only 정책 유지 |

### 4.2 기존 Cloud read/download grace 허용

| 위치 | 필요한 분기 | 기대 동작 |
|---|---|---|
| `lib/services/cloud_service.dart` Cloud 목록/read 함수 | `_canReadExistingCloudClips()` | grace 중 목록 조회 허용, grace 종료 후 차단 |
| `lib/services/cloud_service.dart` `downloadVideo()` | `_canReadExistingCloudClips()` | grace 중 download/restore 허용, grace 종료 후 차단 |
| `lib/managers/video_manager.dart` `syncCloudMetadataToLibrary()` | `canReadExistingCloudClips()` | Free 강등 후 grace 중 Cloud placeholder 유지 |
| `lib/managers/video_manager.dart` `_mergeCloudOnlyPlaceholdersForCurrentAlbum()` | `canReadExistingCloudClips()` | grace 중 Library에 기존 Cloud clip 표시 |
| `lib/screens/cloud_backup_screen.dart` | `isInCloudReadGrace()`와 `canReadExistingCloudClips()` | grace 배너, read-only 보관함, 복원 허용 |
| `lib/screens/library_screen.dart` Cloud restore flow | CloudService download 결과/error copy 표시 | grace 중 복원 허용, 종료 후 안내 |

### 4.3 구독 복구 후 권한 복원

| 위치 | 필요한 분기 | 기대 동작 |
|---|---|---|
| `lib/services/auth_service.dart` subscription sync | 기존 tier sync 흐름 유지 | restore/re-subscribe 후 Cloud 권한 복구 |
| `lib/screens/subscription_management_screen.dart` | 만료/해지 안내 문구 | 만료 전 복원 권장, grace/read-only 안내 |
| `lib/screens/paywall_screen.dart` | 재구독 유도 문구 | 신규 Cloud 사용과 보관함 접근 복구 안내 |

## 5. 필요한 UX 메시지 목록

문구는 사용자 불안을 줄이되 삭제를 암시하지 않는다.

| 상황 | 메시지 목적 | 권장 문구 |
|---|---|---|
| 만료 후 신규 upload 차단 | 신규 Cloud 비용 작업 차단 안내 | `구독이 만료되어 신규 Cloud 업로드가 중지되었어요. 로컬 클립은 그대로 보관됩니다.` |
| 만료 후 Cloud copy 차단 | 미구현/차단 안내 | `구독이 만료되어 Cloud 복사는 사용할 수 없어요. 기존 Cloud 클립은 grace 기간 동안 이 기기에 복원할 수 있어요.` |
| grace 중 Cloud 보관함 | read-only 상태 안내 | `구독이 만료되었지만 기존 Cloud 클립은 만료 후 30일 동안 이 기기에 복원할 수 있어요.` |
| grace 중 download/restore | 복원 가능 안내 | `Cloud 클립을 이 기기에 복원할 수 있어요. 신규 Cloud 업로드는 재구독 후 이용할 수 있습니다.` |
| grace 종료 후 Cloud 접근 차단 | 접근 종료 안내 | `Cloud 접근 가능 기간이 종료되었어요. 구독 복원 또는 재구독 후 Cloud 보관함과 복원을 다시 이용할 수 있어요.` |
| 만료 기준 정보 없음 | 보수적 차단 안내 | `구독 상태를 확인할 수 없어 Cloud 접근을 제한했어요. 구독 복원 또는 재구독 후 다시 시도해주세요.` |
| restore purchase 성공 | 권한 복구 안내 | `구독이 복원되어 Cloud 업로드와 보관함 이용이 다시 가능해요.` |
| 재구독 성공 | 권한 복구 안내 | `구독이 활성화되어 Cloud 기능을 다시 사용할 수 있어요.` |
| queue upload 차단 | 로컬 원본 보존 안내 | `구독 만료로 Cloud 업로드가 중지되었어요. 로컬 클립은 삭제되지 않았습니다.` |

UX 금지 문구:

- `Cloud 클립이 삭제됩니다`
- `자동 삭제되었습니다`
- `복구할 수 없습니다`
- `Storage 정리를 시작합니다`

R3에서는 삭제를 구현하지 않으므로 삭제 예정/완료를 암시하지 않는다.

## 6. 구현 단계

### Step 1. 상태 helper 확인

- `UserStatusManager`에 만료 추정, grace 종료, 신규 Cloud write 가능 여부, 기존 Cloud read 가능 여부 helper를 둔다.
- 새 SharedPreferences key를 추가하지 않는다.
- 월간/연간 product id 기반 만료 추정 로직은 기존 `3s_*` product id만 사용한다.

완료 조건:

- 활성 구독, 만료 직후, grace 중, grace 종료 후, purchase 정보 없음을 함수 단위로 설명 가능하다.

### Step 2. Cloud write gate 적용

- Storage upload 또는 Firestore metadata create 전에 차단한다.
- queue job은 삭제하지 않는다.
- 로컬 원본 파일, local index, project JSON은 변경하지 않는다.
- 오류 코드는 `subscription_expired` 또는 기존 error handling 체계에 맞춘다.

완료 조건:

- 만료 상태에서 Storage object가 새로 생성되지 않는다.
- 만료 상태에서 `videos` metadata가 새 upload로 생성되지 않는다.
- 사용자는 로컬 클립을 계속 볼 수 있다.

### Step 3. Cloud read/download grace gate 적용

- 기존 Cloud list, placeholder merge, download/restore 경로에 read gate를 적용한다.
- grace 중에는 read/download만 허용한다.
- grace 종료 후에는 read/download를 차단한다.
- 차단 시 Cloud metadata/object 삭제는 하지 않는다.

완료 조건:

- grace 중 Cloud 보관함/Library placeholder가 표시된다.
- grace 중 download/restore가 가능하다.
- grace 종료 후 접근 차단 안내가 표시된다.

### Step 4. UX 메시지 적용

- Cloud backup screen, Library Cloud action, subscription management/paywall 안내를 일관되게 맞춘다.
- 메시지는 삭제가 아니라 접근/복원/재구독 중심으로 작성한다.

완료 조건:

- 신규 upload 차단, grace read-only, grace 종료, restore purchase 성공 문구가 각각 구분된다.

### Step 5. QA 문서화

- sandbox 구독 상태 전환은 수동 QA로 분리한다.
- Firebase rules/index, migration/backfill, Storage deletion 검증은 R3 범위에서 제외한다.

완료 조건:

- 아래 QA matrix 결과가 기록된다.

## 7. QA matrix

| ID | 상태 | 절차 | 기대 결과 | 검증 |
|---|---|---|---|---|
| R3-QA-01 | 활성 Standard/Premium | 로컬 클립 Cloud 이동 | upload 성공, `videos` metadata completed, 로컬 원본 보존 | 수동/기기 |
| R3-QA-02 | 활성 Standard/Premium | 촬영 후 자동 Cloud upload queue | local save 후 queue pending/completed 또는 failed 보존 | 수동/기기 |
| R3-QA-03 | 만료 직후 | 로컬 클립 Cloud 이동 | Storage upload 미실행, Firestore 새 metadata 없음, `subscription_expired` 안내, 로컬 원본 보존 | 수동/로그 |
| R3-QA-04 | 만료 직후 | 앱 재시작 후 upload queue restore | queue job 삭제 없음, Cloud upload 재시도 차단, 실패 상태 보존 | 수동/로그 |
| R3-QA-05 | grace 기간 | Cloud 보관함 진입 | 기존 Cloud clip 목록 표시, read-only 안내 배너 표시 | 수동/UI |
| R3-QA-06 | grace 기간 | Cloud-only placeholder가 있는 Library 진입 | placeholder 표시 유지 | 수동/UI |
| R3-QA-07 | grace 기간 | Cloud clip download/restore | 로컬 파일 생성, Cloud metadata/Storage object 삭제 없음 | 수동/Firestore/Storage 확인 |
| R3-QA-08 | grace 기간 | 신규 Cloud upload 시도 | 차단, 로컬 원본 보존, Cloud metadata 신규 생성 없음 | 수동/로그 |
| R3-QA-09 | grace 종료 후 | Cloud 보관함 진입 | 접근 차단 안내, 삭제 없음 | 수동/UI |
| R3-QA-10 | grace 종료 후 | Cloud clip download/restore 시도 | 차단 안내, 로컬/Cloud 데이터 변경 없음 | 수동/로그 |
| R3-QA-11 | purchaseDate/productId 없음 | Cloud 보관함 진입 | 보수적 차단 안내, 삭제 없음 | 수동/상태 주입 |
| R3-QA-12 | restore purchase 성공 | 구독 복원 후 Cloud 이동/보관함 진입 | upload/read/download 권한 복구 | sandbox QA |
| R3-QA-13 | 재구독 성공 | 재구독 후 Cloud 이동/보관함 진입 | 최신 purchase/product 반영, 권한 복구 | sandbox QA |
| R3-QA-14 | Free 신규 사용자 | Cloud 이동/보관함 진입 | 신규 upload 차단, 기존 Cloud read 없음 | 수동/UI |
| R3-QA-15 | Cloud copy | Cloud-only clip 일반 복사 | Cloud copy 생성 없음, 기존 skip/local-only 정책 유지 | 수동/로그 |
| R3-QA-16 | 삭제 경로 감시 | R3 시나리오 전체 수행 | Storage delete/Firestore purge 호출 없음 | 코드리뷰/로그 |

## 8. 배포 전 확인

R3는 Flutter 클라이언트 정책 변경으로 제한한다.

필수 확인:

```cmd
flutter analyze
```

가능하면 관련 수동 QA를 우선한다.

Firebase 관련 명령은 R3 구현 범위가 아니다.

실행하지 않을 명령:

```cmd
npx firebase deploy --only firestore:rules
npx firebase deploy --only firestore:indexes
npx firebase deploy --only storage:rules
```

## 9. 절대 금지 항목

R3 작업에서 아래 항목은 수행하지 않는다.

- Storage object 삭제 구현.
- Firestore document purge 구현.
- 계정 삭제 purge 흐름 변경.
- Firebase rules 변경.
- Firestore index 변경.
- Firestore schema migration.
- 기존 문서 backfill.
- `videos`, `users`, `vlog_projects` collection rename.
- Storage `users/{uid}/videos/{videoId}/{fileName}` prefix 변경.
- SharedPreferences `3s_*`, `cloud_synced_paths`, `local_index_entries_v1` key 변경.
- IAP product id 변경.
- Cloud copy 구현.
- Functions/scheduler 도입.
- broad allow Firebase rule 추가.
- grace 종료 후 자동 삭제 안내 또는 자동 삭제 실행.
- 사용자 원본 영상, 프로젝트 JSON, 로컬 인덱스 초기화.

## 10. 완료 기준

R3 구현 계획은 아래 조건을 만족하면 실행 준비 완료로 본다.

- 신규 Cloud upload/copy 차단 위치가 명확하다.
- 기존 Cloud clip read/download grace 위치가 명확하다.
- UX 메시지가 신규 upload 차단, grace read-only, grace 종료, 권한 복구로 분리되어 있다.
- QA matrix가 활성/만료/grace/grace 종료/복구/Free/Cloud copy 금지/삭제 금지를 모두 포함한다.
- Firebase rules/index, migration/backfill, Storage 삭제, Cloud copy가 범위 밖으로 명시되어 있다.
- R5 Firebase rules/index validation은 PASS로 닫고, R3에서 다시 변경하지 않는다.

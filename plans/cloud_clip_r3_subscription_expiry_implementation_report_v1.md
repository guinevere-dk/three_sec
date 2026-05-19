# Cloud Clip R3 구독 만료 정책 구현 보고서 v1

## 1. 구현 범위

- R3 정책만 Flutter 클라이언트 최소 변경으로 구현했다.
- 구독 만료 즉시 신규 Cloud upload를 차단한다.
- 기존 Cloud clip은 만료 후 30일 grace 동안 목록 조회와 download/restore만 허용한다.
- Storage object 삭제, Firestore schema migration/backfill, Firebase rules/index 변경, Functions 변경, Cloud copy 구현은 수행하지 않았다.

## 2. 기준 문서

- `AGENTS.md`
- `CURRENT_PHASE.md`
- `DATA_COMPATIBILITY.md`
- `plans/cloud_clip_policy_decision_v1.md`
- `plans/cloud_clip_remaining_risk_resolution_plan_v1.md`
- `plans/cloud_clip_deferred_items_execution_guide_v1.md`

## 3. 변경 파일

| 파일 | 변경 요약 |
|---|---|
| `lib/managers/user_status_manager.dart` | 구독 만료 추정 시각, Cloud write 차단, 30일 read grace 판정 helper 추가. 자동 만료 강등 시 purchaseDate/productId를 보존해 grace 판정에 사용. |
| `lib/services/cloud_service.dart` | 신규 upload/queue upload/auto upload에 만료 write guard 적용. Cloud 목록/download에는 read grace guard 적용. 만료 안내 문구와 `subscription_expired` 오류 코드 추가. |
| `lib/managers/video_manager.dart` | Library Cloud placeholder 동기화 조건을 Standard 이상에서 read grace 허용 조건으로 변경. |
| `lib/screens/cloud_backup_screen.dart` | 만료 grace 중 Cloud 보관함 접근과 복원을 허용하고, read-only 안내 배너 표시. grace 종료/권한 없음 안내 문구 표시. |
| `lib/screens/library_screen.dart` | Cloud 이동 실패 안내에 구독 만료 문구 추가. |
| `plans/cloud_clip_r3_subscription_expiry_implementation_report_v1.md` | 구현 결과와 QA 체크리스트 문서화. |

## 4. 변경 전/후 동작

| 시나리오 | 변경 전 | 변경 후 |
|---|---|---|
| 활성 Standard/Premium 신규 Cloud upload | 허용 | 추정 만료 전이면 허용 |
| 결제 만료 시각 이후 신규 Cloud upload | 자동 강등 전까지 허용될 수 있음 | `canStartNewCloudWrite()`에서 즉시 차단 |
| 만료 후 upload queue 복구/재시도 | 실패/재시도 흐름에 의존 | `subscription_expired` 실패 상태로 보존하고 Storage upload 미실행 |
| Free 강등 직후 기존 Cloud 목록/read | Standard 이상 조건 때문에 차단 | 구매 이력 기반 만료 후 30일 grace 내 목록/read 허용 |
| grace 중 Cloud download/restore | Standard 이상 조건 때문에 차단 | read-only 복원 허용 |
| grace 종료 후 Cloud read | 차단 | 삭제 없이 안내/차단 |
| restore purchase/re-subscribe | 기존 setTier/sync 흐름 | `setTier()`가 최신 purchase/product로 덮어써 upload/read 권한 복구 |
| Cloud copy | 미구현/스킵 | 구현하지 않음. 기존 cloud-only 일반 복사 스킵 정책 유지 |
| 삭제 | 일부 계정 삭제 purge 경로 외 일반 clip 삭제는 tombstone | R3 작업에서 Storage object 삭제 추가 없음 |

## 5. 정책 세부 사항

- `UserStatusManager.canStartNewCloudWrite()`는 Standard/Premium이라도 `estimatedExpiryAt`이 지난 경우 신규 Cloud write를 차단한다.
- `UserStatusManager.canReadExistingCloudClips()`는 활성 유료 구독이면 read 허용, 만료 후에는 `lastKnownPaidExpiryAt + 30일` 전까지만 read/download 허용한다.
- 자동 만료 강등은 tier와 pending tier만 Free로 정리하고 `3s_purchase_date`, `3s_product_id` 값은 보존한다. 이는 새 key/schema를 추가하지 않고 grace를 계산하기 위한 보수적 호환 처리다.
- purchase timestamp/productId가 없으면 만료 기준이 불확실하므로 grace를 추정하지 않고 read를 차단한다. 단, 데이터/객체 삭제는 하지 않는다.
- queue에 남은 upload job은 삭제하지 않고 failed 상태와 `subscription_expired` 오류를 남겨 재구독 후 사용자가 재시도할 수 있는 보존 흐름으로 유지한다.

## 6. QA 체크리스트

| 항목 | 절차 | 기대 결과 | 상태 |
|---|---|---|---|
| 만료 전 upload | Standard/Premium 상태에서 로컬 클립 Cloud 이동 | upload 성공, metadata completed, local 원본 보존 | 수동 QA 필요 |
| 만료 직후 upload 차단 | purchaseDate를 과거로 둔 Standard/Premium 상태에서 Cloud 이동 | Storage upload 미실행, `subscription_expired` 안내 표시, 로컬 원본 보존 | 수동 QA 필요 |
| upload queue 차단 | 만료 상태에서 앱 재시작/복귀 후 queue restore | queue job failed 보존, Storage object 생성 없음 | 수동 QA 필요 |
| grace 중 목록 조회 | Free 강등 + purchaseDate/productId 보존 + 만료 후 30일 이내 | Cloud 보관함/Library placeholder 표시 | 수동 QA 필요 |
| grace 중 download/restore | grace 상태에서 Cloud clip 복원 | 로컬 파일 생성, Cloud metadata/Storage object 삭제 없음 | 수동 QA 필요 |
| grace 종료 후 read 차단 | 만료 후 30일 초과 상태 | Cloud 보관함 접근 차단 안내, 삭제 없음 | 수동 QA 필요 |
| restore purchase | 만료/Free 상태에서 restore purchases 후 tier refresh | Cloud upload/read 권한 복구, 기존 metadata 연결 유지 | sandbox QA 필요 |
| 재구독 | 만료/Free 상태에서 재구매 | `setTier()`로 최신 purchase/product 반영, upload/read 권한 복구 | sandbox QA 필요 |
| Cloud copy 금지 | Cloud-only clip 일반 복사 | Cloud copy 생성 없이 기존 스킵 동작 유지 | 수동 QA 필요 |
| 삭제 금지 확인 | R3 경로 수행 중 Storage/Firestore 삭제 호출 여부 확인 | 삭제 호출 없음 | 코드 리뷰 완료 |

## 7. 검증 결과

- `flutter analyze`: 실행 완료, exit code 1.
- 전체 결과: 504 issues.
- 관련 변경 파일 필터 결과: 신규 compile error는 확인되지 않았고, 기존 성격의 `avoid_print`, `curly_braces_in_flow_control_structures`, deprecated/info 항목이 보고됐다.
- 대표 관련 파일 결과:
  - `lib/managers/user_status_manager.dart`: `avoid_print` info 다수.
  - `lib/services/cloud_service.dart`: `avoid_print` info 다수.
  - `lib/managers/video_manager.dart`: 기존 `avoid_print`, `curly_braces_in_flow_control_structures` info.
  - `lib/screens/library_screen.dart`: 기존 style/deprecated info.
  - `lib/screens/cloud_backup_screen.dart`: 필터 결과에 error/warning 없음.

## 8. 미검증 사유와 남은 리스크

- sandbox 구독 만료/restore/re-subscribe는 실제 테스트 계정과 스토어 상태 전파가 필요해 수동 QA가 필요하다.
- 기존 사용자 중 `purchaseDate` 또는 `productId`가 없는 경우 30일 grace 기준을 신뢰할 수 없어 read를 보수적으로 차단한다. 이 경우에도 Cloud metadata/object는 삭제하지 않는다.
- Firestore server-side expiry timestamp가 별도로 확정되어 있지 않아 로컬 purchaseDate/productId 기반 추정 만료를 사용했다.
- upload queue의 `failed` 상태는 기존 복구 대상에 포함되지만, 재구독 후 중복 방지 로직과 사용자의 재시도 흐름을 추가 QA해야 한다.

## 9. 금지 범위 준수 확인

- Storage object 삭제 구현 없음.
- Firestore schema migration/backfill 없음.
- Firebase rules/index 변경 없음.
- Functions 변경 없음.
- Storage path, collection name, SharedPreferences key, IAP product id 변경 없음.
- Cloud copy 구현 없음.

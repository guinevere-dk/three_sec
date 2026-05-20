# Cloud Clip Move Model Policy v1

## 1. Product Policy

Cloud Clip 저장 정책은 sync 모델이 아니라 move 모델이다.

- 하나의 clip은 active 상태 기준으로 기기 또는 Cloud 중 한 곳에만 존재한다.
- 기기 clip을 Cloud로 업로드하는 동작은 복사가 아니라 기기에서 Cloud로 이동하는 동작이다.
- Cloud clip을 기기로 내려받는 동작은 복원이 아니라 Cloud에서 기기로 회수하는 동작이다.
- R3 및 현재 범위에서는 Storage object를 물리 삭제하지 않는다.
- Cloud에서 제거한다는 의미는 active metadata를 trash/tombstone 상태로 전환해 일반 Cloud 목록과 Cloud 접근 흐름에서 제외하는 것이다.

## 2. State Model

정책상 사용자에게 노출되는 active storage state는 두 가지뿐이다.

- `device`: 로컬 파일과 로컬 인덱스가 active이며, Cloud active metadata로 취급하지 않는다.
- `cloud`: Cloud active metadata가 active이며, 앱 Library에는 `cloud_only://` placeholder로 표시된다.

내부 진단과 실패 처리를 위해 다음 derived state는 유지할 수 있다.

- `localOnly`: device 상태의 정상 clip.
- `cloudOnly`: cloud 상태의 정상 clip.
- `pendingUpload`: 기기에서 Cloud로 이동 중.
- `failedUpload`: Cloud 이동 실패 후 기기에 남은 clip.
- `failedDownload`: 기기로 회수 실패 후 Cloud에 남은 clip.
- `cloudSyncedLocal`: legacy 호환 진단 상태. 신규 정상 상태로 생성하면 안 된다.

## 3. Upload Move Sequence

기기에서 Cloud로 이동할 때의 성공 조건은 다음 순서를 만족해야 한다.

1. 사용자가 device/local-only clip을 선택한다.
2. 앱은 signed-in 상태와 Cloud write 권한을 확인한다.
3. Cloud upload를 시작한다.
4. Firestore active metadata 생성과 Storage upload 완료를 확인한다.
5. Cloud metadata의 completed/active 상태를 확인한다.
6. 로컬 파일을 제거한다.
7. 로컬 인덱스, ownership, duration cache, transfer state, legacy synced marker를 제거한다.
8. Cloud metadata pull 또는 동등한 갱신으로 Library에 Cloud-only placeholder를 표시한다.

업로드가 완료되기 전에는 로컬 파일을 제거하지 않는다.

## 4. Download Move Sequence

Cloud에서 기기로 회수할 때의 성공 조건은 다음 순서를 만족해야 한다.

1. 사용자가 Cloud-only clip을 선택한다.
2. 앱은 signed-in 상태와 Cloud read/download 권한을 확인한다.
3. Cloud Storage object를 로컬 고유 경로로 다운로드한다.
4. 로컬 파일 존재와 로컬 인덱스 등록 가능성을 확인한다.
5. 로컬 clip을 device 상태로 등록한다.
6. Cloud active metadata를 trash/tombstone 처리한다.
7. Cloud-only placeholder, Cloud metadata cache, legacy synced marker를 제거한다.

R3 및 현재 범위에서는 Storage object를 물리 삭제하지 않는다.

## 5. Failure/Rollback Rules

- Upload 실패: 로컬 파일과 로컬 인덱스를 보존하고 `failedUpload`로 진단한다.
- Upload metadata 생성 후 Storage upload 실패: Cloud metadata는 failed 상태로 남을 수 있으나 로컬 파일은 보존한다.
- Upload 완료 후 로컬 제거 실패: clip이 일시적으로 legacy `cloudSyncedLocal`처럼 보일 수 있으며, 자동 삭제 repair는 수행하지 않는다.
- Download 실패: Cloud active metadata와 placeholder를 보존하고 `failedDownload`로 진단한다.
- Download 후 로컬 등록 실패: Cloud active metadata를 유지한다.
- Download 후 Cloud trash/tombstone 실패: Cloud active 상태를 유지하고, 중복 active 상태가 생기지 않도록 성공 처리하지 않는다.

데이터 손실 위험이 있으면 삭제보다 보존을 우선한다.

## 6. Legacy cloudSyncedLocal Handling

기존 sync 모델에서 생성된 `cloudSyncedLocal` 데이터는 자동 삭제하거나 정리하지 않는다.

- 기존 로컬 파일을 임의 삭제하지 않는다.
- 기존 Cloud metadata를 임의 trash/tombstone 처리하지 않는다.
- `cloud_synced_paths`를 destructive cleanup 하지 않는다.
- 해당 상태는 진단 대상으로 유지하고, 별도 승인된 repair/migration 계획 없이 자동 변환하지 않는다.

신규 정상 경로는 `cloudSyncedLocal`을 만들면 안 되며, upload/download move 완료 후에는 `device` 또는 `cloud` 중 하나로 귀결되어야 한다.

## 7. R3 Subscription Expiry Interaction

R3 구독 상태별 Cloud move 정책은 다음과 같다.

- Active paid: upload move와 download move 모두 허용한다.
- Expired within 30-day grace: 신규 upload move는 차단한다. Cloud에 남아 있는 기존 clip의 download/move-to-device는 허용한다.
- Expired after grace: Cloud read/download/move-to-device를 차단한다.
- Free never paid: Cloud upload/download 접근을 차단한다.

Grace 중 download/move-to-device는 사용자가 Cloud에 남긴 기존 clip을 기기로 회수하기 위한 데이터 보호 경로이다.

## 8. UI Icon/Badge Semantics

Clip별 storage badge/icon은 두 가지 의미만 노출한다.

- `기기`: device 상태. 로컬 파일이 active이다.
- `Cloud`: cloud 상태. Cloud active metadata가 있고 Library에는 placeholder로 표시된다.

사용자에게 `동기화됨`, `기기+Cloud`, `Cloud done` 같은 sync 의미를 clip badge로 노출하지 않는다.

선택 패널의 transfer action은 상태에 따라 다음처럼 결정한다.

- device/local-only: Cloud로 이동 버튼.
- cloud/cloud-only: 기기로 내려받기 버튼.
- pending 상태: 진행 중으로 비활성화.
- mixed selection: 비활성화.
- legacy `cloudSyncedLocal`: 자동 이동/삭제 없이 비활성화 또는 별도 안내.

## 9. Data Safety Rules

- Storage object 물리 삭제는 R3 및 현재 범위에 포함하지 않는다.
- Firebase rules/index/schema 변경을 전제로 하지 않는다.
- migration/backfill 실행을 전제로 하지 않는다.
- legacy data 자동 삭제를 전제로 하지 않는다.
- 로컬 파일 삭제는 Cloud upload completed/active 확인 이후에만 가능하다.
- Cloud active metadata trash/tombstone 처리는 로컬 다운로드와 로컬 등록 확인 이후에만 가능하다.
- raw uid, email, token, order id, provider 값은 QA 문서와 로그 분석 산출물에 기록하지 않는다.

## 10. QA Matrix

| Scenario | Preconditions | Expected Result | Verdict Criteria |
| --- | --- | --- | --- |
| Active paid upload move | signed-in, active paid, device clip | Cloud active placeholder 생성, 로컬 파일/인덱스 제거 | PASS if active state is Cloud only |
| Active paid download move | signed-in, active paid, Cloud clip | 로컬 파일/인덱스 생성, Cloud active metadata trash/tombstone | PASS if active state is device only |
| Grace upload | signed-in, expired within grace, device clip | 신규 Cloud upload 차단 | PASS if no new Cloud object/metadata active |
| Grace download move | signed-in, expired within grace, Cloud clip | 기기로 회수 허용, Cloud active metadata trash/tombstone | PASS if active state is device only |
| After grace download | signed-in, expired after grace, Cloud clip | Cloud read/download 차단 | PASS if no local file is created |
| Free never paid | signed-in free never paid | Cloud upload/download 차단 | PASS if no Cloud access succeeds |
| Legacy cloudSyncedLocal | existing duplicated active state | 자동 삭제 없음, 진단/안내만 수행 | PASS if no destructive cleanup occurs |
| Failure during upload | network/storage/firestore failure | 로컬 파일 보존 | PASS if device copy remains |
| Failure during download | network/storage/firestore failure | Cloud active metadata 보존 | PASS if Cloud copy remains |

## 11. Go/No-Go Criteria

Go:

- 신규 upload move 후 active state가 Cloud only로 귀결된다.
- 신규 download move 후 active state가 device only로 귀결된다.
- Storage object 물리 삭제 없이 Cloud active 목록에서 제외된다.
- Grace 중 기존 Cloud clip 회수 경로가 허용된다.
- Grace 종료 후 Cloud read/download가 차단된다.
- UI badge가 clip별로 `기기` 또는 `Cloud`만 표시한다.

No-Go:

- 신규 정상 경로에서 `cloudSyncedLocal`이 생성된다.
- upload 실패 시 로컬 파일이 삭제된다.
- download 실패 시 Cloud active metadata가 제거된다.
- R3 범위에서 Storage object 물리 삭제가 발생한다.
- legacy `cloudSyncedLocal` 데이터가 승인 없이 자동 삭제/정리된다.
- Firebase rules/index/schema 변경 또는 migration/backfill이 전제된다.

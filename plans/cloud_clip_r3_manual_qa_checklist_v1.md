# Cloud Clip R3 Manual QA Checklist v1

## 1. 목적

R3 v1 구독 만료 Cloud 접근 정책의 수동 QA 절차를 정의한다.

검증 대상:

- active Standard/Premium은 신규 Cloud write와 기존 Cloud read/download/restore가 가능하다.
- 구독 만료 후 30일 grace 중에는 신규 Cloud write가 차단되고, 기존 Cloud clip list/read/download/restore만 가능하다.
- grace 종료 후에는 기존 Cloud 접근도 차단된다.
- refund/revoked/chargeback류 상태는 grace 없이 차단된다.
- R3에서는 Storage 삭제, Cloud copy, Firebase rules/index 변경, schema 변경, migration/backfill을 수행하지 않는다.

이번 문서는 절차 문서만 추가한다. 코드, Firebase, deploy, npm audit fix는 수행하지 않는다.

## 2. 공통 금지 항목

QA 중에도 아래 작업은 하지 않는다.

- Firebase rules/index 변경.
- Firestore schema 변경.
- migration/backfill.
- Storage object 삭제.
- Cloud copy 구현.
- npm audit fix.
- deploy.
- unrelated cleanup.
- 운영 사용자 데이터로 상태 주입.
- 운영 Firestore/Storage에서 수동 삭제.

## 3. QA 환경 분리

| 구분 | 가능한 검증 | 예시 |
|---|---|---|
| 로컬 조작/테스트 상태 주입 | SharedPreferences 기반 tier, purchaseDate, productId, local grace, UI 분기, CloudService gate 관찰 | active paid, expired within grace, expired after grace, free never paid, guest, grace UI |
| Store sandbox/Google Play Billing 필요 | 실제 purchase token 상태, cancelled/expired/refund/revoked/chargeback entitlement sync | cancelled before expiry, cancelled after expiry, refund/revoked/chargeback |
| 실제 Firebase 운영 배포 후 확인 | 운영 인프라에서 read/write 차단 로그, Storage object 미삭제, Firestore metadata 미증가 | release candidate smoke, 운영 로그 확인 |

권장 순서:

1. 로컬/개발 Firebase 환경에서 상태 주입 QA를 먼저 완료한다.
2. Store sandbox 계정으로 billing 상태 전파 QA를 완료한다.
3. 운영 배포 후에는 read-only smoke와 로그 확인만 수행한다. 운영 데이터 삭제/수정 검증은 하지 않는다.

## 4. 공통 증거 기록 방법

각 시나리오는 아래 증거 중 가능한 항목을 남긴다.

- 앱 화면 스크린샷: CloudBackupScreen, Library, Profile, snackbar/dialog.
- 앱 로그: `subscription_expired`, `subscription_expired_or_grace_ended`, `tier_required`, guest 차단 로그.
- Firestore 확인: `users/{uid}/videos` 문서 수, 신규 metadata 생성 여부, trash/moved/restore 관련 metadata write 여부.
- Storage 확인: `users/{uid}/videos/{videoId}/{fileName}` 신규 object 생성 여부, 삭제 object 없음.
- 로컬 확인: 원본 clip 파일 유지, restore된 로컬 파일 존재, local index/album 반영.
- Billing 증거: sandbox purchase 상태, cancelled/expired/refund/revoked/chargeback 상태 캡처.

QA 기록에는 실제 사용자 uid, token, order id 전체값, OAuth secret, keystore 정보는 남기지 않는다. 필요한 경우 uid/order id는 앞뒤 일부만 마스킹한다.

## 5. PASS/FAIL/BLOCKED 기준

| 판정 | 기준 |
|---|---|
| PASS | 준비 상태가 충족되고, 실행 절차 결과가 기대 결과와 일치하며, 필요한 증거가 기록됨 |
| FAIL | 신규 Cloud write 허용/차단, read/download 허용/차단, Storage 삭제 금지, metadata write 최소화 중 하나라도 정책과 다르게 동작함 |
| BLOCKED | Store sandbox 상태 전파 실패, 계정/기기 준비 실패, Firebase 접근 권한 부족, 테스트용 기존 Cloud clip 부재 등으로 결론을 낼 수 없음 |
| N/A | 해당 환경에서 의도적으로 검증하지 않는 항목. 예: 로컬 상태 주입 QA에서 실제 chargeback 전파 |

FAIL 발생 시 중단 기준:

- grace 중 신규 Storage object가 생성되면 중단.
- grace 종료 후 Cloud list/download가 허용되면 중단.
- refund/revoked/chargeback 상태에서 grace가 열리면 중단.
- R3 경로에서 Storage object 삭제가 발생하면 중단.

## 6. 로컬 조작/테스트 상태 주입 QA

### R3-MQA-01 Active Standard/Premium

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | 로그인 사용자, 개발 Firebase, 기존 또는 신규 로컬 clip, `currentTier=standard` 또는 `premium`, `purchaseDate`가 만료 전으로 계산되는 상태 |
| 실행 절차 | 1. Library에서 로컬 clip을 Cloud로 이동한다. 2. CloudBackupScreen에 진입한다. 3. Cloud clip을 download/restore한다. 4. Profile Cloud stats를 확인한다. |
| 기대 결과 | upload 허용, Storage object와 Firestore metadata 생성, Cloud list/read/download/restore 허용, Profile Cloud stats 표시 |
| 증거 | upload 성공 화면/로그, Firestore metadata, Storage object, Profile stats screenshot |
| PASS 기준 | 신규 write와 read/download가 모두 정상 동작하고 로컬 원본 보존 정책에 위배가 없음 |

### R3-MQA-02 Expired Within 30-Day Grace

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | 로그인 사용자, 기존 Cloud clip 1개 이상, paid productId와 purchaseDate가 있고 `lastKnownPaidExpiryAt` 이후 30일 이내로 계산되는 free/grace 상태 |
| 실행 절차 | 1. CloudBackupScreen에 진입한다. 2. 기존 Cloud 목록이 보이는지 확인한다. 3. Library에서 신규 Cloud upload를 시도한다. 4. 기존 Cloud clip download/restore를 시도한다. |
| 기대 결과 | Cloud list/read 허용, 신규 upload 차단, `subscription_expired` 안내, download/restore 허용 |
| 증거 | read-only 안내 screenshot, upload 차단 snackbar, download/restore 결과, 신규 Storage object 없음 |
| PASS 기준 | 신규 Cloud write는 모두 차단되고 기존 Cloud read/download만 허용됨 |

### R3-MQA-03 Expired After Grace

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | 로그인 사용자, 기존 Cloud clip 1개 이상, paid productId와 purchaseDate가 있고 `lastKnownPaidExpiryAt + 30일` 이후로 계산되는 상태 |
| 실행 절차 | 1. CloudBackupScreen에 진입한다. 2. Library Cloud placeholder/list 노출을 확인한다. 3. 기존 Cloud clip download/restore를 시도한다. 4. 신규 upload를 시도한다. |
| 기대 결과 | Cloud list/read/download/restore 차단, 신규 upload 차단, `subscription_expired_or_grace_ended` 또는 동등한 접근 종료 안내 |
| 증거 | 접근 차단 화면, 로그, Firestore/Storage 삭제 없음 확인 |
| PASS 기준 | Cloud 접근이 차단되고 기존 Cloud metadata/object는 삭제되지 않음 |

### R3-MQA-04 Free Never Paid

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | 로그인 사용자, `currentTier=free`, `purchaseDate/productId` 없음 |
| 실행 절차 | 1. Library에서 Cloud upload를 시도한다. 2. CloudBackupScreen 진입을 시도한다. 3. Profile Cloud stats를 확인한다. |
| 기대 결과 | 신규 upload 차단, Cloud read 차단, `tier_required` 계열 안내, Profile Cloud stats는 비활성 또는 `-`/0 상태 |
| 증거 | snackbar/dialog, Profile screenshot, 로그 |
| PASS 기준 | paid 이력이 없으므로 grace가 열리지 않음 |

### R3-MQA-05 Guest Mode

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | guest mode 또는 로그아웃 상태 |
| 실행 절차 | 1. Library Cloud upload를 시도한다. 2. CloudBackupScreen 진입을 시도한다. 3. Profile Cloud stats를 확인한다. |
| 기대 결과 | 로그인 필요 또는 guest 차단 안내, Cloud upload/read/download 불가 |
| 증거 | guest 안내 screenshot, 로그 |
| PASS 기준 | guest가 Cloud 접근을 시작할 수 없음 |

### R3-MQA-06 Grace 중 Library Upload 버튼/Auto Upload 차단

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | expired within grace 상태, 로컬 clip 1개 이상, auto upload 설정이 있다면 켜진 상태 |
| 실행 절차 | 1. Library 선택 모드에서 Cloud upload 버튼 노출/활성 상태를 확인한다. 2. 버튼을 눌러 upload를 시도한다. 3. 새 clip 저장 또는 queue restore 상황을 만들어 auto/queue upload를 관찰한다. |
| 기대 결과 | 버튼은 숨김 또는 차단 안내를 표시, 실행 시 `subscription_expired`로 차단, queue job은 삭제하지 않고 실패/대기 상태 보존, Storage upload 미실행 |
| 증거 | 버튼 상태 screenshot, snackbar, queue/log, 신규 Storage object 없음 |
| PASS 기준 | 모든 신규 Cloud write 경로가 grace에서 차단됨 |

### R3-MQA-07 Grace 중 CloudBackupScreen Read-Only 안내

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | expired within grace 상태, 기존 Cloud clip 1개 이상 |
| 실행 절차 | 1. CloudBackupScreen에 진입한다. 2. 상단/상태 영역에 read-only 또는 만료 grace 안내가 표시되는지 확인한다. 3. 신규 upload/copy를 유도하는 CTA가 없는지 확인한다. |
| 기대 결과 | 기존 Cloud clip은 보이고, 신규 upload가 불가능함을 명확히 안내, 삭제/정리 예정 문구 없음 |
| 증거 | CloudBackupScreen screenshot |
| PASS 기준 | grace가 read-only 상태로 이해 가능하고 write 유도 UI가 없음 |

### R3-MQA-08 Grace 중 Cloud Restore/Download

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | expired within grace 상태, 기존 Cloud clip 1개 이상, 로컬에 해당 파일이 없거나 restore 대상 album 준비 |
| 실행 절차 | 1. CloudBackupScreen 또는 Library cloud-only item에서 download/restore를 실행한다. 2. restore 후 로컬 Library/album에 표시되는지 확인한다. 3. Firestore/Storage 삭제가 없는지 확인한다. |
| 기대 결과 | download/restore 성공, 로컬 파일 생성, Cloud metadata/object 삭제 없음 |
| 증거 | restore 완료 화면, 로컬 파일/Library screenshot, Storage object 유지 확인 |
| PASS 기준 | grace 중 기존 Cloud clip 회수는 가능하고 Cloud 삭제는 발생하지 않음 |

### R3-MQA-09 Grace 중 Cloud Metadata Lifecycle Write 최소화

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | expired within grace 상태, 기존 Cloud clip 1개 이상, Firestore 콘솔 또는 emulator 로그 확인 가능 |
| 실행 절차 | 1. Cloud clip restore/download를 수행한다. 2. album move, trash/restore, favorite/update metadata 등 Cloud metadata write가 유발될 수 있는 UI를 확인한다. 3. Firestore `users/{uid}/videos` 문서의 update timestamp/field 변화 여부를 기록한다. |
| 기대 결과 | restore/download 중심 동작은 허용하되, active write 권한이 필요한 metadata lifecycle write는 차단 또는 생략됨 |
| 증거 | Firestore before/after screenshot, app log, restore result |
| PASS 기준 | grace 중 불필요한 Cloud metadata write가 발생하지 않음 |

### R3-MQA-10 Profile Cloud Stats 표시

| 항목 | 내용 |
|---|---|
| 분류 | 로컬 조작/테스트 상태 주입 |
| 준비 상태 | active paid, expired within grace, expired after grace, free never paid 상태별 계정 또는 상태 주입 |
| 실행 절차 | 1. 각 상태에서 Profile에 진입한다. 2. Cloud clip count/storage usage 표시를 확인한다. 3. grace 상태에서 stats가 read 가능 상태와 일치하는지 확인한다. |
| 기대 결과 | active/grace에서는 Cloud stats 조회 또는 표시 가능, grace 종료/free never paid/guest에서는 비활성 또는 0/`-` 처리 |
| 증거 | 상태별 Profile screenshot, Cloud stats refresh 로그 |
| PASS 기준 | Profile 표시 기준이 `canReadExistingCloudClips()` 정책과 일치함 |

## 7. Store Sandbox / Google Play Billing QA

### R3-SQA-01 Cancelled Before Expiry

| 항목 | 내용 |
|---|---|
| 분류 | Store sandbox 필요 |
| 준비 상태 | sandbox paid 구독 활성, expiry 전 cancel 수행 가능, entitlement refresh 경로 실행 가능 |
| 실행 절차 | 1. sandbox에서 구독을 구매한다. 2. expiry 전 구독을 cancel한다. 3. 앱에서 restore/refresh를 수행한다. 4. expiry 전 Cloud upload/read를 확인한다. |
| 기대 결과 | expiry 전까지 paid 유지, 신규 upload/read 허용, pending free 예약 또는 동등한 로그 확인 |
| 증거 | sandbox subscription status, app log, upload/read 결과 |
| PASS 기준 | cancel 직후 즉시 free 차단되지 않고 expiry 전 paid entitlement가 유지됨 |

### R3-SQA-02 Cancelled After Expiry

| 항목 | 내용 |
|---|---|
| 분류 | Store sandbox 필요 |
| 준비 상태 | cancelled subscription이 expiry를 지난 sandbox 계정, 기존 Cloud clip 1개 이상 |
| 실행 절차 | 1. expiry 이후 entitlement refresh를 수행한다. 2. Library upload를 시도한다. 3. CloudBackupScreen list/download를 확인한다. |
| 기대 결과 | free로 강등되되 purchase/product 이력이 보존되어 30일 grace read 가능, 신규 upload 차단 |
| 증거 | billing status, local/app log, read-only screenshot, upload 차단 로그 |
| PASS 기준 | cancelled after expiry가 단순 만료처럼 grace를 적용함 |

### R3-SQA-03 Refund/Revoked/Chargeback

| 항목 | 내용 |
|---|---|
| 분류 | Store sandbox 또는 결제 콘솔 상태 필요 |
| 준비 상태 | refund/revoked/chargeback류 inactive 상태를 만들 수 있는 sandbox/테스트 결제 환경 |
| 실행 절차 | 1. 결제 상태를 refund/revoked/chargeback류로 만든다. 2. 앱에서 entitlement refresh/restore를 수행한다. 3. Cloud upload/read/download를 시도한다. |
| 기대 결과 | grace 없이 free reset, 신규 upload 차단, 기존 Cloud read/download도 차단 |
| 증거 | billing state screenshot, app log, Cloud 접근 차단 screenshot |
| PASS 기준 | refund-like 상태에서 `purchaseDate/productId` 기반 grace가 열리지 않음 |
| BLOCKED 기준 | sandbox에서 해당 상태를 재현할 수 없으면 BLOCKED로 기록하고 가능한 대체 증거를 남김 |

## 8. 실제 Firebase 운영 배포 후 Smoke QA

운영 배포 후 확인은 데이터 변경을 최소화한다. 운영 QA 계정과 테스트용 clip만 사용한다.

### R3-PQA-01 Active Paid 운영 Smoke

| 항목 | 내용 |
|---|---|
| 분류 | 실제 Firebase 운영 배포 후 |
| 준비 상태 | 운영 QA 계정, active paid entitlement, 테스트용 로컬 clip |
| 실행 절차 | 1. 테스트 clip 1개를 Cloud upload한다. 2. CloudBackupScreen list/download를 확인한다. 3. Profile stats를 확인한다. |
| 기대 결과 | upload/read/download 정상 |
| 증거 | 화면 캡처, 운영 Firestore/Storage 테스트 object 확인 |
| 주의 | 테스트 object 정리는 기존 운영 정책에 따른다. R3 QA 중 임의 Storage 삭제 금지 |

### R3-PQA-02 Grace/Expired 운영 Smoke

| 항목 | 내용 |
|---|---|
| 분류 | 실제 Firebase 운영 배포 후 |
| 준비 상태 | 운영 QA 계정에서 안전하게 expired/grace 상태를 만들 수 있는 경우에만 수행 |
| 실행 절차 | 1. CloudBackupScreen 진입/read-only 안내를 확인한다. 2. 신규 upload가 차단되는지 확인한다. 3. 기존 Cloud download가 grace 정책에 맞게 동작하는지 확인한다. |
| 기대 결과 | 로컬 QA와 동일. 신규 write 차단, grace read/download 허용 또는 grace 종료 차단 |
| 증거 | 화면 캡처, 로그, 신규 object 미생성 확인 |
| BLOCKED 기준 | 운영에서 안전한 상태 주입/계정 준비가 어렵다면 BLOCKED로 기록하고 Store sandbox 결과로 대체 |

### R3-PQA-03 No Deletion Audit

| 항목 | 내용 |
|---|---|
| 분류 | 실제 Firebase 운영 배포 후 |
| 준비 상태 | 운영 QA 계정, Firebase console/log 접근 |
| 실행 절차 | 1. R3 관련 시나리오 수행 후 Storage object 삭제 이벤트 또는 Firestore purge가 있었는지 확인한다. 2. 테스트 계정 범위에서만 확인한다. |
| 기대 결과 | R3 경로에서 Storage delete/Firestore purge 없음 |
| 증거 | console/log screenshot |
| PASS 기준 | R3 QA 중 자동 삭제 또는 purge가 발생하지 않음 |

## 9. Scenario Coverage Matrix

| 필수 시나리오 | 로컬 상태 주입 | Store sandbox | 운영 배포 후 |
|---|---:|---:|---:|
| 1. active Standard/Premium | R3-MQA-01 | 선택 | R3-PQA-01 |
| 2. expired within 30-day grace | R3-MQA-02 | 선택 | R3-PQA-02 |
| 3. expired after grace | R3-MQA-03 | 선택 | R3-PQA-02 |
| 4. cancelled before expiry | 제한적 | R3-SQA-01 | 선택 |
| 5. cancelled after expiry | 제한적 | R3-SQA-02 | 선택 |
| 6. refund/revoked/chargeback | 제한적 reset 확인 | R3-SQA-03 | 선택 |
| 7. free never paid | R3-MQA-04 | N/A | 선택 |
| 8. guest mode | R3-MQA-05 | N/A | 선택 |
| 9. grace 중 Library upload 버튼/auto upload 차단 | R3-MQA-06 | 선택 | 선택 |
| 10. grace 중 CloudBackupScreen read-only 안내 | R3-MQA-07 | 선택 | 선택 |
| 11. grace 중 Cloud restore/download | R3-MQA-08 | 선택 | 선택 |
| 12. grace 중 Cloud metadata lifecycle write 최소화 확인 | R3-MQA-09 | 선택 | R3-PQA-03 |
| 13. Profile Cloud stats 표시 확인 | R3-MQA-10 | 선택 | R3-PQA-01/R3-PQA-02 |

## 10. QA 결과 기록 템플릿

```md
## R3 QA Result

- Date:
- Tester:
- App build/version:
- Platform/device:
- Firebase environment: local emulator / dev / production
- Billing environment: local state injection / Google Play sandbox / none
- Account type: active paid / grace / expired / free / guest
- Test account id: masked only

### Scenario

- ID:
- Title:
- Preconditions:
- Steps executed:
- Expected result:
- Actual result:
- Verdict: PASS / FAIL / BLOCKED / N/A

### Evidence

- Screenshots:
- Logs:
- Firestore before/after:
- Storage before/after:
- Local file/index evidence:
- Billing evidence:

### Notes

- Deviations:
- Risks:
- Follow-up owner:
- Follow-up issue/doc:
```

## 11. R3 Release Gate

R3를 release-ready로 보려면 아래 조건을 만족해야 한다.

필수 PASS:

- R3-MQA-01 active Standard/Premium.
- R3-MQA-02 expired within 30-day grace.
- R3-MQA-03 expired after grace.
- R3-MQA-04 free never paid.
- R3-MQA-05 guest mode.
- R3-MQA-06 grace 중 Library upload/auto upload 차단.
- R3-MQA-07 grace 중 CloudBackupScreen read-only 안내.
- R3-MQA-08 grace 중 Cloud restore/download.
- R3-MQA-09 grace 중 Cloud metadata lifecycle write 최소화.
- R3-MQA-10 Profile Cloud stats 표시.

Store sandbox 필수 PASS 또는 명시적 BLOCKED 승인:

- R3-SQA-01 cancelled before expiry.
- R3-SQA-02 cancelled after expiry.
- R3-SQA-03 refund/revoked/chargeback.

운영 배포 후 확인:

- R3-PQA-01 active paid smoke.
- R3-PQA-03 no deletion audit.
- R3-PQA-02는 안전한 운영 QA 계정이 있을 때만 수행한다. 안전한 계정이 없으면 Store sandbox 결과로 대체하고 BLOCKED 사유를 기록한다.

Release gate FAIL 조건:

- grace 상태에서 신규 Cloud upload, auto upload, queue upload, copy가 허용됨.
- grace 종료 후 Cloud list/read/download/restore가 허용됨.
- refund/revoked/chargeback류 상태에서 grace가 열림.
- R3 경로에서 Storage object 삭제 또는 Firestore purge가 발생함.
- active paid에서 기존 정상 Cloud upload/read/download가 회귀됨.
- Profile/CloudBackup/Library UI가 서로 다른 권한 기준을 보여 사용자가 write 가능 상태로 오해할 수 있음.

최종 판정:

- 모든 필수 로컬 QA가 PASS이고, Store sandbox 항목이 PASS 또는 승인된 BLOCKED로 정리되며, no deletion audit이 PASS이면 R3 manual QA를 PASS로 닫을 수 있다.

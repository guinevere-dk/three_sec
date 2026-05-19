# Cloud Clip 구현 보류 항목 상세 실행 가이드 v1

## 0. 문서 목적과 범위

이 문서는 Cloud Clip 남은 리스크 중 이전 작업에서 구현하지 않은 R1, R2, R3, R4, R5, R7 항목을 실제 후속 작업으로 전환하기 위한 상세 실행 가이드다.

이번 문서는 실행 절차, 승인 지점, QA 기준, 완료 조건을 정의하기 위한 Markdown 문서이며, 실제 코드, Firebase 설정, Functions, rules, index, DB schema, Storage 객체, SharedPreferences key, IAP product id는 변경하지 않는다.

## 1. 기준 문서와 공통 원칙

### 1.1 우선 확인한 기준 문서

- [AGENTS.md](../AGENTS.md): 사용자 데이터 보존, 기존 기능 유지, 레거시 호환을 최우선으로 둔다.
- [CURRENT_PHASE.md](../CURRENT_PHASE.md): 현재 단계에서 Markdown 운영 문서 정리는 즉시 허용되지만, Firestore/Storage schema/path/rules, Functions endpoint, migration/backfill/purge는 승인 필요 작업이다.
- [DATA_COMPATIBILITY.md](../DATA_COMPATIBILITY.md): `videos`, `users`, `vlog_projects`, `users/{uid}/videos/{videoId}/{fileName}`, `3s_*`, `local_index_entries_v1` 등 데이터 계약은 변경하지 않는다.
- [plans/cloud_clip_remaining_risk_resolution_plan_v1.md](cloud_clip_remaining_risk_resolution_plan_v1.md): Cloud copy, 영구 삭제, 구독 만료 정책, migration/backfill, Firebase rules/index 변경은 독립 단계로 처리한다.
- [plans/cloud_clip_remaining_risk_resolution_report_v1.md](cloud_clip_remaining_risk_resolution_report_v1.md): R1~R5는 구현 전 승인/설계/검증이 필요하고, R7은 테스트 계정과 테스트 장비 기준으로 즉시 안전 수행 가능한 QA 성격의 작업이다.

### 1.2 모든 항목에 적용되는 공통 금지선

- Firestore 컬렉션명 `videos`, `users`, `vlog_projects`를 바꾸지 않는다.
- Storage 경로 `users/{uid}/videos/{videoId}/{fileName}`를 바꾸지 않는다.
- SharedPreferences key `3s_*`, `cloud_synced_paths`, `local_index_entries_v1`, `tutorial_completed_user_{uid}`, `isFirstRun`을 바꾸지 않는다.
- IAP product id `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual`을 바꾸지 않는다.
- Firebase project id 또는 alias `fir-3s-8edb9`를 바꾸지 않는다.
- 사용자 원본 영상, 프로젝트 JSON, local index, Cloud metadata, 계정 소유권, 구독/결제 상태를 삭제하거나 초기화하지 않는다.
- 삭제, migration, backfill, rules 변경은 반드시 dry-run, 수동 승인, rollback 또는 rollback 한계 문서화, staged rollout을 거친다.
- 하나의 작업 패키지에서 Flutter UI, Functions, Firebase rules/index, DB schema, Storage deletion을 동시에 변경하지 않는다.

## 2. 구현 보류 항목 전체 목록과 보류 이유 요약

| ID | 항목 | 보류 이유 | 먼저 필요한 산출물 |
|---|---|---|---|
| R1 | Cloud copy | 새 Storage 객체, 새 metadata, usage 증가, quota, 실패 상태, 새 `videoId`, idempotent usage event 계약이 필요하다. | UX 결정서, API 방식 결정, usage accounting 계약, QA matrix |
| R2 | Storage 영구 삭제 자동화 | 사용자 영상 삭제와 비용/usage 정합성에 직접 영향이 있고 Storage rollback이 제한될 수 있다. | retention 정책, inventory dry-run, manifest, 승인 gate, batch execute 설계 |
| R3 | 구독 만료 Cloud 접근/삭제 정책 | grace 기간, 다운로드 허용, 신규 upload/copy 차단, 사용자 고지, CS 정책이 미확정이다. | Product/Ops 정책 결정서, sandbox QA 결과, 구현 순서 |
| R4 | migration/backfill | 기존 `videos` 문서 field 분포 확인 전 data mutation은 위험하다. | 익명 inventory 집계, fallback 유지 기준, 최소 backfill 계획 |
| R5 | Firebase rules/index 변경 | rules 변경은 보안 완화 위험이 있고 index 변경은 배포와 query 동작에 영향을 준다. | 현재 query 목록, emulator/test 검증 결과, 최소 변경안 |
| R7 | 실제 QA | quota, 저장공간, 재설치, 구독 만료 등 실사용 경계조건 검증이 남아 있다. | 테스트 계정/장비 기반 QA 결과표, 릴리스 gate 판정 |

## 3. R1 Cloud copy 상세 가이드

### 3.1 목표

Cloud copy는 현재 기본 local copy 흐름과 분리된 명시 선택 기능으로 설계한다. 사용자가 Cloud까지 복사한다고 선택한 경우에만 새 Cloud 객체와 metadata를 만들고 Cloud usage를 증가시킨다.

### 3.2 결정해야 할 UX

| UX 결정 항목 | 선택지 | 권장 방향 | 승인자 |
|---|---|---|---|
| 진입점 | 복사 메뉴 안의 보조 선택, 별도 메뉴, 복사 후 Cloud 업로드 제안 | 기본 복사는 local copy 유지, Cloud copy는 명시 버튼으로 분리 | Product/Design |
| 문구 | Cloud까지 복사, 클라우드 복사본 만들기, 백업 포함 복사 | quota 증가와 네트워크 사용을 명확히 알리는 문구 | Product/CS |
| 비용/용량 안내 | 사전 안내, quota 부족 시 차단, 진행 중 안내 | 실행 전 예상 용량과 남은 quota를 표시 | Product/Flutter |
| 실패 표시 | local_only fallback, failed_cloud_copy 상태, 재시도 CTA | 원본 유지와 복사본 상태를 분리 표시 | Product/Flutter |
| 오프라인 처리 | 즉시 차단, queue 등록, local copy만 허용 | Cloud copy는 온라인 필요로 차단하거나 명시 queue 정책 확정 전 차단 | Product/Backend |

### 3.3 API/클라이언트 방식 선택지

| 방식 | 장점 | 리스크 | 적용 조건 |
|---|---|---|---|
| client download/upload | 기존 업로드 경로 재사용 가능, 구현 이해가 쉽다. | 대역폭/배터리 사용 증가, 큰 파일에서 실패 가능성 증가, 원본 다운로드 권한 필요 | 작은 파일 중심, 명확한 진행률 표시가 필요할 때 |
| server-side copy | 사용자 네트워크 비용 감소, 원본 Storage 객체를 서버에서 복사 가능 | Functions 권한, idempotency, quota precheck, owner validation 구현 필요 | 안정적인 Cloud copy와 운영 로깅이 필요할 때 |
| hybrid | local 파일이 있으면 client upload, Cloud-only이면 server-side copy | 분기 복잡도 증가, QA matrix 확대 | local/cloud 상태가 혼재된 실제 서비스 상황 |

권장 1차 방향은 server-side copy 설계안 작성 후 dry-run 또는 mock API로 검증하는 것이다. 실제 Functions 구현은 별도 승인 후 진행한다.

### 3.4 usage accounting idempotency

필수 계약:

1. Cloud copy 요청에는 원본 `videoId`, 대상 `videoId`, 요청자 `uid`, 원본 `storagePath`, 대상 `storagePath`, 예상 `fileSize`, client request id를 포함한다.
2. usage 증가 이벤트는 `users/{uid}/usageEvents/{eventId}` 계약을 사용하고, event id는 중복 요청에서도 동일하게 계산 가능해야 한다.
3. 권장 event id 형식은 논리적으로 `cloud_copy:{uid}:{sourceVideoId}:{targetVideoId}:{sourceGenerationOrHash}`에 해당하는 멱등 key다. 실제 저장 전에는 비밀값이나 원본 개인정보를 포함하지 않는지 검토한다.
4. Storage copy 성공 전 usage를 증가시키지 않는다. 단, reservation 모델을 도입할 경우 reservation과 commit/cancel 이벤트를 분리한다.
5. 동일 event id가 이미 성공 처리된 경우 usage를 중복 증가시키지 않고 기존 성공 결과를 반환한다.
6. 대상 metadata 생성 실패와 Storage copy 성공이 엇갈린 경우 orphan 객체 inventory와 cleanup 정책을 별도로 둔다. 자동 삭제는 R2 gate를 따른다.

### 3.5 quota, 오프라인, 객체 누락 실패 처리

| 실패 조건 | 기대 동작 | 사용자 데이터 보호 기준 | QA 포인트 |
|---|---|---|---|
| quota 부족 | 실행 전 차단, 업그레이드 또는 정리 안내 | 원본과 기존 metadata 변경 없음 | usage 증가 event가 없어야 함 |
| 오프라인 | Cloud copy 차단 또는 명시 queue 처리 | local copy가 생성되어도 Cloud copy 실패와 분리 | 온라인 복귀 후 중복 생성 방지 |
| 원본 Storage 객체 누락 | Cloud copy 실패, 원본 metadata는 유지 | 누락을 이유로 원본 metadata 삭제 금지 | missing object error code 기록 |
| 원본 권한 불일치 | 요청 거부 | 다른 사용자의 객체 접근 금지 | deny case 필수 테스트 |
| target metadata 생성 실패 | 실패 상태 기록 또는 전체 rollback | 원본 유지, usage 중복 증가 금지 | orphan Storage 객체 점검 |
| Storage copy 성공 후 usage commit 실패 | retry 가능한 pending 상태 | usage 정합성 회복 전 완료로 표시 금지 | idempotent retry 확인 |

### 3.6 QA matrix

| 시나리오 | 조건 | 기대 결과 |
|---|---|---|
| local 원본 있음 + Standard | local copy와 Cloud copy가 분리 노출 | Cloud copy 선택 시 새 Cloud metadata와 usage 증가 |
| Cloud-only 원본 + Standard | server-side copy 또는 다운로드 필요 | 원본 Storage 객체가 있으면 복사 성공 |
| Free 사용자 | Cloud copy 차단 | 기존 Cloud metadata 유지, 신규 Cloud 객체 없음 |
| quota 임박 | 예상 용량 기준 precheck | quota 초과면 Storage copy 전 차단 |
| 오프라인 | 네트워크 없음 | Cloud copy 실행 차단 또는 queue 상태 보존 |
| 원본 Storage 객체 삭제됨 | metadata만 남음 | 사용자에게 복사 불가 표시, 원본 metadata 삭제 금지 |
| 중복 탭/재시도 | 동일 요청 반복 | 대상 중복 생성 또는 usage 중복 증가 없음 |
| 다른 uid 객체 참조 | 악의적 요청 | 권한 거부, broad allow 없음 |

### 3.7 구현 순서

1. Product/Design이 Cloud copy UX와 사용자 문구를 승인한다.
2. Backend/Flutter가 source/target metadata, request id, usage event idempotency 계약을 문서화한다.
3. API 방식을 server-side, client, hybrid 중 하나로 결정한다.
4. quota precheck와 실패 code/errorCopy 매핑을 정의한다.
5. mock 또는 dry-run API로 QA matrix를 먼저 검증한다.
6. Flutter UI에서 local copy와 Cloud copy를 명확히 분리한다.
7. Functions 또는 client copy 구현을 별도 작업으로 진행한다.
8. usageEvents 중복 방지와 Storage/Firestore 정합성 검증을 릴리스 gate로 둔다.

### 3.8 절대 하지 말 것

- 기본 복사 기능을 조용히 Cloud copy로 바꾸지 않는다.
- quota precheck 없이 Storage 객체를 먼저 만들지 않는다.
- usage event 없이 `storageUsage`를 직접 증감하지 않는다.
- 원본 객체 누락을 이유로 원본 metadata나 local index를 삭제하지 않는다.
- 다른 사용자의 `storagePath`를 copy할 수 있도록 rules를 완화하지 않는다.

### 3.9 완료 조건

- UX, API 방식, usage idempotency 계약이 승인되어 있다.
- quota, 오프라인, 객체 누락, 권한 불일치, 중복 요청 QA가 통과한다.
- local copy와 Cloud copy가 UI/상태/로그에서 분리되어 있다.
- usage 증가가 정확히 한 번만 발생한다.
- 원본 영상과 원본 metadata 보존이 확인된다.

## 4. R2 Storage 영구 삭제 자동화 상세 가이드

### 4.1 목표

Trash retention이 지난 Cloud 객체를 안전하게 영구 삭제하여 Storage 비용과 usage 정합성을 관리한다. 실제 삭제는 되돌릴 수 없거나 제한적이므로 dry-run과 수동 승인 gate를 필수로 둔다.

### 4.2 retention 정책

결정 항목:

- Trash 진입 시점 기준 retention 기간.
- 구독 만료 grace 정책과 Trash retention의 우선순위.
- 사용자가 직접 영구 삭제를 누른 경우와 자동 purge의 차이.
- 법적/CS 보존 필요성이 있는 계정 제외 조건.
- pending upload, failed upload, restore pending, cloud copy pending 상태 제외 조건.

권장 원칙:

1. retention 기간이 지나지 않은 객체는 절대 삭제하지 않는다.
2. `lifecycleState=trash` 또는 이에 준하는 tombstone 상태만 후보로 둔다.
3. active, restore pending, upload pending, failed but recoverable 상태는 제외한다.
4. 구독 만료로 인한 삭제는 R3 정책 확정 전 R2 자동 삭제 대상에 포함하지 않는다.

### 4.3 inventory query

inventory는 실제 삭제 없이 대상 후보를 산출한다.

필수 필터:

- `uid` 존재.
- `videoId` 존재.
- `storagePath` 존재.
- `storagePath`가 `users/{uid}/videos/{videoId}/{fileName}` prefix 계약과 일치.
- tombstone 또는 trash 상태.
- retention cutoff 이전.
- upload/copy/restore pending이 아님.
- usage 차감 완료 event가 아직 없음.

출력은 개인정보와 실제 경로 노출을 최소화한다.

권장 집계:

- 대상 count.
- fileSize 합계.
- uid별 count의 익명 분포.
- storagePath hash 목록.
- 제외 사유별 count.
- 데이터 이상치 목록: fileSize 없음, storagePath 불일치, metadata는 있으나 object 없음, object는 있으나 metadata 없음.

### 4.4 dry-run manifest

manifest는 execute 전 수동 승인과 사후 감사의 기준이다.

필수 필드:

- manifest id.
- 생성 시각.
- 실행 환경.
- query version.
- retention cutoff.
- candidate count.
- candidate fileSize sum.
- 익명 uid hash.
- videoId hash.
- storagePath hash.
- expected usage decrement.
- 제외 사유 summary.
- 승인자, 승인 시각, 승인 범위.

manifest에는 실제 사용자 uid, 실제 token, 비밀값, 서비스 계정 key를 저장하지 않는다.

### 4.5 수동 승인 gate

execute 전 필수 확인:

1. manifest count와 fileSize 합계가 예상 범위 안에 있다.
2. 샘플 hash를 운영자가 원본 데이터와 대조했을 때 모두 trash/tombstone 상태다.
3. active/pending 상태가 포함되지 않았음이 확인됐다.
4. storagePath prefix가 `users/{uid}/videos/{videoId}/{fileName}` 계약과 일치한다.
5. usage 차감 event idempotency key가 중복 차감을 막는다.
6. rollback 한계가 승인자에게 고지됐다.
7. execute batch 크기와 중단 조건이 승인됐다.

### 4.6 execute batch

권장 실행 절차:

1. manifest id를 입력으로 받는다.
2. manifest가 approved 상태인지 확인한다.
3. batch 단위로 Storage object existence를 재확인한다.
4. Firestore metadata 상태가 dry-run 이후 active/restore로 바뀌지 않았는지 재확인한다.
5. Storage delete를 실행한다.
6. 성공한 객체에 대해서만 usage decrement event를 idempotent하게 기록한다.
7. Firestore metadata에는 tombstone과 deletion result를 기록하되 원본 추적에 필요한 최소 metadata는 보존한다.
8. 실패한 객체는 retry 가능한 상태와 error code를 남긴다.
9. batch마다 성공/실패/skip count와 usage delta를 기록한다.

### 4.7 usage 차감 멱등성

필수 원칙:

- delete event id는 `storage_delete:{uid}:{videoId}:{storagePathHash}:{manifestId}`에 준하는 멱등 key로 설계한다.
- 같은 Storage object에 대해 usage가 두 번 차감되지 않아야 한다.
- Storage object가 이미 없더라도 과거 차감 event가 없다면 metadata 상태와 이전 delete 시도 기록을 확인한 뒤 처리한다.
- fileSize가 없거나 신뢰할 수 없으면 usage 차감은 보류하고 anomaly로 분리한다.
- usage 차감 실패 시 삭제 완료로 사용자에게 표시하지 않는다. 운영 재처리 대상이 되어야 한다.

### 4.8 rollback 한계

명시해야 할 사실:

- Storage 객체 삭제 후 원본 파일 복구는 불가능하거나 보장되지 않는다.
- Firestore metadata export나 manifest는 객체 자체를 복구하지 못한다.
- rollback은 주로 metadata 상태 복구, usage 재가산, 사용자 표시 상태 수정에 한정된다.
- 따라서 실제 삭제 전 retention, dry-run, manifest, 승인 gate가 rollback보다 더 중요하다.

### 4.9 모니터링

필수 지표:

- dry-run candidate count 추이.
- execute success/fail/skip count.
- deleted fileSize 합계.
- usage decrement event count와 delta 합계.
- Storage object not found count.
- metadata state changed skip count.
- anomaly count.
- batch duration과 retry count.
- 사용자 문의 또는 restore 실패 신고 수.

### 4.10 QA/운영 체크리스트

| 체크 | 기대 결과 |
|---|---|
| retention 미도달 trash | 삭제 후보에서 제외 |
| retention 도달 trash | dry-run 후보 포함, execute 전 승인 필요 |
| active Cloud clip | 후보 제외 |
| restore pending | 후보 제외 |
| upload pending | 후보 제외 |
| storagePath prefix 불일치 | anomaly 격리 |
| object already missing | usage 차감 중복 없이 anomaly 또는 재조정 |
| batch 중단 | 완료 batch만 반영, 남은 batch 재개 가능 |
| 중복 execute | 같은 manifest/object usage 중복 차감 없음 |

### 4.11 절대 하지 말 것

- dry-run manifest 없이 execute하지 않는다.
- retention 미도달 객체를 삭제하지 않는다.
- active 또는 pending 상태 객체를 삭제하지 않는다.
- storagePath prefix 검증 없이 삭제하지 않는다.
- usage 차감 event 없이 `storageUsage`를 직접 줄이지 않는다.
- rollback 가능하다고 사용자 또는 운영 문서에 표현하지 않는다.

### 4.12 완료 조건

- retention, inventory query, manifest 형식, 승인 gate가 문서화되고 승인됐다.
- dry-run 결과가 검토되고 이상치가 분리됐다.
- execute는 batch, skip, retry, monitoring 기준을 만족한다.
- usage 차감 멱등성이 검증됐다.
- rollback 한계가 명확히 고지됐다.

## 5. R3 구독 만료 Cloud 정책 상세 가이드

### 5.1 목표

구독 만료 시 사용자 데이터 보존과 결제 권한 제한을 동시에 만족하는 Cloud 접근 정책을 확정한다. 삭제는 가장 마지막 단계이며, 우선은 신규 Cloud 작업 차단과 기존 데이터 보존 정책을 분리한다.

### 5.2 grace 기간

결정 항목:

- 만료 직후 grace 제공 여부.
- grace 기간 길이.
- grace 기간 중 Cloud Library placeholder 노출 여부.
- grace 기간 중 다운로드/복원 허용 여부.
- grace 종료 후 정책: 읽기 제한, 다운로드 제한, 삭제 예정 표시, 장기 보존, 영구 삭제 검토.

권장 원칙:

1. 만료 직후 기존 Cloud 데이터를 즉시 삭제하지 않는다.
2. grace 기간 동안 기존 metadata와 Profile count를 보존한다.
3. 신규 upload와 Cloud copy는 만료 즉시 차단한다.
4. grace 기간 중 읽기전용 다운로드 허용을 기본 정책 후보로 검토한다.
5. grace 이후 삭제가 필요하면 R2의 dry-run/manifest/승인 gate를 반드시 따른다.

### 5.3 읽기전용 다운로드 허용 여부

| 정책 | 장점 | 리스크 | 필요 문구 |
|---|---|---|---|
| grace 중 다운로드 허용 | 사용자 데이터 회수 기회 보장, CS 리스크 감소 | Free 상태에서 Cloud egress 비용 발생 | 기간 내 백업/다운로드 안내 |
| grace 중 다운로드 차단 | 유료 기능 경계 명확 | 데이터 접근 불만과 CS 증가 | 재구독 또는 restore 안내 |
| metadata만 노출 | 데이터 존재 인지 가능 | 사용자가 실제 복구 불가로 인식할 수 있음 | 접근 제한과 복구 방법 명확화 |

권장 1차 정책은 grace 중 읽기전용 다운로드 허용, 신규 upload/copy 차단이다.

### 5.4 신규 upload/copy 차단

차단 대상:

- Standard 자동 업로드.
- 수동 Cloud 백업.
- Cloud copy.
- retry queue 중 아직 Cloud 객체가 생성되지 않은 작업.

보존 대상:

- 기존 Cloud metadata.
- 기존 Cloud object.
- local 원본.
- Trash/tombstone metadata.
- 사용량 기록과 결제 이력.

구현 주의:

- 구독 tier 판정은 기존 `3s_*` product id와 SharedPreferences key 계약을 유지한다.
- Free 전환 시 local_only로 조용히 전환되는 경로가 있으면 사용자에게 명확히 안내한다.
- queue에 남아 있는 upload 작업은 삭제하지 않고 blocked_by_subscription 같은 재시도 가능한 상태로 분리한다.

### 5.5 사용자 고지/CS

필수 고지:

- 구독 만료로 신규 Cloud upload/copy가 중지됨.
- 기존 Cloud 데이터가 즉시 삭제되지 않는지 여부.
- 다운로드 가능 기간 또는 접근 제한 기준.
- 재구매/restore 시 권한 회복 방식.
- 삭제 예정이 있다면 사전 고지, export 기회, 삭제 예정일.

CS 운영 기준:

- sandbox와 실제 결제 상태 불일치 이슈 대응 절차.
- 구독 restore 실패 시 확인할 정보 목록.
- 사용자가 Cloud 데이터 삭제를 요청한 경우 R2 deletion gate 적용 여부.
- grace 종료 후 데이터 접근 문의 대응 문구.

### 5.6 sandbox QA

| 시나리오 | 절차 | 기대 결과 |
|---|---|---|
| 만료 전 Standard | sandbox 구매 후 Cloud upload | upload 허용, Profile tier Standard |
| 만료 직후 | sandbox 만료 대기 또는 상태 강제 갱신 | 신규 upload/copy 차단, 기존 metadata 보존 |
| grace 중 다운로드 | 기존 Cloud clip 복원 또는 다운로드 | 정책에 따라 허용 또는 명확한 차단 문구 |
| grace 종료 후 | 정책 적용 상태 확인 | 삭제가 아니라면 metadata 보존, 삭제라면 R2 gate 필요 |
| 재구매 | sandbox 재구매 | upload/copy 권한 회복, 기존 metadata 연결 유지 |
| restore purchases | 앱 재설치 후 restore | tier와 Cloud 접근 권한 복구 |
| 오프라인 만료 상태 | 네트워크 끊김 후 앱 실행 | 기존 local 데이터 보존, Cloud 작업 보수적 차단 또는 명확한 pending |

### 5.7 재구매/restore 처리

필수 기대 동작:

- 재구매 후 신규 Cloud upload와 Cloud copy가 다시 허용된다.
- 기존 Cloud metadata와 Storage 객체 연결이 유지된다.
- blocked_by_subscription queue는 중복 없이 재개 또는 사용자가 재시도할 수 있다.
- restore purchases 후 tier 상태가 `users/{uid}`와 local state에 일관되게 반영된다.
- product id는 기존 `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual`을 유지한다.

### 5.8 구현 순서

1. Product/Ops가 grace 기간, 다운로드 허용 여부, grace 이후 정책을 승인한다.
2. CS 문구와 사용자 고지 문구를 승인한다.
3. sandbox QA로 현재 동작을 기록한다.
4. 신규 upload/copy 차단 정책을 Cloud upload queue와 Cloud copy 진입점에 분리 적용한다.
5. 기존 Cloud metadata와 placeholder 보존을 검증한다.
6. restore/rebuy 후 권한 회복을 QA한다.
7. grace 이후 삭제가 결정된 경우 R2의 dry-run/manifest/승인 gate로 별도 진행한다.

### 5.9 절대 하지 말 것

- 구독 만료 즉시 Cloud object나 metadata를 삭제하지 않는다.
- Free 전환 시 local index 또는 Cloud placeholder를 초기화하지 않는다.
- product id나 subscription tier 저장 key를 바꾸지 않는다.
- grace 정책 확정 전 삭제 자동화를 구현하지 않는다.
- 결제 상태가 불확실한 사용자를 데이터 삭제 대상으로 삼지 않는다.

### 5.10 완료 조건

- grace, 다운로드 허용, 신규 upload/copy 차단, grace 이후 정책이 승인되어 있다.
- sandbox QA에서 만료, 재구매, restore 시나리오가 통과한다.
- 기존 Cloud metadata와 local 원본 보존이 확인된다.
- 사용자 고지와 CS 대응 기준이 준비되어 있다.
- 삭제가 필요한 경우 R2 gate와 연결되어 있다.

## 6. R4 migration/backfill 상세 가이드

### 6.1 목표

기존 `videos` 문서의 optional field 분포를 파악하고, read fallback으로 충분한지 판단한 뒤, 꼭 필요한 최소 field만 staged backfill한다.

### 6.2 inventory dry-run

dry-run은 mutation 없이 익명 집계만 수행한다.

대상 field 후보:

- `storagePath`
- `storageTier`
- `lifecycleState`
- `cloudState`
- `originalStoragePath`
- `originalStorageTier`
- `fileSize`
- `uploadStatus`
- `completedAt`
- `errorCode`

집계 항목:

- field 존재율.
- null 또는 빈 문자열 비율.
- field 조합별 count.
- `storagePath` prefix 정합성 비율.
- `uid`와 document owner 정합성.
- upload/trash/restore 상태별 field 분포.
- old client로 추정되는 문서 비율.

### 6.3 field 분포 익명 집계

개인정보 보호 기준:

- 실제 uid, fileName, downloadUrl, localPath를 로그나 문서에 남기지 않는다.
- uid는 hash 또는 bucket count로만 표현한다.
- storagePath는 prefix 정합성 여부와 hash로만 표현한다.
- 샘플링이 필요하면 테스트 계정 또는 운영 승인된 익명 샘플만 사용한다.

권장 출력:

| 집계 | 예시 표현 |
|---|---|
| 전체 문서 수 | total videos count |
| storagePath 있음 | count, percent |
| lifecycleState 없음 | count, percent |
| cloudState 없음 | count, percent |
| trash인데 originalStoragePath 없음 | count, percent |
| prefix 불일치 | anomaly count |
| fileSize 없음 | count, percent |

### 6.4 fallback 유지 기준

backfill하지 않고 fallback을 유지할 수 있는 경우:

- old client 문서가 정상 read 가능하다.
- field가 없어도 기본값으로 UI/logic이 안전하게 동작한다.
- Trash/restore에서 원본 metadata 손실 없이 동작한다.
- uploadStatus 또는 cloudState가 없어도 local/cloud 상태를 보수적으로 표시할 수 있다.
- missing field가 삭제나 usage 차감을 유발하지 않는다.

fallback으로 부족한 경우:

- restore에 필요한 original path/tier가 없어 복구 실패가 발생한다.
- deletion candidate 판정에서 active와 trash를 구분할 수 없다.
- usage accounting에 필요한 fileSize가 없어 정합성 회복이 불가능하다.
- old 문서가 Library placeholder 누락을 일으킨다.

### 6.5 최소 backfill 대상 선정

선정 원칙:

1. 사용자 데이터 보존에 직접 필요한 field만 대상으로 삼는다.
2. field rename은 하지 않는다.
3. 컬렉션명, document id, Storage path는 변경하지 않는다.
4. 기존 field 값을 덮어쓰지 않는다. 비어 있거나 없는 field만 보수적으로 채운다.
5. 추론이 불확실하면 backfill하지 않고 anomaly로 분리한다.

가능한 최소 대상 예시:

- trash 상태인데 lifecycle marker가 없고, 기존 tombstone 근거가 명확한 문서.
- Cloud placeholder 복원에 필요한 cloudState 기본값이 명확한 문서.
- fileSize가 metadata와 Storage object metadata에서 일치 확인된 문서.

### 6.6 staged rollout

단계:

1. dry-run inventory만 실행한다.
2. 결과를 검토하고 backfill 필요 여부를 결정한다.
3. 테스트 계정 또는 staging project에서 backfill script를 검증한다.
4. 운영 샘플 소수 uid hash bucket에 dry-run과 write preview를 수행한다.
5. 승인 후 작은 batch로 실제 backfill한다.
6. 각 batch 후 read fallback, Library placeholder, Trash/restore, usage count를 검증한다.
7. 이상치가 발견되면 즉시 중단하고 기존 fallback 유지로 되돌린다.

### 6.7 rollback/검증

rollback 전략:

- backfill 전 변경 예정 field와 기존 값을 manifest에 기록한다.
- 새로 추가한 field는 rollback 시 제거 또는 이전 값 복원이 가능해야 한다.
- 기존 field를 덮어쓴 경우 rollback이 어렵기 때문에 원칙적으로 덮어쓰지 않는다.
- rollback 후 old/new client read가 모두 가능한지 확인한다.

검증 항목:

- app 재시작 후 Library count 유지.
- 로그아웃/로그인 후 Cloud placeholder 유지.
- Trash 이동과 restore 후 metadata 보존.
- Storage path와 Firestore `storagePath` 정합성.
- usage count 불변 또는 의도한 보정만 반영.

### 6.8 절대 하지 말 것

- inventory 없이 backfill하지 않는다.
- field rename, 컬렉션명 변경, Storage path rename을 하지 않는다.
- SharedPreferences key 또는 local index schema를 변경하지 않는다.
- 추론 불확실한 문서를 자동 보정하지 않는다.
- backfill과 deletion을 같은 작업으로 묶지 않는다.

### 6.9 완료 조건

- field 분포 익명 집계가 완료되어 있다.
- fallback 유지 가능 문서와 backfill 필요 문서가 분리되어 있다.
- 최소 backfill 대상과 skip 조건이 승인되어 있다.
- staged rollout과 rollback manifest가 준비되어 있다.
- old/new client 호환 검증이 통과한다.

## 7. R5 Firebase rules/index 상세 가이드

### 7.1 목표

현재 Cloud Clip 관련 query가 기존 rules/index에서 동작하는지 먼저 검증하고, 필요한 경우 보안 완화 없이 최소 index 또는 rule 변경안을 별도 승인한다.

### 7.2 현재 query 수집

수집 대상:

- Flutter에서 `videos`를 조회하는 모든 query.
- `users/{uid}`와 `users/{uid}/usageEvents/{eventId}` 접근 경로.
- Cloud backup/restore, Trash/restore, Profile stats, upload queue 관련 query.
- Storage read/write/delete 대상 path.
- Functions가 Firestore 또는 Storage에 접근하는 query.

기록 항목:

- 파일/함수 위치.
- 컬렉션 또는 path.
- where/orderBy/limit 조건.
- 필요한 권한: read, create, update, delete.
- uid 소유권 조건.
- 필요한 index 여부.
- 성공해야 하는 case와 거부되어야 하는 case.

### 7.3 emulator/test account 검증

검증 원칙:

- rules/index를 바꾸기 전 현 상태를 먼저 테스트한다.
- 테스트 계정 A와 B를 사용해 cross-user deny를 확인한다.
- 운영 데이터가 아닌 emulator 또는 명시 승인된 테스트 계정만 사용한다.

필수 allow case:

- 본인 `uid`의 Cloud metadata read.
- 본인 `uid`의 upload metadata create/update.
- 본인 `uid`의 Trash/restore metadata update.
- 본인 Storage path `users/{uid}/videos/{videoId}/{fileName}` read/write.

필수 deny case:

- 다른 사용자의 `videos` metadata read/update.
- 다른 사용자의 Storage path read/write/delete.
- `uid` mismatch가 있는 metadata create.
- 허용되지 않은 contentType 또는 size upload.
- Cloud copy 편의를 위한 broad path 접근.

### 7.4 index 추가 기준

index 추가가 허용되는 경우:

- 실제 query 실패가 index 부족으로 재현된다.
- query가 제품상 필요한 current behavior다.
- index 추가만으로 해결 가능하고 rules 완화가 필요 없다.
- index cardinality와 비용이 검토됐다.
- 배포 전 emulator 또는 test project에서 검증했다.

index 추가를 보류해야 하는 경우:

- query 자체가 불필요하거나 local filtering으로 대체 가능하다.
- 정렬/필터 조건이 과도해서 비용이 커진다.
- rules 변경과 함께 묶여 보안 검토가 불명확하다.
- R1/R2/R4 같은 미승인 기능을 위해 선제 추가하려는 경우.

### 7.5 rules 변경 금지/허용 조건

허용 조건:

- uid 소유권 조건을 유지하거나 강화한다.
- Storage prefix 검증을 유지하거나 강화한다.
- contentType, size 제한을 유지하거나 강화한다.
- old client 정상 동작을 깨지 않는 deny/allow 범위를 확인했다.

금지 조건:

- 다른 사용자의 `videos` 접근 가능성을 만든다.
- Cloud copy/restore 편의를 위해 broad allow를 추가한다.
- Storage path prefix 검증을 약화한다.
- 인증 없는 read/write 범위를 넓힌다.
- 테스트 없이 운영 rules를 직접 배포한다.

### 7.6 deny case 테스트

| deny case | 기대 결과 |
|---|---|
| user A가 user B의 `videos` 문서 read | denied |
| user A가 user B의 `videos` 문서 update | denied |
| user A가 user B Storage path read | denied |
| uid mismatch metadata create | denied |
| 허용되지 않은 파일 타입 upload | denied |
| size limit 초과 upload | denied |
| delete 권한 없는 active object delete | denied |
| unauthenticated read/write | denied |

### 7.7 배포 gate

배포 전 필수 조건:

1. 현재 query 목록이 문서화되어 있다.
2. emulator 또는 테스트 계정 검증 결과가 있다.
3. index 변경은 최소 변경으로 분리되어 있다.
4. rules 변경은 보안 완화가 아님을 리뷰했다.
5. allow/deny case가 모두 통과했다.
6. rollback 방법이 준비되어 있다.
7. 변경 파일과 배포 명령은 별도 Code/Debug 작업에서 승인 후 실행한다.

### 7.8 절대 하지 말 것

- R1/R2/R4 구현 편의를 위해 broad allow를 추가하지 않는다.
- uid 소유권 조건을 완화하지 않는다.
- Storage prefix 검증을 약화하지 않는다.
- index/rules를 같은 변경에서 대량 수정하지 않는다.
- emulator 또는 test account 검증 없이 운영 배포하지 않는다.

### 7.9 완료 조건

- 현재 query 목록과 필요한 권한이 정리되어 있다.
- allow/deny 테스트 결과가 문서화되어 있다.
- index 부족이면 최소 index 변경안만 분리되어 있다.
- rules 변경이 필요하면 보안 강화 또는 현행 유지 방향임이 확인되어 있다.
- 배포 gate와 rollback 절차가 승인되어 있다.

## 8. R7 실제 QA 상세 가이드

### 8.1 목표

실제 장비와 테스트 계정으로 Cloud Clip 경계조건을 검증하여 릴리스 차단 이슈를 조기에 발견한다. QA는 운영 데이터 변경 없이 테스트 범위에서 수행한다.

### 8.2 공통 QA 기록 양식

| 항목 | 기록 내용 |
|---|---|
| 테스트 ID | R7-* |
| 계정 유형 | Free, Standard, Premium, sandbox expired |
| 장비/OS | Android/iOS, OS version |
| 앱 상태 | 신규 설치, 재설치, 로그인 유지, 로그아웃 후 재로그인 |
| 네트워크 | online, offline, flaky |
| 사전 데이터 | local clips count, cloud clips count, trash count |
| 절차 | 단계별 수행 기록 |
| 기대 결과 | 사전 정의된 expected behavior |
| 실제 결과 | 관찰 결과 |
| Firestore 관찰 | field 변화 요약, 실제 uid/token 기록 금지 |
| Storage 관찰 | object 존재 여부 요약, 실제 path 노출 최소화 |
| local 원본 | 보존 여부 |
| 판정 | pass, fail, blocked |

### 8.3 재설치/재로그인

절차:

1. 테스트 Standard 계정으로 Cloud clip을 업로드한다.
2. Library와 Profile count를 기록한다.
3. 앱 로그아웃 후 재로그인한다.
4. Library placeholder와 Profile count가 유지되는지 확인한다.
5. 앱 삭제 또는 앱 데이터 삭제 후 재설치한다.
6. 동일 계정으로 로그인한다.
7. Cloud placeholder, restore/download 가능 여부, local index 재생성 상태를 확인한다.

기대 결과:

- Cloud metadata가 삭제되지 않는다.
- Profile count와 Library placeholder가 일관된다.
- local 파일이 없어도 Cloud-only clip이 식별된다.
- 기존 로그인 사용자에게 튜토리얼 샘플이 재주입되지 않는다.

### 8.4 Trash/restore

절차:

1. Cloud 업로드 완료 clip을 선택한다.
2. Trash로 이동한다.
3. Library, Trash, Profile count 변화를 기록한다.
4. Firestore metadata에서 lifecycle/tombstone 관련 field 변화를 관찰한다.
5. restore를 실행한다.
6. 원래 album/library 위치, Cloud 상태, local placeholder 상태를 확인한다.
7. 앱 재시작 후 상태가 유지되는지 확인한다.

기대 결과:

- Trash 이동은 Storage object를 즉시 삭제하지 않는다.
- restore 후 Cloud metadata와 local 표시가 복구된다.
- usage가 중복 증감되지 않는다.
- active clip이 영구 삭제 후보로 분류되지 않는다.

### 8.5 Standard 자동 업로드

절차:

1. Standard 계정으로 로그인한다.
2. 새 clip을 촬영한다.
3. local 저장 완료를 확인한다.
4. upload queue 상태를 확인한다.
5. online 상태에서 completed 또는 failed 상태를 확인한다.
6. offline 상태에서 촬영 후 online 복귀 시 queue 재개를 확인한다.

기대 결과:

- local 원본은 upload 성공/실패와 무관하게 보존된다.
- upload pending/failed/completed 상태가 유실되지 않는다.
- 실패 시 사용자에게 재시도 가능 상태로 표시된다.
- Free 계정으로 전환되면 신규 upload는 차단되지만 기존 local 원본은 유지된다.

### 8.6 튜토리얼 재주입

절차:

1. 신규 계정, 기존 로그인 계정, Cloud metadata 보유 계정을 각각 준비한다.
2. 앱 첫 실행, 로그아웃/로그인, 재설치 후 로그인 시나리오를 수행한다.
3. 튜토리얼 sample clip 주입 여부를 확인한다.
4. SharedPreferences 관련 상태는 key 이름을 변경하지 않고 관찰만 한다.

기대 결과:

- 신규 사용자에게만 의도된 튜토리얼이 제공된다.
- 기존 로그인/완료/Cloud metadata 보유 사용자에게 샘플이 자동 재주입되지 않는다.
- `tutorial_completed_user_{uid}`와 `isFirstRun` 계약은 변경되지 않는다.

### 8.7 quota

절차:

1. 테스트 계정의 quota 상태를 준비한다.
2. quota 여유 상태에서 upload를 수행한다.
3. quota 임박 상태에서 upload 또는 Cloud copy 후보를 수행한다.
4. quota 초과 상태에서 upload/copy 차단 문구를 확인한다.
5. 실패 후 local 원본, queue 상태, usage count를 확인한다.

기대 결과:

- quota 초과 시 Storage object 생성 전 차단된다.
- usage가 중복 증가하지 않는다.
- local 원본과 기존 Cloud metadata가 삭제되지 않는다.
- 사용자 문구가 업그레이드/정리/재시도를 명확히 안내한다.

### 8.8 디바이스 저장공간

절차:

1. 테스트 장비에서 저장공간 부족 상태를 만든다.
2. 촬영, import, Cloud restore/download를 각각 시도한다.
3. 실패 시 local staging, partial file, metadata 상태를 확인한다.
4. 저장공간 확보 후 재시도한다.

기대 결과:

- partial file이 원본으로 오인되지 않는다.
- 실패가 Cloud metadata 삭제를 유발하지 않는다.
- 저장공간 확보 후 재시도 가능하다.
- 사용자에게 저장공간 부족 안내가 표시된다.

### 8.9 구독 만료 시나리오별 절차와 기대 결과

| 시나리오 | 절차 | 기대 결과 |
|---|---|---|
| 만료 전 | Standard sandbox 계정으로 upload/restore | Cloud 작업 허용 |
| 만료 직후 | sandbox 만료 후 앱 재실행 | 신규 upload/copy 차단, 기존 metadata 보존 |
| grace 중 | 기존 Cloud clip 다운로드/복원 시도 | 정책에 따라 허용 또는 명확한 안내 |
| grace 이후 | 정책 적용 상태 확인 | 삭제 전에는 metadata 보존, 삭제 시 R2 gate 필요 |
| 재구매 | sandbox 재구매 후 권한 갱신 | upload/restore 권한 회복 |
| restore purchases | 재설치 후 restore purchases | 기존 Cloud metadata 연결 유지 |
| 만료 + 오프라인 | 만료 전 캐시 후 offline 실행 | local 데이터 보존, Cloud 변경 작업 보수적 차단 |

### 8.10 절대 하지 말 것

- 실제 사용자 계정이나 운영 데이터를 QA 대상으로 사용하지 않는다.
- QA 중 Storage object나 Firestore metadata를 수동 삭제하지 않는다.
- 테스트 편의를 위해 rules를 완화하지 않는다.
- 실패 재현을 위해 local 원본을 임의 삭제하지 않는다.
- QA 결과에 실제 uid, token, secret, keystore 정보를 남기지 않는다.

### 8.11 완료 조건

- 재설치/재로그인, Trash/restore, Standard 자동 업로드, 튜토리얼 재주입, quota, 저장공간, 구독 만료 시나리오 결과표가 작성되어 있다.
- local 원본과 Cloud metadata 보존이 확인되어 있다.
- 릴리스 차단 조건이 없거나, 발견된 차단 이슈가 별도 Debug 작업으로 분리되어 있다.
- 테스트 계정/장비 기준으로 재현 절차와 기대 결과가 문서화되어 있다.

## 9. 추천 실행 순서와 승인 체크포인트

### 9.1 작업 패키지 WP1: R7 QA 패스 1

포함:

- 재설치/재로그인 QA.
- Trash/restore QA.
- Standard 자동 업로드 QA.
- 튜토리얼 재주입 QA.

승인 체크포인트:

- 테스트 계정과 테스트 장비 범위 확인.
- 운영 데이터 미사용 확인.
- 결과표 저장 위치 승인.

완료 조건:

- 릴리스 차단 이슈가 없거나 Debug 작업으로 분리됐다.

### 9.2 작업 패키지 WP2: R5 현재 rules/index 검증

포함:

- 현재 query 수집.
- emulator 또는 test account allow/deny 검증.
- index 부족 여부 확인.

승인 체크포인트:

- rules/index 변경 없이 검증만 수행하는 범위 확인.
- deny case 목록 승인.

완료 조건:

- 최소 index/rule 변경 필요 여부가 근거와 함께 결정됐다.

### 9.3 작업 패키지 WP3: R3 구독 만료 정책 결정과 sandbox QA

포함:

- grace 기간 결정.
- 다운로드 허용 여부 결정.
- 신규 upload/copy 차단 정책 결정.
- 사용자 고지/CS 기준 초안.
- sandbox 만료/재구매/restore QA.

승인 체크포인트:

- Product/Ops가 grace와 다운로드 정책 승인.
- CS 문구 승인.
- 삭제 정책은 R2와 분리한다는 점 승인.

완료 조건:

- 정책 결정서와 sandbox QA 결과가 준비됐다.

### 9.4 작업 패키지 WP4: R2 Storage 삭제 dry-run 설계

포함:

- retention 기준.
- inventory query.
- dry-run manifest.
- manual approval gate.
- monitoring 지표.

승인 체크포인트:

- 실제 delete execute는 제외한다는 범위 승인.
- manifest 형식과 개인정보 보호 기준 승인.

완료 조건:

- 삭제 execute 전 단계인 dry-run 설계가 승인됐다.

### 9.5 작업 패키지 WP5: R4 inventory와 최소 backfill 계획

포함:

- `videos` field 분포 익명 집계 설계.
- fallback 유지 기준.
- 최소 backfill 후보 선정 기준.
- staged rollout과 rollback manifest.

승인 체크포인트:

- 실제 backfill write는 제외한다는 범위 승인.
- 익명 집계와 샘플링 기준 승인.

완료 조건:

- backfill 필요 여부가 dry-run 근거로 판단 가능하다.

### 9.6 작업 패키지 WP6: R1 Cloud copy 계약/UX 설계

포함:

- Cloud copy UX.
- API 방식 선택.
- usage idempotency 계약.
- quota/오프라인/객체 누락 실패 처리.
- QA matrix.

승인 체크포인트:

- 기본 local copy를 유지한다는 제품 결정.
- Cloud copy가 usage를 증가시키는 명시 기능이라는 점 승인.
- Functions 또는 client 구현 방식 승인.

완료 조건:

- 구현 가능한 spec과 QA matrix가 준비됐다.

### 9.7 작업 패키지 WP7: R2 execute 별도 승인

포함:

- approved manifest 기반 batch delete.
- usage decrement idempotency.
- monitoring.
- rollback 한계 고지.

승인 체크포인트:

- dry-run 결과 수동 승인.
- execute batch 크기와 중단 조건 승인.
- Storage rollback 한계 승인.

완료 조건:

- batch delete가 중복 usage 차감 없이 수행되고 모니터링된다.

## 10. 전체 릴리스/운영 gate

릴리스 또는 운영 배포 전에 다음 조건을 모두 확인한다.

- R7 핵심 QA에서 local 원본 삭제, Cloud metadata 유실, cross-user access가 없다.
- R5 deny case가 통과하고 broad allow가 없다.
- R3 정책이 Product/Ops/CS 관점에서 승인되어 있다.
- R2 deletion execute는 dry-run manifest와 수동 승인 없이 실행되지 않는다.
- R4 backfill은 inventory와 rollback manifest 없이 실행되지 않는다.
- R1 Cloud copy는 local copy 기본 흐름에 섞이지 않는다.
- 변경 금지 계약 `videos`, `users`, `vlog_projects`, `users/{uid}/videos/{videoId}/{fileName}`, `3s_*` product id/key, Firebase project id는 유지된다.

## 11. 최종 완료 기준

이 가이드는 다음 상태가 되면 후속 구현을 시작할 수 있는 준비 완료로 본다.

1. 각 R 항목별 절대 하지 말 것과 완료 조건이 승인됐다.
2. 작업 패키지별 승인 체크포인트가 담당자에게 배정됐다.
3. QA 결과표와 dry-run manifest 형식이 준비됐다.
4. 실제 코드/설정/Firebase 변경은 별도 작업으로 분리됐다.
5. 사용자 데이터 보존, 기존 기능 유지, 레거시 호환 원칙에 반하는 제안이 제거됐다.

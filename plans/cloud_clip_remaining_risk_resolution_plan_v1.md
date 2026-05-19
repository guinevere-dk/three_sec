# Cloud Clip 남은 리스크 대응 계획 v1

## 0. 문서 목적

이 문서는 `plans/cloud_clip_policy_and_sync_improvement_plan_v1.md` 구현 이후 남은 리스크를 제품/Flutter/Backend/QA/Ops 관점에서 분리하고, 각 리스크를 어떤 순서와 안전장치로 처리할지 정의한다.

본 계획은 즉시 실행 가능한 구현 지시가 아니라, 사용자 데이터 보존과 레거시 호환을 전제로 한 후속 승인/검증 계획이다. 특히 Cloud copy, 영구 삭제 자동화, 구독 만료 후 Cloud 접근 차단/삭제, migration/backfill, Firebase rules/index 변경은 한 번에 묶어 처리하지 않고 독립 단계로 진행한다.

## 1. 기준 원칙

| 원칙 | 적용 방식 |
|---|---|
| 사용자 데이터 보존 우선 | 원본 영상, Cloud metadata, local index, 계정 소유권, 구독 상태를 삭제하거나 초기화하지 않는다. |
| 기존 기능 유지 | 현재 구현된 Cloud placeholder, upload queue, Trash/tombstone, Profile stats 동작을 깨지 않는다. |
| 레거시 호환 | 기존 `videos`, `users`, `users/{uid}/videos/{videoId}/{fileName}`, IAP product id, SharedPreferences key를 변경하지 않는다. |
| 작은 단위 변경 | Flutter UI, Functions, Firebase rules/index, DB schema, Storage deletion을 한 작업에서 동시에 변경하지 않는다. |
| 삭제보다 soft-delete | 실제 Storage 객체 삭제 전 tombstone, retention, dry-run, export, rollback을 먼저 둔다. |
| dual-read/write | 새 field가 필요하면 기존 field fallback을 유지하고 old client 호환을 먼저 검증한다. |

## 2. 남은 리스크 요약

| ID | 리스크 | 영향 | 우선순위 | 처리 방향 | 상태 |
|---|---|---|---|---|---|
| R1 | Cloud copy 기능 미구현 | 사용자가 Cloud 클립 복사를 기대할 때 현재는 기본 local copy로 동작 | P1 | 명시 선택형 Cloud copy로 별도 기능화 | 계획중 |
| R2 | Storage 영구 삭제 자동화 미구현 | Trash 항목이 계속 보존되어 비용/usage 정합성 리스크 | P0 | retention + dry-run + 멱등 usage 차감 후 단계 도입 | 계획중 |
| R3 | 구독 만료 후 Cloud 접근/삭제 정책 미확정 | 결제/CS/데이터 보존 리스크 | P0 | 읽기전용 grace 정책 우선, 삭제 자동화는 후순위 | 계획중 |
| R4 | migration/backfill 미실행 | 기존 문서에 tombstone/original tier field가 없을 수 있음 | P1 | read fallback 유지 후 inventory dry-run, 필요한 경우 backfill | 계획중 |
| R5 | Firebase rules/index 변경 미실행 | 새 query나 field 접근이 일부 환경에서 제한될 수 있음 | P1 | 현재 query 확인 후 rules 완화 없이 최소 index/rule 검토 | 계획중 |
| R6 | `flutter analyze` 기존 warning/info 503개 | 신규 회귀 탐지 신뢰도 저하 | P2 | Cloud 관련 warning부터 좁은 범위 정리 | 계획중 |
| R7 | 실제 quota/저장공간/재설치/만료 QA 미완료 | 릴리스 전 실사용 경계조건 불확실 | P0 | 수동 QA matrix와 테스트 계정/장비 준비 | 계획중 |

## 3. 단계별 처리 계획

### Phase 1. 릴리스 차단 리스크 검증 고정

목표는 현재 구현이 사용자 데이터 보존 원칙을 지키는지 확인하고, 실제 삭제/마이그레이션 없이 위험 경로를 차단하는 것이다.

| 작업 | 담당 | 산출물 | 완료 조건 |
|---|---|---|---|
| Cloud Trash/restore 수동 QA | QA/Flutter | QA 로그, 스크린샷, Firestore field 비교표 | Trash 이동 후 Cloud metadata 보존, restore 후 Cloud 상태 복원 확인 |
| 재설치/재로그인 QA | QA/Flutter | 재설치 시나리오 결과표 | Profile count와 Library placeholder 불일치가 재현되지 않음 |
| Standard 촬영 자동 업로드 QA | QA/Flutter | upload queue 상태표 | 로컬 저장 완료 후 upload pending/completed 또는 failed 상태가 보존됨 |
| 튜토리얼 재주입 QA | QA/Product | 계정 유형별 결과표 | 기존 로그인/완료/Cloud metadata 보유 사용자에게 샘플 자동 주입 없음 |
| quota/저장공간 대체 QA 설계 | QA/Backend | 테스트 계정/장비 준비안 | quota 초과와 디바이스 저장공간 부족 재현 절차 확정 |

릴리스 게이트:

- Cloud 삭제가 `local_only`로 조용히 전환되는 경로가 발견되면 릴리스 보류.
- 재설치 후 Cloud count가 존재하는데 Library placeholder가 표시되지 않으면 릴리스 보류.
- Standard 촬영 자동 업로드 실패가 로컬 원본 삭제를 유발하면 릴리스 보류.
- 기존 로그인 사용자에게 튜토리얼 샘플이 자동 재주입되면 릴리스 보류.

### Phase 2. 구독 만료 Cloud 접근 정책 확정

구독 만료 처리는 데이터 삭제보다 접근 정책을 먼저 확정한다.

권장 정책:

1. 만료 직후 기존 Cloud 데이터는 즉시 삭제하지 않는다.
2. Free 상태에서는 신규 Cloud upload와 Cloud copy를 차단한다.
3. 기존 Cloud 클립은 일정 grace 기간 동안 Library placeholder와 Profile count를 유지한다.
4. grace 기간 중 다운로드/복원 허용 여부는 제품 정책으로 확정한다. 기본 추천은 읽기전용 다운로드 허용이다.
5. grace 이후 영구 삭제가 필요하면 별도 고지, export 기회, dry-run, rollback 계획을 거친다.

검증 matrix:

| 시점 | 기대 동작 | 검증 |
|---|---|---|
| 만료 전 | Standard 권한 유지 | Profile tier, upload 가능 여부 확인 |
| 만료 직후 | 신규 upload 차단, 기존 metadata 보존 | Cloud count/Library placeholder 유지 확인 |
| grace 기간 | 읽기전용 복원 정책 적용 | 복원 허용/차단 문구와 실제 동작 비교 |
| grace 이후 | 최종 정책에 따른 접근 제한 또는 삭제 예정 | 사용자 고지, dry-run 결과, rollback 확인 |
| 재구매/복원 | Cloud 권한 복구 | IAP restore 후 upload/restore 재허용 확인 |

승인 필요:

- grace 기간 길이.
- 만료 후 다운로드 허용 여부.
- grace 이후 삭제 여부.
- Functions/scheduler 도입 여부.
- 사용자 고지 문구와 CS 대응 기준.

### Phase 3. Storage 영구 삭제 자동화 설계

Storage 영구 삭제는 가장 위험한 작업이므로 soft-delete retention이 안정화된 뒤 별도 진행한다.

권장 절차:

1. 영구 삭제 대상 inventory query를 문서화한다.
2. 삭제 대상은 `lifecycleState=trash` 또는 이에 준하는 tombstone 상태이며 retention 기간이 지난 항목으로 제한한다.
3. dry-run Functions를 먼저 만들어 대상 count, fileSize 합계, storagePath 목록 hash만 기록한다.
4. 실제 Storage 삭제 전 Firestore metadata export 또는 삭제 대상 manifest를 보관한다.
5. 삭제는 batch 단위로 수행하고, 각 batch마다 usage 차감 이벤트를 멱등 key로 기록한다.
6. 실패 시 Firestore tombstone metadata는 유지하고 Storage delete retry 상태만 갱신한다.
7. rollback은 Storage 객체 복구가 불가능할 수 있으므로, 실제 삭제 전 retention/gate/manifest 검증을 release gate로 둔다.

필수 safety gate:

- `uid` 소유권 확인.
- `storagePath`가 `users/{uid}/videos/{videoId}/{fileName}` prefix인지 확인.
- 이미 삭제된 객체에 대한 usage 중복 차감 방지.
- active 또는 pending upload 항목 제외.
- dry-run 결과 수동 승인 후 execute.

### Phase 4. Cloud copy 별도 기능 설계

현재 일반 복사는 local copy 정책으로 유지한다. Cloud copy는 사용자가 명시 선택할 때만 Cloud 사용량을 증가시키는 별도 기능으로 도입한다.

권장 UX:

| 액션 | 설명 |
|---|---|
| 로컬 복사 | 현재 기본값. 새 로컬 clip을 만들고 Cloud usage는 증가하지 않는다. |
| Cloud까지 복사 | 명시 선택. 새 Cloud object와 metadata를 만들고 Cloud usage가 증가한다. |
| Cloud 복사 실패 | 원본 유지, 복사본은 local_only 또는 failed_cloud_copy로 표시한다. |

구현 전 확정 필요:

- Storage copy 방식: client download/upload 또는 server-side copy.
- 새 `videoId` 생성 규칙.
- usage accounting event idempotency key.
- 원본 삭제/이동과 복사본 lifecycle 분리.
- quota 초과 시 복사 차단 문구.

권장 순서:

1. 제품 문구와 UX 승인.
2. usage accounting 계약 작성.
3. Cloud copy API dry-run 설계.
4. Flutter UI에서 local copy와 Cloud copy 분리.
5. QA에서 quota 초과/오프라인/Storage 객체 누락 시나리오 검증.

### Phase 5. migration/backfill과 schema 호환성

현재 구현은 optional field와 fallback을 우선한다. 기존 문서 보정이 필요하더라도 바로 migration하지 않는다.

처리 순서:

1. Inventory dry-run으로 기존 `videos` 문서의 field 분포를 확인한다.
2. `storagePath`, `storageTier`, `lifecycleState`, `cloudState`, `originalStoragePath`, `originalStorageTier` 존재 여부를 익명 집계한다.
3. read fallback으로 충분히 처리 가능한 문서는 migration하지 않는다.
4. 복원/Trash 동작에 꼭 필요한 최소 field만 backfill 대상으로 분리한다.
5. backfill은 dry-run, 샘플 사용자, staged rollout, rollback plan 순서로 진행한다.

금지:

- 기존 field rename.
- 컬렉션명 변경.
- Storage path rename.
- local index key 변경.
- 실제 사용자 데이터 삭제를 동반한 migration.

### Phase 6. Firebase rules/index 검토

rules/index 변경은 보안 완화 없이 필요한 최소 범위만 검토한다.

검토 절차:

1. 현재 Flutter query가 기존 rules/index로 모두 동작하는지 emulator 또는 테스트 계정으로 확인한다.
2. query 실패가 index 부족이면 `firebase/firestore.indexes.json` 최소 추가안을 별도 PR/작업으로 만든다.
3. rules 변경이 필요하면 uid 소유권 조건을 강화 또는 유지하는 방향만 허용한다.
4. rules 변경 전후로 read/write deny case를 포함한 테스트를 수행한다.

릴리스 금지 조건:

- uid 소유권 조건 완화.
- 다른 사용자의 `videos` metadata 접근 가능성.
- Storage prefix 검증 약화.
- Cloud copy/restore를 위해 broad allow rule 추가.

### Phase 7. 정적 분석 부채 정리

`flutter analyze`의 기존 warning/info가 많으면 신규 회귀 탐지가 어려워진다. 단, 기능 리스크가 낮으므로 P2로 분리한다.

정리 원칙:

1. Cloud 관련 변경 파일부터 warning을 줄인다.
2. unused import/unused element처럼 의미가 명확한 항목만 소규모로 처리한다.
3. IAP/nullability 경고는 결제 권한 판정에 영향이 있으므로 별도 분석 후 처리한다.
4. 자동 포맷만을 위한 광범위 변경은 하지 않는다.

목표:

- 1차: Cloud 관련 변경 파일의 신규 error 0 유지.
- 2차: Cloud 관련 warning 0.
- 3차: 전체 analyze warning/info를 릴리스 전 관리 가능한 수준으로 축소.

## 4. 실행 체크리스트

| 상태 | ID | 작업 | 우선순위 | 담당 | 검증/산출물 | 승인 |
|---|---|---|---|---|---|---|
| 미시작 | R7-1 | Standard 촬영 자동 Cloud queue 수동 QA | P0 | QA/Flutter | 촬영→로컬 저장→queue/completed/failed 결과표 | 필요 없음 |
| 미시작 | R7-2 | 재설치/재로그인 Cloud placeholder QA | P0 | QA/Flutter | 앱 데이터 삭제/재설치 결과표 | 필요 없음 |
| 미시작 | R7-3 | Trash/restore Cloud metadata 보존 QA | P0 | QA/Flutter | Firestore field 비교표 | 필요 없음 |
| 미시작 | R3-1 | 구독 만료 grace/download 정책 결정 | P0 | Product/Ops | 정책 결정 기록 | 필요 |
| 미시작 | R3-2 | sandbox 구독 만료 QA | P0 | QA/IAP | 만료 전/후 결과표 | 테스트 계정 필요 |
| 미시작 | R2-1 | 영구 삭제 dry-run inventory 설계 | P0 | Backend/Ops | dry-run query/manifest 설계 | 필요 |
| 미시작 | R2-2 | Storage 삭제 execute gate 설계 | P0 | Backend/Ops | retention, manifest, rollback 문서 | 필요 |
| 미시작 | R1-1 | Cloud copy UX/문구 확정 | P1 | Product/Design | UX spec | 필요 |
| 미시작 | R1-2 | Cloud copy usage accounting 계약 작성 | P1 | Backend/Flutter | idempotent event 계약 | 필요 |
| 미시작 | R4-1 | 기존 `videos` field inventory dry-run | P1 | Backend/Ops | 익명 집계 결과 | 필요 |
| 미시작 | R4-2 | 최소 backfill 계획 작성 | P1 | Backend/Ops | dry-run/backfill/rollback 계획 | 필요 |
| 미시작 | R5-1 | 현재 query rules/index 검증 | P1 | Backend/QA | emulator/test account 결과 | 필요 없음 |
| 미시작 | R5-2 | 필요한 경우 최소 index/rule 변경안 작성 | P1 | Backend | 별도 변경안 | 필요 |
| 미시작 | R6-1 | Cloud 관련 analyze warning 정리 | P2 | Flutter | `flutter analyze` 비교 결과 | 필요 없음 |

## 5. 권장 우선순위

1. P0 수동 QA: Trash/restore, 재설치 placeholder, Standard 자동 업로드, 튜토리얼 재주입 차단.
2. 구독 만료 정책 결정: 삭제보다 읽기전용 grace와 신규 Cloud 작업 차단을 먼저 확정.
3. 영구 삭제 자동화 설계: dry-run과 manifest까지만 먼저 진행하고 execute는 별도 승인.
4. rules/index 검증: 현재 구현이 실제 Firebase 환경에서 실패하지 않는지 확인.
5. migration/backfill inventory: 실제 보정 전 field 분포만 먼저 확인.
6. Cloud copy: 기본 local copy 정책 안정화 후 명시 선택 기능으로 도입.
7. 정적 분석 부채: Cloud 관련 파일부터 단계적으로 정리.

## 6. 다음 작업 단위 제안

| 작업 단위 | 포함 항목 | 제외 항목 |
|---|---|---|
| QA 패스 1 | 재설치, Trash/restore, Standard 자동 업로드, 튜토리얼 gate | Firebase rules 변경, 삭제 자동화 |
| Product 결정 1 | 구독 만료 grace/download 정책, Cloud copy UX | 코드 구현 |
| Backend dry-run 1 | Storage 삭제 대상 inventory, existing field inventory | 실제 삭제, backfill execute |
| Firebase 검증 1 | query/rules/index emulator 검증 | rules 완화 |
| Flutter cleanup 1 | Cloud 관련 analyze warning 축소 | 전체 프로젝트 광범위 정리 |

## 7. 완료 기준

이 계획은 아래 조건이 충족되면 v1 종료로 본다.

- P0 수동 QA 결과가 문서화되고 릴리스 차단 이슈가 없다.
- 구독 만료 후 Cloud 접근 정책이 제품/운영 기준으로 확정된다.
- Storage 영구 삭제는 dry-run manifest까지 검증되고 execute 여부가 별도 승인된다.
- Cloud copy는 UX와 usage accounting 계약이 확정되기 전까지 기본 복사 흐름에 섞이지 않는다.
- 기존 문서 migration/backfill은 inventory dry-run 이후 최소 대상만 분리된다.
- Firebase rules/index는 보안 완화 없이 필요한 변경만 별도 승인된다.
- Cloud 관련 정적 분석 warning이 신규 회귀를 가리지 않는 수준으로 관리된다.

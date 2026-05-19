# Cloud Clip 남은 리스크 구현 전 영향도 분류 보고서 v1

## 0. 목적과 범위

이 보고서는 [`plans/cloud_clip_remaining_risk_resolution_plan_v1.md`](cloud_clip_remaining_risk_resolution_plan_v1.md)의 R1~R7 및 실행 체크리스트를 구현 전 관점에서 재분류한 결과다.

이번 하위 작업에서는 코드, Firebase 설정, Functions, rules/index, 로컬 저장 key, DB schema, Storage path를 변경하지 않았다. Architect 모드 및 상위 작업 지시에 따라 Markdown 보고서 작성만 수행했다.

## 1. 판단 기준

분류 기준은 다음 문서를 우선했다.

- [`AGENTS.md`](../AGENTS.md): 사용자 데이터 보존, 기존 기능 유지, 레거시 호환 우선. 코드 변경 요청이 아닌 경우 Markdown 문서만 수정. Firestore/Storage/SharedPreferences/IAP/플랫폼 식별자 변경은 별도 승인 필요.
- [`CURRENT_PHASE.md`](../CURRENT_PHASE.md): 현재는 MVP 안정화와 MOA 브랜드 정렬 단계. 즉시 허용 작업은 문서 정리, 체크리스트, 릴리스 게이트 문서화, 기존 동작을 바꾸지 않는 작은 버그 수정. Firestore/Storage schema/path/rules, Functions endpoint, 로컬 key, migration/backfill/purge는 승인 필요.
- [`DATA_COMPATIBILITY.md`](../DATA_COMPATIBILITY.md): `videos`, `users`, `vlog_projects`, `users/{uid}/videos/{videoId}/{fileName}`, `3s_*`, `local_index_entries_v1` 등 데이터 계약 변경 금지. 삭제, 경로 rename, field rename, schema migration은 dry-run, backup, rollback, 명시 승인 필요.
- [`plans/cloud_clip_remaining_risk_resolution_plan_v1.md`](cloud_clip_remaining_risk_resolution_plan_v1.md): 해당 계획 자체가 즉시 실행 구현 지시가 아니라 후속 승인/검증 계획이며, Cloud copy, 영구 삭제, 구독 만료 정책, migration/backfill, Firebase rules/index 변경을 한 번에 처리하지 말라고 명시.

## 2. 전체 분류 요약

| ID | 항목 | 즉시 코드 구현 여부 | 분류 | 핵심 이유 |
|---|---|---:|---|---|
| R1 | Cloud copy 기능 미구현 | 아니오 | 승인/설계 필요 | Cloud usage 증가, 새 `videoId`, Storage copy, quota 문구, usage accounting 계약 필요 |
| R2 | Storage 영구 삭제 자동화 미구현 | 아니오 | 고위험/승인 필요 | 사용자 영상 삭제, Storage path, usage 차감, rollback 불가 가능성 포함 |
| R3 | 구독 만료 후 Cloud 접근/삭제 정책 미확정 | 아니오 | 제품/운영 승인 필요 | grace 기간, 다운로드 허용, 삭제 여부, CS 고지 정책 미확정 |
| R4 | migration/backfill 미실행 | 아니오 | 승인/드라이런 필요 | 기존 `videos` field 분포 확인 전 backfill 금지, schema/data mutation 포함 |
| R5 | Firebase rules/index 변경 미실행 | 부분 가능 | 검증은 가능, 변경은 승인 필요 | emulator/test 계정 검증은 안전하나 rules/index 변경은 보안/배포 영향 |
| R6 | `flutter analyze` warning/info 부채 | 부분 가능 | 좁은 범위만 안전 후보 | unused import 등 무의미한 정리는 가능하나 광범위 정리와 IAP/nullability는 보류 |
| R7 | quota/저장공간/재설치/만료 QA 미완료 | 코드 구현 아님 | 즉시 안전 수행 가능 | 수동 QA와 결과 문서화는 데이터 계약 변경 없이 가능 |

## 3. 즉시 안전하게 수행 가능한 작업

아래 항목은 사용자 데이터, 레거시 계약, Firebase/Storage schema를 바꾸지 않으므로 지금 단계에서 안전하게 진행 가능한 후보로 분류한다. 단, 이번 하위 작업에서는 보고서 작성만 수행했다.

### 3.1 문서/QA 작업

| 체크리스트 ID | 작업 | 안전한 이유 | 권장 산출물 |
|---|---|---|---|
| R7-1 | Standard 촬영 자동 Cloud queue 수동 QA | 코드/설정 변경 없이 현재 동작 관찰 | 촬영→로컬 저장→queue/completed/failed 결과표 |
| R7-2 | 재설치/재로그인 Cloud placeholder QA | 데이터 삭제는 테스트 계정/테스트 장비 범위에서 수행 가능 | 앱 데이터 삭제/재설치 결과표 |
| R7-3 | Trash/restore Cloud metadata 보존 QA | 현재 구현의 metadata 보존 여부 관찰 | Firestore field 비교표 |
| R5-1 | 현재 query rules/index 검증 | rules/index 자체를 바꾸지 않는 emulator 또는 테스트 계정 검증 | allow/deny case 포함 결과표 |
| R3-2 | sandbox 구독 만료 QA | sandbox 테스트 계정에서 정책 미확정 상태의 현 동작 확인 | 만료 전/후 결과표, 불일치 이슈 목록 |

### 3.2 코드 작업 후보 중 비교적 안전한 범위

아래는 구현 단계에서 Code 모드가 검토할 수 있는 안전 후보이며, 실제 변경 전 파일 단위 영향도 확인이 필요하다.

| 후보 | 안전 조건 | 제외 조건 |
|---|---|---|
| Cloud 관련 파일의 unused import 제거 | 앱 동작 변경 없음, 단일 파일 단위, analyze 결과 비교 | 자동 포맷만을 위한 광범위 변경 |
| Cloud 관련 명확한 dead local variable 제거 | 사용되지 않는 지역 변수만 제거, 동작/타이밍 변경 없음 | nullable/IAP/권한 판정과 연결된 변수 |
| QA 체크리스트 문서 보강 | Markdown 문서만 변경 | 실제 rules/index/Functions/schema 변경 |
| 에러 문구 문서화 | 사용자 고지 정책 초안 수준 | 제품 승인 전 앱 카피 적용 |

## 4. 구현하지 말아야 하는 항목과 사유

### 4.1 R1 Cloud copy 기능

구현하지 말아야 한다.

이유:

- Cloud copy는 새 Storage 객체, 새 metadata, usage 증가, quota 초과 처리, 실패 상태 표시를 모두 포함한다.
- 새 `videoId` 생성 규칙과 idempotent usage accounting key가 확정되지 않았다.
- server-side copy와 client download/upload 중 어느 방식인지 결정되지 않았다.
- 현재 일반 복사는 local copy 정책으로 유지되어야 하며, Cloud copy를 기본 복사 흐름에 섞으면 사용자 기대와 비용/usage 정합성이 흔들릴 수 있다.

필요 승인:

- 제품/디자인: Cloud까지 복사 UX와 문구.
- Backend/Flutter: usage accounting 계약과 event idempotency.
- 운영: quota 초과 및 실패 복구 정책.

권장 후속 작업:

1. Cloud copy UX spec 작성.
2. usage accounting 계약 문서 작성.
3. Cloud copy dry-run 또는 mock API 설계.
4. local copy와 Cloud copy 버튼/흐름을 명확히 분리.

### 4.2 R2 Storage 영구 삭제 자동화

구현하지 말아야 한다.

이유:

- 사용자 원본 영상과 Cloud 백업 삭제를 직접 유발할 수 있다.
- Storage 객체 삭제는 rollback이 불가능하거나 제한적일 수 있다.
- usage 차감 멱등성, tombstone retention, manifest, export, batch retry 정책이 먼저 필요하다.
- [`DATA_COMPATIBILITY.md`](../DATA_COMPATIBILITY.md)는 삭제가 소유권 확인과 사용량 차감 멱등성을 함께 검토해야 한다고 규정한다.

필요 승인:

- Backend/Ops: dry-run query, manifest 형식, execute gate.
- Product/Ops: retention 기간, 사용자 고지, 삭제 정책.
- QA: dry-run 결과 수동 승인 절차.

권장 후속 작업:

1. 삭제 대상 inventory query를 문서화한다.
2. hash 기반 manifest와 count/fileSize 합계만 출력하는 dry-run 설계를 만든다.
3. Firestore metadata export 또는 삭제 대상 manifest 보관 방식을 정한다.
4. execute는 별도 승인 전까지 금지한다.

### 4.3 R3 구독 만료 후 Cloud 접근/삭제 정책

구현하지 말아야 한다.

이유:

- 결제 상태, 접근권, 다운로드 허용, 삭제 여부는 제품/운영/CS 정책이다.
- 신규 upload 차단, 기존 Cloud placeholder 유지, grace 기간 다운로드 허용 여부가 미확정이다.
- 삭제 자동화와 결합하면 사용자 데이터 보존 리스크가 커진다.

필요 승인:

- Product/Ops: grace 기간 길이, 다운로드 허용 여부, grace 이후 삭제 여부.
- CS/Legal 성격의 운영 판단: 사용자 고지 문구와 대응 기준.
- Backend: Functions/scheduler 도입 여부.

권장 후속 작업:

1. 삭제보다 읽기전용 grace 정책을 먼저 결정한다.
2. sandbox 구독 만료 QA로 현재 동작을 기록한다.
3. 정책 확정 후 신규 upload 차단과 기존 metadata 보존을 분리해서 구현한다.

### 4.4 R4 migration/backfill

구현하지 말아야 한다.

이유:

- 기존 `videos` 문서의 field 분포를 확인하지 않은 상태에서 backfill하면 데이터 계약을 손상할 수 있다.
- field rename, 컬렉션명 변경, Storage path rename, local index key 변경은 금지 대상이다.
- optional field와 fallback으로 충분한 경우 migration 자체가 불필요할 수 있다.

필요 승인:

- Backend/Ops: 익명 inventory dry-run 실행 승인.
- 데이터 보호 관점: 샘플 사용자, staged rollout, rollback plan.

권장 후속 작업:

1. `storagePath`, `storageTier`, `lifecycleState`, `cloudState`, `originalStoragePath`, `originalStorageTier` 존재 여부를 익명 집계한다.
2. read fallback으로 처리 가능한 문서는 migration하지 않는다.
3. 꼭 필요한 최소 field만 backfill 대상으로 분리한다.

### 4.5 R5 Firebase rules/index 변경

rules/index 변경은 즉시 구현하지 말아야 한다. 다만 검증 작업은 안전하게 수행 가능하다.

이유:

- rules 변경은 보안 완화 위험이 있다.
- index 변경은 배포와 query 동작에 영향을 줄 수 있다.
- Cloud copy/restore 편의를 위해 broad allow rule을 추가하는 것은 릴리스 금지 조건이다.

필요 승인:

- Backend/Security 성격의 검토: uid 소유권 조건 유지 또는 강화.
- QA: read/write deny case 포함 테스트.

권장 후속 작업:

1. 현재 Flutter query가 기존 rules/index로 동작하는지 emulator/test 계정으로 검증한다.
2. index 부족이 확인된 경우 최소 index 변경안을 별도 문서 또는 PR로 분리한다.
3. rules는 uid 소유권 조건을 완화하지 않는 방향만 검토한다.

### 4.6 R6 정적 분석 부채

일부만 안전하게 구현 가능하다.

안전 후보:

- Cloud 관련 변경 파일의 unused import 제거.
- 명확한 unused local variable 제거.
- 신규 error 0 유지 확인.

구현하지 말아야 하는 범위:

- 전체 프로젝트 자동 포맷.
- 결제/IAP 권한 판정, nullability, provider/login 흐름과 연결된 경고를 분석 없이 수정.
- 의미 변경 가능성이 있는 리팩터링.

필요 승인:

- 광범위 analyze cleanup을 하려면 별도 범위 승인.
- IAP/nullability 경고는 결제/권한 기능 영향도 분석 후 진행.

권장 후속 작업:

1. Cloud 관련 파일 목록을 먼저 확정한다.
2. `flutter analyze` baseline을 기록한다.
3. unused import 같은 무의미한 항목만 소규모로 수정한다.
4. 수정 전후 analyze diff를 보고한다.

### 4.7 R7 QA 미완료

즉시 안전하게 수행 가능하다. 단, 실제 사용자 계정/운영 데이터가 아닌 테스트 계정과 테스트 장비를 사용해야 한다.

이유:

- QA는 현재 구현 관찰과 문서화 중심이며 schema/path/key를 바꾸지 않는다.
- 릴리스 차단 경로를 구현 전 확인하는 활동이다.

주의점:

- 재설치/앱 데이터 삭제 QA는 테스트 장비와 테스트 계정으로 제한한다.
- quota/저장공간 부족 QA는 원본 영상 삭제 여부를 특히 확인한다.
- 만료 QA는 sandbox 구독과 테스트 계정 기준으로만 수행한다.

권장 후속 작업:

1. QA 패스 1을 우선 수행한다.
2. 결과표에 기대 동작, 실제 동작, Firestore field 변화, 로컬 원본 보존 여부를 기록한다.
3. 릴리스 금지 조건이 하나라도 발견되면 구현보다 원인 분석을 우선한다.

## 5. 실행 체크리스트 재분류

| ID | 계획상 작업 | 이번 분류 | 구현/수행 판단 | 비고 |
|---|---|---|---|---|
| R7-1 | Standard 촬영 자동 Cloud queue 수동 QA | 안전 | 수행 가능 | 테스트 계정 기준 |
| R7-2 | 재설치/재로그인 Cloud placeholder QA | 안전 | 수행 가능 | 테스트 장비 앱 데이터 삭제 범위 |
| R7-3 | Trash/restore Cloud metadata 보존 QA | 안전 | 수행 가능 | Firestore field 비교는 관찰 중심 |
| R3-1 | 구독 만료 grace/download 정책 결정 | 승인 필요 | 코드 구현 금지 | Product/Ops 결정 필요 |
| R3-2 | sandbox 구독 만료 QA | 조건부 안전 | 수행 가능 | sandbox 계정 필요, 정책 구현은 금지 |
| R2-1 | 영구 삭제 dry-run inventory 설계 | 승인 필요 | 문서 설계만 가능 | 실제 query 실행/Functions 구현 전 승인 필요 |
| R2-2 | Storage 삭제 execute gate 설계 | 승인 필요 | 문서 설계만 가능 | execute 구현 금지 |
| R1-1 | Cloud copy UX/문구 확정 | 승인 필요 | 문서/UX 초안만 가능 | 앱 반영 전 Product 승인 |
| R1-2 | Cloud copy usage accounting 계약 작성 | 승인 필요 | 계약 문서만 가능 | 코드/DB 변경 금지 |
| R4-1 | 기존 `videos` field inventory dry-run | 승인 필요 | 실행 전 승인 필요 | 익명 집계 설계는 가능 |
| R4-2 | 최소 backfill 계획 작성 | 승인 필요 | 계획 문서만 가능 | backfill execute 금지 |
| R5-1 | 현재 query rules/index 검증 | 안전 | 수행 가능 | 변경 없는 emulator/test 검증 |
| R5-2 | 필요한 경우 최소 index/rule 변경안 작성 | 승인 필요 | 변경안 문서만 가능 | 실제 rules/index 수정 금지 |
| R6-1 | Cloud 관련 analyze warning 정리 | 부분 안전 | 좁은 코드 수정 후보 | unused import 등만 후보, 이번 작업에서는 미수행 |

## 6. 권장 후속 작업 순서

1. QA 패스 1 문서화: R7-1, R7-2, R7-3을 테스트 계정으로 수행하고 결과표를 남긴다.
2. Firebase 검증 1: rules/index를 변경하지 않고 현재 query 동작과 deny case를 확인한다.
3. sandbox 만료 QA: 현 동작만 기록하고 정책 구현은 보류한다.
4. Product/Ops 결정: grace 기간, 다운로드 허용, Cloud copy UX, 삭제 고지 정책을 확정한다.
5. Backend dry-run 설계: Storage 삭제 inventory와 `videos` field inventory를 실제 mutation 없이 설계한다.
6. Flutter cleanup 1: Cloud 관련 파일의 명확한 unused import/unused local variable만 별도 Code 모드에서 소규모로 처리한다.

## 7. 이번 하위 작업에서 변경하지 않은 항목

다음 항목은 승인/QA/운영 결정 없이는 구현하지 않는 것이 안전하다고 판단했다.

- Cloud copy 기능 구현.
- Storage 영구 삭제 Functions 또는 scheduler 구현.
- 구독 만료 후 Cloud 접근 차단/삭제 구현.
- `videos` 문서 backfill 또는 migration 실행.
- Firestore/Storage rules 완화 또는 index 배포 변경.
- `flutter analyze` 전체 부채 정리나 광범위 자동 포맷.
- 로컬 key, Storage path, Firestore 컬렉션/field rename.

## 8. 결론

현재 단계에서 즉시 안전하게 진행할 수 있는 것은 QA/검증/문서화와 제한적인 정적 분석 cleanup 후보에 한정된다. R1, R2, R3, R4, R5 변경안, R6 광범위 cleanup은 사용자 데이터 보존, 기존 기능 유지, 레거시 호환에 직접 영향을 줄 수 있으므로 별도 승인, dry-run, 백업 또는 rollback 계획 없이 구현하지 않는 것이 맞다.

상위 작업에서 Code 모드로 넘길 수 있는 안전 후보는 다음과 같다.

1. QA 결과 문서 템플릿 작성 또는 QA 체크리스트 보강.
2. rules/index 변경 없는 emulator/test 계정 검증 절차 문서화.
3. Cloud 관련 파일의 unused import 등 명확한 analyze cleanup.
4. Cloud copy, deletion, migration/backfill은 구현이 아니라 계약/승인 문서 작성으로만 진행.

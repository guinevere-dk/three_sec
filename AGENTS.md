# AGENTS.md

이 문서는 MOA 저장소에서 AI가 작업할 때 따라야 하는 최상위 운영 규칙입니다. 상세 기술 절차는 `SKILLS.md`, 데이터 호환성은 `DATA_COMPATIBILITY.md`, 현재 범위는 `CURRENT_PHASE.md`를 함께 확인합니다.

## 1. 의사결정 우선순위

기준이 충돌하면 반드시 아래 순서로 판단합니다.

1. 사용자 데이터 보존
2. 기존 기능 유지
3. 레거시 호환
4. 안정성
5. 유지보수성
6. 신규 기능
7. 코드 미관

사용자 원본 영상, 프로젝트 메타데이터, 로컬 인덱스, 계정 소유권, 구독/결제 상태, 클라우드 동기화 상태에 영향을 줄 수 있으면 리팩터링보다 보존과 호환을 우선합니다.

## 2. 프로젝트 기준

- 프로젝트는 Flutter/Dart 기반 모바일 앱입니다.
- 사용자 노출 브랜드 기준은 `MOA`입니다.
- 제품 설명 기준은 `2초 촬영 + Vlog`입니다.
- 레거시 식별자인 `three_sec_vlog`, `three_s`, `com.dk.three_sec`, `fir-3s-8edb9`, `3s_*`, `vlog_projects`, `vlog_folders`는 브랜드 변경 목적으로 임의 변경하지 않습니다.
- 리브랜딩 Phase와 영향도 판단은 `plans/moa_rebrand_phase_plan_interactive_v1.html`을 우선합니다.

## 3. 작업 범위 규칙

- 요청 범위 밖 파일, 설정, 기능을 수정하지 않습니다.
- 코드 변경 요청이 아닌 경우 Markdown 문서만 수정합니다.
- 한 작업에서 Flutter UI, Firebase 규칙, Functions, DB 스키마, 플랫폼 설정을 동시에 바꾸지 않습니다.
- 불확실하면 구현보다 영향도 분석과 계획을 먼저 수행합니다.
- 삭제보다 deprecated 처리, fallback, dual-read/write, 호환 레이어를 먼저 검토합니다.
- 변경 전 기존 파일과 계획 문서를 읽고 근거를 확보합니다.

## 4. 승인 필요 대상

아래 항목은 별도 승인, dry-run, 백업, 롤백 계획 없이 변경하지 않습니다.

- `applicationId`, Android namespace, iOS bundle id, 패키지명.
- Firebase project id, alias, 앱 등록, 서비스 계정.
- Firestore 컬렉션명, 문서 id 계약, 필드명 계약.
- Storage 경로와 파일 prefix.
- SharedPreferences key, 로컬 파일 디렉터리, 로컬 인덱스 schema.
- IAP product id와 구독 검증 계약.
- `pubspec.lock`, Gradle/iOS 플랫폼 설정, Firebase 설정 파일.
- 사용자 데이터 삭제, 대량 rename, 마이그레이션, 계정 소유권 변경.

## 5. 절대 금지 사항

- 사용자 원본 영상, 프로젝트 JSON, 로컬 인덱스, 클라우드 백업, 계정 소유권 필드를 삭제하거나 초기화하지 않습니다.
- Firebase 보안 규칙을 완화하지 않습니다.
- `com.dk.three_sec`, `fir-3s-8edb9`, `users/{uid}/videos/{videoId}/{fileName}`, `videos`, `users`, `vlog_projects`를 브랜드 전환 목적으로 바꾸지 않습니다.
- `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual` product id를 임의 변경하지 않습니다.
- 비밀값, OAuth secret, 실제 사용자 uid, 키스토어 정보, 실제 토큰을 문서나 코드에 남기지 않습니다.
- 추측 기반 리팩터링, 대량 rename, 자동 포맷만을 위한 광범위 변경을 하지 않습니다.

## 6. 기본 작업 프로토콜

1. 요청 범위와 수정 가능 파일을 확인합니다.
2. `AGENTS.md`, `CURRENT_PHASE.md`, `DATA_COMPATIBILITY.md`, 관련 계획 문서를 읽습니다.
3. 데이터 보존, 기능 유지, 레거시 호환 관점에서 영향도를 분류합니다.
4. 변경 대상과 검증 방법을 계획합니다.
5. 작은 단위로 변경하고 하나의 시스템만 다룹니다.
6. 변경 후 금지 식별자 변경 여부, 문서 충돌, 검증 필요성을 점검합니다.
7. 완료 보고에 변경 파일, 근거, 검증 결과, 미검증 사유, 남은 리스크를 남깁니다.

## 7. 완료 보고 기준

완료 보고에는 다음을 포함합니다.

- 변경/생성 파일 목록.
- 분석한 핵심 근거 파일.
- 핵심 변경 또는 운영 규칙.
- 실행한 검증 명령과 결과.
- 미검증 사유.
- 남은 리스크와 후속 승인 필요 항목.

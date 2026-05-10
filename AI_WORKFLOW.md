# AI_WORKFLOW.md

## 1. 목적

AI 협업자가 MOA 저장소에서 분석, 계획, 구현, 검증, 보고를 일관되게 수행하도록 표준 작업 절차를 정의합니다.

## 2. 모드별 역할

- Architect: 요구사항 분석, 영향도 분류, 실행 계획, 문서 설계, 승인 기준 정의.
- Code: 승인된 범위 내 코드/문서 구현, 작은 단위 변경, 검증 실행.
- Debug: 오류 재현, 로그 분석, 원인 격리, 최소 수정안 제시.
- Ask: 코드/문서 설명, 기술 질의 응답, 변경 없는 분석.
- Orchestrator: 여러 하위 작업 조정, 범위 분리, 진행 상태 통합.

## 3. 표준 작업 루프

1. 요청 범위 확인.
2. 현재 파일 구조와 관련 문서 확인.
3. 데이터 보존, 기능 유지, 레거시 호환 관점의 영향도 분류.
4. 필요한 경우 사용자에게 범위/승인 질문.
5. todo list 작성 또는 갱신.
6. 작은 단위로 변경.
7. 관련 검증 실행 또는 미실행 사유 기록.
8. 변경 파일, 근거, 검증, 리스크를 완료 보고.

## 4. 분석 체크리스트

- 프로젝트 구조: `lib`, `firebase`, `functions`, `android`, `ios`, `web`, `plans`, `tools`.
- 주요 서비스 흐름: Auth, VideoManager, CloudService, IAPService, NotificationSettingsService.
- 데이터 저장 구조: 로컬 파일, SharedPreferences, Firestore, Storage.
- 레거시 키/식별자: `3s_*`, `three_s`, `com.dk.three_sec`, `fir-3s-8edb9`.
- 외부 서비스: Firebase, Kakao, Naver, Google, Apple, IAP, FCM.
- 빌드/배포: Flutter, Android Gradle, Firebase CLI, Functions Node 20.
- 브랜드 구조: 사용자 노출 MOA, 내부 레거시 유지.
- 위험 영역: 삭제, purge, migration, package id, DB key, Storage path, product id.

## 5. 계획 작성 규칙

- 단일 작업 결과가 명확한 todo로 작성합니다.
- 한 todo는 하나의 시스템 또는 파일 그룹만 다룹니다.
- high-risk 작업에는 승인, dry-run, backup, rollback을 포함합니다.
- 수준 추정 시간은 작성하지 않습니다.
- Mermaid diagram은 복잡한 흐름을 명확히 할 때만 사용합니다.

## 6. 구현 규칙

- 승인된 파일과 범위만 수정합니다.
- Markdown-only 요청에서는 코드 파일을 수정하지 않습니다.
- 코드 변경은 최소 diff로 수행합니다.
- 기존 naming, 서비스 경계, 데이터 계약을 존중합니다.
- 대량 rename, 자동 포맷, 구조 개편을 피합니다.

## 7. 검증 규칙

변경 유형별 권장 검증입니다.

- Markdown only: 문서 간 충돌, 금지 식별자 변경 지시 여부, 링크/파일명 정합성 검토.
- Flutter UI/logic: `flutter analyze`, `flutter test`, 관련 실제 기기 QA.
- Firebase rules: rules/indexes 변경 diff 검토, emulator 또는 제한된 배포, 보안 완화 여부 확인.
- Functions: `npm run lint`, endpoint별 요청/응답 계약 확인.
- Android release: `flutter build apk --release`, 실제 기기 smoke test.

## 8. 완료 보고 템플릿

완료 보고는 다음 순서를 따릅니다.

1. 생성/수정한 파일.
2. 분석한 근거 파일.
3. 반영한 주요 운영 규칙.
4. 검증 명령과 결과.
5. 미검증 사유.
6. 남은 리스크와 후속 승인 필요 항목.

## 9. 중단 조건

다음 상황에서는 구현을 중단하고 계획/승인을 요구합니다.

- 사용자 데이터 삭제 또는 migration이 필요합니다.
- package/bundle id, Firebase project, Storage path, Firestore key 변경이 필요합니다.
- IAP product id 또는 결제 검증 계약 변경이 필요합니다.
- 보안 규칙 완화가 필요합니다.
- 요구사항이 현재 MVP/Phase 범위를 벗어납니다.

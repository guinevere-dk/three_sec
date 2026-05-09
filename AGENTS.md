# AGENTS.md

이 저장소에서 작업할 때 지킬 최소 운영 규칙입니다. 상세 리브랜딩 근거와 Phase 판정은 `plans/moa_rebrand_phase_plan_interactive_v1.html`을 우선합니다.

## 핵심 기준

- 프로젝트: Flutter/Dart 기반 모바일 앱.
- 현재 브랜드 기준: `MOA`.
- 제품 설명 기준: `2초 촬영 + Vlog`.
- 사용자 노출에서 `원세컨`, `One Second Vlog`, `1s Vlog`, `Three Sec Vlog`, `3s` 브랜드 확산을 피합니다.
- 레거시/호환 영역의 `three_sec_vlog`, `three_s`, `com.dk.three_sec`, `fir-3s-8edb9`, `3s_*`, `vlog_projects`, `vlog_folders`는 영향도 높음 이상으로 보고 임의 변경하지 않습니다.

## 리브랜딩 작업 원칙

- Phase는 계획 문서의 순서대로 순차 진행합니다.
- 기본 실행 가능 범위는 Phase 0~2의 낮음/중간 영향도 작업입니다.
  - Phase 0: inventory, 영향도 분류, 기준선 고정.
  - Phase 1: 사용자 노출 브랜드/카피, 앱 표시명, 웹 manifest 등 문자열 중심 변경.
  - Phase 2: README, plans, benchmark, 운영 지침 등 문서 정렬.
- 영향도 `높음` 및 `매우 높음` 항목은 별도 승인, dry-run, backup, rollback plan 없이 코드/설정/DB/식별자 변경을 하지 않습니다.
- Phase 3 이후의 로컬 키, DB, Firebase, Storage, 패키지/번들 ID, 워크스페이스명 변경은 기본 보류합니다.

## 금지 사항

- 사용자 원본 영상, 프로젝트 메타, 로컬 인덱스, 계정 소유권 필드를 삭제/초기화하지 않습니다.
- Firebase 보안 규칙을 완화하지 않습니다.
- product ID를 임의 변경하지 않습니다.
- `applicationId`, bundle ID, Firebase 프로젝트, Firestore/Storage 실데이터 키, 로컬 저장 키는 브랜드 전환 목적으로 일괄 변경하지 않습니다.
- `pubspec.lock`, 플랫폼 Gradle/iOS 설정, Firebase 설정 파일은 명시 목적 없이 변경하지 않습니다.
- 비밀값, OAuth secret, 실제 사용자 uid, 키스토어 정보, 실제 토큰은 문서나 코드에 남기지 않습니다.

## 실행/검증 기본 명령

Windows 개발 환경 기준으로 프로젝트 루트에서 실행합니다.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Functions 작업 시:

```bash
cd functions
npm install
npm run lint
npm run serve
```

Firebase 배포는 규칙/인덱스/계약 문서 일치 확인 후 수행합니다.

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage:rules
firebase deploy --only functions
```

Android QA 보조: `tools\android_capture_session.cmd`

## 완료 보고

작업 완료 시 변경 파일, 검토 근거, 핵심 변경, 검증 명령과 결과, 미검증 사유, 남은 리스크/후속 승인 필요 항목을 간결히 보고합니다.

# MOA

**MOA**는 2초 촬영으로 일상의 순간을 모아 Vlog/영상 앨범을 만드는 Flutter/Dart 기반 모바일 앱 프로젝트입니다.

## 핵심 원칙

- 브랜드 기준은 **MOA**입니다.
- 제품 설명 기준은 **2초 촬영 + Vlog**입니다.
- 사용자 노출 문구와 문서 카피는 MOA 기준으로 정렬합니다.
- 리브랜딩 Phase와 영향도 판단은 [`plans/moa_rebrand_phase_plan_interactive_v1.html`](plans/moa_rebrand_phase_plan_interactive_v1.html)을 우선합니다.
- 영향도 높음 이상 항목은 별도 승인, dry-run, backup, rollback plan 없이 변경하지 않습니다.

## 개발 및 검증 명령

프로젝트 루트에서 아래 명령을 사용합니다.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Firebase Functions 작업 시에는 [`functions`](functions) 디렉터리에서 아래 명령을 사용합니다.

```bash
cd functions
npm install
npm run lint
npm run serve
```

Firebase 배포는 규칙/인덱스/계약 문서 일치 확인 후 필요한 대상만 수행합니다.

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage:rules
firebase deploy --only functions
```

Android QA 보조 명령은 [`tools/android_capture_session.cmd`](tools/android_capture_session.cmd)를 사용합니다.

## 리브랜딩 보류 및 레거시 호환 항목

아래 항목은 영향도 높음 이상으로 보고, 브랜드 전환 목적으로 임의 변경하지 않습니다.

- [`pubspec.yaml`](pubspec.yaml)의 패키지명 `three_s`
- [`android/app/build.gradle.kts`](android/app/build.gradle.kts)의 패키지 계열
- Firebase alias 및 기존 프로젝트 식별자
- Firestore/Storage 컬렉션, 경로, 키
- IAP product ID
- 로컬 저장 키, DB 키, 마이그레이션 대상 식별자
- 레거시 호환 문자열: `three_sec_vlog`, `three_s`, `com.dk.three_sec`, `fir-3s-8edb9`, `3s_*`, `vlog_projects`, `vlog_folders`

이 항목들은 사용자 원본 영상, 프로젝트 메타, 로컬 인덱스, 계정 소유권, 결제/구독, 클라우드 동기화와 연결될 수 있으므로 별도 승인된 전환 계획 없이 유지합니다.

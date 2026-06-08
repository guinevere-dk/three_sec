# RELEASE_RULES.md

## 1. 릴리스 원칙

- 릴리스 전 사용자 데이터 보존, 기존 기능 유지, 레거시 호환을 우선 검증합니다.
- Firebase 배포는 rules, indexes, storage, functions를 분리합니다.
- 앱 릴리스와 서버/Firebase 변경을 한 번에 묶지 않습니다.
- 미검증 항목은 릴리스 노트와 완료 보고에 명시합니다.

## 2. 공통 preflight

- `AGENTS.md`, `CURRENT_PHASE.md`, `DATA_COMPATIBILITY.md` 위반 여부 확인.
- 변경 파일에 금지 식별자 변경이 없는지 확인.
- 사용자 원본 영상, 로컬 프로젝트, 클라우드 데이터 삭제 로직 변경 여부 확인.
- 브랜드 표기는 사용자 노출에서 `MOA`, `2초 촬영 + Vlog` 기준인지 확인.
- secrets, uid, 토큰, keystore 값이 문서/로그에 포함되지 않았는지 확인.
- 앱 버전 bump 시 `firebase/hosting/app-update.json`의 `latestVersion`과 `minimumRequiredVersion`도 함께 올릴지 반드시 확인하고, 강제 업데이트 범위 영향도를 기록합니다.

## 3. Flutter 검증 명령

```bash
flutter pub get
flutter analyze
flutter test
```

AI에게 Android 릴리스 빌드 요청이 오면 `auth 포함 빌드`로 해석합니다. `.env`에서 `KAKAO_NATIVE_APP_KEY`를 로드하고, `SOCIAL_AUTH_EXCHANGE_URL`은 `.env` 값이 없으면 기본 Functions URL을 사용합니다. 비밀값은 로그/문서/완료 보고에 출력하지 않습니다.

```powershell
Get-Content .env | ForEach-Object { if ($_ -match '^\s*([^#=]+)=(.*)$') { Set-Item "Env:$($matches[1].Trim())" $matches[2].Trim() } }
if (-not $env:SOCIAL_AUTH_EXCHANGE_URL) { $env:SOCIAL_AUTH_EXCHANGE_URL='https://asia-northeast3-fir-3s-8edb9.cloudfunctions.net/social/exchange' }
flutter build appbundle --release `
  --dart-define=KAKAO_NATIVE_APP_KEY=$env:KAKAO_NATIVE_APP_KEY `
  --dart-define=SOCIAL_AUTH_EXCHANGE_URL=$env:SOCIAL_AUTH_EXCHANGE_URL `
  --dart-define=APP_UPDATE_CONFIG_URL=https://fir-3s-8edb9.web.app/app-update.json
```

필요 시 실제 기기에서 다음을 확인합니다.

- 첫 실행, 로그인/게스트 진입.
- 카메라 권한, 촬영, 저장.
- 외부 이미지/영상 가져오기.
- 프로젝트 생성, 편집, 내보내기.
- 앱 재시작 후 로컬 데이터 복구.
- 클라우드 업로드/다운로드/삭제.
- 구독 tier별 기능 제한.
- FCM 권한과 알림 탭 라우팅.

## 4. Firebase 릴리스 게이트

### Firestore rules

- `users/{uid}` 본인 read/write 조건 유지.
- `videos`의 `uid`, `videoId` 불변 조건 유지.
- `vlog_projects`의 `uid` 불변 조건 유지.
- 보안 완화 금지.

배포 명령:

```bash
firebase deploy --only firestore:rules
```

### Storage rules

- `users/{uid}/videos/{videoId}/{fileName}` 본인 접근 조건 유지.
- 영상 파일 타입과 최대 500MB 제한 유지 또는 강화.
- profile 이미지 경로 본인 접근 조건 유지.

배포 명령:

```bash
firebase deploy --only storage:rules
```

### Indexes

- Firestore query 추가 시 `firebase/firestore.indexes.json`와 실제 query를 함께 검토합니다.

배포 명령:

```bash
firebase deploy --only firestore:indexes
```

### Functions

- `functions/package.json`의 `npm run lint`는 `node --check index.js`입니다.
- social exchange와 IAP verify endpoint를 분리 검증합니다.
- product id allowlist 변경은 승인 필요입니다.

검증/배포 명령:

```bash
npm install
npm run lint
firebase deploy --only functions
```

## 5. Android 릴리스 게이트

- `android/app/build.gradle.kts`의 `applicationId = "com.dk.three_sec"` 유지.
- `namespace = "com.dk.three_sec"` 유지.
- release signing key 설정은 로컬 secret로 관리하고 문서화하지 않습니다.
- `isMinifyEnabled`, `isShrinkResources`, proguard 변경 시 release build와 실제 기기 QA 필요.
- `android/app/google-services.json` 존재 여부와 package_name 정합성 확인.
- Play Console 가이드는 `plans/google_play_console_release_guide.md`를 따릅니다.

## 6. iOS/Web 릴리스 게이트

- iOS bundle id 변경은 보류입니다.
- Apple login, StoreKit, App Store metadata 변경은 별도 계획 기준으로 검토합니다.
- Web `web/manifest.json`은 사용자 노출 브랜드는 변경 가능하지만 app identity와 Firebase 연계 설정은 보수적으로 검토합니다.

## 7. 백업과 롤백 기준

- 코드/문서 변경은 Git diff와 commit 단위로 롤백 가능해야 합니다.
- Firebase rules 배포 전 이전 rules 파일을 보존합니다.
- Functions 배포 전 직전 정상 버전, endpoint, env/config를 기록합니다.
- DB/Storage schema 또는 데이터 변경은 사전 export, 샘플 uid dry-run, rollback script 없이 수행하지 않습니다.
- 앱 릴리스 후 crash, 로그인 실패, 저장/불러오기 실패, 결제 검증 실패, 클라우드 권한 실패가 확인되면 즉시 rollout 중단 또는 이전 빌드 유지 전략을 적용합니다.

## 8. `100%출시해라` 운영 순서

사용자가 `100%출시해라`라고 요청하면 먼저 아래 순서를 명시하고, 가능한 단계부터 순서대로 진행합니다.

1. 출시를 위한 버전업
2. push
3. 빌드 생성
4. 빌드 업로드
5. Play 검토
6. 검토 승인
7. staged rollout 시작
8. 실제 스토어 반영 확인
9. `latestPublishedBuild` 갱신
10. 앱 업데이트 팝업 활성화

Play 검토, 검토 승인, 스토어 반영은 Google Play 외부 상태입니다. 빌드 업로드 후에는 사용자에게 출시 완료 또는 스토어 반영 확인 시점을 알려 달라고 요청하고, 그 신호를 받은 뒤 `latestPublishedBuild`와 Hosting 업데이트 팝업을 활성화합니다.

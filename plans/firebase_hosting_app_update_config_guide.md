# Firebase Hosting 앱 업데이트 설정 JSON 운영 가이드

## 1. 목적과 범위

이 문서는 Firebase Hosting에 앱 업데이트 설정 JSON을 배포하고, Flutter 릴리스 빌드에서 `APP_UPDATE_CONFIG_URL`을 주입하는 절차를 정리합니다.

저장소에는 정적 Hosting public 디렉터리와 기본 JSON만 준비합니다. Firebase 프로젝트 선택, Hosting 사이트 활성화, 실제 배포, 릴리스 빌드는 사용자 승인과 로그인 상태가 필요하므로 사용자가 직접 수행합니다.

## 2. 현재 저장소 설정

- Firebase 프로젝트 alias는 `.firebaserc`의 `default`를 그대로 사용합니다.
- Firebase project id, alias, 앱 등록, 서비스 계정은 변경하지 않습니다.
- Hosting public 경로는 `firebase/hosting`입니다.
- 앱 업데이트 JSON 경로는 `firebase/hosting/app-update.json`입니다.
- 현재 앱 버전 기준값은 `pubspec.yaml`의 `1.3.5+135`에서 build number를 제외한 `1.3.5`입니다.

현재 기본 JSON은 강제 업데이트를 실수로 발생시키지 않도록 `latestVersion`과 `minimumRequiredVersion`을 모두 현재 버전과 동일한 `1.3.5`로 둡니다.

```json
{
  "latestVersion": "1.3.5",
  "minimumRequiredVersion": "1.3.5",
  "playStoreUrl": "https://play.google.com/store/apps/details?id=com.dk.three_sec",
  "message": "MOA의 안정적인 이용을 위해 최신 버전으로 업데이트해 주세요."
}
```

## 3. Firebase Hosting 초기화/배포 전 확인 사항

배포 전에 다음을 확인합니다.

1. Firebase CLI가 설치되어 있어야 합니다.

   ```bash
   npm install -g firebase-tools
   ```

2. Firebase CLI에 로그인합니다.

   ```bash
   firebase login
   ```

3. 현재 프로젝트가 의도한 Firebase 프로젝트인지 확인합니다.

   ```bash
   firebase projects:list
   firebase use
   ```

4. `.firebaserc`의 기본 프로젝트가 운영 대상과 일치하는지 확인합니다.
   - 현재 저장소 기준: `fir-3s-8edb9`
   - 이 값은 승인 필요 대상이므로 가이드 절차 중 임의 변경하지 않습니다.

5. Firebase Console에서 Hosting이 아직 활성화되지 않았다면 사용자가 직접 Hosting을 시작합니다.
   - Firebase Console → 프로젝트 선택 → Hosting → 시작하기
   - 사이트 생성/연결 여부 확인
   - 프로젝트 id 또는 site id 변경이 필요하면 별도 승인 후 진행

## 4. JSON 파일 수정 방법

수정 대상 파일은 `firebase/hosting/app-update.json`입니다.

필드 의미는 다음과 같습니다.

| 필드 | 의미 | 운영 주의사항 |
|---|---|---|
| `latestVersion` | 선택 업데이트 안내 기준 버전 | 현재 앱 버전보다 높으면 선택 업데이트 알림이 뜰 수 있습니다. |
| `minimumRequiredVersion` | 강제 업데이트 기준 최저 버전 | 현재 앱 버전보다 높이면 강제 업데이트가 발생합니다. 신중히 변경합니다. |
| `playStoreUrl` | 업데이트 버튼이 여는 Play Store URL | Android applicationId `com.dk.three_sec`를 유지합니다. |
| `message` | 업데이트 다이얼로그 안내 문구 | 사용자에게 노출되는 문구입니다. |

버전 문자열은 앱 코드의 파서에 맞춰 `major.minor.patch` 형식으로 작성합니다. 예: `1.3.6`.

## 5. 배포 방법

Hosting만 배포합니다. Firestore, Storage, Functions는 이 작업 범위에서 배포하지 않습니다.

```bash
firebase deploy --only hosting
```

특정 Hosting site target을 별도로 쓰는 구성이 있다면 기존 운영 절차에 따라 target을 확인한 뒤 배포합니다. 이 저장소 변경에서는 site id나 target alias를 추가하지 않았습니다.

## 6. 배포 후 JSON URL 확인 방법

배포가 완료되면 Firebase CLI 또는 Console에 표시되는 Hosting 도메인을 확인합니다.

일반적인 기본 URL 형식은 다음 중 하나입니다.

```text
https://<firebase-project-id>.web.app/app-update.json
https://<firebase-project-id>.firebaseapp.com/app-update.json
```

현재 `.firebaserc` 기준으로 예상 가능한 URL은 다음과 같습니다.

```text
https://fir-3s-8edb9.web.app/app-update.json
https://fir-3s-8edb9.firebaseapp.com/app-update.json
```

단, 실제 Hosting site id가 다를 수 있으므로 Firebase Console 또는 `firebase deploy --only hosting` 결과에 나온 URL을 최종 기준으로 사용합니다.

브라우저 또는 명령어로 JSON 응답을 확인합니다.

```bash
curl https://fir-3s-8edb9.web.app/app-update.json
```

확인 기준:

- HTTP 200으로 응답합니다.
- JSON root가 object입니다.
- `latestVersion`, `minimumRequiredVersion`이 `major.minor.patch` 형식입니다.
- `minimumRequiredVersion`이 의도치 않게 현재 배포 앱 버전보다 높지 않습니다.

## 7. Flutter 릴리스 빌드에 URL 주입

앱 업데이트 체크는 릴리스 빌드 시 `APP_UPDATE_CONFIG_URL`이 비어 있지 않을 때 활성화됩니다.

Android App Bundle 예시:

```bash
flutter build appbundle --release --dart-define=APP_UPDATE_CONFIG_URL=https://fir-3s-8edb9.web.app/app-update.json
```

Android APK 예시:

```bash
flutter build apk --release --dart-define=APP_UPDATE_CONFIG_URL=https://fir-3s-8edb9.web.app/app-update.json
```

실제 명령에는 배포 후 확인한 Hosting URL을 사용합니다.

## 8. 운영 예시

### 8.1 업데이트 없음

현재 앱이 `1.3.5`일 때:

```json
{
  "latestVersion": "1.3.5",
  "minimumRequiredVersion": "1.3.5",
  "playStoreUrl": "https://play.google.com/store/apps/details?id=com.dk.three_sec",
  "message": "MOA의 안정적인 이용을 위해 최신 버전으로 업데이트해 주세요."
}
```

결과: 업데이트 다이얼로그가 뜨지 않습니다.

### 8.2 선택 업데이트

현재 앱이 `1.3.5`이고 Play Store에 `1.3.6`이 배포된 뒤:

```json
{
  "latestVersion": "1.3.6",
  "minimumRequiredVersion": "1.3.5",
  "playStoreUrl": "https://play.google.com/store/apps/details?id=com.dk.three_sec",
  "message": "새 버전이 준비되었습니다. 더 안정적인 MOA를 사용하려면 업데이트해 주세요."
}
```

결과: `1.3.5` 사용자는 선택 업데이트 안내를 받을 수 있습니다.

### 8.3 강제 업데이트

심각한 장애 또는 정책 이슈로 `1.3.6` 미만을 막아야 할 때:

```json
{
  "latestVersion": "1.3.6",
  "minimumRequiredVersion": "1.3.6",
  "playStoreUrl": "https://play.google.com/store/apps/details?id=com.dk.three_sec",
  "message": "중요한 안정성 개선이 포함되어 있습니다. 계속 사용하려면 업데이트가 필요합니다."
}
```

결과: `1.3.5` 이하는 강제 업데이트 대상이 됩니다. Play Store에 해당 버전이 실제로 배포되고 충분히 전파된 뒤 적용합니다.

## 9. 롤백 방법과 주의사항

### 9.1 JSON 값 롤백

강제 업데이트를 잘못 켠 경우 `minimumRequiredVersion`을 즉시 현재 운영 앱 버전 이하로 낮추고 Hosting만 재배포합니다.

```bash
firebase deploy --only hosting
```

### 9.2 Firebase Hosting 릴리스 롤백

Firebase Console에서 Hosting 릴리스 히스토리를 열고 직전 정상 릴리스로 롤백할 수 있습니다.

주의사항:

- 롤백 전에 어떤 JSON이 배포되는지 확인합니다.
- 강제 업데이트 기준을 높인 상태의 JSON이 CDN/클라이언트 캐시에 남을 수 있으므로 배포 직후 앱에서 재확인합니다.
- Firestore/Storage/Functions 배포와 섞지 않습니다.

## 10. 사용자가 직접 해야 하는 작업 목록

- Firebase Console에서 Hosting 활성화 여부 확인.
- Firebase CLI 로그인 및 대상 프로젝트 확인.
- 필요 시 Hosting site id/target 운영 정책 결정.
- `firebase/hosting/app-update.json`의 버전과 메시지 운영값 검토.
- `firebase deploy --only hosting` 실행.
- 배포 URL에서 JSON 응답 확인.
- Flutter 릴리스 빌드 명령에 `--dart-define=APP_UPDATE_CONFIG_URL=<배포된 JSON URL>` 추가.
- Play Store 배포 상태와 JSON의 `latestVersion`, `minimumRequiredVersion` 정합성 확인.

## 11. 변경 금지 및 승인 필요 항목

이 절차 중 다음 항목은 임의 변경하지 않습니다.

- Firebase project id, alias, 앱 등록, 서비스 계정.
- Firestore/Storage rules 및 데이터 schema.
- Android applicationId `com.dk.three_sec`와 iOS bundle id.
- IAP product id.
- 사용자 원본 영상, 프로젝트 메타데이터, 클라우드 백업 경로.

위 항목 변경이 필요하면 별도 승인, 영향도 분석, dry-run, 백업/롤백 계획을 먼저 준비합니다.

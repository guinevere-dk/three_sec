# Kakao / Naver 소셜 로그인 연동 가이드

버튼은 UI에서 이미 실제 핸들러로 연결되어 있습니다. 그런데 눌러도 동작이 없는 이유는 보통 **네이티브 SDK 연동** 또는 **백엔드 custom token 교환 API**가 미완성이기 때문입니다.

현재 앱이 호출하는 진입점은 아래입니다.
- [`AuthService.signInWithKakao`](lib/services/auth_service.dart:195)
- [`AuthService.signInWithNaver`](lib/services/auth_service.dart:228)
- 공통 custom token 교환: [`_signInWithSocialProviderCustomToken`](lib/services/auth_service.dart:262)

`_signInWithSocialProviderCustomToken`는 `SOCIAL_AUTH_EXCHANGE_URL`이 비어 있으면 곧바로 예외를 던집니다. 예외는 catch로 잡혀 `null`이 되므로 버튼 클릭 후 "아무 일도 안 일어나는" 것처럼 보일 수 있습니다.

---

## 1) 먼저 확인할 우선순위

1. **`SOCIAL_AUTH_EXCHANGE_URL`가 빌드 환경변수로 전달됐는지**
   - `flutter run --dart-define=SOCIAL_AUTH_EXCHANGE_URL=...`
2. **Kakao/Naver 콘솔 앱 등록값이 각 플랫폼에 반영됐는지**
3. **Android `AndroidManifest` / iOS `Info.plist`에 필요한 URL Scheme/메타데이터 추가**
4. **서버에서 소셜 토큰을 Firebase custom token으로 교환해주는 API 동작 확인**

---

## 2) 백엔드: Custom Token 교환 API

앱은 소셜 토큰을 직접 Firebase에 전달하지 않고, 먼저 서버에서 검증 후 custom token을 받아야 합니다.

### 요청 형식
- Method: `POST`
- URL: `SOCIAL_AUTH_EXCHANGE_URL`
- Header: `Content-Type: application/json`
- Body 예시:

```json
{
  "provider": "kakao",
  "accessToken": "<kakao_access_token>",
  "idToken": "<kakao_id_token>"
}
```

or

```json
{
  "provider": "naver",
  "accessToken": "<naver_access_token>"
}
```

### 응답 형식 (최소한 하나라도 존재)
- `firebaseToken`, `customToken`, `token` 중 하나

예시:
```json
{ "firebaseToken": "eyJhbGciOi..." }
```

### 서버에서 해야 할 일
- 공급자 토큰 검증
- Firebase Admin SDK로 UID 결정
- `createCustomToken(uid, additionalClaims?)` 발급
- 앱이 기대하는 키(`firebaseToken`/`customToken`/`token`)로 반환

---

## 3) Android 연동

현재 저장소의 `AndroidManifest.xml`에는 Kakao/Naver용 설정이 없습니다.
- [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml:1)

### 3-1) 문자열 리소스 추가 (`strings.xml`)

`android/app/src/main/res/values/strings.xml`가 없다면 생성합니다.

```xml
<resources>
  <!-- Kakao -->
  <string name="kakao_native_app_key">YOUR_KAKAO_NATIVE_APP_KEY</string>

  <!-- Naver -->
  <string name="naver_client_id">YOUR_NAVER_CLIENT_ID</string>
  <string name="naver_client_secret">YOUR_NAVER_CLIENT_SECRET</string>
  <string name="naver_client_name">three-sec-vlog</string>
</resources>
```

### 3-2) `AndroidManifest.xml`에 메타데이터/URL 스킴 추가

`<application>` 내부 적절한 위치에 다음 항목을 반영합니다.

```xml
<application>
  <!-- Kakao App Key -->
  <meta-data
    android:name="com.kakao.sdk.AppKey"
    android:value="@string/kakao_native_app_key" />

  <!-- Kakao 콜백 스킴(예시) -->
  <meta-data
    android:name="com.kakao.sdk.RedirectUri"
    android:value="kakaoYOUR_KAKAO_NATIVE_APP_KEY://oauth" />

  <!-- Naver 메타데이터(플러그인 버전에 따라 키명은 다를 수 있음) -->
  <meta-data
    android:name="com.naver.nid.client_id"
    android:value="@string/naver_client_id" />
  <meta-data
    android:name="com.naver.nid.client_secret"
    android:value="@string/naver_client_secret" />
  <meta-data
    android:name="com.naver.nid.client_name"
    android:value="@string/naver_client_name" />

  <!-- MainActivity intent filter 예시: 각 provider 공식 가이드에서 요구하는 스킴으로 조정 -->
  <activity android:name=".MainActivity" ...>
    <intent-filter>
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data android:scheme="kakaoYOUR_KAKAO_NATIVE_APP_KEY" />
    </intent-filter>
  </activity>
```

> ⚠️ 위 키/스킴 명칭은 SDK/플러그인 버전별로 조금씩 다를 수 있습니다. 반드시 현재 사용 중인 공식 문서를 기준으로 최종 정합성을 맞추세요.

### 3-3) 앱 실행

```bash
flutter clean
flutter pub get
flutter run --dart-define=SOCIAL_AUTH_EXCHANGE_URL=https://your-domain.example.com/social/exchange
```

---

## 4) iOS 연동

현재 `Info.plist`에는 소셜 로그인 관련 항목이 없습니다.
- [`ios/Runner/Info.plist`](ios/Runner/Info.plist:1)

### 4-1) URL Scheme 등록

- `CFBundleURLTypes`에 Kakao/Naver callback scheme 추가
- Kakao: `kakao<네이티브 앱 키>` 형식
- Naver: 플러그인/콘솔 가이드에서 지정한 스킴 사용

예시(구조):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>kakaoYOUR_KAKAO_NATIVE_APP_KEY</string>
      <string>naverYOUR_NAVER_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

### 4-2) LSApplicationQueriesSchemes

카카오/네이버 인증 앱 호출 시 필요한 쿼리 스킴을 허용하도록 구성합니다.

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>kakaokompassauth</string>
  <string>kakaotalk</string>
  <string>naversearchapp</string>
  <string>naversearchthird</string>
  <string>ispmobile</string>
  <string>itms-apps</string>
</array>
```

### 4-3) 추가 설정
- Apple 로그인은 iOS 대상이므로 관련 키/Capability는 기존 구성 유지
- 빌드 스킴/번들 ID(`PRODUCT_BUNDLE_IDENTIFIER`)와 Kakao/Naver 앱 등록 값 일치 확인

---

## 5) Flutter 코드 초기화(필요 시)

패키지 버전에 따라 앱 시작 시 Kakao SDK 초기화가 필요한 경우가 있습니다.

- 초기화가 필요한 경우 예시:

```dart
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  kakao.KakaoSdk.init(
    nativeAppKey: const String.fromEnvironment('KAKAO_NATIVE_APP_KEY'),
  );

  runApp(const MyApp());
}
```

실행시 `flutter run --dart-define=KAKAO_NATIVE_APP_KEY=...`를 함께 전달하세요.

---

## 6) 실패 케이스 빠른 점검

로그에 출력되는 메시지 기준으로 확인하세요.

- `SOCIAL_AUTH_EXCHANGE_URL이 설정되지 않았습니다.`
  - `main()` 실행 전 `--dart-define` 미지정
- `FlutterNaverLogin.logIn()` 결과 상태가 `loggedIn`이 아님
  - 앱 키/리디렉트/네이티브 콜백 mismatch
- `Kakao 로그인 취소 또는 실패`/`✗ Kakao 로그인 실패`
  - 앱 키/스킴/키해시 불일치 또는 패키지키 mismatch
- 로그인이 바로 성공 메시지 없이 끝남
  - `null` 반환(취소/예외) 시 `_handleKakaoSignIn`/`_handleNaverSignIn`에서 스낵바가 표시되지 않음

> 원하면 아래 링크에 맞춰 코드 레벨 UX를 보완(실패 이유 토스트 표시)해도 됩니다.

---

## 7) 테스트 체크리스트

- [ ] Kakao 앱 설치 상태에서 Kakao 로그인 성공
- [ ] Kakao Talk 미설치 상태에서 계정 로그인(web fallback) 성공
- [ ] Naver 로그인 성공
- [ ] 동일 계정 재로그인/로그아웃 동작
- [ ] 로그아웃 시 Firebase 세션 + SNS 세션 정리(`AuthService.signOut`)
- [ ] `dart-define` 없는 상태에서 명시적 에러 안내 표시

---

## 8) 바로 적용 경로

1) 우선 백엔드 `/social/exchange` API를 띄워서 `SOCIAL_AUTH_EXCHANGE_URL`을 고정하고, Flutter에서 버튼을 다시 눌러 응답까지 확인
2) Android/iOS 네이티브 설정(Manifest/Info.plist)
3) 실제 디바이스에서 OAuth 인텐트/리디렉트가 동작하는지 확인


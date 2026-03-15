# 🔥 Firebase 설정 가이드 (3s Vlog App)

## 📋 목차
1. [Firebase Cloud Functions 배포](#-firebase-cloud-functions-설정-socialexchange)
2. [Firebase Storage 보안 규칙 배포](#firebase-storage-보안-규칙-배포)
3. [Firestore 보안 규칙 배포](#firestore-보안-규칙-배포)
4. [Firebase Console 설정](#firebase-console-설정)
5. [테스트](#테스트)

---

## ⚡ Firebase Cloud Functions 설정 (social/exchange)

`SOCIAL_AUTH_EXCHANGE_URL`은 Firebase Functions로 제공되며 현재 라우트는 아래와 같습니다.

- 함수명: `social`
- 경로: `/exchange`
- 최종 URL(프로젝트: `fir-3s-8edb9`):

```text
https://asia-northeast3-fir-3s-8edb9.cloudfunctions.net/social/exchange
```

### 1) Functions 초기화 (최초 1회)

```bash
cd c:\Users\Guiny\Documents\Python_Project\three_sec_vlog
firebase init functions
```

### 2) 의존성 설치

```bash
cd functions
npm install
```

### 3) 배포

```bash
# Functions 배포
firebase deploy --only functions

# 함수 1개만 배포
firebase deploy --only functions:social
```

### 4) 앱에서 사용할 URL 지정

```bash
flutter run --dart-define=SOCIAL_AUTH_EXCHANGE_URL=https://asia-northeast3-fir-3s-8edb9.cloudfunctions.net/social/exchange
```

### 5) API 응답 포맷(앱 호환)

요청 바디(기본/확장):

```json
{
  "provider": "kakao",
  "accessToken": "<oauth_access_token>",
  "idToken": "<optional_oidc_id_token>",
  "nonce": "<optional_nonce>",
  "providerAudience": "<optional_aud>",
  "clientId": "<optional_client_id>",
  "rawProviderUserId": "<optional_provider_user_id>",
  "appVersion": "1.0.0+12"
}
```

성공 응답(HTTP 200):

```json
{
  "success": true,
  "provider": "kakao",
  "uid": "kakao:123456",
  "firebaseToken": "eyJhbGciOi...",
  "timestamp": "2026-03-14T15:40:00.000Z"
}
```

실패 응답(HTTP 4xx/5xx):

```json
{
  "success": false,
  "error": {
    "code": "INVALID_SOCIAL_TOKEN",
    "message": "소셜 토큰 검증 실패",
    "details": {
      "provider": "kakao",
      "reason": "KAKAO_TOKEN_INVALID",
      "requestAttemptCount": 2,
      "fallbackAttempts": 1,
      "fallbackUsed": true,
      "status": 401,
      "requestId": "req-..."
    },
    "timestamp": "2026-03-14T15:40:00.000Z"
  }
}
```

에러 코드 운영 가이드(요약):

- `INVALID_PROVIDER`: 미지원 provider
- `MISSING_ACCESS_TOKEN`: accessToken 누락
- `INVALID_SOCIAL_TOKEN`: 소셜/OIDC 토큰 검증 실패
- `SOCIAL_USER_NOT_FOUND`: 토큰에서 사용자 식별 실패
- `EXTERNAL_TOKEN_VERIFY_FAILED`: 외부 토큰 검증 중 예외
- `FIREBASE_TOKEN_ERROR`: Firebase custom token 생성 실패

앱 파서는 `firebaseToken`을 기본으로 읽으며, 하위 호환으로 `customToken`, `token`도 지원합니다.

### 6) CORS 허용 오리진(운영 보안) 설정

- 기본 동작: `*`(모든 origin 허용)
- 제한하려면 Firebase Functions 런타임 설정으로 다음 2가지 방식을 사용할 수 있습니다.

```bash
# 방법 A: 환경변수
set SOCIAL_EXCHANGE_ALLOWED_ORIGINS=https://your-app.example.com,https://admin.your-app.example.com
```

```bash
# 방법 B: Firebase Functions 런타임 설정(권장)
firebase functions:config:set social_exchange.allowed_origins="https://your-app.example.com,https://admin.your-app.example.com"
```

## 🌩️ Firebase Storage 보안 규칙 배포

### 1. Firebase CLI 설치 (아직 설치하지 않은 경우)

```bash
npm install -g firebase-tools
```

### 2. Firebase 로그인

```bash
firebase login
```

### 3. Firebase 프로젝트 초기화 (처음 한 번만)

```bash
cd c:\Users\Guiny\Documents\Python_Project\three_sec_vlog
firebase init storage
```

**선택 사항:**
- Use an existing project → 3s-vlog-app 선택
- What file should be used for Storage Rules? → `firebase/storage.rules` 입력

### 4. Storage 규칙 배포

```bash
firebase deploy --only storage:rules
```

**확인:**
```
✔  Deploy complete!
```

---

## 🗄️ Firestore 보안 규칙 배포

### 1. Firestore 초기화 (처음 한 번만)

```bash
firebase init firestore
```

**선택 사항:**
- Use an existing project → 3s-vlog-app 선택
- What file should be used for Firestore Rules? → `firebase/firestore.rules` 입력
- What file should be used for Firestore indexes? → `firebase/firestore.indexes.json` (기본값)

### 2. Firestore 규칙 배포

```bash
firebase deploy --only firestore:rules
```

**확인:**
```
✔  Deploy complete!
```

---

## ⚙️ Firebase Console 설정

### 1. Firebase Storage 버킷 생성

1. [Firebase Console](https://console.firebase.google.com/) 접속
2. 프로젝트 선택 (3s-vlog-app)
3. **Storage** 메뉴 클릭
4. **시작하기** 클릭
5. 보안 규칙: **프로덕션 모드** 선택 (우리가 작성한 규칙 사용)
6. 위치: `asia-northeast3` (서울) 선택
7. **완료** 클릭

### 2. Firestore Database 생성

1. **Firestore Database** 메뉴 클릭
2. **데이터베이스 만들기** 클릭
3. 보안 규칙: **프로덕션 모드** 선택
4. 위치: `asia-northeast3` (서울) 선택
5. **사용 설정** 클릭

### 3. Firestore 인덱스 추가 (필수)

**videos 컬렉션 복합 인덱스:**

```
컬렉션: videos
필드 1: uid (Ascending)
필드 2: createdAt (Descending)
쿼리 범위: Collection
```

**생성 방법:**
1. Firestore Database → **인덱스** 탭
2. **복합 인덱스 추가** 클릭
3. 위 정보 입력
4. **만들기** 클릭

**또는 자동 생성:**
- 앱을 실행하고 영상 목록 조회 시도
- 콘솔 에러 메시지의 링크 클릭하여 자동 생성

---

## 🧪 테스트

### 1. 보안 규칙 시뮬레이터 (Firebase Console)

**Storage Rules Test:**
```javascript
// 인증된 사용자의 자신의 영상 업로드
service = firebase.storage();
path = /users/test-uid-123/videos/video-001/test.mp4;
method = create;
auth = { uid: 'test-uid-123' };
resource = { size: 10000000, contentType: 'video/mp4' };
// ✅ Allow
```

**Firestore Rules Test:**
```javascript
// 인증된 사용자의 자신의 영상 읽기
service = cloud.firestore;
path = /databases/(default)/documents/videos/video-001;
method = get;
auth = { uid: 'test-uid-123' };
resource = { data: { uid: 'test-uid-123' } };
// ✅ Allow
```

### 2. 앱에서 테스트

**업로드 테스트:**
```dart
final cloudService = CloudService();

// 영상 업로드
final videoId = await cloudService.uploadVideo(
  videoFile: File('/path/to/video.mp4'),
  albumName: 'Vlog',
  isFavorite: false,
);

print('업로드 ID: $videoId');
```

**진행률 모니터링:**
```dart
cloudService.uploadProgressStream.listen((progress) {
  print('진행률: ${progress.progressPercent}% (${progress.progressText})');
});
```

**영상 목록 조회:**
```dart
cloudService.getUserVideos().listen((videos) {
  print('영상 개수: ${videos.length}');
  for (var video in videos) {
    print('- ${video.fileName} (${video.fileSizeText})');
  }
});
```

---

## 📊 데이터 구조

### Firestore: `users/{userId}`

```json
{
  "uid": "firebase-uid-123",
  "subscriptionTier": "premium",
  "storageUsage": 5368709120,
  "lastUpdated": "2026-01-30T12:34:56.789Z"
}
```

### Firestore: `videos/{videoId}`

```json
{
  "uid": "firebase-uid-123",
  "videoId": "video-unique-id-001",
  "fileName": "vlog_20260130.mp4",
  "storagePath": "users/firebase-uid-123/videos/video-unique-id-001/vlog_20260130.mp4",
  "albumName": "Vlog",
  "isFavorite": true,
  "fileSize": 157286400,
  "uploadStatus": "completed",
  "uploadProgress": 100,
  "downloadUrl": "https://firebasestorage.googleapis.com/...",
  "createdAt": "2026-01-30T12:00:00.000Z",
  "updatedAt": "2026-01-30T12:05:00.000Z",
  "completedAt": "2026-01-30T12:05:00.000Z"
}
```

---

## 🛡️ 보안 체크리스트

- [x] Storage 규칙: uid 기반 접근 제어
- [x] Firestore 규칙: uid 기반 접근 제어
- [x] Standard 등급 이상만 업로드 가능
- [x] 용량 제한 검증 (Standard: 10GB, Premium: 50GB)
- [x] 파일 타입 검증 (video/mp4, video/quicktime 등)
- [x] 파일 크기 제한 (최대 500MB per file)
- [x] 필수 메타데이터 검증

---

## 🚀 배포 명령어 요약

```bash
# 전체 배포
firebase deploy

# Storage 규칙만
firebase deploy --only storage:rules

# Firestore 규칙만
firebase deploy --only firestore:rules

# 인덱스 배포
firebase deploy --only firestore:indexes

# Functions 배포
firebase deploy --only functions
```

---

## 📞 문의

보안 규칙 관련 문의: [Firebase Security Rules Documentation](https://firebase.google.com/docs/rules)

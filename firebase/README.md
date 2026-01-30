# 🔥 Firebase 설정 가이드 (3s Vlog App)

## 📋 목차
1. [Firebase Storage 보안 규칙 배포](#firebase-storage-보안-규칙-배포)
2. [Firestore 보안 규칙 배포](#firestore-보안-규칙-배포)
3. [Firebase Console 설정](#firebase-console-설정)
4. [테스트](#테스트)

---

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
```

---

## 📞 문의

보안 규칙 관련 문의: [Firebase Security Rules Documentation](https://firebase.google.com/docs/rules)

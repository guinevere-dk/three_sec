# Firestore 사용 규칙 및 동기화 계약서 v1

작성일: 2026-02-25  
대상 프로젝트: `fir-3s-8edb9`  
적용 범위: Library 클립 클라우드 저장 + 편집 프로젝트 클라우드 저장 + 재로그인 시 구조 복원

---

## 1) 목적

- 클라우드 저장소를 **사용자 단위(uid)** 로 일관되게 관리한다.
- `Library(앨범-파일)` 구조와 `편집 프로젝트`를 모두 클라우드에서 복원 가능하게 만든다.
- 로그아웃/재로그인 후에도 동일한 계정이면 동일한 구조가 재동기화되도록 계약을 정의한다.
- 구독 등급(Free/Standard/Premium)에 따른 허용 정책을 명시한다.

---

## 2) 현재 진단 요약 (확정)

- 기존 장애는 API 비활성보다 우선해서 **Firestore 기본 DB 미생성** 이 직접 원인이다.
- 근거 로그: `NOT_FOUND: The database (default) does not exist`.
- 현재 상태: Firestore DB 생성 완료(`Database ID=(default)` 확인).

---

## 3) 데이터 모델 (계약)

아래 문서는 필수 필드와 타입을 고정한다.

### 3.1 `users/{uid}`

```json
{
  "uid": "string",
  "subscriptionTier": "free|standard|premium",
  "storageUsage": 0,
  "storageLimit": 0,
  "productId": "string|null",
  "purchaseDate": "timestamp|null",
  "lastLoginAt": "timestamp",
  "updatedAt": "timestamp",
  "createdAt": "timestamp"
}
```

규칙:
- `uid == documentId`
- `storageUsage`는 바이트 단위
- `storageLimit`는 서버 계산값(Free=0, Standard=10GB, Premium=50GB)

### 3.2 `albums/{albumId}`

```json
{
  "uid": "string",
  "albumId": "string",
  "name": "string",
  "sortOrder": 0,
  "isSystem": false,
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

규칙:
- 사용자별 고유 이름 정책: `(uid, name)` 충돌 금지(앱 레벨/트랜잭션 레벨 보장)
- 시스템 앨범(`일상`, `휴지통`)은 `isSystem=true`

### 3.3 `videos/{videoId}`

```json
{
  "uid": "string",
  "videoId": "string",
  "albumId": "string",
  "albumName": "string",
  "fileName": "string",
  "storagePath": "string",
  "localPath": "string|null",
  "fileSize": 0,
  "isFavorite": false,
  "uploadStatus": "queued|uploading|completed|failed",
  "uploadProgress": 0,
  "downloadUrl": "string|null",
  "errorCode": "string|null",
  "errorMessage": "string|null",
  "errorCopy": "string|null",
  "errorPhase": "string|null",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "completedAt": "timestamp|null"
}
```

규칙:
- `uid`, `videoId` 불변
- `uploadStatus=completed`일 때만 `downloadUrl` 사용 가능
- `albumId` 기준으로 Library 구조 복원

### 3.4 `projects/{projectId}` (편집 프로젝트)

```json
{
  "uid": "string",
  "projectId": "string",
  "title": "string",
  "folderName": "string",
  "lockState": "unlocked|locked",
  "bgmPath": "string|null",
  "bgmVolume": 0.5,
  "quality": "720p|1080p|4k",
  "clips": [
    {
      "id": "string",
      "videoId": "string|null",
      "path": "string",
      "startTimeMs": 0,
      "endTimeMs": 0,
      "originalDurationMs": 0,
      "volume": 1.0
    }
  ],
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

규칙:
- 프로젝트는 사용자 소유(`uid`) 고정
- `clips[].videoId`를 통해 클라우드 clip 메타와 연결 가능하게 유지

---

## 4) 인덱스 정책

필수 인덱스:
- `videos`: `(uid ASC, createdAt DESC)`
- `videos`: `(uid ASC, albumId ASC, createdAt DESC)`
- `projects`: `(uid ASC, updatedAt DESC)`
- `albums`: `(uid ASC, sortOrder ASC)`

---

## 5) 구독 연동 정책 (Standard/Premium)

연동 트리거:
- IAP 성공 후 `AuthService.syncSubscriptionToFirestore()` 호출 시점에 `users/{uid}` upsert

반영 필드:
- `subscriptionTier`, `productId`, `purchaseDate`, `storageLimit`, `updatedAt`

등급 정책:
- Free: 업로드 불가
- Standard: 10GB
- Premium: 50GB

정합성 원칙:
- 앱 로컬 등급(`UserStatusManager`)과 Firestore `subscriptionTier` 불일치 시 **서버값 우선**

---

## 6) 보안 규칙 정책

Firestore:
- 모든 문서는 `request.auth.uid == resource.data.uid` 또는 생성시 `request.resource.data.uid`
- `uid`, `videoId`, `projectId`는 생성 후 변경 불가

Storage:
- 경로: `users/{uid}/videos/{videoId}/{fileName}`
- 읽기/쓰기/삭제 모두 `request.auth.uid == uid`
- 쓰기 시 `isStandardOrAbove`, `isValidVideoFile`, `!exceededStorageLimit`

---

## 7) 동기화 계약 (로그아웃/재로그인 복원)

### 7.1 로그아웃
- 로컬 캐시는 유지 가능하나, 계정 식별 필드는 분리 저장
- 타 계정 로그인 시 이전 계정 캐시를 직접 노출하지 않음

### 7.2 재로그인
- `uid` 기준으로 `albums -> videos -> projects` 순으로 pull
- `albumId`/`videoId` 참조를 기준으로 구조 재구성
- 로컬에 없는 영상은 `downloadUrl` 기반 지연 다운로드 또는 placeholder 처리

### 7.3 충돌 규칙
- 메타데이터: `updatedAt` 최신 우선
- 파일 실체 누락 시 `uploadStatus`와 `errorCode`로 상태 표기

---

## 8) 운영 실행 체크리스트

1. Firestore `(default)` DB 생성 확인 (완료)
2. 규칙 배포: `firestore.rules`, `storage.rules`
3. 인덱스 배포
4. 테스트 계정으로 `users/{uid}` 시드/업데이트 확인
5. Library 업로드/앨범 이동/삭제 시 메타 반영 확인
6. 편집 프로젝트 저장/불러오기 클라우드 반영 확인
7. 로그아웃 후 동일 계정 재로그인 구조 복원 확인

---

## 9) 검증 시나리오 (요약)

- Free 계정: 업로드 차단, 안내문 노출
- Standard 계정: 업로드 성공, 10GB 초과 시 실패
- Premium 계정: 업로드 성공, 50GB 초과 시 실패
- DB/권한 오류: `errorCode` 저장 + 사용자 안내문 노출
- 재로그인: 앨범-파일-프로젝트 구조 유지

---

## 10) 변경 관리 원칙

- 스키마 변경 시 `v2` 문서로 새 계약서 발행
- 필수 필드 삭제 금지(하위호환 유지)
- 장애 분석은 항상 `full/errors/appsignals` 3종 로그로 교차 검증


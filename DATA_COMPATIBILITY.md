# DATA_COMPATIBILITY.md

## 1. 목적

이 문서는 MOA 앱의 변경 금지 key, 식별자, 경로, 데이터 계약을 정리합니다. 브랜드 전환이나 구조 개선 중에도 기존 사용자 데이터와 앱 동작을 보호하는 것이 목적입니다.

## 2. 변경 금지 식별자

아래 값은 별도 승인, dry-run, 백업, 롤백 계획 없이 변경하지 않습니다.

| 영역 | 값 |
|---|---|
| Flutter package name | `three_s` |
| Android namespace | `com.dk.three_sec` |
| Android applicationId | `com.dk.three_sec` |
| Firebase project alias | `fir-3s-8edb9` |
| MethodChannel | `com.dk.three_sec/video_engine` |
| Functions service account | `fir-3s-8edb9@appspot.gserviceaccount.com` |
| IAP product ids | `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual` |

## 3. Firestore 계약

유지해야 하는 컬렉션과 필드입니다.

- `users/{uid}`: `subscriptionTier`, `storageUsage`, `lastUpdated` 등 사용자 상태.
- `users/{uid}/usageEvents/{eventId}`: usage accounting 멱등 이벤트.
- `videos/{videoId}`: `uid`, `videoId`, `fileName`, `storagePath`, `localPath`, `albumName`, `isFavorite`, `fileSize`, `uploadStatus`, `uploadProgress`, `downloadUrl`, `createdAt`, `updatedAt`, `completedAt`, `errorCode`, `errorCopy`.
- `vlog_projects/{projectId}`: `uid`, `localProjectId`, `title`, `clipPaths`, `clipCount`, `folderName`, `lockState`, `clientCreatedAt`, `clientUpdatedAt`, `lastSyncedAt`, `deleted`.

규칙:

- `uid`, `videoId`, `localProjectId`, `cloudProjectId` 연결 계약을 임의 변경하지 않습니다.
- 컬렉션명 `videos`, `users`, `vlog_projects`를 변경하지 않습니다.
- 필드 rename은 dual-read/write, backfill, old client 호환성 검증 없이는 금지합니다.
- 보안 규칙의 uid 소유권 조건을 완화하지 않습니다.

## 4. Storage 계약

- 사용자 영상: `users/{uid}/videos/{videoId}/{fileName}`.
- 프로필 이미지: `users/{uid}/profile/{fileName}`.
- 영상 파일 제한: 최대 500MB, `video/mp4`, `video/quicktime`, `video/x-msvideo`, `video/mpeg`.
- 프로필 이미지 제한: 최대 10MB, `image/jpeg`, `image/png`, `image/webp`.

규칙:

- Storage prefix를 브랜드 변경 목적으로 변경하지 않습니다.
- Firestore `storagePath`와 Storage 객체 경로 정합성을 유지합니다.
- 삭제는 소유권 확인과 사용량 차감 멱등성을 함께 검토합니다.

## 5. 로컬 파일 구조

앱 문서 디렉터리 하위 주요 경로입니다.

- `vlogs/raw_clips/{album}`: 촬영/저장된 raw clip album.
- `vlogs/vlog_projects`: Vlog 결과 파일 또는 project base 계열.
- `vlogs/vlog_folders/{folderName}`: Vlog 폴더 구조.
- `vlog_projects/{projectId}.json`: 프로젝트 JSON 저장 계열.
- `Vlogs/vlog_{timestamp}.mp4`: export 결과 계열.
- `thumbnails`, `thumbnails/timeline`: 썸네일 캐시.
- `recorded_clip_staging`: 녹화 클립 저장 queue staging.

규칙:

- 경로 rename은 기존 파일 탐색 실패와 데이터 유실 위험이 있어 보류합니다.
- 새 경로가 필요하면 old path read, new path write, migration dry-run, rollback을 설계합니다.
- 임시 파일 삭제 로직이 원본을 지우지 않는지 source/destination을 명확히 검증합니다.

## 6. SharedPreferences key

변경 금지 또는 승인 필요 key입니다.

- `3s_user_tier`
- `3s_purchase_date`
- `3s_product_id`
- `3s_user_id`
- `3s_next_user_tier`
- `3s_next_tier_effective_at`
- `3s_guest_login_enabled`
- `cloud_synced_paths`
- `clip_duration_metadata_v1`
- `clip_ownership_metadata_v1`
- `recorded_clip_save_jobs_v1`
- `local_index_entries_v1`
- `tutorial_completed_user_{uid}`
- `isFirstRun`

추가로 notification category, sync queue, capture aspect/quality preference key는 관련 서비스 파일에서 확인 후 변경해야 합니다.

## 7. 마이그레이션 승인 조건

데이터 key, 경로, schema migration은 다음 조건을 모두 만족해야 합니다.

1. 변경 대상 inventory와 영향도 분류 완료.
2. 기존 앱 버전과 신규 앱 버전의 read/write 계약 문서화.
3. dual-read/write 또는 fallback 설계.
4. 샘플 데이터 dry-run.
5. 사용자 데이터 백업 또는 export 전략.
6. 실패 시 rollback 방법.
7. 앱 재시작, 로그아웃/로그인, 오프라인/온라인 전환 검증.
8. 명시 승인.

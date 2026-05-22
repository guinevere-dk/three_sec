# MOA Standard Cloud Cost Control Implementation Prompt

## 0. 목적

MOA 앱의 Standard 구독 정책을 다음 가격 구조로 확정한다.

- Standard 월 구독: 6,900원
- Standard 연 구독: 69,000원
- 출시 첫해 프로모션 연 구독: 59,000원
- Standard 제공 Cloud 용량: 50GB
- Standard 제공 기능:
  - Cloud 백업
  - 프로젝트 저장
  - 1080p 내보내기
  - 편집 기능
  - 기기 변경 시 복원
  - 최근 앨범 자동 캐시

이번 작업의 핵심 목적은 “사용자에게는 50GB Cloud 백업을 제공하되, Cloud Storage 다운로드/재생 트래픽으로 인한 비용 폭증을 방지하는 강한 제어 정책”을 앱과 백엔드 양쪽에 구현하는 것이다.

중요한 전제:

- Cloud는 무제한 스트리밍 공간이 아니다.
- Cloud는 백업/복원 중심이다.
- 반복 재생은 Local Cache 중심이어야 한다.
- 원본 무제한 저장은 금지한다.
- MOA 표준 압축본을 저장한다.
- 사용자별 저장량, 다운로드량, 복원량, 캐시 정책을 반드시 제어한다.

---

## 1. 구현 철학

MOA의 저장 구조는 다음 원칙을 따른다.

```text
Cloud = 백업 창고
Local = 재생 캐시
Export = 필요 시 고화질 생성/다운로드
````

절대 피해야 할 구조:

```text
앨범 열기 → 모든 영상을 Cloud URL로 직접 재생 → 매번 다운로드 발생
```

목표 구조:

```text
앨범 열기 → 로컬 썸네일/프리뷰 우선 표시
재생 요청 → 로컬 캐시 확인
캐시 있음 → 로컬 재생
캐시 없음 → Cloud에서 1회 다운로드 후 로컬 캐시 저장
반복 재생 → 로컬 캐시 사용
```

---

## 2. 반드시 구현해야 하는 정책

### 2.1 사용자별 Cloud 용량 제한

Standard 사용자는 최대 50GB까지만 Cloud를 사용할 수 있다.

구현 요구사항:

* 사용자별 `cloud_used_bytes`를 추적한다.
* 업로드 전 예상 파일 크기를 확인한다.
* 업로드 후 실제 저장 크기를 반영한다.
* 50GB 초과 시 업로드를 차단한다.
* 앱 UI에 현재 사용량을 표시한다.

예시 UI:

```text
Cloud 사용량
18.4GB / 50GB
```

초과 시 문구:

```text
Cloud 저장공간이 부족합니다.
사용하지 않는 앨범을 삭제하거나 Premium으로 업그레이드해 주세요.
```

주의:

* 클라이언트 값만 믿으면 안 된다.
* 서버 또는 Firebase Rules/Cloud Functions에서 반드시 최종 검증해야 한다.
* 클라이언트 조작으로 50GB 초과 업로드가 가능하면 안 된다.

---

### 2.2 원본 영상 저장 금지

Standard Cloud에는 원본 영상을 그대로 저장하지 않는다.

저장 대상은 반드시 MOA 표준 포맷이어야 한다.

표준 포맷 예시:

```text
duration: 2 seconds 중심
fps: 30fps
resolution: 최대 1080p
codec: H.264 우선
bitrate: 앱 정책상 제한
audio: 필요 시 압축
```

구현 요구사항:

* 외부에서 가져온 영상은 업로드 전 표준 포맷으로 변환한다.
* 너무 큰 원본 파일은 Cloud에 직접 업로드하지 않는다.
* 업로드 전 파일 크기, 해상도, fps, duration을 검사한다.
* 정책 위반 파일은 업로드 차단 또는 표준 변환 후 업로드한다.
* Standard 표준 영상의 단일 객체 상한은 Storage Rules의 500MB보다 훨씬 낮게 둔다.
* 권장 Standard 단일 객체 상한은 50MB 이하이다.

주의:

* Storage Rules의 500MB 제한은 레거시/전역 최후 안전장치일 뿐 Standard 업로드 정책 상한이 아니다.
* Quota boundary 테스트와 실제 Standard 영상 객체 상한 테스트를 섞지 않는다.

예외:

* Free 사용자는 Cloud 저장 불가 또는 매우 제한.
* Premium에서만 원본 보관 기능을 검토할 수 있다.
* 이번 Standard 구현에는 원본 저장 기능을 넣지 않는다.

---

### 2.3 Cloud 직접 재생 금지 원칙

Cloud URL을 직접 비디오 플레이어에 넣어 반복 재생하는 구조를 금지한다.

구현 요구사항:

* 재생 전 항상 Local Cache를 먼저 확인한다.
* Local Cache에 없을 때만 Cloud에서 다운로드한다.
* 다운로드한 파일은 Local Cache에 저장한다.
* 다음 재생부터는 Local Cache를 사용한다.
* Cloud URL 기반 스트리밍은 예외 상황에서만 허용한다.

재생 흐름:

```text
playClip(clipId)
  1. localCache.exists(clipId) 확인
  2. 있으면 local file path로 재생
  3. 없으면 cloud에서 다운로드
  4. 다운로드 파일을 local cache에 저장
  5. local file path로 재생
```

금지:

```text
VideoPlayer.network(cloudDownloadUrl)
```

허용:

```text
VideoPlayer.file(localCachedFile)
```

단, Flutter 구조에 맞게 실제 API는 프로젝트 코드 기준으로 조정한다.

---

### 2.4 Local Cache 정책

Local Cache는 비용 통제의 핵심이다.

구현 요구사항:

* 썸네일은 가능한 한 로컬에 저장한다.
* 최근 재생한 클립은 로컬 캐시에 저장한다.
* 최근 사용 앨범은 자동 캐시한다.
* 캐시 용량 상한을 둔다.
* 디바이스 저장공간 부족 시 오래된 캐시부터 삭제한다.

권장 기본값:

```text
thumbnail_cache: 제한적 영구 캐시
preview_cache: 최근 300~500개 클립
video_cache_max_size: 기본 2GB 또는 사용자 설정 가능
cache_eviction_policy: LRU
```

캐시 삭제 우선순위:

1. 오래 재생하지 않은 영상 캐시
2. Cloud에 백업된 영상 캐시
3. 저화질 프리뷰 캐시
4. 썸네일 캐시
5. 아직 Cloud 백업되지 않은 로컬 원본은 절대 자동 삭제 금지

주의:

* Cloud 백업 완료 여부가 확인되지 않은 파일은 삭제하면 안 된다.
* 캐시 삭제와 사용자 원본 삭제를 혼동하면 안 된다.
* “캐시 삭제”는 안전하지만 “프로젝트 데이터 삭제”는 위험하다.

---

### 2.5 다운로드/복원 트래픽 제한

Standard 사용자의 다운로드 트래픽을 완전히 무제한으로 열지 않는다.

구현 요구사항:

* 사용자별 월간 다운로드량을 추적한다.
* 대량 복원 요청 시 제한을 둔다.
* 전체 앨범 일괄 다운로드는 경고 또는 제한한다.
* 반복적인 재다운로드가 발생하지 않도록 캐시를 우선한다.
* `users/{uid}/usageEvents/{eventId}`를 다운로드/업로드 사용량의 원장으로 둔다.
* `users/{uid}.monthlyDownloadBytes`는 빠른 UI/리포팅용 denormalized summary로만 사용한다.
* 값이 불일치하면 `usageEvents`가 우선하며 summary는 원장에서 재계산/보정한다.

권장 정책:

```text
monthly_download_soft_limit: 50GB
monthly_download_hard_limit: 100GB
bulk_restore_daily_limit: 예: 10GB/day
```

Soft limit 도달 시:

```text
이번 달 Cloud 다운로드 사용량이 많습니다.
반복 재생은 로컬 캐시를 우선 사용합니다.
```

Hard limit 도달 시:

```text
이번 달 Cloud 다운로드 한도를 초과했습니다.
다음 달에 다시 이용하거나 Premium으로 업그레이드해 주세요.
```

단, 사용자가 명시적으로 백업한 중요한 개인 데이터를 완전히 막아서는 안 된다.
Hard limit 정책은 법적/UX 리스크가 있으므로, 실제 적용 전 약관/고지 문구와 함께 구현한다.

---

### 2.6 업로드 정책

업로드는 반드시 아래 순서를 따른다.

```text
1. 구독 상태 확인
2. Cloud 용량 확인
3. 파일 정책 검사
4. 표준 포맷 변환
5. 예상 업로드 크기 계산
6. 서버 측 용량 예약 또는 검증
7. 업로드
8. 업로드 성공 후 metadata 반영
9. 실패 시 rollback
```

업로드 중간 실패 시:

* `cloud_used_bytes`가 잘못 증가하면 안 된다.
* 업로드 실패 파일은 orphan file로 남지 않아야 한다.
* orphan file 정리 작업이 필요하다.

---

### 2.7 삭제 정책

사용자가 Cloud 영상을 삭제하면 다음 처리가 필요하다.

```text
1. Cloud 파일 삭제
2. metadata 삭제 또는 상태 변경
3. cloud_used_bytes 차감
4. local cache는 선택적으로 삭제
5. 프로젝트 참조 무결성 확인
```

주의:

* 파일만 삭제하고 metadata가 남으면 안 된다.
* metadata만 삭제하고 Cloud 파일이 남으면 비용 누수가 생긴다.
* 삭제 실패 시 재시도 큐를 둔다.

---

### 2.8 구독 해지 후 정책

Standard 구독 해지 시 정책:

```text
- 신규 Cloud 업로드 차단
- 기존 Cloud 데이터는 일정 기간 유지
- 사용자는 다운로드/복원 가능 기간을 안내받음
- 장기 미결제 시 삭제 가능성을 명확히 고지
```

권장 상태:

```text
active_standard
expired_grace_period
read_only_cloud
scheduled_for_cleanup
deleted
```

예시 정책:

```text
구독 만료 후 30일: 신규 업로드 차단, 기존 데이터 접근 가능
30일 이후: 읽기 전용 또는 제한 접근
90일 이후: 데이터 삭제 대상 가능
```

실제 삭제 정책은 약관/스토어 정책/개인정보 처리방침과 반드시 맞춰야 한다.

---

## 3. 데이터 모델 제안

기존 구조를 확인한 뒤, 필요한 경우 additive migration으로 추가한다.

### 3.1 user_cloud_usage

```sql
user_cloud_usage
- user_id
- plan_type
- cloud_limit_bytes
- cloud_used_bytes
- monthly_download_bytes
- monthly_upload_bytes
- billing_period_start
- billing_period_end
- last_recalculated_at
- created_at
- updated_at
```

### 3.2 cloud_assets

```sql
cloud_assets
- id
- user_id
- project_id
- album_id
- clip_id
- storage_path
- file_size_bytes
- duration_ms
- width
- height
- fps
- codec
- bitrate
- asset_type
  - standard_video
  - thumbnail
  - preview
- backup_status
  - pending
  - uploaded
  - failed
  - deleting
  - deleted
- checksum
- created_at
- updated_at
```

### 3.3 cloud_transfer_events

```sql
cloud_transfer_events
- id
- user_id
- asset_id
- transfer_type
  - upload
  - download
  - restore
  - delete
- bytes
- source
  - app_playback
  - export
  - restore
  - background_sync
- created_at
```

이 테이블은 비용 분석에 중요하다.
나중에 “사용자당 평균 Cloud 원가”를 추정하려면 반드시 이벤트 로그가 필요하다.

---

## 4. 백엔드/서버 측 검증

클라이언트만으로 제어하면 안 된다.

필수 서버 검증:

```text
- 사용자의 구독 상태
- Cloud 용량 한도
- 업로드 파일 크기
- 월간 다운로드량
- asset ownership
- storage path ownership
```

Storage path는 반드시 사용자별 prefix를 둔다.

예:

```text
users/{userId}/cloud_assets/{assetId}/standard.mp4
users/{userId}/cloud_assets/{assetId}/thumbnail.jpg
```

금지:

```text
public/{filename}
shared/{randomName}
```

사용자는 자신의 경로 외에는 읽기/쓰기 불가해야 한다.

---

## 5. Firebase Storage Rules / Security Rules 방향

정확한 문법은 현재 프로젝트 설정에 맞게 작성하되, 원칙은 다음과 같다.

```text
- authenticated user only
- user can access only own path
- file size limit
- content type limit
- no arbitrary path write
- no overwrite without permission
```

예시 원칙:

```text
allow read, write: if request.auth != null
  && request.auth.uid == userId
  && request.resource.size < maxAllowedSize
  && request.resource.contentType.matches('video/.*|image/.*');
```

주의:

* Storage Rules만으로 전체 사용량 합산 제한은 어렵다.
* 용량 제한은 Cloud Functions 또는 서버 API에서 처리해야 한다.
* 클라이언트 직접 업로드를 허용하더라도, 업로드 전후 검증이 필요하다.

---

## 6. 앱 UI/UX 요구사항

### 6.1 가격 표시

Standard 가격:

```text
Standard
월 6,900원
연 69,000원
출시 기념 첫해 59,000원
```

문구 방향:

```text
50GB Cloud 백업
소중한 2초 순간을 안전하게 저장하고,
폰을 바꿔도 다시 이어서 볼 수 있어요.
```

피해야 할 문구:

```text
무제한 스트리밍
원본 영상 무제한 보관
언제든 Cloud에서 바로 재생
```

---

### 6.2 Cloud 사용량 화면

필수 표시:

```text
Cloud 사용량
18.4GB / 50GB

이번 달 다운로드 사용량
6.2GB
```

사용자에게 너무 기술적으로 보이지 않게 한다.

좋은 표현:

```text
Cloud 백업 공간
```

나쁜 표현:

```text
Storage egress quota
```

---

### 6.3 캐시 관리 화면

설정 화면에 아래 항목을 추가한다.

```text
재생 캐시
- 현재 캐시 사용량
- 캐시 비우기
- Wi-Fi에서만 고화질 복원
- 최근 앨범 자동 캐시 on/off
```

주의:

* “캐시 비우기”는 Cloud 백업 데이터를 삭제하지 않는다고 명확히 안내한다.
* 사용자가 불안해하지 않게 해야 한다.

예시 문구:

```text
캐시를 비워도 Cloud에 백업된 영상은 삭제되지 않습니다.
다시 재생할 때 필요한 영상만 다시 불러옵니다.
```

---

## 7. 재생 로직 상세

재생 시 반드시 다음 순서를 구현한다.

```pseudo
Future<File> getPlayableClip(clipId) async {
  final cached = await localCache.find(clipId);

  if (cached.exists && cached.isValid) {
    return cached.file;
  }

  final asset = await cloudAssetRepository.getAsset(clipId);

  await cloudQuotaService.assertDownloadAllowed(asset.fileSizeBytes);

  final downloadedFile = await cloudStorage.downloadToCache(asset.storagePath);

  await localCache.save(
    clipId: clipId,
    file: downloadedFile,
    sizeBytes: asset.fileSizeBytes,
  );

  await cloudUsageRepository.recordDownload(
    assetId: asset.id,
    bytes: asset.fileSizeBytes,
    source: 'app_playback',
  );

  return downloadedFile;
}
```

금지:

```pseudo
return cloudStorage.getDownloadUrl(asset.storagePath)
```

단, 썸네일/프리뷰 등 작은 파일은 상황에 따라 네트워크 URL 사용 가능하나, 반복 표시되는 썸네일은 로컬 캐시한다.

---

## 8. Export 정책

1080p 내보내기는 Standard에 포함한다.

하지만 Export 과정에서 Cloud 원본을 매번 반복 다운로드하면 안 된다.

Export 흐름:

```text
1. 필요한 클립 목록 확인
2. 로컬 캐시 확인
3. 없는 클립만 Cloud에서 다운로드
4. 다운로드한 클립은 캐시에 저장
5. Export 실행
6. Export 결과물은 사용자가 선택할 때만 Cloud 업로드
```

주의:

* Export 결과물을 자동으로 Cloud에 계속 저장하면 비용 증가.
* Export 파일은 별도 asset으로 관리해야 한다.
* 동일 Export를 반복 생성하는 경우 캐시 정책을 검토한다.

---

## 9. 비용 모니터링 지표

출시 후 반드시 다음 지표를 볼 수 있어야 한다.

### 사용자 단위

```text
- 사용자별 cloud_used_bytes
- 사용자별 monthly_download_bytes
- 사용자별 monthly_upload_bytes
- 사용자별 cache_hit_rate
- 사용자별 cloud_playback_count
- 사용자별 local_playback_count
```

### 전체 서비스 단위

```text
- Standard 사용자 평균 Cloud 사용량
- Standard 사용자 평균 월 다운로드량
- 상위 1% 사용자의 Cloud 사용량
- 상위 1% 사용자의 다운로드량
- Cloud 비용 추정치
- 평균 사용자당 Cloud 원가
- 월 구독 실수령 대비 Cloud 원가 비율
```

중요 목표:

```text
평균 Cloud 원가: 1,500원 이하
주의 구간: 2,000원 이상
위험 구간: 2,500원 이상
```

---

## 10. 관리자/운영 리포트

간단한 관리자 리포트 또는 로그 출력 기능을 만든다.

필수 항목:

```text
Daily Cloud Cost Control Report

- total_standard_users
- total_cloud_used_gb
- avg_cloud_used_gb_per_user
- total_download_gb_this_month
- avg_download_gb_per_user
- top_10_storage_users
- top_10_download_users
- estimated_storage_cost
- estimated_download_cost
- estimated_cost_per_standard_user
- risk_level
```

Risk Level 기준:

```text
GREEN:
  avg estimated cloud cost <= 1,500 KRW/user/month

YELLOW:
  1,500 < avg estimated cloud cost <= 2,500

RED:
  avg estimated cloud cost > 2,500
```

---

## 11. 테스트 요구사항

반드시 테스트를 작성한다.

### 11.1 용량 제한 테스트

```text
- quota boundary synthetic test: 49GB used + 500MB reserved upload 가능
- quota boundary synthetic test: 49.8GB used + 500MB reserved upload 차단
- real Standard object test: Standard normalized video가 정책상 단일 객체 상한(권장 50MB 이하)을 넘으면 차단
- 50GB 초과 업로드는 서버에서 차단
- 클라이언트 조작으로도 초과 업로드 불가
```

### 11.2 캐시 재생 테스트

```text
- 첫 재생 시 Cloud 다운로드 발생
- 두 번째 재생 시 Cloud 다운로드 발생하지 않음
- 캐시 삭제 후 재생 시 다시 다운로드 발생
- 다운로드 이벤트가 정확히 기록됨
```

### 11.3 삭제 테스트

```text
- Cloud asset 삭제 시 cloud_used_bytes 차감
- metadata 삭제 후 orphan file이 남지 않음
- Cloud 파일 삭제 실패 시 retry 상태로 남음
```

### 11.4 구독 해지 테스트

```text
- active_standard 사용자는 업로드 가능
- expired 사용자는 신규 업로드 불가
- grace period 사용자는 기존 데이터 접근 가능
- cleanup 대상 사용자는 정책에 따라 제한
```

### 11.5 Export 테스트

```text
- 로컬 캐시가 있으면 Cloud 다운로드 없이 Export
- 캐시가 없는 클립만 다운로드
- 동일 Export 반복 시 다운로드 중복 최소화
```

---

## 12. 구현 우선순위

### P0 - 반드시 출시 전

```text
1. Standard 가격 반영
2. 사용자별 50GB Cloud 사용량 제한
3. 원본 업로드 금지 / 표준 압축본 업로드
4. 재생 시 Local Cache 우선
5. Cloud 직접 반복 재생 금지
6. 업로드/다운로드 이벤트 기록
7. 구독 해지 후 신규 업로드 차단
```

### P1 - 출시 직후라도 빠르게 필요

```text
1. 월간 다운로드량 추적
2. Soft limit / Hard limit 정책
3. 관리자 비용 리포트
4. orphan file 정리 job
5. 캐시 관리 UI
```

### P2 - 이후 고도화

```text
1. Premium 플랜 분리
2. 150GB~200GB Cloud
3. 원본 보관 옵션
4. 고급 복원 옵션
5. 대량 다운로드 유료화 또는 Premium화
```

---

## 13. 완료 기준

### 13.1 P0-Dev Complete

로컬/에뮬레이터 구현 완료 기준이다. Production 배포 승인은 포함하지 않는다.

```text
- Standard 가격이 월 6,900원 / 연 69,000원 / 첫해 프로모션 59,000원으로 반영됨
- Standard 사용자의 Cloud 한도가 50GB로 제한됨
- Standard normalized video의 단일 객체 상한이 Storage Rules 500MB보다 낮은 정책값으로 차단됨
- 50GB 초과 업로드가 클라이언트와 서버 양쪽에서 차단됨
- Cloud 영상 반복 재생 시 매번 다운로드되지 않음
- Local Cache 우선 재생 구조가 구현됨
- 업로드/다운로드/삭제 이벤트가 usageEvents 원장에 기록됨
- monthlyDownloadBytes는 summary로만 사용됨
- Cloud 사용량이 앱에서 표시됨
- 구독 해지 후 신규 업로드가 차단됨
- 기본 테스트가 통과함
- Cloud 비용 모니터링을 위한 최소 데이터가 수집됨
- Production Firebase deploy는 수행하지 않음
```

### 13.2 P0-Release Ready

출시 준비 완료 기준이다.

```text
- Firebase Functions deploy 승인 완료
- Firestore/Storage Rules 변경 시 deploy 승인 완료
- internal track QA 통과
- usage divergence dry-run 검토 완료
- rollback plan 준비 완료
- 실제 Store product details와 가격 문구 일치 확인
```

---

## 14. 개발 시 주의사항

* 기존 프로젝트/앨범/클립 구조를 깨지 말 것.
* 기존 Free/Standard/Premium 정책이 있다면 additive 방식으로 수정할 것.
* DB migration은 되돌릴 수 있게 작성할 것.
* 사용자 파일 삭제 로직은 특히 조심할 것.
* 캐시 삭제와 Cloud 삭제를 명확히 분리할 것.
* Cloud 사용량 계산은 신뢰 가능한 서버 기준으로 처리할 것.
* 업로드 실패/삭제 실패/orphan file에 대한 복구 경로를 둘 것.
* 비용 통제 로직은 UI 숨김이 아니라 실제 백엔드 검증이어야 한다.

---

## 15. AI 작업 방식 지시

작업 전 먼저 현재 코드베이스에서 다음 파일/구조를 조사하라.

```text
- 구독/권한 정책 관리 파일
- Cloud Storage 업로드/다운로드 서비스
- 프로젝트 저장 로직
- 비디오 재생 로직
- Export 로직
- 로컬 캐시 관련 코드
- Firebase/Supabase/백엔드 rules 또는 functions
- 앱 설정 화면
- 가격/결제 화면
```

그다음 아래 순서로 작업하라.

```text
1. 현재 구조 분석 보고
2. 변경 대상 파일 목록 작성
3. 데이터 모델/migration 제안
4. P0 구현
5. 테스트 작성
6. 비용 통제 체크리스트 작성
7. 최종 검증 보고서 작성
```

각 단계마다 결과를 다음 형식으로 보고하라.

```text
## 작업 결과

### 변경 파일
- path/to/file.dart
- path/to/file.ts
- path/to/migration.sql

### 구현 내용
- 내용 요약

### 테스트 결과
- PASS / FAIL / BLOCKED

### 남은 리스크
- 리스크 설명

### 다음 단계
- 다음 작업
```

---

## 16. 최종 원칙

MOA Standard의 핵심 상품은 “무제한 영상 스트리밍”이 아니다.

핵심 상품은 다음이다.

```text
소중한 2초 순간을 안전하게 백업하고,
폰을 바꿔도 다시 복원하며,
자주 보는 추억은 빠르게 로컬에서 재생하는 경험
```

따라서 모든 구현은 다음 원칙을 따라야 한다.

```text
Cloud 비용은 통제한다.
Local Cache로 반복 재생 비용을 줄인다.
Standard 50GB는 백업 용량이지 무제한 스트리밍 권한이 아니다.
```

````

덧붙이면, 이 지시서에서 제일 중요한 줄은 이겁니다.

```text
Cloud URL 기반 직접 반복 재생 금지. 재생은 Local Cache 우선.
````

이거 안 지키면 6,900원으로 올려도 원가가 터질 수 있습니다. 반대로 이 구조만 제대로 잡으면 **6,900원 / 69,000원 / 첫해 59,000원**은 꽤 안정적인 가격입니다.

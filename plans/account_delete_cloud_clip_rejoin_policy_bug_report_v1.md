# Account Delete Cloud Clip Rejoin Policy/Bug Report v1

## 1. 재현 시나리오

사용자가 보고한 흐름:

1. Standard 상태에서 Library Clip을 Cloud/DB에 업로드한다.
2. 구독을 해지한다.
3. 계정을 삭제한다.
4. 계정 삭제 과정에서 DB 데이터가 모두 삭제된 것으로 확인한다.
5. 동일 계정으로 다시 가입한다.
6. Library에 DB Clip이 남아 보인다.
7. 기기로 복원하려고 했으나 Free 상태라 다운로드 버튼이 표시되지 않는다.

본 문서는 구현 변경 없이 현재 정책과 코드 기준으로 버그와 정책 확인 항목을 분리한다.

## 2. 현재 정책 기준

### 2.1 계정 삭제 정책

계정 삭제는 Cloud 데이터 삭제 후 Firebase Auth 계정 삭제, 로컬 세션/데이터 정리를 수행하는 흐름이다.

근거:

- `lib/screens/profile_screen.dart`
  - `deleteAccount()` 호출 시 `purgeCloud: _cloudService.purgeCurrentUserCloudData()`를 전달한다.
  - `localDataPolicy: 'delete'`로 로컬 데이터 삭제 정책을 전달한다.
- `lib/services/auth_service.dart`
  - 계정 삭제는 `purgeCloud()` 성공 후 `deletingUser.delete()`를 호출한다.
  - 이후 `_resetLocalStateAfterSessionEnd(previousUid: uid, localDataPolicy: 'delete')`를 호출한다.
- `lib/services/cloud_service.dart`
  - `purgeCurrentUserCloudData()`는 현재 uid의 `videos`, `vlog_projects`, `users/{uid}` 문서를 삭제한다.
  - completed/downloadUrl이 있는 `videos`의 Storage object 삭제도 시도한다.

정책 판단:

- 계정 삭제가 성공했다면 해당 uid의 Cloud clip metadata는 Library에 다시 나타나면 안 된다.
- 재가입 후 동일 소셜 계정을 쓰더라도, 삭제 전 Cloud 데이터가 재노출되면 “삭제 완료” UX와 충돌한다.

### 2.2 Free/Standard Cloud 읽기 정책

현재 `UserStatusManager` 정책은 다음과 같다.

- Standard/Premium 활성 상태: 기존 Cloud clip read/download 가능.
- Standard/Premium 만료 후 Free 강등: 구매 이력 기반 만료 후 30일 동안 기존 Cloud clip read/download 가능.
- never-paid Free: Cloud clip read/download 불가.

근거:

- `lib/managers/user_status_manager.dart`
  - `canStartNewCloudWrite()`는 Standard 이상이고 만료 전일 때만 true.
  - `canReadExistingCloudClips()`는 Standard 활성 또는 Free 강등 후 30일 grace 안에서만 true.
  - `resetToFree()` 계열로 구매 이력이 제거된 Free는 read/download 권한이 없다.
- `test/user_status_manager_r3_test.dart`
  - `free never-paid user cannot write or read cloud clips`
  - `auto downgraded expired subscription preserves local grace history`

정책 판단:

- 계정 삭제 후 재가입한 Free 사용자는 “Standard에서 Free로 변환된 고객”과 다르다.
- 따라서 다운로드 버튼이 안 보이는 것 자체는 현재 정책과 일치한다.
- 단, Library에 남아 보이는 stale Cloud clip이 있으면 사용자는 복원할 수 없는 항목을 보게 되므로 UX와 데이터 삭제 정책이 깨진다.

## 3. 버그로 분류할 항목

### B1. 계정 삭제 후 Cloud-only placeholder/metadata가 Library에 남는 문제

판정: 버그.

이유:

- Cloud DB가 삭제되었다면 `Cloud-only` clip은 서버에서 다시 내려올 수 없다.
- 그런데 Library에 계속 보인다면 Firestore 잔존이 아니라 로컬 메모리/SharedPreferences/local index/cache 잔존 가능성이 높다.
- `VideoManager.syncCloudMetadataToLibrary()`는 Cloud read 권한이 없거나 Guest면 즉시 return하지만, 이 early return에서 기존 `_cloudMetadataByPath`, `_cloudSyncedPaths`, local index의 Cloud placeholder를 정리하지 않는다.

근거:

- `lib/managers/video_manager.dart`
  - `syncCloudMetadataToLibrary()`:
    - `AuthService().isGuest || !UserStatusManager().canReadExistingCloudClips()`이면 return.
    - 이 경우 기존 Cloud metadata/cache clear가 실행되지 않는다.
  - Cloud metadata pull 성공 시에는 `_cloudMetadataByPath.clear()` 후 새 metadata를 채우지만, 권한 없음/빈 결과/계정 전환 케이스의 정리 보장이 약하다.
  - `clearUserScopedLocalCache()`는 `_cloudSyncedPaths`, `_cloudMetadataByPath`, thumbnail cache를 정리하지만 계정 삭제/로그아웃 흐름에서 호출되지 않는다.
- `lib/services/auth_service.dart`
  - `_clearUserScopedLocalState()`는 SharedPreferences `cloud_synced_paths`만 제거한다.
  - `VideoManager().clearUserScopedLocalCache()`는 호출하지 않는다.
- `lib/managers/video_manager.dart`
  - `handleLogoutLocalData(policy: 'delete')`는 owner가 일치하는 로컬 mp4와 project를 지우지만, cloud-only placeholder는 실제 파일이 아니고 owner mapping도 보장되지 않아 메모리/local index 잔존을 정리하지 못할 수 있다.

권장 수정 방향:

1. 계정 삭제/로그아웃/게스트 진입/계정 전환 시 `VideoManager.clearUserScopedLocalCache()`를 호출한다.
2. `syncCloudMetadataToLibrary()`가 권한 없음, Guest, empty server result일 때도 현재 계정에 속한 cloud-only placeholder와 `_cloudMetadataByPath`를 정리한다.
3. local index에 저장된 `cloud_only://...` 항목도 사용자 세션 종료 시 제거한다.
4. 삭제 성공 직후 Library visible list와 album counts를 강제로 갱신한다.

### B2. Cloud purge의 Storage 삭제 실패가 비차단인 문제

판정: 정책 확인 필요가 있는 잠재 버그.

현재 `purgeCurrentUserCloudData()`는 Storage object 삭제 실패를 로그만 남기고 계속 진행한다. Firestore `videos` 문서는 삭제되므로 Library 목록에서는 사라져야 하지만, 실제 Storage object가 남을 수 있다.

근거:

- `lib/services/cloud_service.dart`
  - `_performPurgeCurrentUserCloudData()`에서 Storage delete 실패 시 `failedStorageDeletes++`만 하고 계속 진행한다.
  - 반환 메시지에는 `storageFailedNonBlocking`이 포함되지만 `success: true`를 반환할 수 있다.

정책 판단:

- 사용자가 이해하는 “계정 삭제(DB 모두 삭제됨)”이 Firestore metadata만 의미한다면 현재 동작은 일부 허용될 수 있다.
- 개인정보 삭제 관점에서 “Cloud 데이터 전체 삭제”라고 표시한다면 Storage delete 실패를 비차단으로 두는 것은 위험하다.

권장 정책 결정:

- 계정 삭제 완료 조건에 Storage physical delete 성공을 포함할지 결정해야 한다.
- 포함한다면 Storage delete 실패 시 계정 삭제를 실패 처리하거나, 삭제 재시도 큐/관리자 cleanup 로그를 남겨야 한다.
- 단, 이 변경은 Storage physical delete/데이터 삭제 정책에 해당하므로 별도 승인과 롤백 계획이 필요하다.

## 4. 정책 확인으로 분류할 항목

### P1. 계정 삭제 후 재가입자는 30일 Cloud 복원 grace 대상인가?

판정: 현재 정책상 대상 아님.

이유:

- 30일 복원 grace는 “Standard에서 Free로 자동/정상 강등된 동일 계정 세션”을 위한 정책이다.
- 계정 삭제는 Cloud 데이터, 사용자 문서, 로컬 구독/구매 히스토리까지 제거하는 종료 행위다.
- 계정 삭제 후 재가입은 새 사용자 상태로 보아야 하며, never-paid Free와 동일하게 Cloud read/download를 허용하지 않는 것이 보수적이다.

정책 문구 제안:

- “계정 삭제 시 Cloud에 저장된 클립과 프로젝트는 삭제되며, 동일한 로그인 수단으로 다시 가입해도 복원할 수 없습니다.”
- “구독 해지 후 기존 Cloud 클립을 30일간 복원하려면 계정을 삭제하지 않아야 합니다.”

### P2. 구독 해지 상태에서 계정 삭제 허용 여부

판정: 현재 흐름은 해지 예약이 확인되면 계정 삭제를 허용하는 방향으로 보인다. 정책 문구 보강 필요.

확인해야 할 점:

- 사용자가 구독 해지를 했지만 아직 유효 기간 안이라면 Standard 기능/Cloud 권한은 만료일까지 유지될 수 있다.
- 그 상태에서 계정 삭제를 선택하면 남은 유료 기간의 Cloud 데이터도 삭제된다.
- 삭제 후 재가입해도 기존 Cloud 데이터는 복원되지 않는다는 안내가 필요하다.

### P3. Free 사용자에게 Cloud-only clip 표시 여부

판정: 일반 never-paid Free에는 표시하지 않는 것이 맞다.

다만 Standard에서 Free로 강등된 30일 grace 사용자는 기존 Cloud clip을 표시하고 다운로드 버튼을 제공해야 한다.

정책 분기:

- Free never-paid: Cloud-only clip 숨김 또는 구독 안내만 표시. 다운로드 버튼 없음.
- Free grace: Cloud-only clip 표시 + 다운로드/복원 버튼 제공. 신규 upload/copy는 차단.
- Standard active: Cloud-only clip 표시 + upload/download 가능.
- Guest: Cloud-only clip 표시하지 않음. Cloud action 비활성.

현재 문제:

- Library transfer button 노출 자체가 `isStandardOrAbove()`에 묶여 있다.
- 따라서 Free grace 사용자가 `canReadExistingCloudClips() == true`여도 다운로드 버튼이 숨겨질 가능성이 있다.

근거:

- `lib/screens/library_screen.dart`
  - `showTransferButton = _userStatusManager.isStandardOrAbove()`
  - download handler 내부는 `canReadExistingCloudClips()`를 검사하지만, 버튼 표시가 먼저 Standard 이상으로 제한된다.

권장 수정 방향:

- download action 노출은 `isStandardOrAbove()`가 아니라 selection action과 `canReadExistingCloudClips()` 기준으로 분리한다.
- upload action은 `canStartNewCloudWrite()` 기준을 유지한다.

## 5. 이번 재현의 최종 판정

### 버그

1. 계정 삭제 후 Library에 DB/Cloud clip이 남아 보이는 현상.
   - Firestore가 실제로 비어 있다면 로컬 cloud placeholder/cache/local index 정리 누락 버그다.
   - Firestore `videos` 문서가 실제로 남아 있다면 `purgeCurrentUserCloudData()` 또는 보안/uid 매칭 문제다.

2. Free grace 사용자에게도 다운로드 버튼이 숨겨질 수 있는 구조.
   - `showTransferButton = isStandardOrAbove()`는 30일 grace 정책과 충돌한다.

### 정책상 정상

1. 계정 삭제 후 동일 계정으로 재가입한 Free 사용자가 Cloud clip 다운로드 권한을 받지 않는 것.
2. never-paid Free가 Cloud read/download를 사용할 수 없는 것.

### 정책 보강 필요

1. “계정 삭제”와 “구독 해지 후 30일 복원”은 동시에 성립하지 않는다는 사용자 안내.
2. 계정 삭제 완료 조건에 Storage object 삭제 성공을 포함할지 여부.
3. 계정 삭제 후 동일 소셜 계정 재가입 시 기존 Cloud 데이터 복원 불가를 명시.

## 6. 권장 QA 체크리스트

### QA-A. 계정 삭제 후 잔존 UI 검증

1. Standard 계정으로 clip 업로드.
2. Firestore `videos.uid == currentUid` 문서 수 확인.
3. 계정 삭제 실행.
4. Firestore `videos.uid == deletedUid`, `vlog_projects.uid == deletedUid`, `users/{deletedUid}`가 0건인지 확인.
5. 앱 재시작 없이 Library 확인.
6. 앱 재시작 후 Library 확인.
7. 동일 소셜 계정 재가입 후 Library 확인.

기대 결과:

- deleted uid의 Cloud-only clip이 Library에 보이지 않아야 한다.
- local index와 `_cloudMetadataByPath`에서 cloud placeholder가 남지 않아야 한다.

### QA-B. Standard to Free grace 다운로드 검증

1. Standard에서 clip 업로드.
2. 계정 삭제 없이 구독 만료/강등 상태를 만든다.
3. 만료 후 30일 이내 상태에서 Library Cloud clip 표시 여부 확인.
4. 다운로드/복원 버튼 표시 여부 확인.
5. 다운로드 성공 후 Cloud metadata가 tombstone/moved-to-device 처리되는지 확인.

기대 결과:

- Free grace 상태에서는 다운로드 버튼이 보여야 한다.
- 신규 upload/copy는 차단되어야 한다.

### QA-C. Never-paid Free 검증

1. 신규 Free 계정으로 가입.
2. Firestore에 해당 uid의 `videos`가 없는 상태 확인.
3. Library에 Cloud-only clip이 보이지 않는지 확인.
4. Cloud upload/download 버튼이 보이지 않거나 Standard 안내만 표시되는지 확인.

기대 결과:

- Cloud-only placeholder가 없어야 한다.
- 다운로드 버튼이 없어야 한다.

## 7. 구현 후보

구현은 아직 수행하지 않는다.

우선순위:

1. `AuthService._resetLocalStateAfterSessionEnd()`에서 `VideoManager().clearUserScopedLocalCache()` 호출.
2. `VideoManager.clearUserScopedLocalCache()`가 local index의 cloud-only 항목도 제거하도록 보강.
3. `syncCloudMetadataToLibrary()` early return 전에 권한 없는 세션의 stale cloud metadata를 정리.
4. Library transfer button 표시 조건을 action별로 분리:
   - upload: `canStartNewCloudWrite()`
   - download: `canReadExistingCloudClips()`
   - cloudDone/progress/disabled: 선택 상태에 맞는 안내
5. 계정 삭제 안내 문구에 “삭제 후 동일 계정 재가입해도 Cloud 데이터 복원 불가” 추가.

## 8. 금지/주의

- Firestore collection/path/schema 변경 금지.
- Storage physical delete 정책 변경은 별도 승인 전까지 금지.
- 삭제 재시도/백필/migration 구현 금지.
- product id, uid 계약, SharedPreferences key rename 금지.
- 기존 사용자의 local raw clip/project를 일괄 삭제하는 변경 금지.

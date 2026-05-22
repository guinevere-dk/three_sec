# Account Delete Cloud Clip Rejoin Fix Plan v1

## 1. 목적

다음 QA에서 확인된 문제를 수정하기 위한 계획서다.

1. Standard 해지 예약 상태에서는 만료일까지 Standard 권한이 유지되어야 한다.
2. 실제 Free grace 상태에서 Cloud-only clip 다운로드 버튼이 보여야 하는지 검증 가능해야 한다.
3. 계정 삭제 후 동일 소셜 계정으로 재가입했을 때, 삭제 전 Cloud clip placeholder가 Library에 남으면 안 된다.

본 문서는 계획서이며, 아직 코드 변경/Firestore rules/schema 변경/Storage physical delete/deploy를 포함하지 않는다.

## 2. QA 요약

### 2.1 Standard 해지 예약 상태

사용자가 Standard 구독을 해지한 뒤 Library Cloud-only clip을 선택했다.

관측 로그:

```text
[UserStatusManager] 초기화 완료: tier=UserTier.standard, productId=3s_standard_monthly, userId=TEwy...vAZ2, nextTier=UserTier.free, nextTierEffectiveAt=2026-06-21 23:29:20.411
[UserStatusManager][Expiry] evaluate ... shouldDowngrade=false tier=UserTier.standard ... expiry=2026-06-21 23:29:20.411
[LibraryTransfer] render selected_count=1 ... cloudOnly=1 ... resolved_action=download show_transfer_button=true can_start_new_cloud_write=true can_read_existing_cloud_clips=true
```

판정:

- 정상.
- 해지 예약 상태는 `nextTier=free`일 뿐 현재 tier는 `standard`다.
- 만료일인 `2026-06-21 23:29:20.411`까지 Standard 권한이 유지되는 것이 정책상 맞다.
- 따라서 앱 UI만으로 “Standard -> Free grace” 상태를 즉시 만들 수 없다.

### 2.2 계정 삭제 후 동일 소셜 계정 재가입

사용자가 계정 삭제 완료 후 동일 소셜 계정으로 다시 로그인했다.

관측 로그:

```text
[AuthService] Firestore에 사용자 데이터 없음 (신규 사용자)
[AuthService][Diag][Session] post firestore sync uid=NfBH...v4X2 localTier=UserTier.free localProduct=null localNextTier=null localNextTierEffectiveAt=null
[AuthService][TierSync] raw firestore data: uid=NfBH...v4X2, tierString=null, productId=null, purchaseDateMillis=null, nextTierString=null, nextTierEffectiveAtMillis=null
[VideoManager][ProjectAccess] loadProjects skipped reason=free_without_paid_history tier=UserTier.free
[CloudService] Free 등급은 Cloud 미지원으로 용량 알림을 스킵합니다.
```

추가 UI/로그 관측:

```text
Library > 일상 3
Cloud filter 선택 시 Cloud clip 표시됨
[LibraryTransfer] render selected_count=1 state_counts localOnly=0 cloudOnly=1 ... resolved_action=download show_transfer_button=false can_start_new_cloud_write=false can_read_existing_cloud_clips=false
```

판정:

- 재가입 후 uid가 기존 `TEwy...vAZ2`가 아니라 `NfBH...v4X2`로 보인다.
- Firestore 사용자 문서는 신규 사용자 상태로 비어 있다.
- 현재 Free without paid history이므로 Cloud read/download 불가는 정상이다.
- 그런데 Cloud filter에 cloud-only clip이 보이는 것은 버그다.
- 서버 pull이 아니라 로컬 stale cloud placeholder/local index/cache가 남은 상태로 판단한다.

## 3. 문제 분리

### 3.1 버그 A: 계정 삭제/세션 종료 후 cloud-only placeholder 잔존

증상:

- 계정 삭제 후 새 uid로 재가입했는데 Library Cloud filter에 이전 계정의 Cloud-only clip이 보인다.
- 선택 로그는 `cloudOnly=1`, `can_read_existing_cloud_clips=false`다.
- 즉 읽을 권한도 없고 서버 pull도 하지 않는 상태에서 cloud-only placeholder만 남아 있다.

근거 코드:

- `lib/services/auth_service.dart`
  - `_resetLocalStateAfterSessionEnd()`는 `VideoManager().handleLogoutLocalData(...)`와 `_clearUserScopedLocalState()`만 호출한다.
  - `_clearUserScopedLocalState()`는 SharedPreferences `cloud_synced_paths`만 제거한다.
  - `VideoManager().clearUserScopedLocalCache()`는 호출하지 않는다.
- `lib/managers/video_manager.dart`
  - `clearUserScopedLocalCache()`는 `_cloudSyncedPaths`, `_cloudMetadataByPath`, `_cloudThumbnailMemoryCache`만 정리한다.
  - local index의 `cloud_only://...` entry는 제거하지 않는다.
  - `syncCloudMetadataToLibrary()`는 Guest 또는 `canReadExistingCloudClips()==false`면 바로 return한다. 이 early return에서 stale cloud metadata/local index를 정리하지 않는다.
  - `_mergeCloudOnlyPlaceholdersForCurrentAlbum()`은 `_cloudMetadataByPath`에 남은 placeholder를 `recordedVideoPaths`에 합친다.
- `lib/services/local_index_service.dart`
  - `local_index_entries_v1`에 `cloudVideoId`, `cloudStoragePath`, `cloudState`, `albumName` 등이 저장될 수 있다.

원인 가설:

1. 계정 삭제 후 in-memory `_cloudMetadataByPath`가 비워지지 않았다.
2. `local_index_entries_v1`에 이전 uid의 `cloud_only://...` entry가 남았다.
3. `cloud_synced_paths`만 제거되고 local index/cloud metadata cleanup이 빠졌다.
4. 재가입 후 Free 상태라 Cloud metadata pull이 early return하면서 stale entry를 정리할 기회가 없다.

### 3.2 버그 B: Free grace download button 노출 조건

증상 후보:

- 실제 Free grace 상태는 이번 QA에서 만들 수 없었다.
- 하지만 코드상 다운로드 버튼 노출이 `isStandardOrAbove()`에 묶여 있다.

근거 코드:

- `lib/screens/library_screen.dart`
  - `showTransferButton = _userStatusManager.isStandardOrAbove()`
  - `_transferHandlerForSelectionState()` 내부에서는 download 시 `canReadExistingCloudClips()`를 확인한다.

정책 충돌:

- Free grace 사용자는 `isStandardOrAbove()==false`이지만 `canReadExistingCloudClips()==true`일 수 있다.
- 따라서 버튼 렌더 조건은 action별로 분리해야 한다.

## 4. 수정 계획

### Phase A. 계정/세션 종료 시 Cloud local state 정리

대상:

- `lib/services/auth_service.dart`
- `lib/managers/video_manager.dart`
- `lib/services/local_index_service.dart` 또는 `VideoManager` 내부 helper

작업:

1. `AuthService._resetLocalStateAfterSessionEnd()`에서 `VideoManager().clearUserScopedLocalCache()`를 호출한다.
2. `signInAsGuest()`, `signOutGuest()`에서도 user-scoped cloud cache를 정리한다.
3. `VideoManager.clearUserScopedLocalCache()`를 확장한다.
   - `_cloudSyncedPaths.clear()`
   - `_cloudMetadataByPath.clear()`
   - `_cloudThumbnailMemoryCache.clear()`
   - `_clipTransferUiStateByPath` 중 `cloud_only://` key 제거
   - `recordedVideoPaths` 중 `cloud_only://` path 제거
   - `favorites` 중 `cloud_only://` path 제거
   - local index에서 `pathOrKey.startsWith('cloud_only://')` 또는 `cloudStorageTier == 'cloud'` entry 제거
   - album counts 갱신
4. 정리 로그 추가:
   - `[VideoManager][UserScopedCloudCache][clear] trigger=... cloudMetadataRemoved=... localIndexRemoved=... recordedPlaceholderRemoved=...`

주의:

- 로컬 mp4 파일은 이 단계에서 삭제하지 않는다.
- 계정 삭제의 로컬 파일 삭제는 기존 `handleLogoutLocalData(policy: delete)`가 담당한다.
- Cloud-only placeholder는 실제 파일이 아니므로 삭제해도 사용자 원본 파일 손실이 없다.

### Phase B. Cloud metadata sync early return 정리

대상:

- `lib/managers/video_manager.dart`

작업:

1. `syncCloudMetadataToLibrary()`가 Guest 또는 `canReadExistingCloudClips()==false`로 return하기 전에 cloud-only stale state를 정리한다.
2. 이 정리는 “권한 없는 세션에서는 Cloud-only placeholder를 표시하지 않는다” 정책을 보장한다.
3. 로그 추가:
   - `[VideoManager][CloudSync] metadata_pull_skipped_clear_stale trigger=... reason=guest|read_gate_blocked ...`

주의:

- Standard active 또는 Free grace 상태에서는 기존 Cloud metadata pull을 유지한다.
- 네트워크 실패 시에는 stale cleanup을 즉시 실행하지 않는다. 권한은 있는데 네트워크만 실패한 경우 기존 표시를 보존할 수 있다.

### Phase C. Library transfer button action별 노출

대상:

- `lib/screens/library_screen.dart`

작업:

1. 현재 `showTransferButton = isStandardOrAbove()`를 action-aware helper로 교체한다.
2. 제안 helper:

```dart
bool _shouldShowTransferButton(LibraryClipTransferAction action) {
  if (AuthService().isGuest) return false;
  switch (action) {
    case LibraryClipTransferAction.upload:
      return _userStatusManager.canStartNewCloudWrite();
    case LibraryClipTransferAction.download:
      return _userStatusManager.canReadExistingCloudClips();
    case LibraryClipTransferAction.cloudDone:
    case LibraryClipTransferAction.progress:
    case LibraryClipTransferAction.disabled:
      return _userStatusManager.canStartNewCloudWrite() ||
          _userStatusManager.canReadExistingCloudClips();
  }
}
```

3. `_transferHandlerForSelectionState()`의 download branch에서 `canStartNewCloudWrite()` 요구를 제거할지 검토한다.
   - 현재 download branch는 read gate 통과 후 write gate도 요구한다.
   - Cloud-only를 기기로 복원하면서 서버 metadata를 tombstone 처리하는 `markVideoMovedToDevice()`가 Cloud write 성격을 가진다.
   - Free grace 정책이 “기존 Cloud clip을 30일간 720p로 다운로드”라면 tombstone write를 요구하지 않거나, grace download 시 tombstone 실패를 비차단으로 처리해야 한다.

정책 결정 필요:

- Free grace 다운로드 후 Cloud metadata를 tombstone 처리해야 하는가?
- 아니면 30일 동안 여러 번 다운로드 가능하게 두고, grace 종료 후 read 차단만 할 것인가?

권장:

- Free grace에서는 다운로드 성공 후 Cloud metadata tombstone을 필수로 하지 않는다.
- Standard active에서는 기존처럼 `markVideoMovedToDevice()`를 유지한다.
- 이러면 Free grace가 write 권한 없이 read/download만 가능하다는 정책과 맞다.

### Phase D. QA harness 추가

문제:

- 운영 UX에서는 해지 예약 상태가 만료일까지 Standard로 유지되므로 즉시 Free grace 상태를 만들 수 없다.

작업 후보:

1. Debug/dev build 전용 method channel 또는 hidden QA action 추가.
2. 기능:
   - 현재 local tier를 Free로 전환하되 `purchaseDate/productId`는 보존한다.
   - 또는 `downgradeExpiredSubscriptionToFreePreservingHistory(reason: 'qa')` 직접 호출.
3. 릴리스 빌드에서는 완전히 비활성화한다.
4. QA 로그:
   - `[QA][Subscription] force_expired_free_grace applied`

대안:

- unit/widget test로 먼저 검증한다.
- `SharedPreferences.setMockInitialValues()`를 사용해:
  - `3s_user_tier` 없음
  - `3s_purchase_date`는 과거 Standard 구매일
  - `3s_product_id=3s_standard_monthly`
  - expected: `canReadExistingCloudClips()==true`, download button visible

## 5. 테스트 계획

### Unit/Widget

1. `VideoManager.clearUserScopedLocalCache()`가 cloud-only local index entry를 제거하는지 테스트.
2. `syncCloudMetadataToLibrary()` read gate blocked 시 stale cloud-only placeholder가 제거되는지 테스트.
3. `LibraryScreen` transfer visibility:
   - Standard active + cloudOnly: download button visible.
   - Free grace + cloudOnly: download button visible.
   - Free never-paid + cloudOnly stale: stale가 정리되어 표시되지 않음.
   - Guest: transfer hidden.

### Emulator Tap-through

1. Standard active:
   - Cloud-only clip 선택.
   - 로그: `resolved_action=download show_transfer_button=true can_read_existing_cloud_clips=true`.
2. 계정 삭제:
   - Cloud clip 업로드.
   - 계정 삭제.
   - 동일 소셜 계정 재가입.
   - 기대: Firestore 신규 사용자, Library Cloud filter empty.
3. Free grace:
   - QA harness로 expired Free grace 상태 구성.
   - Cloud-only clip 선택.
   - 기대: `show_transfer_button=true can_start_new_cloud_write=false can_read_existing_cloud_clips=true`.
   - 다운로드 성공.

## 6. 이번 QA로 확정된 결론

1. 해지 예약 상태에서 다운로드 버튼이 보이는 것은 정상이다.
2. 계정 삭제 후 재가입한 Free without paid history에서 Cloud clip이 보이는 것은 버그다.
3. 현재 로그상 재가입 후 Firestore는 신규 사용자 상태로 보이므로, Library Cloud clip 잔존은 DB 재조회보다 local stale state 가능성이 높다.
4. Free grace 다운로드 버튼은 실제 tap-through로 검증하지 못했다. 운영 정책상 즉시 Free grace 상태를 만들 수 없기 때문이다.
5. 코드상 `showTransferButton=isStandardOrAbove()`는 Free grace 정책과 충돌할 가능성이 높으므로 수정 대상이다.

## 7. 금지/주의

- Firestore collection/path/schema 변경 금지.
- Firebase rules/index 변경 금지.
- Storage physical delete 정책 변경 금지.
- migration/backfill 금지.
- 계정 삭제 로직에서 사용자 로컬 원본 파일을 추가로 일괄 삭제하는 변경 금지.
- Debug QA harness는 릴리스 빌드에 노출 금지.

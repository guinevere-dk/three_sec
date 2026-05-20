# R3 Cloud Upload UI Route Probe v1

작성일: 2026-05-19

범위: 코드 변경 없이 기존 앱에서 local-only clip을 Cloud로 업로드하는 UI 진입점을 역추적한다.

보안/데이터 원칙:
- raw email/password/token/order id/provider 값은 기록하지 않는다.
- uid는 이 문서에 기록하지 않는다.
- Firebase rules/index/schema, Storage object, Cloud copy 구현, deploy는 변경하지 않았다.

## 결론

기존 앱의 수동 Cloud upload UI 진입점은 `CloudBackupScreen`이 아니라 `LibraryScreen`의 clip 선택 하단 패널이다.

정확한 동선:
1. signed-in + active paid 상태에서 Library 화면으로 이동한다.
2. local-only clip이 있는 앨범으로 들어간다.
3. 가능하면 보관 위치 필터를 `device`/`기기`로 전환해 local-only clip만 보이게 한다.
4. 상태 badge가 `기기`인 clip 하나를 길게 눌러 선택 모드로 진입한다.
5. 하단 선택 패널에서 왼쪽 두 번째 Cloud 아이콘을 누른다.
6. 이때 아이콘이 `cloud_upload_rounded` 모양이어야 upload 경로다. 아이콘이 download 모양이면 선택한 clip이 cloud-only 또는 cloud-synced라서 download/read 경로다.

`CloudBackupScreen`의 floating action button은 `이 기기에 복원`이며 `CloudService.downloadVideo()`를 호출하는 read/download 전용 경로다. 이 화면에서는 local-only clip upload가 시작되지 않는다.

## 호출 경로 요약

### Manual Library upload 경로

근거:
- `lib/screens/library_screen.dart:748`에서 선택 모드 하단 패널을 `MediaWidgets.buildLibrarySelectionPanel(...)`로 표시한다.
- `lib/screens/library_screen.dart:749`에서 선택 상태에 따라 Cloud transfer icon을 결정한다.
- `lib/screens/library_screen.dart:752`에서 선택 상태에 따라 Cloud transfer handler를 결정한다.
- `lib/screens/library_screen.dart:755`에서 `showTransferButton: _userStatusManager.isStandardOrAbove()`로 Standard 이상에서만 Cloud transfer 버튼을 노출한다.
- `lib/screens/library_screen.dart:976`의 `_resolveSelectionActionState()`가 선택 clip들의 cloud sync 여부로 local/cloud/mixed를 판정한다.
- `lib/screens/library_screen.dart:1004`의 `_transferHandlerForSelectionState()`가 local 선택이면 `_moveSelectedLocalToCloud`를 반환한다.
- `lib/screens/library_screen.dart:1041`의 `_moveSelectedLocalToCloud()`가 pending upload UI 상태를 표시하고 background 작업을 시작한다.
- `lib/screens/library_screen.dart:1067`의 `_moveSelectedLocalToCloudInBackground()`가 실제 파일 존재 여부를 확인한 뒤 `CloudService.uploadVideoImmediate()`를 호출한다.

Manual upload sequence:

```text
LibraryScreen selection panel
  -> _resolveSelectionActionState()
  -> _transferIconForSelectionState(local) = Icons.cloud_upload_rounded
  -> _transferHandlerForSelectionState(local)
  -> _moveSelectedLocalToCloud()
  -> _moveSelectedLocalToCloudInBackground()
  -> CloudService.uploadVideoImmediate()
  -> Firestore videos metadata uploadStatus=uploading
  -> Storage putFile
  -> Firestore videos metadata uploadStatus=completed
  -> VideoManager.markClipCloudSynced()
  -> cloud_synced_paths persisted
```

### Auto upload 경로

근거:
- `lib/managers/video_manager.dart:4000`에서 정상 저장 완료 후 `_enqueueAutoCloudUploadAfterLocalSave(...)`를 호출한다.
- `lib/managers/video_manager.dart:4261`에서 fallback 저장 완료 후에도 `_enqueueAutoCloudUploadAfterLocalSave(...)`를 호출한다.
- `lib/managers/video_manager.dart:4406`의 `_enqueueAutoCloudUploadAfterLocalSave()`는 guest가 아니고 `UserStatusManager().isStandardOrAbove()`일 때만 진행한다.
- `lib/managers/video_manager.dart:4419`에서 `CloudService.uploadVideo(...)`를 호출한다.
- `lib/services/cloud_service.dart:580`의 `uploadVideo()`는 Firestore metadata를 `uploadStatus: queued`로 만든 뒤 upload queue에 넣는다.
- `lib/services/cloud_service.dart:874`의 `_processUploadQueue()`와 `lib/services/cloud_service.dart:928`의 `_executeUpload()`가 queued upload를 처리한다.

Auto upload는 새 녹화 저장 후의 자동 enqueue 경로다. 기존 local-only clip을 수동으로 Cloud에 올리는 QA 동선은 Library 선택 패널의 immediate upload 경로를 사용해야 한다.

## uploadVideo / uploadVideoImmediate 호출 위치

| API | 호출 위치 | 의미 |
| --- | --- | --- |
| `CloudService.uploadVideo(...)` | `lib/managers/video_manager.dart:4419` | 새로 저장된 clip의 auto upload queue 등록 |
| `CloudService.uploadVideo(...)` | `lib/services/cloud_service.dart:1467` | `enqueuePendingLocalUploads(...)`에서 미동기화 local clip들을 queue 등록 |
| `CloudService.uploadVideoImmediate(...)` | `lib/screens/library_screen.dart:1089` | Library 선택 패널에서 local-only clip을 즉시 Cloud로 이동/upload |

QA에서 기존 local-only fixture를 Cloud로 올릴 때 기대해야 하는 진입 API는 `uploadVideoImmediate()`다.

## _moveSelectedLocalToCloudInBackground 조건

`_moveSelectedLocalToCloudInBackground()`는 다음 조건을 통과한 target마다 `uploadVideoImmediate()`를 호출한다.

| 조건 | 근거 | 실패 시 동작 |
| --- | --- | --- |
| 선택 target이 존재해야 함 | `lib/screens/library_screen.dart:1042` | no-op |
| guest가 아니어야 함 | `lib/screens/library_screen.dart:1045` | guest blocked toast |
| 신규 Cloud write 가능 상태여야 함 | `lib/screens/library_screen.dart:1050` | cloud write blocked toast |
| target이 이미 cloud synced가 아니어야 함 | `lib/screens/library_screen.dart:1077` | upload failed state |
| target local file이 존재해야 함 | `lib/screens/library_screen.dart:1082` | upload failed state |
| `uploadVideoImmediate()`가 videoId를 반환해야 함 | `lib/screens/library_screen.dart:1089` | lastImmediateUploadErrorCode/Copy 기반 실패 toast |

성공하면 `lib/screens/library_screen.dart:1108`에서 `videoManager.markClipCloudSynced(path)`가 호출되어 `cloud_synced_paths`에 반영된다.

## local-only / cloud-only / cloud-synced 판정

근거:
- `lib/managers/video_manager.dart:3198`에서 cloud-only placeholder path는 `cloud_only://...` 형식이다.
- `lib/managers/video_manager.dart:4404`의 `isClipCloudSynced(path)`는 `_cloudSyncedPaths.contains(path)`로 판정한다.
- `lib/managers/video_manager.dart:4963`의 `getClipStatusBadge(path)`는 placeholder면 `Cloud`, synced면 `동기화됨`, 그 외에는 `기기`를 반환한다.
- `lib/managers/video_manager.dart:4982`의 `isClipVisibleByStorageFilter(path, filter)`는 `device` 필터에서 `!isClipCloudSynced(path) && !cloud_only`만 표시한다.

상태 판정:

| UI/내부 상태 | 판정 조건 | Cloud 버튼 의미 |
| --- | --- | --- |
| local-only | `!isClipCloudSynced(path)` 그리고 `!cloud_only://...` | upload |
| cloud-only placeholder | path가 `cloud_only://...` | download/restore |
| cloud-synced local clip | `isClipCloudSynced(path)` | download/restore 상태로 분류될 수 있음 |
| mixed selection | selected set에 local과 cloud가 섞임 | transfer handler null |

QA fixture는 `기기` badge 또는 device filter에만 표시되는 clip이어야 한다. `Cloud` 또는 `동기화됨` badge clip을 선택하면 upload가 아니라 read/download 계열로 흐른다.

## 하단 Cloud 버튼 결정 조건

근거:
- `lib/screens/library_screen.dart:976` `_resolveSelectionActionState()`
- `lib/screens/library_screen.dart:993` `_transferIconForSelectionState()`
- `lib/screens/library_screen.dart:1004` `_transferHandlerForSelectionState()`
- `lib/widgets/media_widgets.dart:481` `buildLibrarySelectionPanel(...)`
- `lib/widgets/media_widgets.dart:517`에서 Cloud transfer 버튼은 selection panel의 두 번째 버튼이다.

| SelectionActionState | icon | handler | 의미 |
| --- | --- | --- | --- |
| `local` | `Icons.cloud_upload_rounded` | `_moveSelectedLocalToCloud` | Cloud upload |
| `cloud` | `Icons.download_rounded` | `_removeSelectedCloudBackup` | Cloud restore/download |
| `mixed` | `Icons.download_for_offline_rounded` | `null` | 혼합 선택, 버튼 disabled |

버튼 위치:
- 하단 floating selection panel의 첫 번째 버튼은 favorite이다.
- 두 번째 버튼이 Cloud transfer 버튼이다.
- 세 번째 버튼은 project create 버튼이다.
- 이후 copy/move/delete 버튼이 이어진다.

## 버튼 hidden/disabled 조건

Cloud transfer 버튼이 숨겨지거나 동작하지 않는 주요 조건:

| 상태 | 결과 | 근거 |
| --- | --- | --- |
| `_userStatusManager.isStandardOrAbove() == false` | 버튼 자체가 숨겨짐 | `lib/screens/library_screen.dart:755` |
| guest 상태 | handler가 guest blocked toast | `lib/screens/library_screen.dart:1005` |
| local 선택이지만 `canStartNewCloudWrite() == false` | write blocked toast | `lib/screens/library_screen.dart:1011` |
| mixed selection | handler `null`, disabled 색상 | `lib/screens/library_screen.dart:1017`, `lib/widgets/media_widgets.dart:614` |
| selected clip이 cloud-synced/cloud-only | download/restore handler로 분기 | `lib/screens/library_screen.dart:1015` |

active paid 상태에서 필요한 precondition:
- signed-in manual Google login 상태여야 한다.
- guest가 아니어야 한다.
- UI가 Standard 이상으로 로드되어 `showTransferButton`이 true여야 한다.
- `canStartNewCloudWrite()`가 true여야 한다.
- 선택 clip이 local-only여야 한다.
- 해당 local file이 실제로 존재해야 한다.

## CloudBackupScreen 경로는 upload가 아님

근거:
- `lib/screens/cloud_backup_screen.dart:31`에서 `_isAllowed`는 기존 Cloud clips read 권한 기준이다.
- `lib/screens/cloud_backup_screen.dart:65`에서 `CloudService.getCompletedUserVideos()`로 Cloud 목록을 조회한다.
- `lib/screens/cloud_backup_screen.dart:114`의 `_downloadSelected()`가 선택된 Cloud videos를 처리한다.
- `lib/screens/cloud_backup_screen.dart:153`에서 `CloudService.downloadVideo(...)`를 호출한다.
- `lib/screens/cloud_backup_screen.dart:162`에서 `videoManager.registerCloudRestoredClip(...)`로 로컬 복원 clip을 등록한다.
- `lib/screens/cloud_backup_screen.dart:209`의 floating action button label은 `이 기기에 복원`이다.

따라서 CloudBackupScreen에서 사용자가 누르는 주요 Cloud 동작은 Cloud upload가 아니라 Cloud read/list + download/restore다.

## v1 user action이 download/read로 분류된 이유

v1 user action capture에서 `CloudService.uploadVideo`, `uploadVideoImmediate`, upload queue, `_executeUpload`, Firestore metadata create, `cloud_synced_paths` 관련 hit가 0이었다. 반면 CloudService 목록 조회와 download request/completion 흐름이 관찰되었다.

이는 다음 중 하나와 일치한다.
1. 사용자가 `CloudBackupScreen`의 `이 기기에 복원` 동작을 눌렀다.
2. Library에서 `Cloud` 또는 `동기화됨` 상태 clip을 선택해 하단 두 번째 버튼이 download icon 상태였고, `_removeSelectedCloudBackup()` 경로로 진입했다.
3. 선택 set이 local-only가 아니라 cloud 또는 cloud-only placeholder 중심이었다.

특히 `CloudBackupScreen`은 설계상 upload UI가 없고 `getCompletedUserVideos()`와 `downloadVideo()`만 사용한다. 따라서 v1 capture의 read/download 로그는 UI route 선택 오류로 분류한다.

## 다음 QA에서 사용자가 눌러야 할 정확한 절차

사용자 안내 문구:

```text
Library 화면에서 Cloud 보관함이 아닌 일반 앨범으로 들어가세요.
보관 위치 필터가 있으면 '기기'를 선택하세요.
badge가 '기기'인 local-only clip 하나를 길게 눌러 선택하세요.
하단 패널의 왼쪽 두 번째 Cloud 아이콘이 위쪽 화살표(upload) 모양인지 확인한 뒤 그 버튼을 누르세요.
아이콘이 아래쪽 화살표(download)라면 누르지 말고, '기기' clip을 다시 선택하세요.
```

AI capture 기대 로그:
- `CloudService.uploadVideoImmediate` 관련 hit > 0
- `CloudService.uploadVideo`는 manual Library upload에서는 0일 수 있음
- Firestore metadata create/update: `uploadStatus=uploading` 이후 `completed` 흐름
- Storage upload/putFile 흐름
- `cloud_synced_paths` 또는 `markClipCloudSynced` 이후 상태 반영
- download/read-only 로그만 있고 upload 관련 hit가 0이면 UI route 실패

## 판정

| 항목 | 결과 |
| --- | --- |
| 기존 앱의 local-only clip manual Cloud upload UI route 확인 | PASS |
| `uploadVideo` 호출 위치 확인 | PASS |
| `uploadVideoImmediate` 호출 위치 확인 | PASS |
| `_moveSelectedLocalToCloudInBackground` 호출 조건 확인 | PASS |
| local-only/cloud-only 판정 조건 확인 | PASS |
| 하단 Cloud 버튼 upload/download 결정 조건 확인 | PASS |
| 버튼 hidden/disabled 조건 확인 | PASS |
| active paid precondition 확인 | PASS |
| auto upload 경로 존재 여부 확인 | PASS |
| v1 user action이 download/read 흐름을 탄 이유 설명 | PASS |

## 남은 리스크

- 현재 UI에는 Cloud transfer 버튼에 텍스트 label이 없고 icon만 있다. 사용자가 `cloud_upload_rounded`와 `download_rounded`를 육안으로 구분해야 하므로 capture 재시도 전 안내가 필요하다.
- `showTransferButton`은 `isStandardOrAbove()` 기준이고 실제 write gate는 `canStartNewCloudWrite()` 기준이다. expired grace 상태에서는 버튼 표시 여부와 write 차단 UX를 별도로 확인해야 한다.
- local-only fixture가 없거나 이미 `cloud_synced_paths`에 포함된 clip만 보이는 경우 upload route에 진입할 수 없다. 이 경우 device filter에서 새 local-only clip을 먼저 만들어야 한다.

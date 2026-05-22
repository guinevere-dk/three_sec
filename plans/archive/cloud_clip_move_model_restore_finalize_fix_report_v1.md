# Cloud Clip Move Model Restore Finalize Fix Report v1

## Scope
- Enforce the policy that an active clip is stored in exactly one place: device or Cloud.
- Fix Profile > Cloud CLIP > restore-to-device so restored clips do not remain active Cloud clips.
- Keep Storage physical objects intact. Cloud deletion means active Firestore metadata tombstone/trash only.

## Root Cause
- `CloudBackupScreen._downloadSelected()` downloaded Cloud clips and called `registerCloudRestoredClip()`.
- `registerCloudRestoredClip()` defaulted `cloudSynced=true`, so restored local files became `cloudSyncedLocal`.
- The Profile Cloud backup route did not tombstone Cloud active metadata after restore.
- `_removeCloudPlaceholdersForVideo()` removed metadata and markers, but did not remove placeholder paths from `recordedVideoPaths`.

## Changes
- Added `CloudService.markVideoMovedToDevice(videoId)` for restore/move-to-device tombstone.
  - Uses read/download entitlement gate.
  - Does not physically delete Storage objects.
  - Logs masked video id only.
- Updated Library download move route to use `markVideoMovedToDevice()`.
- Updated Profile Cloud backup restore route:
  - If matching local file already exists, tombstone Cloud active metadata and finalize local state without duplicate download.
  - If downloading fresh, only finalizes local state after download and Cloud tombstone both succeed.
  - Rolls back newly downloaded local file if Cloud tombstone fails.
- Updated `VideoManager.registerCloudMovedToDeviceClip()` finalize behavior:
  - Keeps restored local clip as `localOnly`.
  - Removes local legacy cloud marker.
  - Removes Cloud-only placeholder metadata, marker, transfer state, local index entry, and recorded path.
- Added count/state regression test for cloud-to-device finalize.

## Policy Result
- Device restore success results in active device/localOnly state.
- Cloud active count drops after tombstone refresh.
- Library badge remains two-state only: `기기` or `Cloud`.
- A restored local clip is uploadable again as a device clip if moved back to Cloud later.

## Validation
- `dart format` PASS for changed files.
- `flutter test test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart test\cloud_thumbnail_metadata_model_test.dart test\media_widgets_cloud_only_renderer_test.dart` PASS.
- `flutter test test\video_manager_clip_storage_state_test.dart` PASS after final import cleanup.
- `flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true` PASS.
- `flutter analyze ...` completed with existing info/warning analyzer debt; no blocking compile error. Main categories: `avoid_print`, braces style, deprecated `withOpacity`, and existing unused helper.

## Remaining Runtime Check
- Install the latest debug APK and repeat Profile > Cloud CLIP > 전체 선택 > 이 기기에 복원.
- Expected:
  - Profile Cloud CLIP count decreases after returning/refreshing Profile.
  - Library shows restored clips as `기기`.
  - Selecting a restored clip resolves to upload action without “Cloud 동기화됨” mismatch.

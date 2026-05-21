# Free Project Access Policy Update Report v1

## Scope

- Free-tier Project DB access policy update.
- Guest Free Project isolation.
- Free export should not create a saved Project.
- Standard-to-Free users may read existing Project DB only during the paid-history grace window.

## Changed Files

- `lib/main.dart`
- `lib/managers/video_manager.dart`

## Policy Applied

- Guest mode cannot read Project DB/local Project archive.
- Free users without paid history cannot read Project DB/local Project archive.
- Standard/Premium users can read and write Project DB.
- Expired paid users in the existing 30-day grace window can read existing Project records for 720p download, but cannot start new Cloud writes.
- Free export from Library uses a transient Project object only; it is not inserted into `vlogProjects`, not written as `vlog_projects/{id}.json`, and not upserted to Firestore.

## Key Changes

- `VideoManager.loadProjects()` now returns an empty Project list when the session is Guest or Free without paid-history grace.
- Loaded Projects are filtered by `ownerAccountId` for the current user.
- Ownerless legacy Projects remain visible only for active paid users to preserve old local data compatibility.
- `_hydrateProjectCloudMetadata()` is skipped unless the current session can read existing Cloud clips.
- `VideoManager.createProject()` now supports `persist: false` for transient export-only Projects.
- Library Free merge/export calls `createProject(..., persist: false)`.
- Single-clip Free edit/export fallback also calls `createProject(..., persist: false)`.
- `saveProject()` now skips Project Cloud upsert when the current session cannot start new Cloud writes.

## Verification

- `dart format lib\main.dart lib\managers\video_manager.dart`
  - PASS
- `flutter test test\video_manager_clip_storage_state_test.dart test\user_status_manager_r3_test.dart`
  - PASS, 27 tests passed.
- `flutter analyze lib\managers\video_manager.dart test\video_manager_clip_storage_state_test.dart`
  - FAIL due existing repository lints in `video_manager.dart`; no new compile error observed.
- `flutter analyze lib\main.dart lib\managers\video_manager.dart`
  - FAIL due existing repository warnings/lints in `main.dart` and `video_manager.dart`.

## Emulator QA

- Device: `emulator-5554`.
- Mode: Guest Free.
- PASS: Project tab showed `기본 0` and `휴지통 0`.
- PASS: Log showed `loadProjects skipped reason=guest tier=UserTier.free`.
- PASS: Library Free export of 2 selected clips completed at 720p.
- PASS: Export log showed `caller=MergeFlow_free` and `"quality":"720p"`.
- PASS: No `ProjectCloudSave` log appeared during Free export.
- PASS: Returning to Project tab after Free export still showed `기본 0` and `휴지통 0`.
- PASS: No `FATAL EXCEPTION`, `Unhandled Exception`, or `FlutterError` was observed in the checked log window.

## Notes

- `flutter run -d emulator-5554` timed out with the known Windows stdout pipe error, but the app installed/launched and QA proceeded on the updated build.
- Existing Project files were not deleted. They are hidden from Guest/never-paid Free by access filtering to preserve user data.

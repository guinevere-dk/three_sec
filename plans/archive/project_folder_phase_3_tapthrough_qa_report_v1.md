# Project Folder Phase 3 Tap-through QA Report v1

## Scope

- Phase P3 Project card UX QA.
- Device: Android emulator `sdk gphone64 x86 64 (emulator-5554)`.
- Date: 2026-05-21.

## Preconditions

- Current working tree was launched with `flutter run -d emulator-5554`.
- Existing Project data was preserved.
- QA did not perform export or project move/copy/delete actions.

## Checklist

| Item | Result | Evidence |
| --- | --- | --- |
| App launches with current build | PASS | App was active after `flutter run`; UI dump showed main bottom navigation. |
| Project tab is visible | PASS | Bottom navigation showed `Camera`, `Library`, `Project`, `Profile`. |
| Project folder list opens | PASS | Tapping Project showed `Project` title and folders `기본` and `휴지통`. |
| Default Project folder opens | PASS | Tapping `기본` showed `기본 / 7 Projects`. |
| Project cards render | PASS | UI dump showed 7 project cards with titles such as `Vlog_2026521` and `Vlog_2026520`. |
| Cloud clip count appears on mixed projects | PASS | Several project card descriptions showed `Cloud 1`, for example `05/21 • 3 clips • Cloud 1`. |
| Project list does not show Missing state | PASS | UI dump for Project card list contained no `Missing` or `File Missing` text. |
| Project card opens edit screen | PASS | Tapping the first Project opened `Vlog_2026521` edit screen with `만들기`, `Canvas 9:16`, timeline controls, and 3 clips. |
| Edit screen does not show Missing state | PASS | Edit screen dump contained no `File Missing`, `Missing`, or Cloud load failure UI. |
| Closing edit returns to Project context | PASS | Tapping close returned to `기본 / 7 Projects`, not Library. |
| Project cloud save preserves cloud-only reference | PASS | logcat showed `ProjectCloudSave` with `cloudSaveStatus=success`, `cloudOnlyClipCount=1`, `cacheLikeClipCount=0`, `hasCloudProjectId=true`, `hasCloudSyncedAt=true`. |
| Runtime crash check | PASS | Filtered logcat found no `FATAL EXCEPTION`, Dart `Unhandled Exception`, or `FlutterError`. |

## Commands

- `flutter devices`
- `flutter run -d emulator-5554`
- `adb logcat -c`
- `adb shell input tap ...`
- `adb shell uiautomator dump`
- `adb shell cat /sdcard/window_dump.xml`
- `adb logcat -d -t ...`

The `adb` commands were executed via the Android SDK platform-tools path because `adb` is not available on `PATH`.

## Notes

- `flutter run` again timed out from the shell with the known stdout pipe close issue, but the app installed/launched and was responsive.
- logcat remains noisy with repeated `CloudService][StorageUsage]` entries.
- Emulator audio produced `pcm_writei failed` warnings while the edit preview was active. They did not block the QA path and no app crash was observed.

## Untested

- Export from the opened Project was not tapped in this pass.
- Move/copy/delete Project actions were not tapped to avoid mutating existing user organization.
- A fully Cloud-only Project card was not available in the visible sample; mixed Cloud projects were verified through `Cloud 1` card text and edit entry.

## Conclusion

Phase P3 tap-through QA passed for Project card rendering, mixed Cloud clip count display, absence of Missing state in the Project list and edit screen, edit entry, Project-context return, and cloud project save preservation.

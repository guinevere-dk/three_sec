# Project Folder Phase 1-2 Tap-through QA Report v1

## Scope

- Phase 1: Main navigation Project tab exposure and routing.
- Phase 2: Project folder list, create, open, and delete flows.
- Device: Android emulator `sdk gphone64 x86 64 (emulator-5554)`.
- Date: 2026-05-21.

## Preconditions

- App was launched on the emulator with the current working tree.
- Existing user data was preserved.
- QA avoided project move/copy actions because those can mutate existing project membership.

## Checklist

| Item | Result | Evidence |
| --- | --- | --- |
| Bottom navigation shows 4 tabs | PASS | UI dump showed `Camera`, `Library`, `Project`, `Profile` with Project at bounds `[540,2204][810,2361]`. |
| Project tab opens Project screen | PASS | Tapping Project showed `Project` title and folder cards. |
| Default folders are visible | PASS | Folder list showed `기본` with 7 projects and `휴지통` with 0 projects. |
| Create Project folder dialog opens | PASS | Plus action opened `새 Project 폴더` dialog with input and `취소`/`확정` actions. |
| New Project folder can be created | PASS | Entered `QA_P2`; folder list showed `QA_P2` with 0 projects. |
| New empty folder can be opened | PASS | Opening `QA_P2` showed `QA_P2 / 0 Projects` and empty state `No Projects. Merge clips to create one!`. |
| Folder selection mode works | PASS | Long-pressing `QA_P2` showed selection mode `1개 선택됨` and delete action. |
| Folder delete confirmation works | PASS | Delete dialog showed `폴더 삭제` and `폴더는 삭제되고 Project는 휴지통으로 이동합니다.` |
| Test folder cleanup completed | PASS | After confirming delete, folder list no longer showed `QA_P2`. |
| Existing default folder can be opened | PASS | Opening `기본` showed `기본 / 7 Projects` and 7 project cards. |
| Missing state not shown in Project folder flow | PASS | `기본` folder dump showed project cards and no `Missing` text. |
| Runtime crash check | PASS | logcat filter found no `FATAL EXCEPTION`, app crash, or Dart `Unhandled Exception` for the tap-through path. |

## Commands

- `flutter devices`
- `flutter run -d emulator-5554`
- `adb shell logcat -c`
- `adb shell input tap ...`
- `adb shell input text QA_P2`
- `adb shell input swipe ...`
- `adb shell uiautomator dump`
- `adb shell cat /sdcard/window_dump.xml`
- `adb logcat -d -t ...`

The `adb` commands were executed through the Android SDK platform-tools path because `adb` was not available on `PATH`.

## Notes

- `flutter run` timed out from the shell after installation/launch, but the app was active and responsive on the emulator.
- logcat remained noisy with repeated `ProfileScreen][Diag] build` and `CloudService][StorageUsage]` entries because the current main shell keeps Profile alive in the `IndexedStack`.
- Emulator camera logs included repeated `EmulatedRequestProcessor: ApplyOverrideZoom` messages. These appear emulator/camera related and did not block the Project folder QA path.

## Untested

- Moving/copying existing projects between folders was not tapped through in this pass to avoid mutating existing user project organization.
- Export-to-Project return path was not re-tested in this Project folder pass; it was outside Phase 1-2 folder navigation/create/delete scope.

## Conclusion

Phase 1-2 tap-through QA passed for Project tab visibility, Project folder visibility, folder creation, folder opening, folder deletion, cleanup, and opening the existing default Project folder.

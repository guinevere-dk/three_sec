# Cloud-only Placeholder Renderer Fix Report v1

## Scope

- Implemented an explicit Cloud-only card renderer for Library grid clips.
- No Firebase rules/index/schema, Storage object, migration/backfill, thumbnail generation/upload, legacy cleanup, deploy, or Cloud copy changes were made.
- No raw uid, local path, Storage path, or file name is recorded.

## Changed Files

- `lib/widgets/media_widgets.dart`
- `lib/screens/library_screen.dart`
- `test/media_widgets_cloud_only_renderer_test.dart`

## Implementation Summary

### `MediaWidgets.buildMediaGridItem`

- Added optional `isCloudOnly` parameter with default `false`.
- When `isCloudOnly == true`, the widget now renders a dedicated Cloud card body instead of invoking the generic thumbnail `FutureBuilder`.
- The Cloud card body contains:
  - large Cloud icon
  - `Cloud` label
  - `길게 눌러 기기로 받기` guidance
- Duration badge rendering is skipped for Cloud-only cards because the current model has no Cloud duration metadata.
- Existing badge overlay remains unchanged, so the card still shows the `Cloud` badge.

### `LibraryScreen`

- Reads `videoManager.getClipStorageState(path)` for each visible clip.
- Passes `isCloudOnly: storageState == ClipStorageState.cloudOnly` into `MediaWidgets.buildMediaGridItem`.
- Existing tap behavior is unchanged:
  - single tap on Cloud-only shows the existing snackbar guidance
  - long-press selection remains available
  - selected Cloud-only transfer action remains download/move-to-device

### Tests

- Added `test/media_widgets_cloud_only_renderer_test.dart`.
- Verifies Cloud-only card renders Cloud UI text/icon.
- Verifies Cloud-only card does not call the thumbnail callback.

## Verification

### Format

Command:

```text
dart format lib\widgets\media_widgets.dart lib\screens\library_screen.dart test\media_widgets_cloud_only_renderer_test.dart
```

Result: PASS.

### Tests

Command:

```text
flutter test test\video_manager_clip_storage_state_test.dart test\library_clip_transfer_action_test.dart test\media_widgets_cloud_only_renderer_test.dart
```

Result: PASS, 18 tests passed.

### Analyzer

Command:

```text
flutter analyze lib\widgets\media_widgets.dart lib\screens\library_screen.dart test\media_widgets_cloud_only_renderer_test.dart
```

Result: WARN/INFO only. Analyzer reported existing info-level lints:

- `curly_braces_in_flow_control_structures` in `lib/screens/library_screen.dart`
- deprecated `withOpacity` use in `lib/screens/library_screen.dart`
- deprecated `withOpacity` use in `lib/widgets/media_widgets.dart`

No new compile error was found in the Cloud-only renderer implementation.

### Build

Command:

```text
flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true
```

Result: PASS.

### Runtime Install / Visual Check

Command:

```text
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Result: BLOCKED.

Reason: emulator returned `INSTALL_FAILED_INSUFFICIENT_STORAGE`. App data reset, `pm clear`, wipe data, uninstall/reinstall, or Storage deletion were not performed.

Runtime visual confirmation remains pending until emulator storage is recovered without violating the data preservation constraints.

## Expected Runtime Behavior

- Cloud-only Library cards should no longer appear as plain gray fallback tiles.
- Cloud-only cards should show a deliberate Cloud placeholder body.
- Cloud-only cards should not invoke local thumbnail loading.
- Single tap should still show the existing instruction snackbar.
- Long-press selection should still resolve to download/move-to-device.

## Verdict

Implementation: PASS.

Automated tests/build: PASS.

Analyzer: PASS with existing info-level lint debt.

Runtime visual confirmation: BLOCKED by emulator insufficient storage.

# Emulator Storage Recovery for Cloud-only Renderer Check v1

## Scope

- Goal: recover enough emulator storage to install the Cloud-only placeholder renderer build without clearing app data.
- Preserved:
  - `com.dk.three_sec` app data
  - manual login/session data
  - QA fixtures and Cloud-only placeholder metadata
- Not used:
  - `adb uninstall com.dk.three_sec`
  - `adb shell pm clear com.dk.three_sec`
  - emulator wipe data
  - app internal `files`, `shared_prefs`, or `databases` deletion

## Initial Storage State

Command:

```text
adb shell df -h
```

Relevant result:

| Mount | Size | Used | Avail | Use |
| --- | ---: | ---: | ---: | ---: |
| `/data` | 5.8G | 5.2G | 466M | 92% |
| `/storage/emulated` | 5.8G | 5.2G | 466M | 92% |

Initial reinstall result:

```text
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Result: BLOCKED, `INSTALL_FAILED_INSUFFICIENT_STORAGE`.

Debug APK size: 196,555,688 bytes.

## Non-Destructive Recovery Actions

### Package Cache Trim

Commands:

```text
adb shell pm trim-caches 1G
adb shell cmd package trim-caches 1G
```

Result: both commands completed successfully.

Post-trim storage:

| Mount | Size | Used | Avail | Use |
| --- | ---: | ---: | ---: | ---: |
| `/data` | 5.8G | 5.1G | 541M | 91% |
| `/storage/emulated` | 5.8G | 5.1G | 541M | 91% |

Reinstall after trim still failed with `INSTALL_FAILED_INSUFFICIENT_STORAGE`.

### Temp / Cache Inspection

Checked non-app-data temp candidates:

- `/data/local/tmp`: about 780K only, not a meaningful recovery target.
- `/sdcard`: about 4K at top-level check time.

Checked app private size without deleting anything:

| App private area | Size |
| --- | ---: |
| `cache` | 8K |
| `code_cache` | 8K |
| `shared_prefs` | 160K |
| `files` | 52K |
| `app_flutter` | 84M |
| `databases` | 340K |
| total | 85M |

No app internal data was deleted. App cache/code_cache were too small to matter.

### Fastdeploy Attempt

Command:

```text
adb install -r --fastdeploy build\app\outputs\flutter-apk\app-debug.apk
```

Result:

- Fastdeploy detected a large shared APK entry ratio.
- Output included a deploy-agent stream warning, so this was not accepted as the final install proof.
- After the attempt, `/data` free space increased to 728M.

### Final Install

Command:

```text
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Result: PASS, `Success`.

No app uninstall, app clear, wipe data, Storage delete, Firebase change, migration, backfill, or legacy cleanup was performed.

## Data Preservation Evidence

Post-install app SharedPreferences remained readable.

Count-only evidence:

| Probe | Result |
| --- | ---: |
| SharedPreferences readable | true |
| `cloud_only://` marker count | 33 |
| local index Cloud video id count | 11 |
| local index key present | true |

Raw uid, path, Storage path, and file name values were not output.

## Runtime Visual Check

After successful install, the app launched and Library was opened.

Cloud-only renderer result:

- Album detail showed 11 Cloud-only cards.
- Cards rendered as deliberate Cloud placeholder UI, not plain gray fallback.
- Card body showed:
  - Cloud icon
  - `Cloud`
  - `길게 눌러 기기로 받기`
- Existing Cloud badge remained visible.
- The generic local thumbnail gray fallback was not observed for Cloud-only cards.

Long-press transfer check:

- Long-press selected one Cloud-only card.
- Bottom selection panel retained the download icon/action position.
- This confirms the Cloud-only download/move-to-device selection path remains reachable.

## Follow-up UI Adjustment During Check

The first runtime selection check exposed a small selected-card overflow warning. A layout-only adjustment was applied in `lib/widgets/media_widgets.dart`:

- Cloud placeholder content is wrapped in `FittedBox(scaleDown)` with a stable inner width.
- This keeps the Cloud icon/text within compact selected cards.

Verification after adjustment:

```text
dart format lib\widgets\media_widgets.dart
flutter test test\media_widgets_cloud_only_renderer_test.dart test\library_clip_transfer_action_test.dart
flutter build apk --debug --dart-define=GUEST_LOGIN_ENABLED=true
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Results:

- Format: PASS
- Tests: PASS
- Build: PASS
- Install: PASS
- Runtime selected-card visual check: PASS, no overflow warning observed.

## Verdict

Storage recovery: PASS.

App data preservation: PASS.

Cloud-only renderer runtime visual check: PASS.

Download/move-to-device long-press route visibility: PASS.

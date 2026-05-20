# Cloud Clip Phase B Path-Like Log Source Triage v1

## Verdict

Strict gate: WARN / exception recommended.

The remaining path-like hits are `I/flutter` entries from the app process, but the hit lines have no known app component markers. Count-only classification points to Flutter/plugin/runtime output rather than an app-controlled `CloudService`, `VideoManager`, `LibraryTransfer`, `UserStatusManager`, or `Profile` log.

No raw matching line, raw path, raw filename, raw uid, email, token, order id, or provider value was printed in this triage.

## Procedure

1. Cleared logcat before reproducing MMQA-01 upload action window.
2. User manually performed the same upload action.
3. Captured logcat after completion.
4. Scanned only count/tag/marker data.
5. Did not print raw matching lines.

## Functional Action Window Check

Phase B upload path still succeeded during the reproduced window:

| Signal | Count/Value |
| --- | ---: |
| `LibraryTransfer` | 8 |
| `ThumbnailUpload` | 1 |
| `uploadVideoImmediate_call_count` | 4 log-token hits |
| `StorageException` | 0 |
| `permission_denied` | 0 |
| thumbnail result | success |
| thumbnail generation success | 1 |
| thumbnail upload success | 1 |
| thumbnail metadata commit success | 1 |
| local cleanup executed | true |

## I/flutter Path-Like Hit Summary

| Metric | Count |
| --- | ---: |
| `I/flutter` path-like total | 4 |
| app pid available | true |
| hits from app pid | 4 |
| email-like hits | not part of this blocker |
| raw uid-like hits | not part of this blocker |

The reproduced run had 4 hits, not 5. The previous v2 run had 5. The difference appears run-window dependent.

## Per-Hit Raw-Safe Classification

| Hit | Tag | Severity | App PID | Known App Marker Count | Local Data Prefix Count | `.mp4` Pattern Count | Cloud Storage `users/` Count | Package Marker Count | Runtime Marker Count | Source Bucket |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | flutter | I | true | 0 | 1 | 2 | 0 | 1 | 1 | flutter_runtime |
| 2 | flutter | I | true | 0 | 0 | 2 | 0 | 0 | 1 | flutter_runtime |
| 3 | flutter | I | true | 0 | 0 | 2 | 0 | 0 | 1 | flutter_runtime |
| 4 | flutter | I | true | 0 | 0 | 2 | 0 | 0 | 1 | flutter_runtime |

Known app markers checked:

- `CloudService`
- `VideoManager`
- `LibraryTransfer`
- `UserStatusManager`
- `Profile`
- `thumbnailLog`
- `Firebase`
- `Storage`

All direct hit marker counts were zero.

## Surrounding Window Marker Check

For each hit, a nearby raw-safe window was checked without printing lines.

| Hit | Nearby Known Marker Count | Nearby Runtime Marker Count | Nearby Path-Like Count |
| --- | ---: | ---: | ---: |
| 1 | 9 | 9 | 1 |
| 2 | 13 | 14 | 3 |
| 3 | 13 | 14 | 3 |
| 4 | 12 | 14 | 3 |

Interpretation:

- The hits occurred during the app upload window, so nearby app markers exist.
- The matching lines themselves do not carry app component markers.
- Runtime marker counts are present on each hit.
- This pattern is consistent with Flutter/plugin/runtime forwarding through `I/flutter`, not with a structured app log breadcrumb.

## Code Search

Raw-safe `rg` search for app path logging candidates found remaining candidates outside the MMQA upload path:

- `lib\models\edit_command.dart` trim command logs
- `lib\screens\clip_extractor_screen.dart` invalid clip logs
- `lib\screens\video_edit_screen.dart` duration error log
- `lib\generate_icon.dart` tooling script

Relevant upload path code already uses redacted markers in:

- `CloudService`
- `VideoManager`
- `LibraryTransfer`

Thumbnail-generation-related package usage in the upload path:

- `video_player` via `VideoPlayerController.file(...)`
- `video_thumbnail` via `VideoThumbnail.thumbnailData(...)`

The remaining hits are likely emitted by Flutter/plugin/runtime while those APIs handle a local file.

## Source Bucket Decision

Source bucket:

```text
flutter_runtime / plugin_runtime
```

Rationale:

- tag is `I/flutter`
- app pid is true, which is expected for Flutter/plugin stdout
- known app component marker count is zero on every hit
- runtime marker count is present on every hit
- Cloud Storage `users/` marker count is zero
- CloudService marker count is zero
- VideoManager marker count is zero
- LibraryTransfer marker count is zero

## Recommendation

Do not block MMQA-01 functional PASS on these hits if the strict gate allows a documented runtime/plugin exception.

Recommended QA gate adjustment:

- App-controlled logs remain FAIL if raw path-like values appear with known app markers such as `CloudService`, `VideoManager`, `LibraryTransfer`, `UserStatusManager`, `Profile`, or app-defined diagnostic prefixes.
- `I/flutter` path-like hits with:
  - known app marker count = 0
  - Cloud Storage `users/` marker count = 0
  - token/email/uid count = 0
  - runtime/plugin marker count > 0
  may be classified as `plugin_runtime_exception`.

Residual risk:

- Because raw lines were not inspected, this remains a conservative source classification based on marker/count evidence.
- If policy requires zero path-like values in app pid logs regardless of source, then Phase B remains blocked until plugin/runtime output can be suppressed or avoided.

## Follow-Up Options

Option A: Accept documented exception.

- Mark MMQA-01 Phase B as functional PASS with `plugin_runtime_exception` WARN.
- Continue to next QA scenario.

Option B: Engineering mitigation.

- Investigate whether `video_thumbnail` or `video_player` emits file paths through Flutter stdout.
- Replace or wrap thumbnail generation with a path-silent native method only if required by security policy.

Option C: Strict blocking.

- Keep MMQA blocked until all `I/flutter` path-like hits are eliminated, even when not attributable to app code.

## Forbidden Actions Observed

No forbidden action was performed:

- no raw line output
- no Firebase rules/index/schema change
- no Storage object deletion
- no migration/backfill
- no deploy
- no unrelated cleanup

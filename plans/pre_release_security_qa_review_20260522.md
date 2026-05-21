# Pre-Release Security and QA Review - 2026-05-22

## Summary

Verdict: Conditional GO for an internal/staged Android release.

Automated gates passed for Flutter tests, Dart analysis without fatal infos, Firebase Functions syntax, Firestore/Storage rules tests, and Android release AAB build. No Firebase rules/index/schema diff was detected in this review. No deploy, migration, backfill, Storage physical delete, or Firebase config change was performed.

Post-review remediation was applied for code-addressable log privacy findings:

1. Native Android edit/export/media logs now redact local media paths and path lists.
2. `VideoEditScreen` debug logs in Cloud resolving/missing-clip paths now avoid raw `clip.path` output.
3. Follow-up grep checks did not find raw media path interpolation in the reviewed native/Dart log patterns.

Remaining release risks are not build blockers, but should be acknowledged before public rollout:

1. A local ignored `.env` file contains test login credentials. It is not tracked, but must not be packaged, copied, uploaded, or shared.
2. Several tracked `logs/` artifacts exist in the repo. Pattern scan did not find the local `.env` credential values in tracked source/logs, but log hygiene should remain a pre-release checklist item.
3. Full manual Play-track smoke QA was not repeated during this review.

## Scope

Reviewed areas:

- Subscription tier behavior: Free / Standard / dormant Premium normalization.
- Project folder and Project access behavior.
- Cloud clip materialization and session cache guards.
- Export quality policy, 4K clamp, and 720p/1080p Standard policy.
- Account deletion and account-scoped local Cloud metadata cleanup path.
- Firebase Functions syntax.
- Firestore and Storage rules allow/deny tests.
- Android release appbundle build.
- Secret and credential pattern scan.

Out of scope:

- Deploy.
- Firebase rules/index/schema edit.
- Data migration or backfill.
- Storage physical deletion beyond existing app logic.
- Production database mutation.

## Verification Commands

| Check | Result | Notes |
|---|---:|---|
| `flutter test` | PASS | 91 tests passed. Re-run after log redaction changes. |
| `flutter analyze --no-fatal-infos` | PASS | 498 existing info-level lints remain. No fatal warning/error. Re-run after log redaction changes. |
| `npm --prefix functions run lint` | PASS | `node --check index.js` passed. |
| `npx firebase emulators:exec --only firestore,storage "npm --prefix functions run test:rules:r5"` | PASS | Firestore/Storage allow/deny rules passed. |
| `npx firebase emulators:exec --only firestore,storage "npm --prefix functions run test:rules:thumbnail-storage"` | PASS | Thumbnail Storage rules passed. |
| `flutter build appbundle --release` | PASS | Rebuilt `build/app/outputs/bundle/release/app-release.aab`, 57,922,407 bytes after log redaction changes. |
| Native/Dart raw path log grep | PASS | No reviewed raw `$outputPath`, `$inputPath`, `$bgmPath`, `$imagePath`, `$outputDir`, `clip.path`, or path interpolation log patterns found after redaction. |
| `.env` tracking check | PASS | `.env` is ignored by `.gitignore` and not tracked by Git. |

Initial direct rules test runs without emulators failed with `ECONNREFUSED` on ports `8080`/`9199`. Re-running through `firebase emulators:exec` passed.

## Build Output

- Artifact: `build/app/outputs/bundle/release/app-release.aab`
- Size: 57,922,407 bytes
- App version: `1.3.6+136`
- Android applicationId: `com.dk.three_sec`
- Android namespace: `com.dk.three_sec`
- Firebase project id in local config: `fir-3s-8edb9`
- Release minification: enabled
- Resource shrinking: enabled

Build warnings:

- Java source/target 8 obsolete warning.
- Some plugin deprecated/unchecked API notes, mainly from transitive Android plugin code.
- Gradle namespace fallback logs for Flutter plugins.

These are not release blockers, but should be tracked as platform maintenance work.

## Security Review

### Firebase Rules

Status: PASS.

Observed:

- Firestore rules continue to require `request.auth != null` and owner UID matching for user/video/project paths.
- Storage rules continue to require authenticated owner UID matching for user video/profile paths.
- Firebase rules/index/schema files were not modified in this review.
- Rules tests passed under emulator.

Risk: Low.

### Subscription and Tier Gates

Status: PASS by code review and tests.

Observed:

- Free users remain blocked from `VideoEditScreen`.
- Free users use quick 720p export without project persistence.
- Standard users can access editing and project save.
- Dormant Premium is normalized to Standard-level runtime permissions.
- 4K requests are clamped to 1080p by central quality policy.
- Standard export quality options are 720p and 1080p, with 1080p default.
- Library transfer button now separates Cloud write permission from existing Cloud read/download permission.

Risk: Low.

### Cloud Clip and Session Cache

Status: PASS by code review and tests.

Observed:

- `cloud_only://` references remain the project-safe representation.
- `edit_session_cache` and `export_session_cache` paths are guarded against Project JSON/local index persistence.
- User-scoped Cloud local cache is cleared on logout/session end/guest transitions.
- Cloud metadata sync clears stale local Cloud placeholders when the current session cannot read Cloud clips.
- Tests cover session cache path guard and stale cloud-only local index cleanup.

Risk: Low.

### Account Deletion and Rejoin Scenario

Status: PASS for local-client stale Cloud cleanup path.

Observed:

- The previously observed issue, Cloud-only clips remaining visible after account deletion/rejoin as a new Free user, is addressed on the local client path.
- `syncCloudMetadataToLibrary()` now clears stale Cloud-only local state when Cloud read is not allowed.
- Logout/account deletion session cleanup invokes user-scoped cache clearing.

Remaining risk:

- Production account deletion still depends on existing Cloud deletion logic and Firebase ownership enforcement. No production DB mutation was performed in this review.

Risk: Medium until one final production-like manual deletion/rejoin smoke pass is completed.

### Secret and Credential Scan

Status: Conditional PASS.

Observed:

- No private key material was found in app/functions source scan.
- `android/app/google-services.json`, keystore files, and `key.properties` are ignored.
- A local `.env` file exists, is ignored, and is not tracked.
- The local `.env` contains test login credential-like values. Values are intentionally not repeated in this report.
- Tracked source/plans/logs include placeholder token terms and documentation references, not the local `.env` credential values from this scan.

Required before source sharing or CI packaging:

- Do not include `.env`.
- Do not include ignored local keystore/config files outside the secure release process.
- Rotate the local test account password if this workspace or terminal transcript has been shared beyond the trusted release operator.
- Existing tracked `logs/` artifacts were not removed in this remediation because untracking/removing repository history artifacts should be an explicit release-operator decision.

Risk: Medium for repo/package hygiene, Low for app binary if ignored files are not included.

### Logging and Privacy

Status: PASS after remediation.

Observed:

- Many Dart service logs now mask UID/email/token/path values.
- `AuthService` and `CloudService` have explicit redaction helpers and masked diagnostics.
- Native Android `MainActivity.kt` now redacts local media paths in edit/export/audio/preflight/sticker/image conversion logs.
- `VideoEditScreen` Cloud resolving/missing clip debug logs now use redacted path markers instead of raw `clip.path`.

Remediated examples:

- `android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`: `paths`, `outputPath`, `bgmPath`, `imagePath`, `outputDir`, and preflight `path` logs.
- `lib/screens/video_edit_screen.dart`: Cloud resolving/debug logs with clip path context.

Follow-up guard:

- Keep future production logs limited to counts, indexes, quality, tier, error code, and redacted path markers.
- If a new path-bearing diagnostic is added, use the same redaction convention before release.

Risk: Low.

### Android Manifest and Permissions

Status: PASS with normal media-app permissions.

Observed:

- Media read permissions: `READ_MEDIA_VIDEO`, `READ_MEDIA_IMAGES`, `READ_MEDIA_AUDIO`.
- Legacy write permission is capped with `maxSdkVersion=32`.
- No `MANAGE_EXTERNAL_STORAGE`, `QUERY_ALL_PACKAGES`, or install-package permission was observed.
- Main activity is exported, which is expected for launcher entry.

Risk: Low.

## QA Review

### Automated QA

PASS:

- Subscription lock tests.
- Quality policy tests.
- Brightness adjustment policy tests.
- Cloud clip session resolver tests.
- Cloud thumbnail metadata/model tests.
- Library transfer action tests.
- Media widget Cloud-only rendering tests.
- User status grace/read/write tests.
- Video manager clip storage state tests.
- App boot smoke widget test.

### Manual QA Not Repeated In This Review

Manual tap-through should still be repeated on the release candidate build before production rollout:

1. Fresh install -> Guest/Free user -> Library -> Project folder upsell -> Subscribe button route.
2. Free user selected clip -> direct 720p export -> no Project save.
3. Standard user -> Library local clip -> Project create -> edit screen access.
4. Standard user -> Cloud-only clip -> edit screen -> no File Missing -> Cloud resolving/buffering/ready state.
5. Mixed local + Cloud clips -> export -> export session materialization -> Gallery/MOA output.
6. Standard unsubscribe scheduled -> remains Standard until expiry.
7. Expired Standard/Free grace -> existing Cloud clip download visible and works at 720p policy boundary.
8. Account deletion -> same provider rejoin -> no stale old account Cloud clips visible.

## Release Readiness

Recommended action:

- Internal/staged release: OK.
- Public production rollout: OK only after one final tap-through smoke pass and operator confirmation that ignored `.env` / release credentials are not packaged or shared.

No hard blocker was found in automated build/test/rules gates.

## Files/Settings Verified Unchanged

No diff detected for:

- `firebase/firestore.rules`
- `firebase/storage.rules`
- `firebase/firestore.indexes.json`
- `firebase.json`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/google-services.json`
- `functions/index.js`
- `functions/package.json`

Legacy identifiers remain:

- `com.dk.three_sec`
- `fir-3s-8edb9`
- `videos`
- `vlog_projects`
- `users/{uid}/videos/{videoId}/{fileName}`
- `3s_standard_monthly`
- `3s_standard_annual`
- `3s_premium_monthly`
- `3s_premium_annual`

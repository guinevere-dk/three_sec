# MOA 2.1.13 Release Report

## Scope

- Version: `2.1.13+223`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% production release

## Change Summary

- Improved Profile Help & Feedback so it no longer opens email immediately.
- Added an in-app choice between Help and Feedback before launching the email app.
- Added detailed Help sections for recording, library/albums, Vlog creation/editing, cloud backup, and account/subscription basics.

## App Update Policy

- `firebase/hosting/app-update.json` was not updated during release submission.
- User confirmed Play publication after release submission, then `latestPublishedVersion` was changed to `2.1.13` and `latestPublishedBuild` was changed to `223`.
- No Firebase, package identity, IAP, Storage, Firestore, or SharedPreferences contract was changed for this submission.

## QA Evidence

- `flutter analyze lib/screens/help_feedback_screen.dart lib/screens/profile_screen.dart test/help_feedback_screen_test.dart` passed with no issues.
- `flutter test test\\help_feedback_screen_test.dart` passed with 2 tests.
- Android emulator QA verified Profile -> Help & Feedback -> Help details -> Feedback -> email app handoff before release submission. Screenshot captured at `C:\\tmp\\moa_help_feedback_feedback.png`.
- Auth-included release AAB build succeeded for `build\\app\\outputs\\bundle\\release\\app-release.aab`.
- AAB artifact size at submission: `61,514,795` bytes.
- Play API `validate-only` passed for production versionCode `223`, rollout `1.0`, release `MOA 2.1.13 (223)`; validation edit id `01627630920618857670`.
- Play API commit succeeded for production release `MOA 2.1.13 (223)` with rollout `1.0`; commit edit id `02810439403053281405`.
- Production track verification returned `MOA 2.1.13 (223)` with versionCode `223` and `status: completed`.
- User confirmed Play publication, and app-update JSON was activated for `2.1.13+223`.
- `firebase deploy --only hosting --project fir-3s-8edb9` completed successfully after app-update activation.
- Live app-update JSON verification returned `latestPublishedVersion: 2.1.13` and `latestPublishedBuild: 223` from both `https://fir-3s-8edb9.web.app/app-update.json` and `https://fir-3s-8edb9.firebaseapp.com/app-update.json`.

## Release Tool Safety

- Production uploads require `--confirm-production`.
- 100% production release requires `--confirm-full-production`.
- App update popup activation is performed only after Play approval and store reflection are confirmed.

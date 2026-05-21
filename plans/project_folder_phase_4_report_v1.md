# Project Folder Phase 4 Report v1

## Scope

- Phase P4: Subscription-state UX for Project folders and Project actions.
- Free users should keep access to existing Project records, but editing is gated behind Standard.
- Free users can still export existing Projects directly at 720p.

## Changed Files

- `lib/main.dart`
- `lib/screens/project_screen.dart`

## Key Changes

- Added a Project-screen callback from `main.dart` to open `SubscriptionManagementScreen`.
- Free users entering a Project folder now see an inline Standard 안내 panel instead of being sent directly to a paywall.
- The inline panel explains:
  - Standard enables Project editing,
  - Free users can still export without opening the editor,
  - Standard benefits include Project editing, Cloud integration, and high-quality export.
- Added `구독하러가기` button that opens the subscription management page.
- Free users do not enter `VideoEditScreen` from Project cards.
- Free users can tap the Project card or the visible `720p 내보내기` button to run the existing 720p export fallback.
- Standard/Premium users retain the existing Project-card-to-edit-screen flow.

## Compatibility Notes

- Existing Project JSON, clip paths, Cloud-only placeholders, `vlog_projects`, and `vlog_folders` contracts are unchanged.
- IAP product ids and subscription validation contracts are unchanged.
- Free fallback export still uses `kQuality720p`, `kUserTierFree`, and `ProjectScreen_free_export`.

## Verification

- `dart format lib\main.dart lib\screens\project_screen.dart`
  - PASS
- `flutter analyze lib\screens\project_screen.dart`
  - PASS, no issues found.
- `flutter test test\cloud_clip_session_resolver_test.dart test\video_manager_clip_storage_state_test.dart`
  - PASS, 34 tests passed.
- `flutter analyze lib\main.dart lib\screens\project_screen.dart`
  - Existing repository issues remain in `main.dart`; no `project_screen.dart` issue remains.

## Untested

- Emulator tap-through for the Free tier gate has not been run in this pass.
- Actual Google Play purchase flow was not tested.
- Direct 720p Project export from the Free UI was not executed to avoid creating extra gallery output during implementation verification.

## Residual Risk

- The inline Free export button shares the Project card surface; visual spacing should be confirmed on emulator for small screens.
- Subscription management opens directly from Project rather than first switching to the Profile tab, while using the same subscription management page that Profile opens.

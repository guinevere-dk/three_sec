---
name: moa-flutter-firebase-work
description: Safe implementation workflow for MOA Flutter, Dart, Firebase, and Functions changes. Use when editing lib/, test/, firebase rules or indexes, functions/, Android/iOS/web platform integration, auth, camera, video processing, cloud sync, IAP, notifications, or service-layer code.
---

# MOA Flutter Firebase Work

## Required Context

Read `AGENTS.md`, `CURRENT_PHASE.md`, `DATA_COMPATIBILITY.md`, and `SKILL.md` before implementation. If the change touches release or deploy behavior, also read `RELEASE_RULES.md`.

## Flutter/Dart

- Respect existing boundaries under `lib/screens`, `lib/services`, `lib/managers`, and `lib/models`.
- Reuse existing service layers for Firebase, Storage, API, local index, and persistence work.
- Preserve null safety. Handle nullable inputs explicitly.
- Check `mounted` before updating UI after async work.
- For save, delete, sync, import, export, and restore flows, make call conditions, failure handling, and rollback behavior explicit.
- Avoid broad refactors, mass formatting, debug print sprawl, magic numbers, and temporary feature flags.

High-risk files require extra restraint:

- `lib/main.dart`: app initialization, Firebase, Kakao SDK, FCM, AuthGate, navigation, tutorial, and native channel behavior are mixed.
- `lib/managers/video_manager.dart`: local files, projects, clips, export, thumbnails, and sync state are data-sensitive.
- `lib/services/cloud_service.dart`: Firestore/Storage writes, deletes, and upload queues are data-sensitive.
- `lib/services/local_index_service.dart`: preserve `local_index_entries_v1`.
- `lib/managers/user_status_manager.dart`: preserve subscription keys and downgrade policy.

## Firebase And Functions

- Review `firebase/firestore.rules`, `firebase/storage.rules`, `firebase/firestore.indexes.json`, `firebase.json`, and `.firebaserc` together when touching Firebase behavior.
- Do not weaken rules. Preserve uid ownership conditions.
- Do not change `videos`, `users`, `vlog_projects`, `usageEvents`, Storage prefixes, product IDs, provider UID contracts, service account assumptions, or CORS policy without approval.
- For Functions, keep endpoint contracts stable and run the Functions lint/check command before deploy.
- Separate deploy targets: Firestore rules, indexes, Storage rules, and Functions should not be bundled unless explicitly requested.

## Validation

Prefer the smallest meaningful validation set:

- `flutter analyze` for Dart code changes.
- Targeted `flutter test` when behavior has tests.
- `npm run lint` from `functions/` for Functions changes.
- Firebase emulator/staging validation for rules or cloud behavior when possible.

If validation cannot be run, state the reason and the risk.

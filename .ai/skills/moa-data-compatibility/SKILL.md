---
name: moa-data-compatibility
description: Data preservation and compatibility rules for MOA. Use before changing local files, SharedPreferences keys, local index schemas, Firestore collections or fields, Storage paths, cloud sync, account ownership, subscription state, IAP products, migrations, deletion logic, or backup/restore behavior.
---

# MOA Data Compatibility

## Required Context

Read `DATA_COMPATIBILITY.md` first. Also read `AGENTS.md`, `CURRENT_PHASE.md`, and the files that implement the affected contract.

Common implementation files:

- `lib/managers/video_manager.dart`
- `lib/services/cloud_service.dart`
- `lib/services/local_index_service.dart`
- `lib/managers/user_status_manager.dart`
- `firebase/firestore.rules`
- `firebase/storage.rules`
- `functions/index.js`

## Impact Check

Before editing, determine whether the change touches:

- User original videos or exported vlogs.
- Project JSON, local project metadata, albums, folders, or trash state.
- `local_index_entries_v1` or other local index data.
- SharedPreferences keys such as `3s_user_tier`, `3s_product_id`, `cloud_synced_paths`, or `recorded_clip_save_jobs_v1`.
- Firestore collections `videos`, `users`, `vlog_projects`, or `usageEvents`.
- Storage paths such as `users/{uid}/videos/{videoId}/{fileName}` or `users/{uid}/profile/{fileName}`.
- Subscription, purchase verification, account ownership, usage accounting, or cloud sync state.

## Rules

- Preserve existing read/write keys and paths unless an approved migration plan exists.
- Do not rename Firestore collections, Storage prefixes, SharedPreferences keys, package IDs, product IDs, or local directories for branding purposes.
- Do not delete or initialize original videos, project JSON, local indexes, cloud backups, or ownership fields.
- If a new key or path is needed, design old-path read, new-path write, migration dry-run, rollback, and old-client compatibility.
- For field rename, require dual-read/write, backfill plan, and old-client verification.
- For deletion code, verify source and destination clearly and prove originals are not affected.
- For Firestore or Storage rules, preserve or strengthen uid ownership checks. Never weaken security rules.

## Validation

Choose validation proportional to impact:

- Save, load, edit, export, app restart restore.
- Logout/login and guest/social login transitions.
- Offline/online cloud sync transitions.
- Upload, download, delete, usage accounting idempotency.
- Relevant unit/widget tests and `flutter analyze`.
- Firebase emulator or staging validation for rules/functions where possible.

Record any skipped validation and the residual risk.

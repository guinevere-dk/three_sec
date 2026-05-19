---
name: moa-release-precheck
description: Release, QA, build, deployment, and store-readiness checklist for MOA. Use before Android/iOS/Web release work, Firebase deploys, version bumps, Play Console or App Store tasks, production QA, crash-risk assessment, or completion reports for release-facing changes.
---

# MOA Release Precheck

## Required Context

Read `RELEASE_RULES.md`, `AGENTS.md`, `CURRENT_PHASE.md`, and `DATA_COMPATIBILITY.md`. Read relevant release plans under `plans/` for the platform or feature being released.

## Release Principles

- Verify user data preservation, existing behavior, and legacy compatibility before release polish.
- Do not bundle app release with server/Firebase changes unless explicitly approved.
- Deploy Firebase targets separately: rules, indexes, Storage rules, and Functions.
- Record unverified items, reasons, and risk in the completion report.
- For version bumps, check whether `firebase/hosting/app-update.json` versions also need coordinated updates and document forced-update impact.

## Common Preflight

Check:

- No violation of `AGENTS.md`, `CURRENT_PHASE.md`, or `DATA_COMPATIBILITY.md`.
- No accidental changes to forbidden identifiers.
- No new deletion or initialization path for original videos, local projects, cloud data, subscription state, or ownership fields.
- User-facing brand uses `MOA` and `2초 촬영 + Vlog`.
- No secrets, real user IDs, keystore values, OAuth secrets, or live tokens in code, docs, or logs.

## Validation Commands

Flutter app:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Functions from `functions/`:

```bash
npm install
npm run lint
```

Firebase deploy targets, only when approved:

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage:rules
firebase deploy --only functions
```

## Manual QA Surface

For release-impacting changes, consider first run, login/guest entry, camera permission, recording, saving, external media import, project create/edit/export, app restart restore, cloud upload/download/delete, subscription tier gating, FCM permission, and notification routing.

## Platform Gates

- Android: keep `applicationId = "com.dk.three_sec"` and `namespace = "com.dk.three_sec"` unless explicitly approved. Check signing, R8/shrink, permissions, Firebase config, and Play Console docs.
- iOS/Web: treat bundle ID, Apple login, StoreKit, manifest, store metadata, and Firebase-linked settings as release-sensitive.
- Firebase rules: preserve uid ownership and do not weaken file type, size, or ownership checks.
- Functions: verify social exchange and IAP endpoints separately; product ID allowlist changes require approval.

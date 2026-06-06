# MOA 2.1.8 Release Report

## Scope

- Version: `2.1.8+218`
- Package: `com.dk.three_sec`
- Track: Google Play production
- Rollout: 100% requested explicitly by the user for this hotfix

## App Update Policy

- `latestVersion` changed to `2.1.8`.
- `latestVersionCode` changed to `218`.
- `minimumRequiredVersion` remains `1.3.6`.
- No forced-update expansion was made for `2.1.8`; clients below `1.3.6` remain the forced-update floor.

## Change Summary

- Fixed Standard plan recordings remaining local instead of completing Cloud upload.
- Fixed same-account Cloud Project visibility on a fresh emulator/device state.
- Stabilized Project default-folder counts when entering and leaving the folder.

## QA Evidence

- Pending. This report will be finalized after build, Play validation/commit, and Firebase Hosting deployment.

## Release Tool Safety

- Production uploads require `--confirm-production`.
- 100% production releases require `--confirm-full-production`.

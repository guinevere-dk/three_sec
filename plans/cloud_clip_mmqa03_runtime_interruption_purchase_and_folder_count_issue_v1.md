# Cloud Clip MMQA-03 Runtime Interruption: Purchase Apply and Folder Count Issues v1

## Summary

MMQA-03 / R3-MQA-03 grace upload-block runtime QA was interrupted by two user-observed issues:

1. Profile showed Free, the user performed a subscription action, but the app did not update to Standard.
2. A folder tile showed 2 clips, but entering the folder showed 14 clips including Cloud clips.

The MMQA-03 action window is invalidated because a subscription action occurred during the fixture window.

Raw uid, email, token, order id, provider, purchase token, local path, storage path, and file name values are not recorded in this document.

## Current Runtime Context

- Build type: debug APK.
- Dart defines:
  - `GUEST_LOGIN_ENABLED=true`
  - `R3_QA_SUBSCRIPTION_LOCK=true`
- QA lock verification before interruption:
  - `qa_lock_marker_count=2`
  - `firestore_paid_overwrite_count=0`
  - `source=firestore_cache before_tier=free after_tier=free result=skipped reason_code=qa_lock_applied`
- Local state was intentionally injected as Free with within-30-day grace history for MMQA-03.

## Issue 1: Subscription Action Did Not Update Profile to Standard

### Observation

User reported:

- Profile was Free.
- User subscribed.
- Subscription state did not change to Standard in the app.

Runtime log scan showed repeated Profile build markers with:

- `tier=UserTier.free`
- product id marker present
- no raw account identifier printed in app-controlled marker

App-controlled IAP markers in the scanned window were not sufficient to show a completed purchase apply path:

- no clear app `purchase update -> verify -> setTier -> Firestore sync -> Standard` sequence was observed,
- no clear `server_verify result=applied` marker was observed in the sampled app logs.

Android/Play system logs showed a pending-acknowledgement style subscription notification. The raw notification/account values are intentionally not recorded.

### Important Caveat

This happened while the app was running with:

```text
R3_QA_SUBSCRIPTION_LOCK=true
```

The QA lock is designed to preserve local Free/grace against Firestore paid cache reconciliation. It does not intentionally block store/server purchase verification, but this build/state is not a clean production purchase-flow test environment.

### Initial Classification

Status: BLOCKED / needs focused IAP runtime triage.

Likely buckets to investigate:

- purchase stream event not received,
- purchase event received but verification did not run,
- verification ran but did not apply local `setTier`,
- purchase pending acknowledgement because app did not complete/apply the purchase,
- QA lock/free-grace fixture confused Profile state after purchase,
- Profile UI did not reload after successful IAP apply.

### Required Follow-Up

Run a focused, raw-safe IAP apply triage outside MMQA-03:

1. Use a normal debug build without `R3_QA_SUBSCRIPTION_LOCK=true`.
2. Do not manually alter purchase state.
3. Open Profile/Subscription Management.
4. Capture only count/status markers:
   - `PurchaseStatus.purchased/restored/pending/error/canceled`
   - `_verifyPurchase`
   - `server_verify`
   - `setTier`
   - `syncSubscriptionToFirestore`
   - `completePurchase`
   - `EntitlementRefresh source=server_verify`
   - Profile final tier
5. Do not print raw order id, purchase token, provider, uid, or email.

## Issue 2: Folder Tile Count 2 vs Folder Detail 14

### Observation

User reported:

- Folder tile says 2 clips.
- Inside folder, 14 clips appear when Cloud clips are included.

### Current Code Path

Folder grid count:

- `lib/screens/library_screen.dart`
  - folder tile uses `videoManager.albumCounts[albumName] ?? 0`
- `lib/managers/video_manager.dart`
  - `albumCounts` is populated from local raw album directories only.
  - `_recalculateAlbumCounts()` counts `.mp4` files in each raw clip album directory.

Folder detail:

- `VideoManager.loadClipsFromCurrentAlbum()` loads local `.mp4` files into `recordedVideoPaths`.
- It then calls `_mergeCloudOnlyPlaceholdersForCurrentAlbum()`.
- `_mergeCloudOnlyPlaceholdersForCurrentAlbum()` appends Cloud-only placeholders for the current album when there is no matching local active file.
- `LibraryScreen._buildDetailView()` renders `visibleClipPaths` from `videoManager.recordedVideoPaths`.
- With the default/all storage filter, local device clips and Cloud-only placeholders are both visible.

### Root Cause

The folder tile count and folder detail list use different count semantics:

- folder tile count = local device `.mp4` count only,
- folder detail count = local device clips + Cloud-only placeholders.

This is expected from the current implementation but inconsistent with the move-model UX.

### Product Semantics Conflict

Move model says a clip is active in exactly one place:

- Device/localOnly, or
- Cloud/cloudOnly.

Therefore a folder should not show a single ambiguous count unless the count definition is explicit.

Current UI makes the folder tile look like the folder contains 2 clips, while the detail screen shows total active clips across Device + Cloud.

### Required Fix Direction

Recommended:

1. Define folder count semantics explicitly:
   - `deviceCount`
   - `cloudCount`
   - `totalActiveCount = deviceCount + cloudCount`
2. Update folder tile to use either:
   - total active count, or
   - split display such as `2 device / 12 cloud`.
3. Keep Library storage filters:
   - `all`: localOnly + cloudOnly
   - `device`: localOnly only
   - `cloud`: cloudOnly only
4. Ensure Cloud-only placeholders are counted once and not duplicated with local active files.
5. Add count-only diagnostics for:
   - folder local count,
   - folder cloudOnly count,
   - folder total active count,
   - detail visible count by filter.

## MMQA-03 Status

Current MMQA-03 run status: INVALIDATED / BLOCKED.

Reasons:

- User performed a subscription action during the grace fixture window.
- The app remained Free afterward, but the purchase apply flow requires separate investigation.
- The folder count mismatch can confuse fixture selection and evidence counts.

## Recommended Next Steps

1. Close the current MMQA-03 attempt as BLOCKED/INVALIDATED.
2. Run IAP apply triage without QA subscription lock.
3. Create a folder count semantics fix plan for move model.
4. After those are understood, recreate MMQA-03 grace fixture with QA lock enabled and no Subscription Management or purchase navigation during the action window.

## Restrictions Observed

- No purchase state was changed by AI.
- No Firestore user profile was modified by AI.
- No Firebase rules/index/schema change.
- No deploy.
- No Storage object deletion.
- No raw sensitive values recorded.

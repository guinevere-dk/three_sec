# Cloud Clip Thumbnail Storage Rules Deploy Plan v1

## 1. Change Summary

Deploy the emulator-validated Firebase Storage rules change that allows canonical Cloud clip thumbnails at:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

The rule change allows:

- authenticated owner read
- authenticated owner create/update for `poster.jpg`
- `image/jpeg` only
- max size 10MB

The rule change denies:

- unauthenticated read/write
- cross-user read/write
- non-image writes
- oversized writes
- non-`poster.jpg` thumbnail filenames
- arbitrary nested non-thumbnail paths
- thumbnail delete

No broad recursive allow is introduced.

## 2. Emulator Validation Evidence

Source report:

```text
plans/cloud_clip_thumbnail_storage_rules_validation_report_v1.md
```

Validated commands:

```text
npx firebase emulators:exec --only storage "npm --prefix functions run test:rules:thumbnail-storage"
```

Result:

```text
PASS
[Thumbnail storage rules] allow/deny tests passed
```

Existing R5 regression:

```text
npx firebase emulators:exec --only storage,firestore "npm --prefix functions run test:rules:r5"
```

Result:

```text
PASS
[R5 rules/index] allow/deny rules tests passed
```

The direct npm test without emulator failed with `ECONNREFUSED 127.0.0.1:9199`, which is expected when the Storage emulator is not running.

## 3. Deploy Target

Deploy target:

```text
firebase/storage.rules
```

Firebase deploy scope:

```text
storage
```

Do not deploy:

- Firestore rules
- Firestore indexes
- Functions
- Hosting

## 4. Pre-Deploy Checklist

Before deploy, confirm:

- `firebase/storage.rules` diff contains only the thumbnail rule and helper.
- `allow delete: if false` is present for thumbnail path.
- no `{allPaths=**}` broad recursive allow was added.
- `functions/test/thumbnail_storage_rules.test.js` passes in emulator.
- existing R5 rules/index regression passes in emulator.
- current Firebase project/alias is correct.
- deploy operator has explicit approval to deploy Storage rules only.
- no app data mutation, migration, backfill, or Storage object deletion is planned.

Recommended command to verify project target before deploy:

```text
firebase use
```

If the active project is not the intended target, stop.

## 5. Deploy Command

Candidate command:

```text
firebase deploy --only storage
```

This plan does not execute the command automatically.

Deploy should be run only after explicit approval.

## 6. Rollback Plan

Rollback artifact:

- previous committed `firebase/storage.rules`
- or a saved copy of the pre-deploy Storage rules from Firebase Console / repository state

Rollback steps:

1. Restore the previous `firebase/storage.rules`.
2. Re-run emulator regression tests:

```text
npx firebase emulators:exec --only storage,firestore "npm --prefix functions run test:rules:r5"
```

3. Deploy Storage rules only:

```text
firebase deploy --only storage
```

4. Confirm thumbnail upload is denied again if rollback is intentionally restoring prior behavior.

Rollback does not delete any Storage object and does not alter Firestore data.

## 7. Post-Deploy Validation

Immediately after deploy:

1. Run a small owner thumbnail upload through the app path or a controlled QA action.
2. Confirm Storage no longer returns permission-denied for:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

3. Confirm non-owner/unauthenticated access remains denied through emulator-tested assumptions or a controlled negative check if available.
4. Confirm existing video upload path still works:

```text
users/{uid}/videos/{videoId}/{fileName}
```

5. Confirm no Storage physical delete occurred.

Raw uid/path values must not be printed in QA artifacts. Use masked uid and count/status-only evidence.

## 8. MMQA-01 Phase B Rerun Plan

After Storage rules deploy:

1. Rebuild/reinstall latest app if runtime is not current.
2. Confirm signed-in QA account and active Standard state.
3. Confirm app-controlled sensitive log gate remains PASS after CloudService redaction.
4. Prepare or reuse a verified localOnly/uploadable QA clip.
5. Clear logcat before action.
6. User manually selects the localOnly clip and taps upload move.
7. Collect count/status-only evidence:
   - `uploadVideoImmediate_call_count`
   - `thumbnail_generation_attempt/success/failure`
   - `thumbnail_upload_attempt/success/failure`
   - `thumbnail_metadata_commit_success/failure`
   - `local_cleanup_executed`
8. Verify:
   - `thumbnailStatus=completed`
   - `thumbnailStoragePath` present
   - `durationMs` present
   - thumbnailReadyCount increased
   - local active file/index removed
   - resulting state is cloudOnly
   - no cloudSyncedLocal normal success
   - no Storage physical delete
   - sensitive log gate PASS

Expected outcome after successful deploy:

- thumbnail Storage upload should no longer fail with permission-denied.
- If it still fails, classify the new failure by tag/count only.

## 9. Forbidden Items

Do not:

- deploy Firestore rules
- deploy Firestore indexes
- deploy Functions
- deploy Hosting
- run migration/backfill
- delete Storage objects
- change product thumbnail path
- broaden Storage access with recursive allow
- run `firebase deploy` without explicit approval

## 10. Go / No-Go

Go for approval request:

- emulator thumbnail rules test PASS
- R5 regression PASS
- deploy command limited to `firebase deploy --only storage`

No-Go:

- active Firebase project is unclear
- tests are not passing
- deploy scope includes Firestore/Functions/Hosting
- rollback artifact is unavailable

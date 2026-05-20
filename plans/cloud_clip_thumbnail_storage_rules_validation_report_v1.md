# Cloud Clip Thumbnail Storage Rules Validation Report v1

## Verdict

PASS for local emulator validation.

No deploy was executed.

## Scope

Implemented and validated a minimal Firebase Storage rules change for the canonical Cloud thumbnail path:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

Unchanged:

- Firestore schema
- Firestore rules/indexes
- product thumbnail path
- migration/backfill
- Storage physical delete policy
- product code

## Changed Files

- `firebase/storage.rules`
- `functions/test/thumbnail_storage_rules.test.js`
- `functions/package.json`

## Storage Rules Change

Added a dedicated thumbnail match:

```text
match /users/{userId}/videos/{videoId}/thumbnails/{fileName}
```

Allowed:

- owner read
- owner create/update only when:
  - `fileName == poster.jpg`
  - content type is `image/jpeg`
  - size is at or below 10MB

Denied:

- delete
- unauthenticated access
- cross-user access
- non-`poster.jpg` thumbnail file names
- arbitrary nested non-thumbnail paths
- non-JPEG thumbnail writes
- oversized thumbnail writes

No broad recursive allow was added.

## Test Implementation

Added:

```text
functions/test/thumbnail_storage_rules.test.js
```

Added npm script:

```text
npm --prefix functions run test:rules:thumbnail-storage
```

### Allow Cases

| ID | Scenario | Result |
| --- | --- | --- |
| TS-ALLOW-01 | owner uploads `image/jpeg` thumbnail under size cap | PASS |
| TS-ALLOW-02 | owner reads own thumbnail | PASS |

### Deny Cases

| ID | Scenario | Result |
| --- | --- | --- |
| TS-DENY-01 | unauthenticated read | PASS |
| TS-DENY-02 | unauthenticated write | PASS |
| TS-DENY-03 | user B writes under user A thumbnail path | PASS |
| TS-DENY-04 | owner writes `text/plain` | PASS |
| TS-DENY-05 | owner writes image over size cap | PASS |
| TS-DENY-06 | owner writes arbitrary nested non-thumbnail path | PASS |
| TS-DENY-07 | owner deletes thumbnail | PASS |

Additional strictness:

- owner writing `thumbnails/not-poster.jpg` is denied.

## Validation Commands

Initial direct run without emulator:

```text
npm --prefix functions run test:rules:thumbnail-storage
```

Result:

- FAIL, expected environment issue
- reason: Storage emulator was not running (`ECONNREFUSED 127.0.0.1:9199`)

Thumbnail Storage rules emulator test:

```text
npx firebase emulators:exec --only storage "npm --prefix functions run test:rules:thumbnail-storage"
```

Result:

- PASS
- output included: `[Thumbnail storage rules] allow/deny tests passed`

Existing R5 regression:

```text
npx firebase emulators:exec --only storage,firestore "npm --prefix functions run test:rules:r5"
```

Result:

- PASS
- output included: `[R5 rules/index] allow/deny rules tests passed`

Note:

- The R5 run printed expected Firestore permission-denied emulator diagnostics for deny assertions after the script completed successfully.

## Safety Checks

| Check | Result |
| --- | --- |
| deploy not executed | PASS |
| Firestore schema unchanged | PASS |
| Firestore rules/indexes unchanged | PASS |
| Storage physical delete for thumbnail denied | PASS |
| broad recursive Storage allow avoided | PASS |
| product thumbnail path unchanged | PASS |
| existing video Storage R5 regression passed | PASS |

## Follow-Up

This rules change is locally validated and ready to be raised for explicit approval/deploy planning.

Do not deploy as part of this report. A separate deployment gate should include:

- reviewer approval of `firebase/storage.rules`
- emulator PASS evidence from this report
- rollback plan for Storage rules
- post-deploy MMQA-01 rerun for Phase B thumbnail upload

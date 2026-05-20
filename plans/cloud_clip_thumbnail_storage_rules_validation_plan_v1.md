# Cloud Clip Thumbnail Storage Rules Validation Plan v1

## 1. Objective

Validate a minimal Firebase Storage rules change for the canonical Cloud thumbnail path:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

The change must allow only the authenticated owner to read/write thumbnail images, while denying unauthenticated access, cross-user access, non-image uploads, oversize uploads, arbitrary nested paths, and physical delete.

This is a validation plan only. No deploy is included.

## 2. Current Blocker

Current `firebase/storage.rules` allows video uploads only at:

```text
users/{uid}/videos/{videoId}/{fileName}
```

That rule:

- matches only one object segment below `{videoId}`
- requires `isValidVideoFile()`
- accepts video content types only

Phase B thumbnails are stored at:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

This path is deeper and uses `image/jpeg`, so it is denied by current rules.

## 3. Proposed Minimal Rules Shape

Candidate change for approval after emulator tests pass:

```text
match /users/{userId}/videos/{videoId}/thumbnails/{fileName} {
  allow read: if request.auth != null
              && request.auth.uid == userId;

  allow write: if request.auth != null
               && request.auth.uid == userId
               && isValidThumbnailFile();

  allow delete: if false;
}

function isValidThumbnailFile() {
  let maxSize = 10 * 1024 * 1024;
  let validTypes = ['image/jpeg'];

  return request.resource.size <= maxSize
      && request.resource.contentType in validTypes;
}
```

Notes:

- Keep the existing video rule unchanged.
- Keep the existing profile image rule unchanged.
- Do not introduce broad recursive access under `videos/{videoId}`.
- Do not allow delete in the current scope.
- Do not change the Cloud thumbnail path.

## 4. Required Test Coverage

Recommended location:

- extend `functions/test/r5_rules_index.test.js`, or
- create a dedicated `functions/test/thumbnail_storage_rules.test.js`

Preferred approach:

- create a dedicated thumbnail Storage rules test file to keep R5 regression coverage readable
- add a `functions/package.json` script such as `test:rules:thumbnail-storage`

### Allow Cases

| ID | Case | Expected |
| --- | --- | --- |
| TS-ALLOW-01 | owner uploads `image/jpeg` thumbnail under size cap to `users/userA/videos/videoA/thumbnails/poster.jpg` | allow |
| TS-ALLOW-02 | owner reads own thumbnail path | allow |

### Deny Cases

| ID | Case | Expected |
| --- | --- | --- |
| TS-DENY-01 | unauthenticated read thumbnail | deny |
| TS-DENY-02 | unauthenticated write thumbnail | deny |
| TS-DENY-03 | user B writes under user A thumbnail path | deny |
| TS-DENY-04 | owner writes non-image content type, for example `text/plain` | deny |
| TS-DENY-05 | owner writes image over size cap | deny |
| TS-DENY-06 | owner writes arbitrary nested non-thumbnail path under the video folder | deny |
| TS-DENY-07 | owner deletes thumbnail | deny |

## 5. Emulator Test Design

Use `@firebase/rules-unit-testing` with the Storage emulator, following the existing R5 test pattern.

Test contexts:

- authenticated `userA`
- authenticated `userB`
- unauthenticated context

Paths:

```text
users/userA/videos/videoA/thumbnails/poster.jpg
users/userA/videos/videoA/thumbnails/not-poster.jpg
users/userA/videos/videoA/other/poster.jpg
users/userA/videos/videoA/poster.jpg
users/userB/videos/videoB/thumbnails/poster.jpg
```

Recommended strictness:

- If policy requires exactly `poster.jpg`, tests should deny `not-poster.jpg`.
- If policy allows future thumbnail variants, tests can allow `{fileName}` under `thumbnails/`.
- For Phase B, strict `poster.jpg` is preferable because product code writes exactly that object.

## 6. Proposed Test Pseudocode

```js
const userA = testEnv.authenticatedContext('userA');
const userB = testEnv.authenticatedContext('userB');
const anon = testEnv.unauthenticatedContext();

const storageA = userA.storage();
const storageB = userB.storage();
const storageAnon = anon.storage();

const path = 'users/userA/videos/videoA/thumbnails/poster.jpg';
const jpegBytes = new Uint8Array([1, 2, 3]);

await assertSucceeds(
  storageA.ref(path).put(jpegBytes, { contentType: 'image/jpeg' }),
);

await assertSucceeds(storageA.ref(path).getDownloadURL());

await assertFails(storageAnon.ref(path).getDownloadURL());
await assertFails(
  storageAnon.ref(path).put(jpegBytes, { contentType: 'image/jpeg' }),
);

await assertFails(
  storageB.ref(path).put(jpegBytes, { contentType: 'image/jpeg' }),
);

await assertFails(
  storageA.ref(path).put(jpegBytes, { contentType: 'text/plain' }),
);

await assertFails(
  storageA.ref('users/userA/videos/videoA/other/poster.jpg')
    .put(jpegBytes, { contentType: 'image/jpeg' }),
);

await assertFails(storageA.ref(path).delete());
```

Oversize test should use a byte array larger than the proposed cap. If the emulator/runtime allocation cost is a concern, reduce the proposed thumbnail cap to a small testable value only if production policy agrees. Otherwise keep the 10MB policy and allocate `10MB + 1 byte` in the rules test.

## 7. Validation Sequence

1. Add failing thumbnail Storage rules tests first against current rules.
2. Confirm tests fail for owner thumbnail upload/read under current rules.
3. Apply minimal Storage rules change locally.
4. Run thumbnail Storage rules emulator tests.
5. Run existing R5 rules/index regression test.
6. Confirm:
   - old video upload allow/deny behavior remains unchanged
   - profile image behavior remains unchanged
   - thumbnail allow/deny matrix passes
7. Produce validation report.
8. Only then request explicit approval for rules change and later deploy.

## 8. Commands

Existing R5 test:

```text
cd functions
npm run test:rules:r5
```

Proposed new script:

```json
{
  "scripts": {
    "test:rules:thumbnail-storage": "node test/thumbnail_storage_rules.test.js"
  }
}
```

Proposed validation command:

```text
cd functions
npm run test:rules:thumbnail-storage
npm run test:rules:r5
```

No deploy command is part of this plan.

## 9. Approval Gate

Rules change may be proposed for approval only after:

- thumbnail Storage emulator tests pass
- existing R5 rules/index tests pass
- no broad recursive allow is introduced
- delete remains denied for thumbnails
- product path remains `users/{uid}/videos/{videoId}/thumbnails/poster.jpg`

## 10. Risks

Main risk:

- Accidentally allowing arbitrary nested writes under `users/{uid}/videos/{videoId}`.

Mitigation:

- Add explicit deny test for non-thumbnail nested path.
- Avoid `match /users/{userId}/videos/{videoId}/{allPaths=**}` unless it is constrained very tightly and separately justified.

Secondary risk:

- Thumbnail delete might become allowed through a broad rule.

Mitigation:

- Add explicit owner delete deny test.
- Keep thumbnail delete rule as `false` in current scope.

## 11. Go / No-Go

Go:

- Implement emulator tests and minimal rules change in a separate rules-validation task.

No-Go:

- Deploying rules from this plan.
- Changing product thumbnail path to fit current rules.
- Allowing Storage physical delete for thumbnails in the current scope.
- Broadly allowing all nested video paths.

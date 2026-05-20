# Cloud Clip Thumbnail Storage Permission Triage v1

## Verdict

Rules change is required.

The Phase B thumbnail upload path is not covered by the current Firebase Storage rules. The runtime `permission-denied` result is consistent with the current rules.

No rules/code/deploy changes were made in this triage.

## Files Inspected

- `firebase/storage.rules`
- `firebase.json`
- `lib/services/cloud_service.dart`
- `functions/test/r5_rules_index.test.js`
- `plans/cloud_clip_r5_firebase_rules_index_validation_report_v1.md`

## Current Video Upload Path

CloudService video upload path:

```text
users/{uid}/videos/{videoId}/{fileName}
```

Code locations:

- `uploadVideo(...)`
- `uploadVideoImmediate(...)`
- `_executeUpload(...)`

Video upload uses:

- `putFile(...)`
- `SettableMetadata(contentType: video/mp4 | video/quicktime | video/x-msvideo | video/mpeg)`

Current Storage rule:

```text
match /users/{userId}/videos/{videoId}/{fileName}
```

Write condition:

```text
request.auth != null
&& request.auth.uid == userId
&& isValidVideoFile()
```

`isValidVideoFile()` allows:

- max size: 500MB
- content types:
  - `video/mp4`
  - `video/quicktime`
  - `video/x-msvideo`
  - `video/mpeg`

## Phase B Thumbnail Upload Path

CloudService thumbnail upload path:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

Upload uses:

- `putData(...)`
- `SettableMetadata(contentType: image/jpeg)`

## Required Checks

### 1. Existing video path allow pattern

Allowed pattern:

```text
users/{userId}/videos/{videoId}/{fileName}
```

This is a single object directly under the video id folder.

Example allowed:

```text
users/userA/videos/videoA/videoA.mp4
```

R5 rules test currently covers this case.

### 2. Whether `thumbnails` child path is included

No.

The thumbnail path has two segments after `{videoId}`:

```text
thumbnails/poster.jpg
```

Current rule only captures one segment:

```text
{fileName}
```

Firebase Storage rules path matching is structural. `users/{uid}/videos/{videoId}/thumbnails/poster.jpg` does not match `users/{uid}/videos/{videoId}/{fileName}`.

### 3. Whether `image/jpeg` is allowed

No for the video path.

The only image allow helper is `isValidProfileImageFile()`, but it applies only to:

```text
users/{userId}/profile/{fileName}
```

The video object rule uses `isValidVideoFile()`, which does not include `image/jpeg`.

### 4. Whether size limits fit thumbnails

Current relevant limits:

- video path: 500MB, video content types only
- profile image path: 10MB, image content types only

No thumbnail-specific size rule exists.

A thumbnail rule would need an image-specific size cap. Reusing the profile image cap would be conservative but should be explicitly designed and tested.

### 5. Whether auth uid ownership condition matches

The intended thumbnail path embeds the same owner uid:

```text
users/{uid}/videos/{videoId}/thumbnails/poster.jpg
```

The existing ownership model can apply safely:

```text
request.auth != null && request.auth.uid == userId
```

The runtime failure is not likely caused by uid mismatch if video upload succeeds in the same action window. It is explained by path/contentType mismatch.

### 6. Whether rules change can be avoided by changing path

Not safely under the current product policy.

Possible no-rules-change workaround:

```text
users/{uid}/profile/{fileName}
```

This would allow `image/jpeg`, but it is not acceptable because:

- it separates thumbnail ownership from the video object prefix
- it does not match the approved thumbnail policy path
- it weakens object organization and later cleanup/repair reasoning
- it would require code and metadata path changes anyway

Another possible workaround:

```text
users/{uid}/videos/{videoId}/poster.jpg
```

This would match the existing single-depth video rule, but would still fail because `image/jpeg` is not accepted by `isValidVideoFile()`.

Using a fake video content type for JPEG bytes is not acceptable.

Conclusion: rules change is required.

### 7. Whether emulator test cases are needed

Yes.

This should be handled as a separate R5-style validation plan with Storage emulator allow/deny tests before any deploy.

Existing R5 rules test already has Storage coverage for:

- owner video upload allowed
- other-user video access denied
- non-video file under video path denied

It should be extended with thumbnail-specific cases.

## Required R5-Style Validation Plan

Create a separate plan before changing rules.

Minimum proposed allow cases:

| Case | Expected |
| --- | --- |
| owner uploads `users/{uid}/videos/{videoId}/thumbnails/poster.jpg` with `image/jpeg` under size cap | allow |
| owner reads same thumbnail path | allow |

Minimum proposed deny cases:

| Case | Expected |
| --- | --- |
| unauthenticated thumbnail read/write | deny |
| user B writes under user A thumbnail path | deny |
| owner writes thumbnail with non-image content type | deny |
| owner writes thumbnail over size cap | deny |
| owner writes arbitrary nested non-thumbnail path | deny unless explicitly designed |
| owner deletes thumbnail | deny or allow only if a separate delete policy is approved |

Open policy point:

- Current R3/Rcurrent policy says Storage physical delete is out of scope and should not occur. A thumbnail rule can omit `delete` allow for thumbnail objects unless a future approved plan needs it.

## Candidate Rule Shape For Future Approval

This is not implemented in this triage.

Possible minimal addition:

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

This candidate must be reviewed against current product policy before implementation.

## Go / No-Go

No-Go for another runtime MMQA-01 PASS attempt until thumbnail Storage rule support is approved, tested in emulator, and deployed.

Go for a separate R5-style rules validation plan.

Do not change the thumbnail path to fit existing rules. The existing rules do not provide a policy-correct no-change path for canonical Cloud thumbnails.

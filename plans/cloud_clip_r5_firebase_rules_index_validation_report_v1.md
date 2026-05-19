# Cloud Clip R5 Firebase rules/index 검증 보고서 v1

## 0. 작업 범위와 결론

본 문서는 R5 Firebase rules/index 검증 작업의 산출물이다. 범위는 현재 Flutter/Functions의 Firestore query와 Storage 접근 패턴 수집, index 필요성 판단, emulator allow/deny 테스트 산출물 작성, 최소 rules/index 변경, 배포 전 회귀 테스트 체크리스트 문서화로 제한했다.

결론:

- Firestore rules는 `users/{uid}/usageEvents/{eventId}` 하위 컬렉션에 본인 uid 고정 조건을 추가했다.
- Firestore index는 현재 앱 query 중 `videos` + `uid` + optional filter + `createdAt desc` 조합에 필요한 최소 composite index 4개를 추가했다.
- Storage rules는 변경하지 않았다. 기존 `users/{uid}/videos/{videoId}/{fileName}` prefix와 contentType/size 제한을 유지한다.
- emulator 테스트 파일은 Node rules unit test로 추가했다.
- Java 21 설치 및 PATH 구성 후 Firebase emulator 실행에 성공했다. Firestore/Storage emulator allow/deny rules 테스트와 index static assertion은 PASS다.
- 사용자 데이터, Firestore 문서, Storage 객체 mutation은 수행하지 않았다.

## 1. 기준 문서와 핵심 제약

| 기준 파일 | 확인 내용 | R5 적용 |
|---|---|---|
| [AGENTS.md](../AGENTS.md) | 사용자 데이터 보존, 기존 기능 유지, 레거시 호환 우선 | broad allow 금지, 최소 변경만 수행 |
| [CURRENT_PHASE.md](../CURRENT_PHASE.md) | Firestore/Storage rules 변경은 승인 필요 | 사용자 승인 후 uid 유지/강화 방향으로만 변경 |
| [DATA_COMPATIBILITY.md](../DATA_COMPATIBILITY.md) | `videos`, `users`, `vlog_projects`, Storage `users/{uid}/videos/{videoId}/{fileName}` 계약 유지 | 컬렉션명/path/field rename 없음 |
| [plans/cloud_clip_policy_decision_v1.md](cloud_clip_policy_decision_v1.md) | rules 완화 금지, emulator allow/deny 검증 후 최소 변경 | deny case 포함 테스트 산출물 작성 |
| [plans/cloud_clip_remaining_risk_resolution_plan_v1.md](cloud_clip_remaining_risk_resolution_plan_v1.md) | R5는 현재 query 확인 후 rules 완화 없이 최소 index/rule 검토 | R1/R2/R3/R4 구현 제외 |
| [plans/cloud_clip_deferred_items_execution_guide_v1.md](cloud_clip_deferred_items_execution_guide_v1.md) | R5 query 수집, allow/deny, 최소 변경, 배포 gate | 본 보고서 항목 구성 기준 |

## 2. 문제 원인 후보와 확정 진단

검토한 잠재 원인 7개:

1. `users/{uid}/usageEvents/{eventId}` 하위 컬렉션 rules 부재.
2. `videos` 복합 query index 부재.
3. `vlog_projects` 복합 query index 부재.
4. `videos` list query와 `resource.data.uid` read rule의 query filter 정합성 문제.
5. Firestore `storagePath`와 Storage prefix 불일치.
6. emulator 테스트 의존성/Java 환경 부재 또는 PATH 문제.
7. 계정 삭제/정리 흐름의 실제 데이터 mutation 위험.

최종적으로 가장 가능성이 높은 원인 2개로 좁혔다.

| 확정 원인 | 근거 | 처리 |
|---|---|---|
| `users/{uid}/usageEvents/{eventId}` rules 부재 | [lib/services/cloud_service.dart](../lib/services/cloud_service.dart)에서 `users/{uid}/usageEvents/{eventId}` create/read가 발생하지만 기존 [firebase/firestore.rules](../firebase/firestore.rules)는 `users/{uid}` 문서 match만 존재 | uid 본인 조건과 payload uid 고정 조건을 가진 하위 match 추가 |
| `videos` composite index 부재 | [lib/services/cloud_service.dart](../lib/services/cloud_service.dart)의 `getUserVideos()`는 `uid` equality + `createdAt desc`, optional `albumName`, `isFavorite` 조합을 사용하고 기존 [firebase/firestore.indexes.json](../firebase/firestore.indexes.json)은 비어 있었음 | 현재 query 조합에 필요한 최소 4개 index 추가 |

## 3. Firestore query inventory

### 3.1 Flutter CloudService

| 위치 | 컬렉션/path | 작업 | 조건 | orderBy/limit | 권한 | index 판단 | rules 판단 |
|---|---|---|---|---|---|---|---|
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_getCurrentStorageUsage` | `users/{uid}` | get | doc id = current uid | 없음 | read | 단일 문서, index 불필요 | 기존 본인 read로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_updateStorageUsageIdempotent` | `users/{uid}` | transaction get/set | doc id = current uid | 없음 | read/write | 단일 문서, index 불필요 | 기존 본인 write로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_updateStorageUsageIdempotent` | `users/{uid}/usageEvents/{eventId}` | transaction get/create | event doc id | 없음 | read/create | 단일 문서, index 불필요 | 기존 부재 → 최소 rules 추가 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `uploadVideo` | `videos/{videoId}` | generated doc id + set | `uid == auth.uid` payload | 없음 | create | 단일 문서, index 불필요 | 기존 create + `isValidVideoMetadata()`로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `uploadVideoImmediate` | `videos/{videoId}` | set/update | `uid == auth.uid` payload | 없음 | create/update | 단일 문서, index 불필요 | 기존 create/update로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_executeUpload` | `videos/{videoId}` | update progress/status | doc id | 없음 | update | 단일 문서, index 불필요 | 기존 update로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_safeUpdateFailureMetadata` | `videos/{videoId}` | update error fields | doc id | 없음 | update | 단일 문서, index 불필요 | 기존 update로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `getSyncStatusSummary` | `videos` | getDocs | `where uid == auth.uid` | 없음 | list/read | 단일 equality, composite 불필요 | query가 uid로 제한되어 허용 예상 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `getCompletedVideoCount` | `videos` | getDocs | `where uid == auth.uid`, `where uploadStatus == completed` | 없음 | list/read | equality 조합, composite 불필요 | query가 uid로 제한되어 허용 예상 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `getCompletedUserVideos` | `videos` | getDocs | `where uid == auth.uid`, `where uploadStatus == completed` | 없음 | list/read | equality 조합, composite 불필요 | query가 uid로 제한되어 허용 예상 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `downloadVideo` | `videos/{videoId}` | get | doc id + app-side owner/prefix check | 없음 | read | 단일 문서, index 불필요 | owner doc만 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `updateVideoMetadata` | `videos/{videoId}` | update | doc id | 없음 | update | 단일 문서, index 불필요 | 기존 update로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `markVideoMovedToAlbum` | `videos/{videoId}` | get + set merge | doc id + app-side uid check | 없음 | read/update | 단일 문서, index 불필요 | owner doc만 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `markVideoInTrash` | `videos/{videoId}` | get + set merge | doc id + app-side uid check | 없음 | read/update | 단일 문서, index 불필요 | owner doc만 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `restoreVideoFromTrash` | `videos/{videoId}` | get + set merge | doc id + app-side uid check | 없음 | read/update | 단일 문서, index 불필요 | owner doc만 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `getUserVideos` | `videos` | snapshots | `where uid == auth.uid`, optional `albumName`, optional `isFavorite` | `orderBy createdAt desc` | list/read | composite 필요 | query가 uid로 제한되어 허용 예상 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `deleteVideo` | `videos/{videoId}` | get + set merge tombstone | doc id + app-side uid check | 없음 | read/update | 단일 문서, index 불필요 | owner doc만 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `findUserVideoByLocalPath` | `videos` | getDocs | `where uid == auth.uid`, `where localPath == localPath` | 없음 | list/read | equality 조합, composite 불필요 | query가 uid로 제한되어 허용 예상 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `findUserVideoByLocalPath` fallback | `videos` | getDocs | `where uid == auth.uid`, `where fileName == localName` | 없음 | list/read | equality 조합, composite 불필요 | query가 uid로 제한되어 허용 예상 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_performPurgeCurrentUserCloudData` | `videos` | getDocs + delete | `where uid == auth.uid` | 없음 | list/delete | 단일 equality, composite 불필요 | 본인 삭제 허용, 실제 실행은 계정 삭제 흐름에서만 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_performPurgeCurrentUserCloudData` | `vlog_projects` | getDocs + delete | `where uid == auth.uid` | 없음 | list/delete | 단일 equality, composite 불필요 | 본인 삭제 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_performPurgeCurrentUserCloudData` | `users/{uid}` | delete | doc id = current uid | 없음 | delete | 단일 문서, index 불필요 | 본인 delete 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `upsertVlogProjectMetadata` | `vlog_projects/{projectId}` | set merge | payload `uid == auth.uid` | 없음 | create/update | 단일 문서, index 불필요 | 기존 rules로 허용 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `getUserVlogProjectMetadataMap` | `vlog_projects` | getDocs | `where uid == auth.uid`, `where deleted == false` | 없음 | list/read | equality 조합, composite 불필요 | query가 uid로 제한되어 허용 예상 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `deleteVlogProjectMetadata` | `vlog_projects/{projectId}` 또는 query | delete | doc id 또는 `uid + localProjectId` | 없음 | delete/list | equality 조합, composite 불필요 | 본인 삭제 허용 |

### 3.2 Flutter AuthService

| 위치 | 컬렉션/path | 작업 | 조건 | 권한 | index 판단 | rules 판단 |
|---|---|---|---|---|---|---|
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `_logProfileDocSnapshot` | `users/{uid}` | get | doc id = current uid | read | 단일 문서, index 불필요 | 기존 본인 read로 허용 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `_applySocialProfileFromExchange` | `users/{uid}` | set merge | doc id = current uid | write | 단일 문서, index 불필요 | 기존 본인 write로 허용 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `_syncSubscriptionFromFirestore` | `users/{uid}` | get + set merge | doc id = current uid | read/write | 단일 문서, index 불필요 | 기존 본인 read/write로 허용 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `_updateUserProfile` | `users/{uid}` | set merge | doc id = current uid | write | 단일 문서, index 불필요 | 기존 본인 write로 허용 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `updateCurrentUserProfile` | `users/{uid}` | set merge | doc id = current uid | write | 단일 문서, index 불필요 | 기존 본인 write로 허용 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `syncSubscriptionToFirestore` | `users/{uid}` | set merge | doc id = current uid | write | 단일 문서, index 불필요 | 기존 본인 write로 허용 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `syncPendingSubscriptionChangeToFirestore` | `users/{uid}` | set merge | doc id = current uid | write | 단일 문서, index 불필요 | 기존 본인 write로 허용 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `syncFreeTierToFirestore` | `users/{uid}` | set merge | doc id = current uid | write | 단일 문서, index 불필요 | 기존 본인 write로 허용 |

### 3.3 Functions

| 위치 | Firestore/Storage 사용 | 판단 |
|---|---|---|
| [functions/index.js](../functions/index.js) | HTTPS social token exchange, IAP schema/business validation. Admin SDK Firestore/Storage query 없음 | rules/index 대상 query 없음 |
| [functions/scripts/cloud_clip_delete_dry_run_inventory.js](../functions/scripts/cloud_clip_delete_dry_run_inventory.js) | Admin SDK로 `videos` 전체 collection scan 및 Storage bucket listing | dry-run inventory script이며 security rules 적용 대상 아님. 실제 mutation 없음 |
| [functions/scripts/cloud_clip_r4_migration_backfill_inventory.js](../functions/scripts/cloud_clip_r4_migration_backfill_inventory.js) | Admin SDK로 collection read, optional limit | dry-run inventory script이며 security rules 적용 대상 아님. 실제 mutation 없음 |

### 3.4 Collection group 사용 여부

정적 검색 결과 Flutter/Functions에서 `collectionGroup()` 사용은 발견되지 않았다.

## 4. Storage 접근 inventory와 rules 대조

| 위치 | Storage path | 작업 | metadata/contentType | rules 대조 | 변경 여부 |
|---|---|---|---|---|---|
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `uploadVideoImmediate` | `users/{uid}/videos/{videoId}/{fileName}` | `putFile` | 확장자 기반 `video/mp4`, `video/quicktime`, `video/x-msvideo`, `video/mpeg` | [firebase/storage.rules](../firebase/storage.rules)의 본인 uid + video contentType + 500MB 제한과 일치 | 변경 없음 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_executeUpload` | `users/{uid}/videos/{videoId}/{fileName}` | `putFile` | 동일 | 동일 | 변경 없음 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `downloadVideo` | Firestore `storagePath`, app-side `users/{uid}/videos/{videoId}/` prefix 확인 후 `writeToFile` | read/download | 해당 없음 | rules 본인 uid read와 일치. app-side prefix 검증 유지 | 변경 없음 |
| [lib/services/cloud_service.dart](../lib/services/cloud_service.dart) `_performPurgeCurrentUserCloudData` | Firestore `storagePath` | `delete` | 해당 없음 | rules 본인 uid delete와 일치하나 실제 계정 삭제 흐름에서만 호출 | 변경 없음 |
| [lib/services/auth_service.dart](../lib/services/auth_service.dart) `updateCurrentUserProfile` | `users/{uid}/profile/avatar_*.jpg` | `putFile` | `image/jpeg` | profile path 본인 uid + image contentType + 10MB 제한과 일치 | 변경 없음 |

Storage rules 변경을 하지 않은 이유:

- 현재 client path가 [DATA_COMPATIBILITY.md](../DATA_COMPATIBILITY.md)의 Storage 계약과 일치한다.
- read/write/delete 모두 본인 uid path에 제한되어 있다.
- prefix/contentType/size 조건 약화가 필요하지 않다.
- broad allow 추가 필요성이 없다.

## 5. Index 판단과 변경 내용

기존 [firebase/firestore.indexes.json](../firebase/firestore.indexes.json)은 빈 배열이었다. 현재 query 중 composite index가 필요한 것은 `getUserVideos()`의 `videos` collection stream이다.

추가한 최소 composite index:

| collectionGroup | fields | 대응 query |
|---|---|---|
| `videos` | `uid ASC`, `createdAt DESC` | `where uid == auth.uid` + `orderBy createdAt desc` |
| `videos` | `uid ASC`, `albumName ASC`, `createdAt DESC` | album filter + createdAt sort |
| `videos` | `uid ASC`, `isFavorite ASC`, `createdAt DESC` | favorite filter + createdAt sort |
| `videos` | `uid ASC`, `albumName ASC`, `isFavorite ASC`, `createdAt DESC` | album + favorite filter + createdAt sort |

보류한 index:

- `videos`의 `uid + uploadStatus`는 equality filters만 사용하므로 composite index를 추가하지 않았다.
- `videos`의 `uid + localPath`, `uid + fileName`도 equality filters만 사용하므로 composite index를 추가하지 않았다.
- `vlog_projects`의 `uid + deleted`, `uid + localProjectId`도 equality filters만 사용하므로 composite index를 추가하지 않았다.
- R1/R2/R4 미승인 기능을 위한 선제 index는 추가하지 않았다.

## 6. Rules 변경 내용과 보안 판단

변경 파일: [firebase/firestore.rules](../firebase/firestore.rules)

추가한 rules:

- `users/{userId}/usageEvents/{eventId}` read: `request.auth.uid == userId`.
- create: `request.auth.uid == userId` 그리고 `request.resource.data.uid == userId`.
- update: 기존 `resource.data.uid == userId`와 신규 payload uid 불변.
- delete: 명시적으로 `false`.

보안 판단:

- uid 소유권 조건을 완화하지 않았다.
- 다른 사용자의 `usageEvents` read/write를 허용하지 않는다.
- event payload uid mismatch create를 차단한다.
- 사용량 이벤트 삭제를 차단해 idempotency audit trail 보존을 강화한다.
- `videos` rules와 Storage rules는 완화하지 않았다.

## 7. Emulator allow/deny 테스트 산출물

추가 파일:

- [functions/test/r5_rules_index.test.js](../functions/test/r5_rules_index.test.js)

추가 npm script:

- [functions/package.json](../functions/package.json)의 `test:rules:r5`

추가 dev dependency:

- [functions/package.json](../functions/package.json)의 `@firebase/rules-unit-testing`
- [functions/package-lock.json](../functions/package-lock.json) 갱신

테스트 케이스 요약:

| 구분 | 케이스 | 기대 결과 |
|---|---|---|
| Firestore allow | userA가 `users/userA` read | allow |
| Firestore deny | userA가 `users/userB` read | deny |
| Firestore allow | userA가 `videos/videoA` read | allow |
| Firestore deny | userA가 userB 소유 `videos/videoB` read/update | deny |
| Firestore deny | userA가 `uid=userB` metadata create | deny |
| Firestore allow | userA가 `videos`에서 `uid == userA` query | allow |
| Firestore allow | userA가 `videos`에서 `uid == userA` + `orderBy createdAt desc` query | allow |
| Firestore deny | userA가 `videos`에서 `uid == userB` query | deny |
| Firestore allow | userA가 `users/userA/usageEvents/*` create | allow |
| Firestore deny | userA가 payload uid mismatch usage event create | deny |
| Firestore deny | userA가 usage event delete | deny |
| Storage allow | userA가 본인 video path에 `video/mp4` upload | allow |
| Storage deny | userA/userB가 다른 uid video path read/write | deny |
| Storage deny | userA가 `text/plain` video path upload | deny |
| Index static | 추가된 4개 composite index signature 확인 | pass |

실행 명령:

```cmd
npx firebase emulators:exec --only firestore,storage "npm --prefix functions run test:rules:r5"
```

실행 결과:

- Java 21 설치 후 Firebase emulator 실행 성공.
- Firestore emulator 정상 시작 및 종료.
- Storage emulator 정상 시작 및 종료.
- `[R5 rules/index] allow/deny rules tests passed`
- `Script exited successfully (code 0)`
- PASS: Firestore/Storage allow/deny rules 테스트와 index static assertions 통과.
- 참고: `PERMISSION_DENIED` 로그는 deny-case 테스트에서 기대한 정상 차단 결과다.

대체 검증:

```cmd
node --check functions/test/r5_rules_index.test.js && npm --prefix functions run lint
```

- 결과: 성공.
- 의미: rules test 파일 JavaScript 문법과 Functions entrypoint 문법은 유효하다.

```cmd
npx firebase firestore:indexes > NUL && echo firebase-indexes-json-ok
```

- 결과: `firebase-indexes-json-ok`.
- 의미: Firebase CLI가 [firebase/firestore.indexes.json](../firebase/firestore.indexes.json)을 로드할 수 있다.

## 8. 배포 전 회귀 테스트 체크리스트

### 8.1 Emulator 검증 결과

Java 21 설치 및 PATH 구성 후 아래 명령을 실행했다.

```cmd
npx firebase emulators:exec --only firestore,storage "npm --prefix functions run test:rules:r5"
```

결과:

- PASS: Firestore allow case 통과.
- PASS: Firestore cross-user deny case 통과.
- PASS: `usageEvents` uid mismatch deny 통과.
- PASS: Storage cross-user deny 통과.
- PASS: Storage contentType deny 통과.
- PASS: index static assertions 통과.
- PASS: Firestore/Storage emulator 정상 시작 및 종료.
- 참고: `PERMISSION_DENIED` 로그는 deny-case 테스트의 정상 차단 결과다.

### 8.2 수동/앱 회귀 체크리스트

| 영역 | allow case | deny/guard case | 판정 기준 |
|---|---|---|---|
| Cloud upload | Standard user가 clip upload 완료 | Free/expired user 신규 upload 차단 | local 원본 보존, metadata uid 본인 |
| Cloud restore/download | 본인 Cloud clip restore | 다른 uid `storagePath` 접근 불가 | prefix 검증 실패 시 downloadUrl fallback 미사용 |
| Cloud library query | 본인 `videos` 목록 표시 | `uid` filter 없는 broad query 없음 | 다른 사용자 metadata 미노출 |
| Trash/restore | 본인 metadata tombstone/restore update | 다른 uid doc update 불가 | Storage object 즉시 삭제 없음 |
| Usage accounting | upload 완료 event 1회 create | event uid mismatch/create/delete deny | storageUsage 중복 증가/차감 없음 |
| Profile image | 본인 profile image upload | 다른 uid profile path upload/read deny | image type/size 제한 유지 |
| Vlog project metadata | 본인 `vlog_projects` upsert/read/delete | 다른 uid project read/update deny | uid field 불변 유지 |

### 8.3 배포 명령과 rollback

배포 전 최종 확인 명령:

```cmd
npx firebase emulators:exec --only firestore,storage "npm --prefix functions run test:rules:r5"
```

배포 명령은 자동 실행하지 않는다. 별도 승인 후에만 아래 대상을 분리해 배포한다.

```cmd
npx firebase deploy --only firestore:rules
npx firebase deploy --only firestore:indexes
npx firebase deploy --only storage:rules
```

Rollback 기준:

- rules 배포 후 본인 Cloud upload/restore가 permission denied로 회귀하면 [firebase/firestore.rules](../firebase/firestore.rules)의 직전 버전으로 되돌린다.
- index 배포 후 query 실패가 계속되면 Firebase Console의 generated index link와 현재 [firebase/firestore.indexes.json](../firebase/firestore.indexes.json)을 대조한다.
- Storage rules는 변경하지 않았으므로 Storage 회귀가 발생하면 이번 R5 변경보다는 기존 client path/contentType 회귀를 우선 의심한다.

## 9. 변경 파일 목록

| 파일 | 변경 내용 |
|---|---|
| [firebase/firestore.rules](../firebase/firestore.rules) | `users/{uid}/usageEvents/{eventId}` 본인 uid 기반 rules 추가, delete deny |
| [firebase/firestore.indexes.json](../firebase/firestore.indexes.json) | `videos` 현재 query용 최소 composite index 4개 추가 |
| [functions/package.json](../functions/package.json) | `test:rules:r5` script와 `@firebase/rules-unit-testing` dev dependency 추가 |
| [functions/package-lock.json](../functions/package-lock.json) | rules test dependency lock 갱신 |
| [functions/test/r5_rules_index.test.js](../functions/test/r5_rules_index.test.js) | emulator allow/deny 및 index static assertion 테스트 추가 |
| [plans/cloud_clip_r5_firebase_rules_index_validation_report_v1.md](cloud_clip_r5_firebase_rules_index_validation_report_v1.md) | 본 검증 보고서 생성 |

## 10. 남은 리스크와 후속 승인 필요 항목

| 리스크 | 상태 | 후속 조치 |
|---|---|---|
| Java PATH/버전 문제 | resolved | Java 21 설치 및 PATH 구성 후 emulator 실행 성공 |
| Firebase emulator rules/index 테스트 | PASS | `npx firebase emulators:exec --only firestore,storage "npm --prefix functions run test:rules:r5"` 통과 |
| `@firebase/rules-unit-testing` 추가로 npm audit 기존/신규 취약점 표시 | 남은 리스크 | 별도 dependency audit 작업에서 `npm audit` 결과 검토 |
| `users/{uid}` write rule은 여전히 넓은 본인 write | 남은 리스크 | 별도 rules hardening 작업에서 user profile/subscription field-level 검증 검토 |
| 실제 앱 회귀 테스트 미수행 | 남은 리스크 | Cloud upload/restore/library query/trash/usage accounting/profile image/vlog project metadata 수동 회귀 테스트 필요 |
| firebase deploy 미수행 | 의도적 보류 | 자동 실행 금지. 별도 승인 후 rules/index/storage rules를 분리 배포 |

## 11. 최종 판정

R5 범위에서 필요한 최소 변경과 emulator 검증은 PASS다. 변경은 uid 소유권을 완화하지 않고, `usageEvents` 하위 컬렉션을 본인 uid에 고정하며, 현재 Flutter query에 필요한 `videos` composite index만 추가했다. Storage rules는 변경하지 않아 prefix/contentType/size 제한을 유지했다.

Java 21 설치 및 PATH 구성 후 Firestore/Storage emulator가 정상 시작/종료했고, `npx firebase emulators:exec --only firestore,storage "npm --prefix functions run test:rules:r5"` 실행 결과 `[R5 rules/index] allow/deny rules tests passed` 및 `Script exited successfully (code 0)`를 확인했다. 로그의 `PERMISSION_DENIED`는 deny-case 테스트에서 기대한 정상 차단 결과다.

배포 전 남은 리스크는 `npm audit` 검토, `users/{uid}` field-level hardening, 실제 앱 회귀 테스트로 분리한다. `firebase deploy`는 아직 자동 실행하지 않았으며, 별도 승인 후 분리 배포해야 한다.

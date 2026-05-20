# Cloud Clip R3 Local QA Fixture Setup Plan v1

## 1. Test Account Requirements

R3 local manual QA는 운영 사용자 데이터 없이 non-production 테스트 계정만 사용한다.

필수 계정 조건:

- Firebase Auth에 로그인 가능한 테스트 계정.
- 운영 사용자 uid, 운영 이메일, 실제 결제 토큰을 사용하지 않는다.
- 계정 이름/이메일은 QA 전용임을 명확히 식별할 수 있어야 한다.
- 테스트 계정 uid는 QA 결과 문서에 전체값을 남기지 않고 앞/뒤 일부만 마스킹한다.
- 테스트 계정은 기존 사용자의 Cloud clip, Storage object, Firestore document를 참조하지 않는다.
- 앱이 지원하는 실제 로그인 경로를 사용한다. Firebase Auth 세션을 SharedPreferences 조작으로 위조하지 않는다.

권장 계정:

| 계정 | 목적 | 상태 |
|---|---|---|
| `moa-r3-paid-qa` | active paid, grace, expired 재현 | 동일 계정을 재사용하되 SharedPreferences tier/history만 주입 |
| `moa-r3-free-qa` | signed-in free never paid 재현 | purchaseDate/productId 없이 signed-in 상태 유지 |

로그인 후 확인할 값:

- Firebase Auth current user가 존재한다.
- `UserStatusManager.userId` 또는 로그의 uid가 테스트 계정 uid와 일치한다.
- `AuthService.isGuest == false`.
- `FlutterSharedPreferences.xml`에 `flutter.3s_auth_mode_guest`가 없거나 `false`다.

## 2. Test Cloud Clip Fixture Requirements

R3-MQA-02/03/07/08/09는 기존 Cloud clip이 있어야 한다.

fixture 생성 원칙:

- active paid 상태에서 테스트 계정으로 직접 Cloud upload를 1회 수행해 fixture를 만든다.
- 운영 계정의 기존 Cloud clip을 복사하거나 참조하지 않는다.
- Cloud copy 기능은 사용하지 않는다.
- Storage object 삭제는 QA 중 수행하지 않는다.
- Firestore schema를 변경하지 않는다. 테스트 표시용 임의 field를 추가하지 않는다.

fixture 준비 절차:

1. Android emulator 또는 테스트 기기에서 앱 실행.
2. `moa-r3-paid-qa` 테스트 계정으로 로그인.
3. SharedPreferences를 active paid 상태로 주입한다.
4. 앱 재시작.
5. Library의 테스트 local clip 1개를 Cloud upload한다.
6. Firestore `users/{maskedUid}/videos`에서 새 metadata 문서 id를 기록한다.
7. Storage `users/{maskedUid}/videos/{videoId}/{fileName}` object 경로를 기록한다.
8. CloudBackupScreen에서 해당 clip이 목록에 보이는지 확인한다.

기록해야 할 fixture 정보:

| 항목 | 기록 방식 |
|---|---|
| 테스트 계정 uid | 마스킹 |
| videoId | 전체 기록 가능하나 실제 uid/token과 연결하지 않음 |
| Firestore path | `users/{maskedUid}/videos/{videoId}` |
| Storage path | `users/{maskedUid}/videos/{videoId}/{fileName}` |
| 생성 시각 | QA 문서에 기록 |
| 원본 local clip | tutorial/test clip만 사용 |

## 3. Safe SharedPreferences State Injection Method

R3 v1 grace는 로컬 SharedPreferences 기반이다. 상태 주입은 테스트 앱 데이터에만 수행한다.

Android 저장 위치:

```text
/data/user/0/com.dk.three_sec/shared_prefs/FlutterSharedPreferences.xml
```

Flutter SharedPreferences XML key prefix:

| Dart key | Android XML key |
|---|---|
| `3s_user_tier` | `flutter.3s_user_tier` |
| `3s_purchase_date` | `flutter.3s_purchase_date` |
| `3s_product_id` | `flutter.3s_product_id` |
| `3s_user_id` | `flutter.3s_user_id` |
| `3s_next_user_tier` | `flutter.3s_next_user_tier` |
| `3s_next_tier_effective_at` | `flutter.3s_next_tier_effective_at` |
| `3s_auth_mode_guest` | `flutter.3s_auth_mode_guest` |

Value format:

| Field | XML type | Value example |
|---|---|---|
| tier | string | `UserTier.standard`, `UserTier.premium`, or absent/free |
| purchaseDate | long | Unix epoch milliseconds |
| productId | string | `3s_standard_monthly`, `3s_standard_annual`, `3s_premium_monthly`, `3s_premium_annual` |
| userId | string | signed-in Firebase uid |
| guest mode | boolean | `false` for signed-in QA |

Safe injection protocol:

1. Sign in through the app with the non-production test account.
2. Confirm app is not in guest mode.
3. Force stop the app before editing prefs.
4. Pull a backup copy of `FlutterSharedPreferences.xml`.
5. Edit only R3 subscription keys in a temp copy.
6. Push the temp copy back with `run-as com.dk.three_sec`.
7. Restart the app.
8. Confirm `UserStatusManager` initialization log shows expected tier/product/user id.
9. After each scenario, restore from the backup or inject the next scenario state explicitly.

Example command skeleton:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb shell am force-stop com.dk.three_sec
& $adb shell run-as com.dk.three_sec cp shared_prefs/FlutterSharedPreferences.xml shared_prefs/FlutterSharedPreferences.r3qa.bak.xml
& $adb shell run-as com.dk.three_sec cat shared_prefs/FlutterSharedPreferences.xml > C:\tmp\r3qa_FlutterSharedPreferences_before.xml
```

The actual XML edit should be done on a copied file and reviewed before pushing.

Do not edit:

- Firebase Auth internal files.
- FCM/Firebase messaging preference files.
- local index schema keys except as evidence observation.
- production app package data.

## 4. Active Paid State Setup

Purpose:

- R3-MQA-01.
- Fixture creation for later grace/expired scenarios.

Required state:

- Signed-in test account.
- `flutter.3s_auth_mode_guest=false` or absent.
- `flutter.3s_user_id=<testUid>`.
- `flutter.3s_user_tier=UserTier.standard` or `UserTier.premium`.
- `flutter.3s_product_id=3s_standard_monthly` or another valid `3s_*` product id.
- `flutter.3s_purchase_date=<epochMillis that makes estimatedExpiryAt in the future>`.
- Remove pending tier keys unless testing cancellation:
  - `flutter.3s_next_user_tier`
  - `flutter.3s_next_tier_effective_at`

Recommended date:

- Monthly product: purchaseDate = now minus 5 days.
- Annual product: purchaseDate = now minus 30 days.

Expected helper state:

| Helper | Expected |
|---|---|
| `isStandardOrAbove()` | true |
| `canStartNewCloudWrite()` | true |
| `canReadExistingCloudClips()` | true |
| `isInCloudReadGrace()` | false |

QA after setup:

- Upload a test local clip.
- Verify Firestore metadata and Storage object are created for the test account only.
- Verify CloudBackupScreen list/download and Profile stats work.

## 5. Expired Within Grace Setup

Purpose:

- R3-MQA-02.
- R3-MQA-06.
- R3-MQA-07.
- R3-MQA-08.
- R3-MQA-09.
- R3-MQA-10 grace branch.

Required prerequisite:

- Existing test Cloud clip fixture already created under the signed-in test account.

Recommended state:

- Signed-in test account.
- `flutter.3s_auth_mode_guest=false` or absent.
- `flutter.3s_user_id=<testUid>`.
- `flutter.3s_user_tier` absent or `UserTier.free` equivalent by removing the key.
- `flutter.3s_product_id=3s_standard_monthly`.
- `flutter.3s_purchase_date=<epochMillis whose inferred monthly expiry is after now minus 30 days and before/equal now>`.
- Remove pending tier keys.

Concrete date guidance:

- Monthly product: purchaseDate = now minus 35 days.
- Expected inferred expiry is roughly now minus 5 days.
- Expected grace ends roughly 25 days in the future.

Expected helper state:

| Helper | Expected |
|---|---|
| `isStandardOrAbove()` | false |
| `lastKnownPaidExpiryAt` | non-null and in the past |
| `cloudReadGraceEndsAt` | non-null and in the future |
| `canStartNewCloudWrite()` | false |
| `canReadExistingCloudClips()` | true |
| `isInCloudReadGrace()` | true |

QA after setup:

- Existing Cloud list/read visible.
- New upload, auto upload, queue upload blocked.
- Error/reason should be `subscription_expired` for new write.
- CloudBackupScreen shows read-only/grace 안내.
- Existing Cloud download/restore works.
- Cloud metadata lifecycle write is blocked or skipped unless active write permission exists.

## 6. Expired After Grace Setup

Purpose:

- R3-MQA-03.
- R3-MQA-10 expired branch.

Required prerequisite:

- Existing test Cloud clip fixture under the signed-in test account.

Recommended state:

- Signed-in test account.
- `flutter.3s_auth_mode_guest=false` or absent.
- `flutter.3s_user_id=<testUid>`.
- `flutter.3s_user_tier` absent or free.
- `flutter.3s_product_id=3s_standard_monthly`.
- `flutter.3s_purchase_date=<epochMillis whose inferred monthly expiry is older than 30 days>`.
- Remove pending tier keys.

Concrete date guidance:

- Monthly product: purchaseDate = now minus 70 days.
- Expected inferred expiry is roughly now minus 40 days.
- Expected grace ended roughly 10 days ago.

Expected helper state:

| Helper | Expected |
|---|---|
| `isStandardOrAbove()` | false |
| `lastKnownPaidExpiryAt` | non-null and older than 30 days |
| `cloudReadGraceEndsAt` | non-null and in the past |
| `canStartNewCloudWrite()` | false |
| `canReadExistingCloudClips()` | false |
| `isInCloudReadGrace()` | false |

QA after setup:

- Cloud list/read/download/restore blocked.
- New upload blocked.
- Existing Firestore metadata and Storage object are not deleted.
- Profile Cloud stats inactive or `-`/0.

## 7. Signed-In Free Never Paid Setup

Purpose:

- R3-MQA-04.
- R3-MQA-10 free branch.

Required state:

- Signed-in test account.
- `flutter.3s_auth_mode_guest=false` or absent.
- `flutter.3s_user_id=<testUid>`.
- Remove all paid history keys:
  - `flutter.3s_user_tier`
  - `flutter.3s_purchase_date`
  - `flutter.3s_product_id`
  - `flutter.3s_next_user_tier`
  - `flutter.3s_next_tier_effective_at`

Expected helper state:

| Helper | Expected |
|---|---|
| `isStandardOrAbove()` | false |
| `lastKnownPaidExpiryAt` | null |
| `cloudReadGraceEndsAt` | null |
| `canStartNewCloudWrite()` | false |
| `canReadExistingCloudClips()` | false |
| `isInCloudReadGrace()` | false |

QA after setup:

- New Cloud upload blocked.
- CloudBackupScreen blocked with tier-required style 안내.
- Profile Cloud stats inactive or `-`/0.
- No grace messaging should appear because there is no paid history.

## 8. Firestore Before-After Capture Method

Firestore evidence must be limited to the test account.

Before each scenario:

1. Record masked uid.
2. Open Firebase Console or approved dev/test project tooling.
3. Navigate to:

```text
users/{testUid}/videos
```

4. Capture:
   - document count,
   - fixture videoId,
   - relevant metadata fields,
   - `updatedAt` or equivalent timestamp if present.

After each scenario:

1. Capture the same collection/document view.
2. Compare document count and fixture document fields.
3. Record whether a new metadata document was created.
4. Record whether fixture metadata changed.
5. Record whether any purge/delete happened.

Expected by scenario:

| Scenario | Firestore expectation |
|---|---|
| R3-MQA-01 active paid upload | new test metadata may be created |
| R3-MQA-02 grace | no new upload metadata from blocked write; existing metadata readable |
| R3-MQA-03 after grace | no new metadata; no delete |
| R3-MQA-04 free never paid | no new metadata |
| R3-MQA-06 grace upload/queue block | no new metadata from blocked write |
| R3-MQA-07 grace read-only | existing metadata readable; no write CTA metadata |
| R3-MQA-08 grace restore/download | no delete; only local restore expected |
| R3-MQA-09 metadata lifecycle | no unnecessary lifecycle write while in grace |
| R3-MQA-10 Profile stats | read behavior matches access policy |

Do not:

- Add test marker fields to existing schema.
- Edit Firestore documents to force state.
- Delete documents during R3 QA.
- Use operating user uid.

## 9. Storage Before-After Capture Method

Storage evidence must be limited to the test account path.

Before each scenario:

1. Navigate to the fixture path:

```text
users/{testUid}/videos/{videoId}/{fileName}
```

2. Capture object existence, size, created/updated metadata if visible.
3. Record object count under `users/{testUid}/videos/{videoId}`.

After each scenario:

1. Recheck the same path.
2. Confirm object still exists unless the scenario is active paid upload creating a new test object.
3. Confirm no extra object was created during blocked write scenarios.
4. Confirm no object was deleted during read/download/restore or blocked scenarios.

Expected by scenario:

| Scenario | Storage expectation |
|---|---|
| R3-MQA-01 active paid upload | new test object may be created |
| R3-MQA-02 grace write block | no new object |
| R3-MQA-03 after grace | no new object and no deletion |
| R3-MQA-04 free never paid | no new object |
| R3-MQA-06 grace upload/queue block | no new object |
| R3-MQA-08 grace restore/download | fixture object remains |
| R3-MQA-09 lifecycle write minimum | fixture object remains; no delete |

Do not:

- Delete Storage object during R3 QA.
- Rename/move Storage object.
- Create Cloud copy.
- Use object paths outside the test uid.

## 10. Rerun Plan for R3-MQA-01~04 and R3-MQA-06~10

Recommended rerun order:

| Order | Scenario | Setup | Key evidence |
|---:|---|---|---|
| 1 | R3-MQA-04 signed-in free never paid | signed-in free, no paid keys | upload blocked, CloudBackup blocked, Profile stats inactive |
| 2 | R3-MQA-01 active paid | active paid state | upload success, fixture created, Cloud list/download, Profile stats |
| 3 | R3-MQA-02 expired within grace | same account, free with preserved purchase/product history | list/read allowed, upload blocked |
| 4 | R3-MQA-07 grace read-only 안내 | same grace state | CloudBackup read-only 안내 |
| 5 | R3-MQA-08 grace restore/download | same grace state | local restore, no Storage delete |
| 6 | R3-MQA-09 grace metadata lifecycle write minimum | same grace state | Firestore before/after unchanged for lifecycle writes |
| 7 | R3-MQA-06 grace Library upload/auto upload block | same grace state | button/queue blocked, no new object |
| 8 | R3-MQA-10 Profile stats matrix | active, grace, expired, free snapshots | Profile display matches `canReadExistingCloudClips()` |
| 9 | R3-MQA-03 expired after grace | after-grace state | Cloud read/download blocked, no delete |

For each scenario record:

- Date.
- App version.
- Firebase environment.
- Account type.
- Scenario ID.
- Preconditions.
- Steps executed.
- Expected result.
- Actual result.
- Verdict.
- Evidence path or description.
- Follow-up action.

## 11. Cleanup Policy

R3 local QA cleanup must not violate the current prohibition against Storage deletion.

During R3 QA:

- Do not delete Storage objects.
- Do not delete Firestore metadata.
- Do not purge account data.
- Do not run migration/backfill.
- Do not change rules/index.

Allowed cleanup during the same QA session:

- Restore emulator SharedPreferences backup for the test app.
- Force-stop/restart the test app.
- Clear only local emulator app data if it does not affect Firestore/Storage and only after evidence is captured.

Deferred cleanup:

- Test Cloud fixture cleanup is a separate task.
- It requires explicit approval because it may delete Firestore/Storage test data.
- Cleanup plan must identify exact test uid, videoId, and object path.
- Cleanup must not target broad prefixes or production user data.

Recommended default:

- Keep test Cloud fixture for repeatable R3 regression QA.
- Mark the fixture path in QA docs outside the app schema rather than adding Firestore fields.

## 12. Go/No-Go Criteria

Go to rerun R3 local manual QA only if all conditions are true:

- Non-production signed-in Firebase Auth test account is ready.
- Test account uid is recorded and masked.
- Existing test Cloud clip fixture is created or R3-MQA-01 is scheduled to create it first.
- SharedPreferences backup/restore procedure is rehearsed on the test app package.
- Active, grace, after-grace, and signed-in free states have exact purchaseDate epoch values prepared.
- Firestore before-after capture access is available for the test uid.
- Storage before-after capture access is available for the test uid path.
- QA operator confirms no operating user data will be used.

No-go if any condition is true:

- Only guest mode is available.
- No signed-in test account exists.
- Existing Cloud clip fixture is missing and active paid upload cannot be run.
- SharedPreferences state cannot be safely backed up/restored.
- Firebase Console/tooling access cannot be limited to the test uid.
- Any step requires Firebase rules/index/schema changes.
- Any step requires Storage deletion, Cloud copy implementation, migration/backfill, npm audit fix, deploy, or unrelated cleanup.

Release implication:

- Until this fixture setup is complete and R3-MQA-01~04 plus R3-MQA-06~10 are rerun, R3 local manual QA remains partially BLOCKED.

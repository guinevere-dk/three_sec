# R3 Upload Fixture Capture Result v1

작성일: 2026-05-19

범위:
- 사용자가 local-only fixture의 Cloud upload 버튼을 직접 누른 직후 상태 전환과 로그를 count-only로 확인한다.
- raw local path, uid, email, token, order id, provider raw value는 기록하지 않는다.
- Firestore/Storage 직접 수정, Firebase rules/index/schema 변경, migration/backfill, Storage 삭제, Cloud copy, deploy는 수행하지 않았다.

## Preconditions

이전 산출물:
- `plans/cloud_clip_r3_local_only_fixture_creation_result_v1.md`

업로드 전 상태:

| 항목 | 값 |
| --- | ---: |
| active tier | `UserTier.standard` |
| all filter visible clips | 8 |
| `기기` filter visible clips | 1 |
| `cloud_synced_paths` real local marker count | 7 |
| derived `localOnlyCount` | 1 |
| derived `cloudSyncedLocalCount` | 7 |
| derived `uploadableCount` | 1 |
| selected fixture count | 1 |
| expected transfer action | upload / `cloud_upload_rounded` |

## Capture Caveat

사용자가 "upload 버튼을 눌렀다"고 먼저 보고했다.

따라서 이번 capture는 이상적인 절차인 "AI가 `logcat -c` 후 사용자가 클릭" 형태가 아니다. Post-click logcat과 state transition evidence를 수집했다.

이 제한 때문에 CloudService raw call-flow evidence는 `BLOCKED/PARTIAL`로 기록하고, local state transition evidence는 별도로 판정한다.

## Post-Click Logcat Count

Post-click logcat count-only scan:

| keyword | count |
| --- | ---: |
| `CloudService` | 0 |
| `uploadVideoImmediate` | 0 |
| `uploadVideo` | 0 |
| `_moveSelectedLocalToCloud` | 0 |
| `_moveSelectedLocalToCloudInBackground` | 0 |
| `Storage putFile` | 0 |
| `putFile` | 0 |
| `uploadStatus` | 0 |
| `completed` | 0 |
| `markClipCloudSynced` | 0 |
| `cloud_synced_paths` | 0 |
| `canStartNewCloudWrite` | 0 |
| `subscription_expired` | 0 |
| `tier_required` | 0 |
| `auth uid missing` | 0 |
| `permission denied` | 0 |
| `immediate upload metadata` | 0 |
| `upload_completed` | 0 |

Interpretation:
- Log-based upload call evidence was not captured.
- This is likely due to the missing pre-click logcat clear/action window and/or release/log behavior.
- No gate block keywords were observed.

## State Transition Evidence

Post-click SharedPreferences count-only evidence:

| 항목 | before upload | after upload |
| --- | ---: | ---: |
| tier | `UserTier.standard` | `UserTier.standard` |
| `cloud_synced_paths` real local marker count | 7 | 8 |
| `cloud_synced_paths` `cloud_only://` marker count | 5 | 7 |

Post-click UI evidence:

| UI state | result |
| --- | ---: |
| `기기` filter visible clip count | 0 |
| `전체` filter visible clip count | 8 |
| `전체` filter selected after check | true |
| album `8 Clips` label present | true |

Derived state after upload:

| count | value |
| --- | ---: |
| `localFileCount` | 8 |
| `localOnlyCount` | 0 |
| `cloudSyncedLocalCount` | 8 |
| `cloudOnlyCount` | 0 current visible set |
| `pendingUploadCount` | 0 |
| `failedUploadCount` | 0 |
| `failedDownloadCount` | 0 |
| `uploadableCount` | 0 |

Interpretation:
- The single local-only fixture moved out of the `기기`/local-only filter.
- The real local marker count increased from 7 to 8.
- The visible all-filter count remains 8.
- This is consistent with the fixture transitioning from `localOnly` to `cloudSyncedLocal`.

## Sensitive Log Gate

Final count-only sensitive scan:

| 항목 | count |
| --- | ---: |
| sensitive-like total | 0 |
| app_or_flutter | 0 |
| sdk_or_system | 0 |

Verdict:
- app-controlled sensitive log gate: PASS
- Raw sensitive values were not printed.

## Verdict

| 항목 | verdict | reason |
| --- | --- | --- |
| User-performed upload click | PASS | user reported button press |
| Upload call log evidence | BLOCKED/PARTIAL | no pre-click `logcat -c`; post-click CloudService/upload hits were 0 |
| Gate block evidence | PASS | no subscription/auth/permission block keyword hits |
| Local state transition | PASS | real local sync marker count 7 -> 8 |
| Fixture no longer local-only | PASS | `기기` filter count 1 -> 0 |
| Derived post-upload state | PASS | `cloudSyncedLocalCount=8`, `uploadableCount=0` |
| Sensitive app log gate | PASS | app_or_flutter sensitive-like count 0 |

Overall:
- R3 upload fixture state transition is PASS.
- Firestore/Storage before-after evidence is still needed for full R3 signed-in QA completion because this capture did not include direct Firestore/Storage evidence or log-based upload call evidence.

Recommended next step:
1. Do not delete or mutate Storage/Firestore.
2. Capture Firestore `videos` and Storage object before/after using read-only, redacted/count-only evidence if tooling is available.
3. If another upload capture is required, first create another verified local-only fixture, then run `adb logcat -c` before the user presses upload.

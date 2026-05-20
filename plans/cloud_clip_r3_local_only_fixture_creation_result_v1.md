# R3 Local-Only Fixture Creation Result v1

작성일: 2026-05-19

범위:
- R3 Cloud upload fixture QA를 재개하기 위한 새 local-only fixture 생성 및 검증
- raw local path, uid, email, token, order id, provider raw value는 기록하지 않는다.
- 기존 7개 clip 상태와 `cloud_synced_paths`는 수동 변경하지 않는다.
- Firestore/Storage 직접 수정, Firebase rules/index/schema 변경, migration/backfill, Storage 삭제, Cloud copy, deploy는 수행하지 않았다.

## 1. Starting State

이전 runtime diagnostics 기준:

| 항목 | 값 |
| --- | ---: |
| current visible Library clips | 7 |
| `cloudSyncedLocalCount` | 7 |
| `localOnlyCount` | 0 |
| `uploadableCount` | 0 |
| R3 upload fixture QA | NO-GO |

판정:
- 기존 7개 clip은 upload fixture로 사용하지 않는다.

## 2. Free Never-Paid Injection

절차:
1. 앱 완전 종료: `am force-stop com.dk.three_sec`
2. SharedPreferences XML backup 생성
3. 구독 관련 key만 free never-paid 상태로 변경
4. `cloud_synced_paths`는 보존
5. 앱 재실행

Sanitized evidence:

| 항목 | 결과 |
| --- | --- |
| backup before | `C:\tmp\r3_fixture_prefs_before_20260519_152025.xml` |
| backup after free | `C:\tmp\r3_fixture_prefs_free_20260519_152025.xml` |
| tier | `UserTier.free` |
| product id | absent |
| purchase date | absent |
| `cloud_synced_paths` entry | present |
| sensitive pattern count after free launch | 0 |

## 3. User-Created Local Fixture

사용자가 free 상태에서 새 2초 clip을 생성했다.

중요:
- AI는 raw fixture path를 출력하지 않았다.
- AI는 기존 7개 clip이나 `cloud_synced_paths`를 수동 변경하지 않았다.
- Free 상태이므로 신규 Cloud auto-upload가 발생하지 않아야 하는 조건에서 생성했다.

After fixture creation count-only evidence:

| 항목 | 값 |
| --- | ---: |
| tier | `UserTier.free` |
| visible Library clips | 8 |
| `cloud_synced_paths` real local marker count | 7 |
| `cloud_synced_paths` `cloud_only://` marker count | 5 |

Derived count:

| count | value |
| --- | ---: |
| `localFileCount` | 8 |
| `localOnlyCount` | 1 |
| `cloudSyncedLocalCount` | 7 |
| `cloudOnlyCount` | 0 current visible set |
| `pendingUploadCount` | 0 |
| `failedUploadCount` | 0 |
| `failedDownloadCount` | 0 |
| `uploadableCount` | 1 |

판정:
- 새 fixture는 `localOnly` / uploadable 상태로 생성됐다.

## 4. Active Standard Restore

절차:
1. 앱 완전 종료
2. SharedPreferences XML backup 생성
3. active Standard state 주입
4. `cloud_synced_paths` 보존
5. 앱 재실행

Sanitized evidence:

| 항목 | 결과 |
| --- | --- |
| backup before Standard | `C:\tmp\r3_fixture_prefs_before_standard_20260519_152519.xml` |
| backup after Standard | `C:\tmp\r3_fixture_prefs_standard_20260519_152519.xml` |
| tier | `UserTier.standard` |
| product id | present |
| purchase date | present |
| `cloud_synced_paths` real local marker count | 7 |

Post-relaunch runtime evidence:

| 항목 | 값 |
| --- | ---: |
| tier standard log count | 212 |
| tier free log count | 0 |
| visible Library clips after entering album | 8 |
| `기기` filter visible clip count | 1 |
| `기기` filter selected | true |

Derived count after Standard:

| count | value |
| --- | ---: |
| `localFileCount` | 8 |
| `localOnlyCount` | 1 |
| `cloudSyncedLocalCount` | 7 |
| `cloudOnlyCount` | 0 current visible set |
| `pendingUploadCount` | 0 |
| `failedUploadCount` | 0 |
| `failedDownloadCount` | 0 |
| `uploadableCount` | 1 |

판정:
- active Standard 복귀 후에도 새 local-only fixture는 uploadable 상태를 유지했다.

## 5. Upload Action Readiness

UI count-only evidence:

| 항목 | 결과 |
| --- | --- |
| `기기` filter visible clip count | 1 |
| local-only fixture selected | true |
| `1개 선택됨` present | true |
| `Select All` present | true |
| selection panel/button area present | true |

Reducer verification:

Command:

```powershell
flutter test test\library_clip_transfer_action_test.dart
```

Result:

```text
All tests passed. 6 tests.
```

Relevant reducer cases:
- `localOnly` => upload action / `cloud_upload_rounded`
- `failedUpload` => upload retry / `cloud_upload_rounded`
- `cloudSyncedLocal` => cloudDone / `cloud_done_rounded`

판정:
- 현재 `기기` filter에 보이는 단일 fixture는 derived `localOnly` 후보 1개다.
- 해당 fixture만 선택한 상태에서 Phase 2A reducer 기준 Cloud transfer action은 upload / `cloud_upload_rounded`다.
- AI는 upload 버튼을 누르지 않았다.

## 6. Sensitive Log Gate

Final count-only log scan:

| 항목 | count |
| --- | ---: |
| sensitive-like total | 3 |
| app_or_flutter | 0 |
| sdk_or_system | 3 |

판정:
- app-controlled sensitive log gate: PASS
- SDK/system sensitive-like hits are WARN only; raw values were not printed.

## 7. Verdict

R3 Cloud upload fixture capture 재개 가능 여부: GO

조건:
- signed-in manual Google login state maintained.
- active Standard state restored.
- local-only fixture exists.
- `uploadableCount >= 1`.
- existing 7 cloud-synced clips were not modified.
- `cloud_synced_paths` was not manually deleted or cleaned.
- app-controlled sensitive log gate remains clean.

다음 capture 시작 조건:
1. 현재 Library `기기` filter에 보이는 단일 fixture를 유지한다.
2. logcat clear.
3. 사용자가 하단 Cloud transfer upload 버튼을 직접 누른다.
4. 10-20초 대기.
5. Cloud upload logs, Firestore metadata, Storage upload evidence를 count-only/redacted 방식으로 수집한다.

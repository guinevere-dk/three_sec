# Cloud Clip R3 Local Manual QA Result v1

## 1. Summary

- Date: 2026-05-19
- App build/version: `1.3.6+136` (`pubspec.yaml`), Profile UI 표시 `v1.3.6`
- Device: Android emulator `emulator-5554`, Pixel 9, Android 15 API 35
- Firebase environment: local Android emulator app run. Firebase test account was not available, and Firestore/Storage data QA was not exercised.
- Billing environment: Store sandbox not used.
- Test data scope: emulator-local guest session and tutorial sample clips only.
- Production user data: not used.
- Code/Firebase/deploy changes: none.

Verdict summary:

| Scenario | Verdict | Notes |
|---|---|---|
| R3-MQA-01 active Standard/Premium | BLOCKED | No signed-in paid test account and no prepared test Cloud clip |
| R3-MQA-02 expired within 30-day grace | BLOCKED | No signed-in test account, existing Cloud clip, or safe local state injection harness |
| R3-MQA-03 expired after grace | BLOCKED | Same blocker as R3-MQA-02 |
| R3-MQA-04 free never paid | BLOCKED | Requires signed-in free test account; guest-only run is covered separately |
| R3-MQA-05 guest mode | PASS | Guest entry, CloudBackup block, Profile Cloud stats inactive, Library Cloud action disabled/blocked evidence collected |
| R3-MQA-06 grace Library upload/auto upload 차단 | BLOCKED | Requires expired-within-grace state and upload/queue setup |
| R3-MQA-07 grace CloudBackupScreen read-only 안내 | BLOCKED | Requires expired-within-grace state and existing Cloud clip |
| R3-MQA-08 grace Cloud restore/download | BLOCKED | Requires expired-within-grace state and existing Cloud clip |
| R3-MQA-09 grace metadata lifecycle write 최소화 | BLOCKED | Requires expired-within-grace state plus Firestore before/after access |
| R3-MQA-10 Profile Cloud stats 표시 | BLOCKED | Guest/free display checked, but active/grace/expired state matrix not executable |

Supporting automated check:

```cmd
flutter test test\user_status_manager_r3_test.dart
```

Result:

- PASS
- `00:00 +5: All tests passed!`

This unit test result is supporting evidence only. It does not replace the blocked manual Cloud/Firebase scenarios.

## 2. Environment Evidence

Commands executed:

```cmd
flutter devices
flutter emulators
flutter run -d emulator-5554 --debug --dart-define=GUEST_LOGIN_ENABLED=true
```

Observed:

- Connected devices included `sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64 • Android 15 (API 35)`.
- Available emulator: `Pixel_9`.
- App package installed/running: `com.dk.three_sec`.
- Foreground activity confirmed: `com.dk.three_sec/.MainActivity`.

Evidence files:

| Evidence | Path |
|---|---|
| Launch/login UI dump | `C:\tmp\r3_mqa_window.xml` |
| App launch screenshot | `C:\tmp\r3_mqa_launch2.png` |
| Guest permission dialog dump | `C:\tmp\r3_mqa_guest_permission_window.xml` |
| Guest Library after notification denial | `C:\tmp\r3_mqa_guest_after_deny_window.xml` |
| Guest Profile Cloud stats dump | `C:\tmp\r3_mqa_guest_profile_after_skip_window.xml` |
| Guest CloudBackup blocked screen dump | `C:\tmp\r3_mqa_guest_cloud_tap_window.xml` |
| Guest Library selected clip action state dump | `C:\tmp\r3_mqa_guest_clip_longpress_window.xml` |

Relevant log evidence:

```text
[CloudService] ✗ 게스트 모드에서는 인증 기반 조회가 비활성입니다.
[CloudService] ⛔ 큐 복구 스킵: 로그인 사용자 미확인
[Main][ProfileTab][Diag] after_select selectedIndex=2 tier=UserTier.free productId=null
[UserStatusManager] 초기화 완료: tier=UserTier.free, productId=null, userId=guest_... , nextTier=null, nextTierEffectiveAt=null
```

The guest uid is intentionally masked.

## 3. Scenario Results

### R3-MQA-01 Active Standard/Premium

- Account type: active Standard/Premium
- Preconditions: signed-in test account, active paid local state, test local clip, development Firebase, existing Cloud read/write access.
- Steps executed:
  - Environment readiness checked.
  - Android emulator launched and app foreground verified.
  - No paid signed-in test account was available, so upload/read/download steps were not executed.
- Expected result: upload allowed, Storage object and Firestore metadata created, Cloud list/read/download/restore allowed, Profile Cloud stats displayed.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: `flutter devices`, `flutter emulators`, app foreground evidence in section 2.
- Follow-up action: prepare a non-production signed-in Standard/Premium test account and test clip; rerun this scenario.

### R3-MQA-02 Expired Within 30-Day Grace

- Account type: expired within grace
- Preconditions: signed-in test account, existing Cloud clip, paid productId/purchaseDate history, local free/grace state within 30 days.
- Steps executed:
  - Environment readiness checked.
  - No signed-in test account, existing Cloud clip, or approved state injection harness was available.
- Expected result: existing Cloud list/read allowed, new upload blocked with `subscription_expired`, download/restore allowed, no new Storage object.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no safe Cloud test fixture available.
- Follow-up action: create a dev/test account with at least one Cloud clip and a documented SharedPreferences state injection procedure for R3 grace.

### R3-MQA-03 Expired After Grace

- Account type: expired after grace
- Preconditions: signed-in test account, existing Cloud clip, paid history where `lastKnownPaidExpiryAt + 30 days` is in the past.
- Steps executed:
  - Environment readiness checked.
  - Required signed-in Cloud fixture/state was unavailable.
- Expected result: Cloud list/read/download/restore blocked, new upload blocked, no Cloud metadata/object deletion.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no safe Cloud test fixture available.
- Follow-up action: reuse the R3-MQA-02 fixture and inject an after-grace purchaseDate.

### R3-MQA-04 Free Never Paid

- Account type: signed-in free never paid
- Preconditions: signed-in test account, `currentTier=free`, no purchaseDate/productId.
- Steps executed:
  - Guest free-like state was observed, but signed-in free never-paid state was not available.
- Expected result: upload blocked, Cloud read blocked, `tier_required`-class 안내, Profile Cloud stats inactive or `-`/0.
- Actual result: signed-in free never-paid was not executed.
- Verdict: BLOCKED
- Evidence path or description: guest-mode free display evidence exists, but it is not a signed-in free account substitute.
- Follow-up action: create a non-production signed-in free test account with no purchase history.

### R3-MQA-05 Guest Mode

- Account type: guest
- Preconditions: no production user account; local emulator app run with guest entry enabled; tutorial sample clips present.
- Steps executed:
  - Launched app on Android emulator.
  - Confirmed login screen includes guest entry.
  - Tapped guest entry.
  - Denied notification permission to continue without external services.
  - Confirmed Library screen loads with tutorial sample clips.
  - Opened Profile and verified guest mode/free state and Cloud stats inactive display.
  - Tapped Profile Cloud area and confirmed CloudBackup access is blocked for guest mode.
  - Long-pressed a local tutorial clip in Library and confirmed selection mode; Cloud action button at bottom was disabled in the guest/free context.
- Expected result: guest cannot start Cloud upload/read/download; Profile Cloud stats inactive; CloudBackup blocked with guest 안내.
- Actual result:
  - Guest mode entered successfully.
  - Profile showed guest mode, Free state, device clips count, Cloud clip as `-`, Cloud usage unavailable/inactive.
  - CloudBackup screen showed guest-mode Cloud access block text.
  - Log showed authenticated Cloud queue/query skipped for guest/no signed-in user.
  - Library clip selection showed a disabled bottom action in the expected Cloud action position.
- Verdict: PASS
- Evidence path or description:
  - `C:\tmp\r3_mqa_window.xml`
  - `C:\tmp\r3_mqa_guest_permission_window.xml`
  - `C:\tmp\r3_mqa_guest_after_deny_window.xml`
  - `C:\tmp\r3_mqa_guest_profile_after_skip_window.xml`
  - `C:\tmp\r3_mqa_guest_cloud_tap_window.xml`
  - `C:\tmp\r3_mqa_guest_clip_longpress_window.xml`
  - log snippets in section 2
- Follow-up action: none for guest-mode local QA. Recheck on physical Android before release if required by the broader release gate.

### R3-MQA-06 Grace 중 Library Upload 버튼/Auto Upload 차단

- Account type: expired within grace
- Preconditions: grace state, local clip, auto upload enabled or queue restore setup.
- Steps executed:
  - Guest Library selection was exercised, but grace state was not available.
- Expected result: upload button hidden/blocked, `subscription_expired`, queue job preserved, no Storage upload.
- Actual result: grace-specific path not executed.
- Verdict: BLOCKED
- Evidence path or description: guest Library selection evidence exists at `C:\tmp\r3_mqa_guest_clip_longpress_window.xml`, but it is not grace coverage.
- Follow-up action: prepare grace state and queue fixture; capture Storage before/after.

### R3-MQA-07 Grace 중 CloudBackupScreen Read-Only 안내

- Account type: expired within grace
- Preconditions: grace state and existing Cloud clip.
- Steps executed:
  - Not executed due missing grace Cloud fixture.
- Expected result: existing Cloud clips visible, read-only/grace 안내 visible, no upload/copy CTA.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no grace Cloud fixture.
- Follow-up action: prepare existing Cloud clip on a test account and inject within-grace state.

### R3-MQA-08 Grace 중 Cloud Restore/Download

- Account type: expired within grace
- Preconditions: grace state, existing Cloud clip, restore target local state.
- Steps executed:
  - Not executed due missing grace Cloud fixture.
- Expected result: download/restore succeeds, local file created, Cloud metadata/object not deleted.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no grace Cloud fixture.
- Follow-up action: prepare Cloud clip and Storage before/after capture.

### R3-MQA-09 Grace 중 Cloud Metadata Lifecycle Write 최소화

- Account type: expired within grace
- Preconditions: grace state, existing Cloud clip, Firestore before/after visibility.
- Steps executed:
  - Not executed due missing grace Cloud fixture and Firestore before/after access.
- Expected result: restore/download allowed; active-write metadata lifecycle operations blocked or skipped.
- Actual result: not executed.
- Verdict: BLOCKED
- Evidence path or description: no Firestore before/after evidence available.
- Follow-up action: prepare dev/test Firestore account, capture document snapshots before/after restore and metadata actions.

### R3-MQA-10 Profile Cloud Stats 표시

- Account type: active paid / grace / expired after grace / free never paid / guest
- Preconditions: state matrix across active, grace, expired, free, guest.
- Steps executed:
  - Guest state only was executed.
  - Profile in guest mode displayed Free/guest state, device clip count, Cloud clip `-`, Cloud usage inactive.
- Expected result: active/grace shows Cloud stats; grace ended/free never paid/guest shows inactive or 0/`-`.
- Actual result: guest branch matched expectation; active/grace/expired/free signed-in branches not executed.
- Verdict: BLOCKED
- Evidence path or description: `C:\tmp\r3_mqa_guest_profile_after_skip_window.xml`
- Follow-up action: rerun with the same account/state fixtures required by R3-MQA-01 through R3-MQA-04.

## 4. Follow-Up Actions

Required before closing R3 local manual QA as PASS:

1. Prepare a non-production Firebase Auth test account.
2. Prepare at least one test Cloud clip under that account.
3. Document a safe local SharedPreferences state injection method for:
   - active Standard/Premium,
   - expired within 30-day grace,
   - expired after grace,
   - signed-in free never paid.
4. Capture Firestore and Storage before/after snapshots for Cloud write/read/restore scenarios.
5. Rerun R3-MQA-01, R3-MQA-02, R3-MQA-03, R3-MQA-04, R3-MQA-06, R3-MQA-07, R3-MQA-08, R3-MQA-09, and R3-MQA-10.

## 5. Release Gate Impact

R3 local manual QA is not fully PASS.

- PASS: guest mode only.
- BLOCKED: paid/grace/expired/free signed-in Cloud scenarios.

Release gate remains blocked until the missing non-production test account, Cloud clip fixture, and safe state injection procedure are available and the blocked scenarios are rerun.

## 6. Prohibited Scope Confirmation

Confirmed not performed:

- Firebase rules/index change.
- Firestore schema change.
- migration/backfill.
- Storage object deletion.
- Cloud copy implementation.
- npm audit fix.
- deploy.
- unrelated cleanup.
- production user data access.

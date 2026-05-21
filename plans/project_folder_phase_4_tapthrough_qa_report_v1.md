# Project Folder Phase 4 Tap-Through QA Report v1

## Scope

- Phase P4 Project-folder subscription UX.
- Standard user path: Project folder -> Project detail -> Edit screen.
- Free user path: Project folder inline Standard guidance, subscription CTA, and 720p direct export fallback.

## Environment

- Device: Android emulator `emulator-5554`.
- App package: `com.dk.three_sec`.
- Current signed-in entitlement during QA: `UserTier.standard`, product `3s_standard_monthly`.
- QA date: 2026-05-21.

## Standard Path Result

- PASS: App launched on the emulator after `flutter run -d emulator-5554`.
- PASS: Project tab was visible in bottom navigation.
- PASS: Project folder list showed Project folders including `기본` and `휴지통`.
- PASS: Opening `기본` showed 7 Project cards.
- PASS: Standard user did not see the inline Standard upsell panel in the folder detail view.
- PASS: Standard user did not see the `720p 내보내기` Free fallback button.
- PASS: Tapping a Project card opened `VideoEditScreen`.
- PASS: Edit screen showed the Project title, canvas controls, trim/transform controls, and clip timeline.
- PASS: No `File Missing` state was observed on the opened Project during this pass.
- PASS: Logcat check did not show `FATAL EXCEPTION`, `Unhandled Exception`, or `FlutterError` during the Standard path.

## Free Path Attempt

- RESOLVED: The user logged back in with Guest mode, and the emulator showed a real Free state.
- PASS: Profile showed Guest mode and `Free`.
- PASS: Project tab did not immediately route to a paywall.
- PASS: Project folder list remained accessible and showed `기본` and `휴지통`.
- PASS: Opening `기본` showed the inline Standard guidance panel.
- PASS: The panel showed `Standard 구독 시 Project 편집 가능`.
- PASS: The panel explained that Free users can export directly at 720p without opening the Project.
- PASS: Benefit chips were visible: `Project 편집`, `Cloud 연동`, `고화질 내보내기`.
- PASS: `구독하러가기` opened `구독 관리`.
- PASS: The subscription management screen showed `현재 구독 상태`, `Free`, and `현재 무료 플랜 이용 중`.
- PASS: Project cards showed `720p 내보내기`.
- PASS: Tapping a `720p 내보내기` button exported through `ProjectScreen_free_export`.
- PASS: Tapping a Project card body also exported through `ProjectScreen_free_export`.
- PASS: Both Free exports completed as `quality=720p` and were saved to gallery.
- PASS: After Free export, the UI stayed on Project detail and did not open `VideoEditScreen`.
- PASS: No `Canvas`, `Trim`, or `Transform` edit-screen UI appeared during Free export checks.
- PASS: Logcat did not show `FATAL EXCEPTION`, `Unhandled Exception`, or `FlutterError` during Free retest.

## Previous Free-State Setup Attempt

- Earlier in this pass, a real Free entitlement state could not be held on the Standard account.
- I backed up `shared_prefs/FlutterSharedPreferences.xml` before attempting the Free state.
- I removed only `flutter.3s_user_tier` from SharedPreferences and relaunched the app.
- The app restored `UserTier.standard` from entitlement sync at startup.
- I retried with emulator network disabled, then relaunched the app.
- The app still restored `UserTier.standard` from Firestore cache / startup entitlement sync.
- The original SharedPreferences file was restored after the attempt.
- Emulator network was re-enabled after the attempt.
- RESTORED: SharedPreferences again contained `flutter.3s_user_tier=UserTier.standard` and `flutter.3s_product_id=3s_standard_monthly` after that cleanup.

## Free Path Not Verified

- Actual Google Play purchase completion from `Standard 구독하기` was not executed.
- Free export from Projects containing Cloud-only material was not executed in this retest; the verified export Project contained local clips.

## Supporting Log Evidence

- Guest Free profile:
  - UI dump showed `게스트 모드`, `Standard 구독하기`, and `Free`.
- Free export button:
  - `MergeComplete ... caller=ProjectScreen_free_export`
  - `SavedToGallery ... album=2S_Vlog`
  - `export_complete ... "quality":"720p"`
- Free Project card body:
  - `MergeComplete ... caller=ProjectScreen_free_export`
  - `SavedToGallery ... album=2S_Vlog`
  - `export_complete ... "quality":"720p"`
- Startup entitlement sync after local tier deletion:
  - `UserStatusManager` initialized as `UserTier.standard`.
  - `EntitlementRefresh` applied `firestore_paid`.
  - Product remained `3s_standard_monthly`.
- The same Standard entitlement was restored even after disabling emulator Wi-Fi and data before relaunch.

## Commands Run

- `flutter devices`
- `flutter run -d emulator-5554`
- `adb shell input tap ...`
- `adb shell uiautomator dump`
- `adb logcat -d -t ...`
- `adb shell run-as com.dk.three_sec cp shared_prefs/FlutterSharedPreferences.xml shared_prefs/FlutterSharedPreferences.phase4_before_free_qa.xml`
- `adb shell run-as com.dk.three_sec sed -i '/flutter.3s_user_tier/d' shared_prefs/FlutterSharedPreferences.xml`
- `adb shell svc wifi disable`
- `adb shell svc data disable`
- `adb shell svc wifi enable`
- `adb shell svc data enable`
- `adb shell run-as com.dk.three_sec cp shared_prefs/FlutterSharedPreferences.phase4_before_free_qa.xml shared_prefs/FlutterSharedPreferences.xml`

## Residual Risk

- Phase P4 Standard behavior is tap-through verified.
- Phase P4 Free behavior is tap-through verified in Guest Free mode for local-clip Projects.
- Cloud-containing Project Free export still needs a separate decision/QA expectation because Phase P4's Free path directly exports instead of opening the editor.

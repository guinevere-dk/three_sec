# R3 User Action Cloud Upload Log Capture v2

작성일: 2026-05-19

범위: 사용자가 LibraryScreen local-only upload route로 Cloud upload fixture 생성을 재시도하는 동안, AI는 앱 UI를 조작하지 않고 상태/logcat만 수집한다.

보안 원칙:
- raw email/password/token/order id/provider 값은 기록하지 않는다.
- uid는 기록하지 않는다.
- UI hierarchy/logcat raw line 전체를 문서에 붙이지 않는다.
- Firebase rules/index/schema, Storage object, Cloud copy 구현, deploy는 변경하지 않는다.

## 전제 확인

| 항목 | 결과 |
| --- | --- |
| emulator 연결 | PASS |
| `adb logcat -c` | PASS |
| active paid SharedPreferences state | PASS: `tier=UserTier.standard` |
| product id presence | present만 확인, raw value 미기록 |
| purchase date presence | not present |
| app-controlled sensitive log gate | 기존 triage 기준 app_dart_log=0, app_native_log=0 유지 전제 |
| Cloud upload UI route | LibraryScreen 선택 패널의 local-only upload route 사용 예정 |

`cloud_synced_paths` before:
- key 존재: `flutter.cloud_synced_paths`
- raw value 미출력
- 저장 형식상 JSON 파싱 실패
- metadata-only probe: string entry, stored char count 883, comma-like count 9
- before count: exact unavailable, approximate 10

## 사용자 보고

사용자 보고:

```text
업로드 버튼이 어떤 상태에서도 나타나지 않는다.
```

이 보고 시점에서 upload click은 수행되지 않았다. 따라서 Cloud upload fixture 생성 capture는 진행하지 않고 route/blocker triage로 전환했다.

## 현재 UI 상태 Probe

`uiautomator dump`를 사용해 text/content-desc/bounds 중심으로 현재 화면을 확인했다. raw hierarchy 전체는 문서화하지 않는다.

관찰 결과:
- package: `com.dk.three_sec`
- 현재 화면: Library 일반 앨범 상세 화면
- 앨범: `일상`, 7 clips
- 필터: `전체` selected
- `기기` 필터 버튼 존재, selected=false
- clip thumbnail 7개 표시
- 하단 navigation: Camera / Library / Profile
- 선택 모드 표시 없음
- `1개 선택됨` 또는 `N개 선택됨` 표시 없음
- `Select All` 표시 없음
- 하단 floating selection panel 표시 없음
- Cloud transfer button 표시 없음

판정:
- 현재 화면은 CloudBackupScreen이 아니고 일반 Library album이므로 route 위치는 맞다.
- 그러나 clip selection mode에 진입하지 않은 상태다.
- `LibraryScreen` 구현상 upload/download Cloud transfer 버튼은 `_isClipSelectionMode && _selectedClipPaths.isNotEmpty`일 때만 하단 floating selection panel에 나타난다.
- 따라서 이 시점에 upload 버튼이 보이지 않는 것은 expected behavior다.

## 관련 코드 근거

### Floating selection panel 표시 조건

근거:
- `lib/screens/library_screen.dart:727`  
  `(_isClipSelectionMode && _selectedClipPaths.isNotEmpty)`일 때만 floating action button 영역에 selection panel을 표시한다.
- `lib/screens/library_screen.dart:748`  
  휴지통이 아닌 일반 앨범에서는 `MediaWidgets.buildLibrarySelectionPanel(...)`을 사용한다.
- `lib/screens/library_screen.dart:755`  
  Cloud transfer button은 `showTransferButton: _userStatusManager.isStandardOrAbove()`일 때만 포함된다.

현재 UI probe에서는 selection mode가 아니므로 `_isClipSelectionMode && _selectedClipPaths.isNotEmpty` 조건이 성립하지 않는다.

### Selection mode 진입 조건

근거:
- `lib/screens/library_screen.dart:691`의 clip `onLongPress`
- long press 시 `_isClipSelectionMode = true`
- long press한 path가 `_selectedClipPaths`에 추가됨
- selection mode title은 `lib/screens/library_screen.dart:540`에서 `"${_selectedClipPaths.length}개 선택됨"` 형태로 표시됨

따라서 다음 재시도에서 먼저 확인해야 할 화면 신호는 upload icon이 아니라 `1개 선택됨` title과 하단 selection panel 출현이다.

### Cloud upload icon 표시 조건

근거:
- `lib/screens/library_screen.dart:976` `_resolveSelectionActionState()`
- 선택된 모든 path가 `!videoManager.isClipCloudSynced(path)`이면 `_SelectionActionState.local`
- `lib/screens/library_screen.dart:993` `_transferIconForSelectionState(local)`은 `Icons.cloud_upload_rounded`
- `lib/screens/library_screen.dart:1004` `_transferHandlerForSelectionState(local)`은 `_moveSelectedLocalToCloud`
- `lib/widgets/media_widgets.dart:517`에서 Cloud transfer button은 selection panel의 두 번째 icon button

즉 upload button은 다음 조건이 모두 만족될 때만 보인다.
1. 일반 앨범 상세 화면
2. 휴지통 아님
3. clip long press로 selection mode 진입
4. selected clip count > 0
5. app memory의 `UserStatusManager.isStandardOrAbove() == true`
6. selected set이 local-only clip으로만 구성됨

## Logcat Sanitized Probe

사용자 보고 직후 raw line을 출력하지 않고 count-only로 확인했다.

| pattern | count |
| --- | ---: |
| `UserStatusManager` | 0 |
| `ProfileScreen` | 293 |
| `LibraryTrace` | 0 |
| `tier=UserTier.free` | 293 |
| `tier=UserTier.standard` | 293 |
| `tier=UserTier.premium` | 0 |
| `album_enter_tap` | 0 |
| `detail_render` | 0 |
| `create_project_button_visible` | 0 |
| `Standard` | 293 |

해석:
- ProfileScreen 로그에는 free/standard가 모두 count되었다. ProfileScreen 초기화 전후 tier가 함께 찍히는 구조라 raw line 없이 단정하지 않는다.
- SharedPreferences probe 기준 active paid tier는 `UserTier.standard`다.
- 현재 UI에서 Standard upsell text는 관찰되지 않았다.
- 현재 blocker는 paid state보다는 selection mode 미진입으로 분류한다.

## Upload 관련 로그 분석

이번 v2 attempt에서는 사용자가 upload 버튼을 누르지 못했다고 보고했으므로 upload capture window가 성립하지 않았다.

| 키워드/흐름 | 결과 |
| --- | --- |
| `uploadVideoImmediate` | N/A: 버튼 미클릭 |
| `uploadVideo` | N/A: 버튼 미클릭 |
| `_moveSelectedLocalToCloud` | N/A: 버튼 미클릭 |
| `_moveSelectedLocalToCloudInBackground` | N/A: 버튼 미클릭 |
| `Storage putFile` | N/A |
| `uploadStatus` create/update | N/A |
| `completed` | N/A |
| `markClipCloudSynced` | N/A |
| `cloud_synced_paths` after | N/A |
| `canStartNewCloudWrite` gate | N/A |
| `subscription_expired` | N/A |
| `tier_required` | N/A |
| `auth uid missing` | N/A |
| `permission denied` | N/A |

## Verdict

| 항목 | verdict | 사유 |
| --- | --- | --- |
| Cloud upload fixture 생성 | BLOCKED | 사용자가 upload button을 찾지 못해 click 미수행 |
| active paid state 유지 | PASS | SharedPreferences tier is `UserTier.standard` |
| app-controlled sensitive log gate | PASS/WARN | raw sensitive value 미출력, 기존 app_dart/app_native clean 전제 |
| Library 일반 앨범 route | PASS | 현재 UI가 Library 일반 앨범 상세로 확인됨 |
| local-only upload button 표시 | BLOCKED | 현재 UI가 selection mode가 아니므로 selection panel 자체가 없음 |
| CloudService upload 진입 | N/A | upload button 미클릭 |
| Firestore metadata create/update 추정 | N/A | upload button 미클릭 |
| Storage upload 추정 | N/A | upload button 미클릭 |

## 다음 조치

사용자에게 다음 절차로 재시도하도록 안내한다.

```text
현재 화면은 Library 일반 앨범 상세까지는 맞습니다.
먼저 '기기' 필터를 누른 뒤, 보이는 clip 썸네일 하나를 짧게 탭하지 말고 1초 정도 길게 눌러 주세요.
상단 제목이 '1개 선택됨'으로 바뀌어야 selection mode에 진입한 것입니다.
그때 화면 하단에 floating selection panel이 떠야 합니다.
하단 패널의 왼쪽 첫 번째는 favorite, 왼쪽 두 번째가 Cloud transfer입니다.
왼쪽 두 번째 아이콘이 구름 + 위쪽 화살표이면 upload이므로 누르고, 아래쪽 화살표이면 누르지 말고 중단해 주세요.
```

만약 `1개 선택됨` 상태와 하단 selection panel은 보이는데 Cloud transfer 버튼만 없다면 다음 분류로 전환한다.
- app memory의 `UserStatusManager.isStandardOrAbove()`가 false일 가능성
- active paid SharedPreferences 주입 후 앱 완전 종료/재실행 필요 가능성
- UI에서 Standard/Premium 상태 reload 누락 가능성
- 이 경우 코드 변경 없이 재실행 후 Profile 화면에서 Standard 상태 로드 로그를 raw uid 없이 count-only로 확인한다.

## 최종 상태

BLOCKED: upload route는 Library 일반 앨범으로 맞지만, 현재 capture 시점에는 clip selection mode가 아니어서 Cloud transfer/upload button이 나타날 수 없는 상태였다. Cloud upload fixture evidence collection은 아직 시작되지 않았다.

# Cloud Clip R3 Analyzer Delta Triage Report v1

## 1. Scope

R3 v1 구독 만료 Cloud 접근 정책 구현 이후, 지정 파일 대상 `flutter analyze` 결과 453 issues를 전체 style cleanup 없이 분류했다.

이번 triage에서 하지 않은 것:

- `avoid_print`, `deprecated_member_use`, style/info cleanup 없음.
- Firebase rules/index 변경 없음.
- npm audit fix 없음.
- deploy 없음.
- R3와 무관한 warning 수정 없음.

## 2. Command

```cmd
flutter analyze lib\managers\user_status_manager.dart lib\services\cloud_service.dart lib\services\iap_service.dart lib\services\auth_service.dart lib\managers\video_manager.dart lib\screens\library_screen.dart lib\screens\cloud_backup_screen.dart lib\screens\profile_screen.dart test\user_status_manager_r3_test.dart
```

Result:

- Exit code: 1
- Total: 453 issues

## 3. Severity Summary

| Severity | Count | R3 관련 판정 |
|---|---:|---|
| error | 0 | R3 compile error 없음 |
| warning | 3 | 모두 기존 IAP nullability warning으로 판정 |
| info | 450 | 기존 analyzer/style 부채. 이번 작업에서 미수정 |

## 4. Error Triage

Analyzer error는 0개다.

R3 변경 파일에서 compile break, missing import, unresolved symbol, type mismatch는 확인되지 않았다.

## 5. Warning Triage

| File | Line | Rule | Message 요약 | R3 delta 판정 |
|---|---:|---|---|---|
| `lib/services/iap_service.dart` | 652 | `unnecessary_null_comparison` | null이 될 수 없는 operand를 null 비교 | R3 비관련 |
| `lib/services/iap_service.dart` | 652 | `invalid_null_aware_operator` | null이 될 수 없는 receiver에 `?.` 사용 | R3 비관련 |
| `lib/services/iap_service.dart` | 658 | `unnecessary_null_comparison` | null이 될 수 없는 operand를 null 비교 | R3 비관련 |

근거:

- warning 위치는 `_safePurchaseOrderId(PurchaseDetails purchase)` 내부 Android purchase order id 로깅/선택 로직이다.
- R3에서 변경한 `iap_service.dart` hunk는 `_applyInactiveSubscriptionToFree()` 블록이며, 위치는 1208 라인 이후다.
- R3 변경은 `CANCELLED`, `EXPIRED`, refund-like inactive 상태 처리이며, 652/658 라인의 Android purchase id nullability 계약을 바꾸지 않았다.
- `auth_service.dart`, `user_status_manager.dart`에서는 warning severity가 보고되지 않았다. 두 파일의 보고 항목은 `avoid_print` 등 info다.

따라서 이번 R3 delta에서 새로 생긴 error/warning은 없음으로 판정한다.

## 6. Info Debt Not Fixed

이번 작업에서 수정하지 않은 analyzer info 부채:

- `avoid_print`
- `curly_braces_in_flow_control_structures`
- `deprecated_member_use`
- `depend_on_referenced_packages`
- `prefer_conditional_assignment`
- `unnecessary_brace_in_string_interps`
- `no_leading_underscores_for_local_identifiers`

이 항목들은 R3 기능 회귀와 직접 관련 없는 style/deprecation/info cleanup이므로 범위 밖으로 둔다.

## 7. File-Specific Notes

| File | Analyzer delta 판단 |
|---|---|
| `lib/managers/user_status_manager.dart` | R3 helper 관련 compile error/warning 없음. 기존 `avoid_print` info 다수만 존재. |
| `lib/services/cloud_service.dart` | R3 gate/reason code 관련 compile error/warning 없음. 기존 `avoid_print` info 다수만 존재. |
| `lib/services/iap_service.dart` | warning 3개 존재. R3 변경 hunk 밖의 기존 Android order id nullability 부채로 분리. |
| `lib/services/auth_service.dart` | R3 local grace 보존 변경 관련 compile error/warning 없음. 기존 `avoid_print` 등 info만 존재. |
| `lib/managers/video_manager.dart` | R3 restore metadata write guard 관련 compile error/warning 없음. 기존 style/info만 존재. |
| `lib/screens/library_screen.dart` | R3 upload button gate 관련 compile error/warning 없음. 기존 style/deprecated info만 존재. |
| `lib/screens/cloud_backup_screen.dart` | 이번 analyzer 대상에서 error/warning 없음. |
| `lib/screens/profile_screen.dart` | R3 Cloud stats 기준 변경 관련 compile error/warning 없음. 기존 info만 존재. |
| `test/user_status_manager_r3_test.dart` | error/warning 없음. |

## 8. Changes Made In This Triage

Code changes: none.

Created report:

- `plans/cloud_clip_r3_analyzer_delta_triage_report_v1.md`

R3 관련 error/warning이 없으므로 최소 수정 대상도 없다.

## 9. Remaining Analyzer Debt

릴리스 전 별도 cleanup 작업으로 분리할 항목:

| Debt | Count/Location | Priority |
|---|---|---|
| Existing IAP nullability warnings | `lib/services/iap_service.dart:652`, `lib/services/iap_service.dart:658` | Medium. R3 비관련이나 warning severity라 별도 수정 권장 |
| Production `print` usage | 여러 R3 대상 파일 | Low/Medium. 로깅 정책 정리 작업으로 분리 |
| Style info | braces, local identifier naming, interpolation 등 | Low. 기능 회귀와 분리 |
| Deprecated API usage | `withOpacity`, `updateEmail` 등 | Medium. SDK upgrade 대응 작업으로 분리 |
| IAP package dependency info | `in_app_purchase_android`, `in_app_purchase_storekit` import | Medium. pubspec 의존성 정책 확인 후 별도 처리 |

## 10. Verdict

R3 v1 구현으로 새로 발생한 analyzer error/warning은 확인되지 않았다.

현재 `flutter analyze` 실패의 직접 원인은 기존 analyzer 부채 453개 중 warning 3개와 info 450개이며, R3 compile stability 관점에서는 추가 코드 수정 없이 진행 가능하다.

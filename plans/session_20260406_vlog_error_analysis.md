# 세션 로그 분석 결과 (211855 / 213407)

## 결론
`vlog` 생성(클립 17개 병합) 중 발생한 앱 종료는 **앱 내부 Dart 예외가 1차 원인**이 아니라,
시스템 레벨에서의 **`force-stop`에 의해 앱 프로세스가 외부에서 종료된 케이스**로 판단됨.

동일 패턴은 두 세션 모두 반복됨.

- 1차 세션: [logs/session_20260406_211855_full.log](logs/session_20260406_211855_full.log:83123)
- 2차 세션: [logs/session_20260406_213407_full.log](logs/session_20260406_213407_full.log:3191)

---

## 증거 정리

### 1) 강제 종료 시그니처
`ActivityManagerService.forceStopPackage`에서 `ActivityManagerShellCommand.runForceStop` 경로를 통해
패키지 정지 로그가 명시됨.

- `Force stopping com.dk.three_sec ... from pid ...` 
  - [211855: `force stopping` 라인](logs/session_20260406_211855_full.log:83123)
  - [213407: `force stopping` 라인](logs/session_20260406_213407_full.log:3190)

- 같은 흐름에서 실제 프로세스 종료 로그:
  - [211855: `Killing ... com.dk.three_sec` / `from pid 27601`](logs/session_20260406_211855_full.log:83165)
  - [213407: `Killing ... com.dk.three_sec` / `from pid 5484`](logs/session_20260406_213407_full.log:65832)

- 앱 Activity 종료 정리:
  - [211855: `Force removing ActivityRecord` 및 `app died`](logs/session_20260406_211855_full.log:83170)
  - [213407: 강제 종료 직후 Launcher 포커스 복귀 로그](logs/session_20260406_213407_full.log:65817)

### 2) 병합 직전/중의 사용자 동작 로그 존재
병합 진입 로그는 앱 코드상으로 정상 시작됨을 보여준다.

- 병합 시작: [`_handleMerge()` 시작 로그](lib/main.dart:1558)
- `createProject` 호출 로그: [211855: 1600행](logs/session_20260406_211855_full.log:1600)
- [213407: 19964~19965행](logs/session_20260406_213407_full.log:19964)

### 3) 메모리 압박은 배경 노이즈로 다수 동시 존재
종료 직전/직후 다수의 `lmkd` 메모리 회수 로그가 반복되어 메모리 여유가 낮은 환경에서 실행 중이었음.

- [211855: `lmkd` 관련 라인 일부](logs/session_20260406_211855_full.log:24933)
- [213407: `lmkd` Reclaim·skip 로그 반복](logs/session_20260406_213407_full.log:11561)
- [213407: 카메라/시스템 메모리 회수 증가 구간](logs/session_20260406_213407_full.log:13279)

---

## 가능성별 판별

### 1순위: 외부 `force-stop` (우선 원인)
- 셸 커맨드 기반으로 보이는 `runForceStop` 문자열과 함께 종료.
- 특정 pid (`27601`, `5484`)가 종료 사유로 기록되어 있어 앱 코드 스택과 직접 연결이 안 되는 형태.

참조:
- [211855 종료 로그 블록](logs/session_20260406_211855_full.log:83123)
- [213407 종료 로그 블록](logs/session_20260406_213407_full.log:65817)

### 2순위: 메모리 압박 동반 요인
- 종료 자체 트리거는 아니더라도, 병합/카메라 동작 구간에서 `lmkd`가 빈번. 장치 상태가 불안정.
- 병합 동작에서 카메라/영상 처리 동시 동작이 있어 리스크가 높아짐.

참조:
- [`exportVlog()`](lib/managers/video_manager.dart:1499) (권한/출력 경로/네이티브 호출 구간)
- [213407 `lmkd` 연속 구간](logs/session_20260406_213407_full.log:13179)

### 낮은 확률군: 앱 내부 크래시/예외
- 앱 내부 크래시일 경우라면 동일 지점에서 Dart 스택/`Native Error` 직후 앱 종료 패턴이 먼저 보여야 하나,
시스템 `force-stop` 패턴이 선행됨.

참조:
- [_handleMerge() 예외 처리 블록](lib/main.dart:1608)
- [mergeVideos 실패 시 PlatformException 로그](lib/managers/video_manager.dart:1581)

---

## 최종 판정
**원인:** 외부 강제종료(`force-stop`)가 1차 원인.

**부가 요인:** 병합 직전/중 메모리 압박 지표(`lmkd`)가 높아, 외부 종료가 일어나지 않았더라도
안정성 위험이 컸을 가능성 존재.

---

## 다음 단계 권고

1. 테스트/자동화 시 `am force-stop com.dk.three_sec`를 발동시키는 스텝/스크립트 정리.
2. 병합 직전/직후를 계측해 강제종료 원인 구분 포인트를 더 명확화.
3. 기기 메모리 여유 임계 구간에서 병합을 피하거나 클립 수/해상도 제한 가드 추가.

---

## 로그 포인트(권장 추가 계측)

- [`_handleMerge()`](lib/main.dart:1557) 시작/종료, 선택 clip 개수, 소요시간, 세션ID 로그.
- [`VideoManager.createProject()`](lib/managers/video_manager.dart:950) 클립별 duration 썸네일 계산 시간, 실패 clip 갯수 로그.
- [`VideoManager.exportVlog()`](lib/managers/video_manager.dart:1492) 네이티브 호출 인자 요약(`clipCount`, 총재생시간, tier, 품질), 플랫폼 결과/에러 상세코드.
- Flutter 생명주기/메모리 경고 이벤트에서 세션로그 연결(앱 재시작, 메모리압력 진입).

---

## 검증 체크리스트(Force-stop vs App Crash)

- [ ] **ADB 강제종료 시그니처 확인**
  - [ ] `ActivityManagerShellCommand.runForceStop` 문자열 탐지 여부 확인.
  - [ ] `Force stopping com.dk.three_sec` 라인 존재 여부 확인.
  - [ ] 동일 타임라인에서 `Killing ... com.dk.three_sec` 라인 존재 여부 확인.
  - [ ] 위 3개가 같은 종료 이벤트 블록으로 묶이는지 확인.

- [ ] **병합 세션 로그와 종료 로그 상호관계 분석**
  - [ ] 병합 시작점 `[_handleMerge]` 로그 시각/라인 기록.
  - [ ] `createProject` 계측 로그 시각/라인 기록.
  - [ ] `exportVlog` 계측 로그 시각/라인 기록.
  - [ ] 종료 시그니처 직전 마지막 병합 단계가 무엇인지 매핑.
  - [ ] 병합 로그 단절 시점과 강제종료 시점의 선후관계 판정.

- [ ] **메모리 압박 지표와 종료 이전 경과시간 상관관계 확인**
  - [ ] 세션 내 `didHaveMemoryPressure`/메모리 경고 발생 횟수 집계.
  - [ ] 첫 메모리 경고 시점부터 종료 시점까지 경과시간 기록.
  - [ ] 마지막 메모리 경고 시점부터 종료 시점까지 경과시간 기록.
  - [ ] 메모리 경고 밀집 구간과 병합 고부하 구간 중첩 여부 확인.

- [ ] **Dart/Flutter 예외 선행 여부 확인**
  - [ ] 종료 직전 윈도우에서 `PlatformException` 발생 여부 확인.
  - [ ] 종료 직전 윈도우에서 일반 `Exception` 발생 여부 확인.
  - [ ] 예외가 있다면 강제종료 시그니처보다 먼저 발생했는지 선후관계 판정.
  - [ ] 예외가 있어도 프로세스 종료 원인이 force-stop인지 별도 표기.

- [ ] **강제종료 후 재시작/세션 복구 경로 기록 여부 확인**
  - [ ] 강제종료 후 런처 포커스 복귀 또는 앱 재실행 로그 존재 여부 확인.
  - [ ] 앱 재시작 시 세션 복구 진입 로그 존재 여부 확인.
  - [ ] 복구 실패 시 사용자 영향(진행중 병합 유실 여부) 기록.
  - [ ] 최종 판정에 `Force-stop`과 `App Crash`를 분리 표기.

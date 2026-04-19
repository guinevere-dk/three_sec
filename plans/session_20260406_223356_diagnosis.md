# Session 2026-04-06 22:33:56 진단 보고서

## 1) 증상 요약
- 병합 시도 중 앱 프로세스가 종료됨.
- 종료 직전 앱 로그에는 병합 1차/2차 시도 흔적이 있으나 Flutter FATAL/Unhandled 예외는 확인되지 않음.

## 2) 가능 원인(6개) 점검
1. Flutter/Dart 런타임 예외(전역 에러 포함)
2. Media3 병합 파이프라인 내부 예외
3. 무음 클립 다량 입력 + 오디오 트랙 정책 불일치
4. 메모리 압박/OOM 또는 시스템 리소스 회수
5. 사용자/도구/외부 프로세스의 강제 중지(`am force-stop` 계열)
6. Activity/Window 정리 중 2차 예외(표면적 후행 로그)

## 3) 로그 근거

### A. 외부 강제중지 직접 근거
- `force stop from ... ActivityManagerShellCommand.runForceStop` 이후
- `Force stopping com.dk.three_sec ... from pid 4135`
- 직후 `Killing ... stop com.dk.three_sec due to from pid 4135`

근거: [session_20260406_223356_full.log](../logs/session_20260406_223356_full.log)

### B. 앱 내부 크래시 단서 부재
- 앱 신호 로그에 병합 시도/프로젝트 생성 로그는 존재
- 동일 구간에 Flutter FATAL/Unhandled stack 흔적 부재

근거: [session_20260406_223356_appsignals.log](../logs/session_20260406_223356_appsignals.log), [session_20260406_223356_appfull.log](../logs/session_20260406_223356_appfull.log)

### C. 무음 클립 다수 + fallback 경로 동작
- 다수 클립에서 `오디오 트랙이 없습니다`
- `forceAudioTrack API 미지원` fallback 반복

근거: [session_20260406_223356_errors.log](../logs/session_20260406_223356_errors.log), [MainActivity.kt](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt)

## 4) 최종 축약 진단(우선순위)

### 1순위(가장 유력)
외부에서 프로세스 강제 중지됨. 즉, **앱 내부 크래시가 1차 원인이라기보다 종료 지시가 먼저 발생**.

### 2순위(동반 리스크)
무음 클립 대량 입력 + 오디오 트랙 fallback 경로로 병합 부담이 커진 상태에서, 외부 종료 이벤트와 겹치며 실패 체감이 증폭.

## 5) 이번 변경 목적(진단 로그 강화)
- 강제종료 재발 시 “병합 세션/시도 정보 + 라이프사이클 + 네이티브 병합 상태”를 한 번에 맞춰서 확인 가능하게 함.
- 원인 귀속(외부 stop vs 내부 merge fail)을 로그만으로 빠르게 확정 가능하도록 함.

## 6) 추가된 확인 포인트
- Android 라이프사이클 로그(`3S_LIFECYCLE`): onCreate/onStart/onResume/onPause/onStop/onTrimMemory/onDestroy
- 병합 인자 수신 로그(`MergeArgs`)
- 병합 시작/완료 로그(`MergeBegin`, `MergeComplete`)
- Flutter 라이프사이클 로그(`[Main][Lifecycle]`)

## 7) 재검증 체크리스트
1. 동일 시나리오 재현 후 `3S_LIFECYCLE` 태그 기준으로 시계열 정렬
2. `MergeBegin` 이후 `MergeComplete(status=error|success)` 존재 여부 확인
3. `Force stopping ... from pid ...`가 나타나면 해당 시점 직전의 `sessionId/traceId/attempt`를 대조
4. Flutter 쪽 `[VideoManager][Export] invoking_merge`와 Native `MergeArgs`의 세션/시도값 일치 여부 확인

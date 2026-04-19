# 클립이 1s로 보이는 문제와 "진짜 2s(앞자리 2)" 보장 방법 분석 (v1)

## 문제 정의

- 현재 일부 클립이 UI에서 `1s`로 표시됨.
- 요구사항은 **반올림/표시 트릭 없이**, 실제 미디어 길이 자체가 `2.xxxs` 또는 최소 `2.000s`가 되도록 만드는 것.

---

## 현재 코드에서 확인된 사실

1. 정책 목표 길이는 이미 2초로 선언됨.
   - [`kTargetClipMs = 2000`](../lib/constants/clip_policy.dart:1)
   - [`kTargetClipSecForDisplay = 2`](../lib/constants/clip_policy.dart:2)

2. 녹화 타이머는 2초 + 안전버퍼(120ms) 기준으로 stop 트리거됨.
   - [`_targetRecordingMilliseconds = kTargetClipMs`](../lib/screens/capture_screen.dart:71)
   - [`_recordingStopDelayMs = kRecordingUiSafetyBufferMs`](../lib/screens/capture_screen.dart:72)
   - [`stopTriggerMs = _targetRecordingMilliseconds + _recordingStopDelayMs`](../lib/screens/capture_screen.dart:450)

3. 저장 시 normalize에서 실제 클립 길이를 `min(source, target)`로 잘라냄.
   - [`clipMs = min(sourceDurationMs, targetDurationMs)`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:720)

4. 길이 뱃지 표시는 `Duration.inSeconds`(내림) 사용.
   - [`final int seconds = d.inSeconds; return '${seconds}s';`](../lib/widgets/media_widgets.dart:435)

즉, 파일 길이가 `1999ms`면 표시는 반드시 `1s`가 됨.

---

## 왜 1s가 나오는가 (핵심 원인)

원인은 보통 아래 2가지가 겹칩니다.

1. **실제 결과물이 2000ms 미만으로 저장되는 경우**
   - source가 2초 미만이면 normalize가 target으로 늘리지 않고 그대로 짧은 길이를 사용.
   - 근거: [`clipMs = min(sourceDurationMs, targetDurationMs)`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:720)

2. **컨테이너/타임스탬프 단위로 2000이 정확히 표현되지 않아 1999ms 근처로 읽히는 경우**
   - UI는 내림이므로 `1s`로 떨어짐.

---

## "앞자리 2"를 보장하는 방법 비교

## A안) 61프레임(약 2.033s @30fps)로 정책 변경

- 개념: 목표를 2000ms가 아니라 약 `2034ms`로 잡아서, 내림해도 항상 `2s`가 되게 함.
- 장점
  - 구현이 가장 단순.
  - 현재 표시 로직([`inSeconds`](../lib/widgets/media_widgets.dart:436)) 그대로 둬도 2로 보일 확률이 높음.
- 단점
  - 정책 길이가 사실상 2초가 아니라 2.03초로 바뀜.
  - 전체 파이프라인(컷 길이, 편집 감각, 템플릿 타이밍)에 미세한 누적 영향.

> "정확히 2초 정책"보다 "2로 보이게"가 최우선일 때 실용적.

## B안) 정확 2초(60프레임) 보장 + 부족분 강제 패딩(권장)

- 개념:
  1. normalize 출력 목표는 계속 2000ms 유지.
  2. source가 2000ms보다 짧으면 **마지막 프레임 hold + 오디오 무음 패딩**으로 2000ms를 채움.
  3. 출력 타임스탬프를 CFR 기준(예: 30fps)으로 정렬해 최종 duration이 2000ms 미만으로 떨어지지 않게 보장.

- 장점
  - 정책 의미(2초)를 그대로 지킴.
  - 표시 트릭 없이도 `2s` 달성 가능.
- 단점
  - 구현 난이도 높음(특히 오디오/비디오 동기화, 인코더별 편차 대응).
  - Android/iOS 양쪽 정합성 검증 필요.

> "정책도 진짜 2초여야 한다"면 가장 정석.

## C안) 녹화 stop 시점을 더 늦추기만 함

- 개념: [`_recordingStopDelayMs`](../lib/screens/capture_screen.dart:72) 증가.
- 장점: 쉬움.
- 단점: normalize에서 여전히 [`min(source, target)`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:720)라서, source가 특정 상황에서 2초 미만이면 근본 해결 안 됨.

> 단독 해법으로는 불충분.

---

## 권장안

### 1순위: B안 (정확 2초 보장형)

- 이유: 요구사항이 "반올림 말고 실제 시간이 2"에 가까움.
- 구현 포인트(요약)
  - normalize 단계에서 `sourceDurationMs < targetDurationMs`인 경우 패딩 분기 추가.
    - 진입 지점: [`normalizeVideoDuration(...)`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:671)
  - 최종 검증: export 후 duration 재조회해서 `< 2000ms`면 재시도/보정.
    - 조회 함수: [`getVideoDurationMs(...)`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:623)

### 빠른 대안: A안 (2034ms 정책)

- 릴리즈 급할 때 현실적.
- 정책을 2.034초로 받아들일 수 있는지 먼저 결정 필요.

---

## 테스트 기준 (필수)

1. 저장 직후 duration(ms) 로그 수집
   - 현재 normalize 완료 로그 참고: [`normalizedDurationMs`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:765)
2. 최소 50회 연속 촬영에서 `duration >= 2000ms` 비율 측정
3. 다양한 기기(고/중/저사양, 30/60fps 센서)에서 동일 검증
4. 라이브러리 뱃지가 전부 `2s` 이상인지 확인
   - 표기 함수: [`_formatDurationShort()`](../lib/widgets/media_widgets.dart:435)

---

## 최종 결론

- 현재 1s 표시는 **UI 내림 + 실제 결과물이 2초 미만으로 떨어지는 케이스**의 결합 문제입니다.
- "반올림 없이 앞자리 2" 요구를 정확히 만족하려면,
  - **정석:** normalize에서 실제 결과물 길이를 최소 2000ms 이상으로 강제(B안)
  - **실무 타협:** 목표를 61프레임(약 2034ms)로 상향(A안)

B안을 기본 권장합니다.

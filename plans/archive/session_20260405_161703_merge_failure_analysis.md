# 병합 실패 로그 분석 보고서 (`session_20260405_161703`)

## 1) 결론 요약

- 병합 플로우는 Flutter에서 정상 시작되어 네이티브까지 진입합니다.
- 실제 실패 지점은 Media3 변환 과정이며, 최종적으로 `Asset loader error`로 표면화됩니다.
- 가장 유력한 1순위 원인은 **오디오 트랙이 없는 MediaItem이 시퀀스에 포함되어 Media3 시퀀스 오디오 가정이 깨지는 문제**입니다.
- 코덱 협상 관련 경고/미지원 로그는 보조 요인(2순위)으로 보입니다.

---

## 2) 사용자 액션 기준 타임라인

1. 병합 시작
   - `MergeFlow start selectedCount=16`
2. 프로젝트 생성 완료
   - `MergeFlow createProject done ... clipCount=16`
3. Export 시작
   - `Start Exporting... (Count: 16)`
4. 실패 반환
   - `Native Error: Media3 Error: Asset loader error`

> 근거 로그
>
> - [`logs/session_20260405_161703_appsignals.log:160`](../logs/session_20260405_161703_appsignals.log:160)
> - [`logs/session_20260405_161703_appsignals.log:165`](../logs/session_20260405_161703_appsignals.log:165)
> - [`logs/session_20260405_161703_appsignals.log:167`](../logs/session_20260405_161703_appsignals.log:167)
> - [`logs/session_20260405_161703_appsignals.log:171`](../logs/session_20260405_161703_appsignals.log:171)

---

## 3) 핵심 예외 스택

- `ExoPlaybackException: Unexpected runtime error`
- `Caused by: java.lang.IllegalStateException: The preceding MediaItem does not contain any audio track...`
- 상위 래핑: `androidx.media3.transformer.ExportException: Asset loader error`

> 근거 로그
>
> - [`logs/session_20260405_161703_errors.log:48416`](../logs/session_20260405_161703_errors.log:48416)
> - [`logs/session_20260405_161703_errors.log:48422`](../logs/session_20260405_161703_errors.log:48422)
> - [`logs/session_20260405_161703_errors.log:48441`](../logs/session_20260405_161703_errors.log:48441)
> - [`logs/session_20260405_161703_errors.log:48462`](../logs/session_20260405_161703_errors.log:48462)

---

## 4) 코드 경로 상관관계

### Flutter 측

- export 시작 로그 후 네이티브 메서드 호출:
  - `platform.invokeMethod('mergeVideos', args)`

> 근거
>
> - [`lib/managers/video_manager.dart:1543`](../lib/managers/video_manager.dart:1543)
> - [`lib/managers/video_manager.dart:1566`](../lib/managers/video_manager.dart:1566)

### Android 네이티브 측

- `MethodChannel`에서 `mergeVideos` 인자 수신 및 호출
- `videoSequence`를 생성한 뒤 `EditedMediaItemSequence(videoSequence)`로 구성
- `Transformer.start(composition, outputPath)` 실행

> 근거
>
> - [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:121`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:121)
> - [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:153`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:153)
> - [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:644`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:644)
> - [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:701`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:701)
> - [`android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:815`](../android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt:815)

---

## 5) 가설 정리 (6개)

1. **[유력 1순위]** 오디오 없는 미디어 아이템이 시퀀스에 포함/선행되어 Media3 오디오 트랙 연속성 가정 위반
2. **[유력 2순위]** 디바이스/코덱 협상 실패 (`NoSupport sizeAndRate`, Codec2 경고 누적)
3. MethodChannel 인자 매핑 누락
4. BGM/노이즈 억제 이펙트 조합 문제
5. 16개 병합으로 인한 리소스 한계
6. 파일 경로/권한/저장소 문제

### 축소 결과

- 1순위: **오디오 트랙 불연속(핵심 원인)**
- 2순위: **코덱 호환성 이슈(보조 원인)**

> 코덱 관련 근거
>
> - [`logs/session_20260405_161703_full.log:276780`](../logs/session_20260405_161703_full.log:276780)
> - [`logs/session_20260405_161703_full.log:281709`](../logs/session_20260405_161703_full.log:281709)
> - [`logs/session_20260405_161703_errors.log:4302`](../logs/session_20260405_161703_errors.log:4302)

---

## 6) 권장 수정 순서

1. 시퀀스 생성 전 각 클립 오디오 트랙 유무 preflight 검사/로그
2. 오디오 없는 아이템 처리 정책 적용
   - 시퀀스 분리 또는
   - `EditedMediaItemSequence.Builder.experimentalSetForceAudioTrack(true)` 적용 검토
3. 실패 시 해상도/프로파일 fallback 재시도(코덱 호환성 우회)
4. 네이티브 예외 원인(cause) 문자열을 Flutter로 상세 전달

---

## 7) 최종 판정

- 본 세션(`20260405_161703`) 병합 실패는 UI 액션 미동작이 아니라, **네이티브 Media3 export 단계 예외로 인해 결과 파일 생성이 중단된 케이스**입니다.
- 사용자 관찰 증상(“아무 일도 안 일어남”)은 실제로는 export 실패가 토스트/로그로만 처리되어 체감상 무반응처럼 보인 상황과 일치합니다.

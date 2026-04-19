# 앱 첫 진입 카메라 오픈 속도 개선 + 폰 내장 카메라 앱 대체 사용 분석 (v1)

## 1) 현재 구조 요약 (코드 기반)

- 앱 시작 시 `main()`에서 카메라 목록을 미리 조회합니다: `availableCameras()` 호출 후 전역 `cameras` 저장.
  - 근거: `cameraFuture = _loadAvailableCameras()` → `cameras = await cameraFuture` in [`main()`](../lib/main.dart:130), [`_loadAvailableCameras()`](../lib/main.dart:116)
- 메인 탭은 `IndexedStack`이며 기본 탭이 카메라(인덱스 0)입니다.
  - 근거: [`_selectedIndex = 0`](../lib/main.dart:320), [`IndexedStack(index: _selectedIndex)`](../lib/main.dart:1029)
- 카메라 탭 진입 시 `CaptureScreen.initState()`에서 즉시 카메라 초기화가 시작됩니다.
  - 근거: [`_initCamera()`](../lib/screens/capture_screen.dart:204), [`_initCameraAsync()`](../lib/screens/capture_screen.dart:252)
- 녹화물 저장은 단순 파일 저장이 아니라 "정규화(normalize)" 단계(네이티브 채널 호출)를 포함합니다.
  - 근거: [`saveRecordedVideo()`](../lib/managers/video_manager.dart:2948), [`_normalizeRecordedVideo()`](../lib/managers/video_manager.dart:3043)

---

## 2) 첫 진입 카메라 오픈이 느려질 수 있는 핵심 원인

### A. 초기화 전/후 중복 비용

- 카메라 목록 선조회는 이미 하고 있으나, 실제 미리보기 준비 단계에서 다시 큰 비용이 발생합니다.
- 특히 `_initCameraAsync()` 내부에서 아래가 순차 실행됩니다.
  1. 필요 시 4K 지원 탐지용 별도 컨트롤러 생성/초기화/폐기
     - [`_probe4kSupport()`](../lib/screens/capture_screen.dart:233)
  2. 실제 사용 컨트롤러 `initialize()`
     - [`candidate.initialize()`](../lib/screens/capture_screen.dart:303)
  3. 부가 설정 호출(포커스/노출/줌 min/max 조회 및 적용)
     - [`setFocusMode()`](../lib/screens/capture_screen.dart:327), [`setExposureMode()`](../lib/screens/capture_screen.dart:332), [`getMinZoomLevel()`](../lib/screens/capture_screen.dart:338)

→ 즉, "프리뷰 보이기"까지 필요한 작업이 많고, 일부는 첫 프레임 이후로 미뤄도 되는 성격입니다.

### B. 품질 후보 fallback 루프 비용

- 품질 모드에 따라 프리셋 후보를 순회하며 실패 시 다시 초기화 시도합니다.
  - [`_resolutionCandidatesForMode()`](../lib/screens/capture_screen.dart:208)
  - 반복 시도: [`for (final preset in candidates)`](../lib/screens/capture_screen.dart:292)

→ 특정 디바이스에서 첫 후보 실패 시 체감 지연이 커질 수 있습니다.

### C. 오디오 포함 초기화

- 초기화에서 `enableAudio: true`를 사용하고 있습니다.
  - [`CameraController(..., enableAudio: true)`](../lib/screens/capture_screen.dart:296)

→ 첫 진입 목적이 "프리뷰"라면, 오디오는 녹화 시작 직전에 준비해도 되는지 검토할 가치가 있습니다(플러그인/기기 제약 확인 필요).

---

## 3) 속도 개선 우선순위 제안 (실행 가능)

## P0 (즉시 적용 권장)

1. **첫 프리뷰 전 필수 작업 최소화**
   - 첫 프리뷰 표시 성공을 목표로 하고, 아래는 프리뷰 이후 비동기 지연 적용:
     - 4K probe
     - 노출/줌 범위 조회
     - 일부 부가 설정(실패 허용)

2. **`_probe4kSupport()` 지연 실행/캐시 강화**
   - 현재는 초기화 시점에서 probe가 실행될 수 있음.
   - 앱 최초 1회 + 카메라 렌즈별 캐시로 줄이고, 기본 모드는 1080p fast path 유지.

3. **해상도 fallback 루프 단축**
   - 기기별로 마지막 성공 프리셋을 저장해 다음 실행 시 첫 후보로 사용.

## P1 (체감 개선)

4. **탭 전환 직후 prewarm**
   - 현재 기본 탭이 카메라라 이미 유리하나, 앱 런치 직후 UI first frame 이후에 최소 프리뷰용 prewarm 루틴 분리 가능.

5. **TTFF 세분화 로깅 추가**
   - 이미 전체 TTFF 로깅 존재: [`logFirstCameraPreviewReady()`](../lib/main.dart:83)
   - 여기에 단계별(컨트롤러 init 시작/완료, probe 시간 등) 지표를 추가해 병목을 기기군별로 분리.

## P2 (구조 개선)

6. **컨트롤러 생명주기 재사용 전략 검토**
   - 탭 이동 시 완전 dispose 대신 상태 보존(메모리/배터리와 트레이드오프).

---


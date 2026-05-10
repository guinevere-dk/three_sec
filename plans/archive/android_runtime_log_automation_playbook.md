# Android 런타임 로그 자동 수집/분석 플레이북

## 1) 목표
- 앱 **실행 시작 → 사용자 동작 → 앱 종료(스와이프 아웃 포함)** 전체 구간의 로그를 1회 세션 단위로 수집
- 수집 로그에서 P0/P1 위험 신호(크래시, ANR 전조, 권한/저장공간/백그라운드/네트워크 실패)를 빠르게 분류

---

## 2) 사전 조건
- Windows + Android SDK + adb 사용 가능
- 단말/에뮬레이터 1대 연결
- 프로젝트 루트에서 실행

확인 명령:

```cmd
adb devices
```

---

## 3) 세션 로그 자동 수집 (CMD)

### 3-1. 로그 저장 폴더 생성
```cmd
if not exist logs mkdir logs
```

### 3-2. 기존 logcat 버퍼 정리
```cmd
adb logcat -c
```

### 3-3. 세션 타임스탬프 파일명 생성 후 캡처 시작
```cmd
for /f %i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%i
adb logcat -v threadtime > logs\session_%TS%_full.log
```

> 위 명령 실행 후 터미널을 열어둔 상태에서 앱을 실행/조작/종료합니다.

### 3-4. 앱 실행 (새 터미널)
```cmd
flutter run -d android
```

### 3-5. 테스트 종료 후 로그 수집 중지
- 로그 수집 터미널에서 `Ctrl + C`

---

## 4) 필수 재현 시나리오(최소 세트)
- 정상 플로우: 캡처(1초) → 라이브러리 선택 → 브이로그 생성 → 편집 진입 → 내보내기 시도 → 앱 종료
- 실패 플로우 4종:
  1. 권한 거부(카메라/마이크 또는 저장소)
  2. 저장공간 부족(촬영 또는 내보내기)
  3. 백그라운드 전환(처리/내보내기 중 잠금 또는 스와이프 종료)
  4. 네트워크 단절(오프라인 업로드/동기화)

각 시나리오마다 로그 파일 1개를 별도로 생성하는 것을 권장합니다.

---

## 5) 1차 자동 필터링 (오류 신호 추출)

아래 명령으로 핵심 에러 라인만 추출:

```cmd
findstr /I /C:" E/ " /C:" FATAL EXCEPTION" /C:"ANR" /C:"PlatformException" /C:"OutOfMemoryError" /C:"permission" /C:"denied" /C:"No space" /C:"timeout" logs\session_%TS%_full.log > logs\session_%TS%_errors.log
```

Flutter/Dart 레이어 신호 추출:

```cmd
findstr /I /C:"[Capture]" /C:"[VideoManager]" /C:"[CloudService]" /C:"[IAPService]" /C:"[AuthService]" /C:"[EditScreen]" logs\session_%TS%_full.log > logs\session_%TS%_appsignals.log
```

길이 정책 계측 키 추출(Phase 4 권장):

```cmd
findstr /I /C:"sourceDurationMs=" /C:"targetDurationMs=" /C:"normalizedDurationMs=" logs\session_%TS%_full.log > logs\session_%TS%_duration_metrics.log
```

---

## 6) 분석 기준 (릴리즈 게이트 관점)
- P0 즉시 차단:
  - `FATAL EXCEPTION`, 네이티브 크래시, 내보내기/브이로그 생성 불가, 데이터 유실 징후
- P1 경고:
  - 반복 timeout, 복구 가능한 권한/네트워크 실패, 성능 저하(프리징 체감)

분류 포맷(권장):
- 이벤트 시각
- 기능 영역(캡처/편집/내보내기/과금 등)
- 증상
- 추정 원인
- 재현 가능성
- 우선순위(P0/P1/P2)

---

## 7) 현재 코드 기준 의심 원인 후보(7개)
1. 캡처 컨트롤러 초기화/dispose 타이밍 경합
2. 편집 화면 컨트롤러 스왑 시점 race condition
3. 내보내기 전 권한/저장공간 체크 누락 또는 예외 전파 불충분
4. 백그라운드 전환 시 작업 상태 보존 정책 불일치
5. 네트워크 장애 시 재시도/오프라인 분기 불안정
6. IAP/인증 콜백 비동기 스트림 에러 처리 누락
7. 대용량 미디어에서 메모리 압박(OOM) 대비 미흡

### 우선 검증할 가능성 높은 2개
- (A) 편집/내보내기 구간의 비동기 컨트롤러 수명주기 경합
- (B) 저장공간/권한 실패 시 에러 표면화 부족으로 인한 사용자 체감 “무응답”

### 가설 검증용 로그 포인트(추가 계측 권장)
- 공통: `sessionId`, `scenarioId`, `screen`, `action`, `result`, `errorCode`, `elapsedMs`
- 캡처: `cameraInitStart/Done`, `startRecord`, `stopRecord`, `saveRecordedVideo`, 예외 stack
- 편집: `_loadClip`, controller swap, dispose, export start/end
- 내보내기: 권한 검사 결과, 저장공간 여유(MB), native engine 호출/응답 코드
- 생명주기: `paused/resumed/detached` 시 작업 상태 스냅샷

---

## 8) 제출 산출물 템플릿
- `logs/session_YYYYMMDD_HHMMSS_full.log`
- `logs/session_YYYYMMDD_HHMMSS_errors.log`
- `logs/session_YYYYMMDD_HHMMSS_appsignals.log`
- `logs/session_YYYYMMDD_HHMMSS_duration_metrics.log`
- 재현 메모(사용자 동작 타임라인 5~10줄)

이 4가지를 기반으로 다음 단계에서 원인 확정 및 수정 우선순위를 결정합니다.

---

## 9) 1초 길이 정책 모니터링 운영 (릴리즈 후 1주)
- 관찰 기간: 릴리즈 직후 7일
- 표본 기준: 캡처/정규화 성공 케이스 일별 100건 이상
- 실패 정의(권장):
  - `normalizedDurationMs`가 **1.0초 ± 0.15초** 범위를 벗어나는 케이스
  - 혹은 정규화 성공 로그 누락 + 저장 실패 로그 동반 케이스
- 일일 점검 항목:
  1. 길이 실패율(%)
  2. 기기군/OS 버전별 편차
  3. Android/iOS 간 편차 비교
  4. 회귀 징후(전일 대비 급증 여부)

운영 기록 포맷(권장):
- 날짜
- 플랫폼(Android/iOS)
- 샘플 수
- 실패 건수
- 실패율
- 상위 원인 3개
- 조치 상태(관찰/수정중/핫픽스)

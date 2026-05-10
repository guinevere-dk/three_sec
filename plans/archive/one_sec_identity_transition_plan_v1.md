# 1.5초 실제 길이 / 1s 표시 정책 반영 계획서 v1

작성일: 2026-03-30  
대상: `three_sec_vlog` 앱(Flutter + Android/iOS)

---

## 0) 목표

- 앱의 길이 처리 정책을 **실제 1.5초(1500ms)**로 정렬하고, 사용자 노출 카피는 **`1s`**로 유지한다.
- 촬영/변환/추출/편집 핵심 동선을 동일 정책으로 정합한다.
- 브랜드 정체성 문구(`3s`)는 범위에서 제외하고, 기능 카피는 `1.5초 실제`와 `1s 표시`가 충돌하지 않게 정리한다.

---

## 1) 사전 조사 요약 (수정 대상)

### A. 길이 정책 하드코딩(핵심)

1. **촬영 UI/타이머**
   - `lib/screens/capture_screen.dart`
   - 현재값: `int _remainingTime = 3`, `_targetRecordingMilliseconds = 3500`, clamp 상한 `3`
   - 조정: 표시 라벨은 `1`/`1s` 유지, 실제 timeout 기준은 1500ms로 변경

2. **녹화 저장 정규화(클립 길이 표준화)**
   - `lib/managers/video_manager.dart`
   - 현재값: `_targetRecordingDurationMs = 3000`
   - 조정: `_targetRecordingDurationMs`를 `1500`(또는 정책 상수)로 정렬

3. **구간 추출(편집 보조 화면)**
   - `lib/screens/clip_extractor_screen.dart`
   - 현재값: `start + 3000`, `total - 3000`, 토스트/안내문구의 `3초`
   - 조정: 계산은 `1500ms`, 안내/카피는 노출 규칙상 **`1초`/`1s`** 유지

4. **네이티브 기본값/로직(Android)**
   - `android/app/src/main/kotlin/com/dk/three_sec/MainActivity.kt`
   - 현재값: `convertImageToVideo` 기본 duration `?: 3`, `normalizeVideoDuration` fallback `3000L`, `extractClips` 기본 end `start + 3000L`
   - 조정: 실제 처리값은 1500ms 기반으로 정합하고 로그/표시는 노출/실제 분리 규칙 적용

5. **네이티브 로직(iOS)**
   - `ios/Runner/AppDelegate.swift`
   - `normalizeVideoDuration(targetDurationMs)` 경로 확인 필요
   - 조정: Flutter의 target ms를 신뢰하고 비정상값은 1500ms로 보정

6. **편집 duration fallback**
   - `lib/screens/video_edit_screen.dart`
   - 현재값: `Duration(seconds: 3)`
   - 조정: `Duration(milliseconds: 1500)`로 변경

### B. 사용자 노출 카피(브랜딩/문구)

1. 로그인/온보딩/알림성 문구
    - `lib/screens/login_screen.dart` (`1초의 일상을 기록하세요` 등 기능 텍스트)
    - `lib/screens/announcements_screen.dart` (`1초 영상만으로...` 등 기능 텍스트)
   - `lib/main.dart` (`3s로 나만의 영상앨범...`)
   - 조정: 기능 노출은 `1s`로 정렬, `3s` 브랜드 표기는 유지 범위로 분리

2. 테스트/운영 문서
   - `plans/android_capture_manual_test_checklist.md` (3초 고정 녹화)
   - `plans/android_qa_journey_release_gate_v1.md` (3초 녹화 시나리오)
   - `plans/android_runtime_log_automation_playbook.md` (캡처 3초)
   - 조정: 해당 문서는 실제는 1500ms, 노출은 1s 기준으로 갱신

---

## 2) 변경 원칙

1. **실제 길이와 노출 라벨 분리**
   - 실제 처리 상수: `1500ms`
   - 노출 라벨: `1s`

2. **하위호환성 유지**
   - 기존 3초 자산은 재생/편집 호환성을 유지하고, 신규 생성분만 새 정책 적용

3. **브랜드 노출 고정**
   - `3s` 브랜드명/아이덴티티 문구는 정책 범위 외로 유지
   - 기능 카피만 `1s` 표시 규칙으로 정렬

---

## 3) 실행 계획 (단계별)

## Phase 1. 코어 길이 정책 전환

### 1-1. Flutter 상수 정리
- `lib/constants/clip_policy.dart` 또는 기존 상수 위치 정비
  - 실제 길이: `kTargetClipMs = 1500`
  - 표시 라벨: `kTargetClipSec = 1`
  - 타이머 버퍼: `kRecordingUiSafetyBufferMs` 정책 재정의

### 1-2. 촬영 화면 적용
- `capture_screen.dart`
  - `_remainingTime`/카운트다운 라벨은 표시 전용 `1`(`1s`) 유지
  - 실제 종료 트리거는 `1500ms` 정책 상수에 정렬
  - REC 타이머 피드백(진동/토스트/안내) 튜닝

### 1-3. 저장 정규화 적용
- `video_manager.dart`
  - `_targetRecordingDurationMs = 1500`
  - `normalizeVideoDuration` 인자(`targetDurationMs`)의 `1500` 정책 전달 검증

### 1-4. 구간 추출 적용
- `clip_extractor_screen.dart`
  - `3000` 기반 계산식을 `1500ms` 기반으로 변경
  - 안내/토스트는 노출 규칙(`1초`/`1s`) 적용

### 1-5. 편집 fallback 조정
- `video_edit_screen.dart`
  - duration fallback `Duration(milliseconds: 1500)`로 조정(정책 상수 참조)

**완료 기준(DoD)**
- 신규 촬영 클립 길이 평균 1.5초(1500ms)±허용오차
- 추출 클립 생성 분포가 1.5초 기준을 만족
- duration 조회 실패 시 `1500ms` fallback 정상 동작

---

## Phase 2. 네이티브 정합성

### 2-1. Android 정합성
- `MainActivity.kt`
  - `convertImageToVideo` 기본 duration을 1500 정책 경로로 정렬
  - `normalizeVideoDuration` fallback `3000L` → `1500L`
  - `extractClips` 기본 end `start + 3000L` → `start + 1500L`
  - 주석/로그 길이 문구를 **1500ms(실제) / 1s(표시)**로 구분

### 2-2. iOS 정합성
- `AppDelegate.swift`
  - `normalizeVideoDuration` 전달 target이 1500인지 검증
  - 전달값 부재 시 기본값을 1500으로 방어

**완료 기준(DoD)**
- Android/iOS 모두 이미지→영상 변환, 길이 정규화가 1.5초(1500ms) 기준으로 정합
- 플랫폼별 길이 편차가 운영 임계치 내 존재

---

## Phase 3. 카피/문서/QA 동기화

### 3-1. 사용자 문구 정리
- 대상: `login_screen.dart`, `announcements_screen.dart`, `main.dart`, `clip_extractor_screen.dart`
- 작업
  - 기능 문구의 `3초`를 `1s` 표시 규칙으로 정렬
  - 브랜드 `3s` 문구는 범위 분리 후 유지

### 3-2. QA/운영 문서 정리
- 대상: `plans/android_capture_manual_test_checklist.md`, `plans/android_qa_journey_release_gate_v1.md`, `plans/android_runtime_log_automation_playbook.md`
- 작업
  - 시나리오 기준 시간을 `1.5초(1500ms)` 기반으로 전환
  - 실패 임계치와 허용오차도 1500ms 기준으로 재정의

**완료 기준(DoD)**
- 앱 내 노출 문구와 QA 문서가 **실제 1500ms / 노출 1s** 규칙을 반영
- QA 담당자가 문서만으로 정책 충돌 지점을 판별 가능

---

## 4) 테스트 계획

### 4-1. 기능 테스트
- 촬영 단일 탭: 자동 종료 타이밍이 1500ms 정책을 따른다
- 연속 촬영 N회: 길이 분포(최소/최대/평균) 확인
- 구간 추출: 마지막 구간에서 음수/범위초과 없음
- 이미지→영상 변환: 결과 길이 1500ms
- 편집 진입: duration 캐시 실패 fallback 정상

### 4-2. 회귀 테스트
- 기존 3초 자산이 포함된 프로젝트 열기/편집/내보내기 호환성 확인
- Android/iOS 교차 검증(길이 편차/오디오 싱크)

### 4-3. 계측 권장
- 로그 키 추가/검증: `targetDurationMs`, `sourceDurationMs`, `normalizedDurationMs`
- `targetDurationMs` 기준값이 1500 또는 정책 상수와 일치하는지 확인
- 릴리즈 초기 1주일 길이 실패율 모니터링

---

## 5) 리스크 및 대응

1. **짧은 길이 전환으로 UX 체감 변화**
   - 대응: 카운트다운/진동/토스트 타이밍 보강

2. **기기별 인코더 지연으로 1.5초 편차 증가**
   - 대응: 네이티브 정규화 후 길이 로그 및 허용오차 운영

3. **브랜드(`3s`)와 기능(1.5초/1s) 혼선**
   - 대응: 릴리즈 노트에 “표시 1s, 실제 1.5초” 명시
   - 브랜드명 정비는 다음 단계에서 별도 결정

---

## 6) 최종 적용 순서

1. 코어 상수/길이 로직 정렬(Flutter + Android/iOS)
2. 내부 QA를 통한 길이/추출/편집/내보내기 검증
3. 사용자 카피 및 운영 문서 동기화
4. 스테이징 릴리즈 후 모니터링
5. 모니터링 결과 기반 게이트 통과 시 프로덕션 반영

---

## 7) 이번 변경 범위에서 제외(권장)

- 패키지명 `com.dk.three_sec`
- Firebase 프로젝트명/URL (`fir-3s-8edb9`)
- IAP 상품 ID (`3s_*`)

위 항목은 결제/스토어/백엔드 연계 영향도가 크므로 길이 정책 전환과 분리한다.


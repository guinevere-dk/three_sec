# Edit 하단 기능 고도화 조사/설계 계획서 v1 (구현 전)

## 0. 문서 목적
- 본 문서는 **구현 문서가 아니라 설계/기획 문서**다.
- 범위: 편집 하단 기능 중 미완성/미흡 영역인 **자막, 스티커, 화면회전(Transform), AI 기능**.
- 기준 화면: [`VideoEditScreen`](lib/screens/video_edit_screen.dart:158).

## 1. 조사 범위와 출처

### 1-1. 내부 벤치마크/기존 문서
- 편집 메인 UI 패턴: [`benchmark/Design_Spec_Edit_Main_v1.md`](benchmark/Design_Spec_Edit_Main_v1.md)
- AI 패널 패턴: [`benchmark/Design_Spec_Edit_AI_v1.md`](benchmark/Design_Spec_Edit_AI_v1.md)
- 트리머/사운드 연결 패턴: [`benchmark/Design_Spec_Edit_Trimmer_v1.md`](benchmark/Design_Spec_Edit_Trimmer_v1.md), [`benchmark/Design_Spec_Edit_Sound_v1.md`](benchmark/Design_Spec_Edit_Sound_v1.md)
- 기존 통합 개선안: [`plans/edit_screen_integration_plan.md`](plans/edit_screen_integration_plan.md)

### 1-2. 현재 앱 코드 기준점
- 하단 툴바 진입점: [`_buildToolbarSection()`](lib/screens/video_edit_screen.dart:1839)
- 텍스트 액션: [`_showAdvancedCaptionDialog()`](lib/screens/video_edit_screen.dart:3003)
- 스티커 액션: [`_showStickerLibrary()`](lib/screens/video_edit_screen.dart:3067)
- Transform 액션(현재 비어있음): [`_buildToolbarItem(Icons.crop_rotate, "Transform", () {})`](lib/screens/video_edit_screen.dart:1857)
- AI/Effects 액션(현재 필터 다이얼로그): [`_showFilterDialog()`](lib/screens/video_edit_screen.dart:2951)
- 오버레이 렌더링: [`_buildStickerWidget()`](lib/screens/video_edit_screen.dart:3180), [`_buildSubtitleWidget()`](lib/screens/video_edit_screen.dart:3213)

### 1-3. 외부(업계 공통) 패턴 조사 관점
실제 서비스별 세부 UI는 다르지만, 숏폼 편집기(틱톡/릴스/쇼츠/캡컷 계열)에서 공통적으로 반복되는 구조를 추상화했다.

1) 하단 툴바 → 모드 진입(텍스트/스티커/트랜스폼/AI)
2) 미리보기 캔버스 직접 조작(드래그/핀치/회전)
3) 하단 속성 패널(스타일/시간/애니메이션/강도)
4) 타임라인 트랙 반영(클립 기준/전체 기준)
5) 비파괴 편집 상태 저장 후 최종 렌더링 합성

---

## 2. 현재 상태 진단 (우리 앱)

## 2-1. 자막
- 데이터 모델은 이미 존재: [`SubtitleModel`](lib/screens/video_edit_screen.dart:19) (text/위치/font/time range)
- 추가/수정 진입은 단일 텍스트 입력 다이얼로그 중심: [`_showAdvancedCaptionDialog()`](lib/screens/video_edit_screen.dart:3003)
- 미리보기 조작은 이동/확대 위주: [`_buildSubtitleWidget()`](lib/screens/video_edit_screen.dart:3213)
- 한계
  - 자막 트랙(목록/순서/레이어) 부재
  - 스타일 프리셋/정렬/폰트/애니메이션 체계 부재
  - 타임라인 기반 정밀 시간 편집 UX 부재

## 2-2. 스티커
- 데이터 모델/추가/이동·스케일은 존재: [`StickerModel`](lib/screens/video_edit_screen.dart:55), [`_showStickerLibrary()`](lib/screens/video_edit_screen.dart:3067), [`_buildStickerWidget()`](lib/screens/video_edit_screen.dart:3180)
- 한계
  - 회전/미러/투명도/블렌딩/레이어 순서 제어 부재
  - 카테고리/검색/최근 사용/즐겨찾기 등 라이브러리 관리 부재
  - 시간축(in/out) 편집 UI 부재

## 2-3. 화면회전(Transform)
- 하단 버튼 노출은 있으나 실행 로직 없음: [`_buildToolbarItem(Icons.crop_rotate, "Transform", () {})`](lib/screens/video_edit_screen.dart:1857)
- 벤치마크에는 Transform이 독립 툴로 존재: [`Transform` 라벨](benchmark/Design_Spec_Edit_Main_v1.md:160)
- 한계
  - 90도 회전/플립/줌/위치/캔버스 맞춤(fill/fit) 부재
  - 키프레임 없는 정적 변환조차 미완성

## 2-4. AI 기능
- 메인 하단에는 Effects 버튼 존재: [`Effects` 영역](benchmark/Design_Spec_Edit_Main_v1.md:170)
- 현재 앱은 필터 선택 중심: [`_showFilterDialog()`](lib/screens/video_edit_screen.dart:2951)
- AI 전용 패널 패턴은 별도 설계 존재: [`AI Magic Tools`](benchmark/Design_Spec_Edit_AI_v1.md:58)
- 한계
  - “AI 작업 큐/진행 상태/실패 복구”가 데이터 모델에 반영되지 않음
  - 기능 on/off 토글 수준 이상의 파라미터 체계 부재
  - 구독 등급/비용/시간(처리 대기) UX가 일관되지 않음

---

## 3. 기능별 업계 공통 구성 패턴

## 3-1. 자막 (Caption/Subtitles)
일반 구성은 아래 4층으로 분리된다.

1) **콘텐츠층**: 텍스트, 타임코드(in/out), 화자/자동자막 세그먼트
2) **스타일층**: 폰트/크기/컬러/배경/그림자/정렬/애니메이션 프리셋
3) **배치층**: 캔버스 좌표, safe area 스냅, 회전/스케일
4) **트랙층**: 자막 블록 리스트, 병합/분할, 레이어 우선순위

핵심 UX 패턴:
- “캔버스 직접 조작 + 하단 속성 패널 + 타임라인 블록 편집”의 3점 구조
- 빠른 결과를 위해 “스타일 프리셋” 우선 제공, 세부 파라미터는 2차 패널로 분리

## 3-2. 스티커
일반 구성:

1) 라이브러리(카테고리/검색/최근/즐겨찾기)
2) 캔버스 조작(이동/확대/회전/미러)
3) 속성(불투명도, 블렌드, 그림자/외곽선)
4) 시간 제어(in/out, 페이드)
5) 레이어 제어(앞/뒤 배치)

핵심 UX 패턴:
- 추가 즉시 중앙 배치 → 바로 조작
- 선택 시 바운딩 박스 + 회전 핸들 + 삭제/복제 퀵 액션

## 3-3. 화면회전/Transform
일반 구성:

1) 빠른 변환: 90° 회전, 좌우/상하 플립
2) 프레이밍: Fit / Fill / Stretch + 위치 오프셋
3) 미세 조정: scale/rotation/x/y 슬라이더 리셋
4) 클립별 적용 또는 전체 적용(scope)

핵심 UX 패턴:
- “원탭 프리셋(90도, 미러)” + “정밀 슬라이더” 동시 제공
- 원본 비율/캔버스 비율 불일치 시 가이드(잘림 영역 표시)

## 3-4. AI 기능
일반 구성:

1) AI 툴 목록(토글형 또는 카드형)
2) 각 툴 파라미터(강도, 모드, 대상 구간)
3) 작업 실행/대기열/진행률/취소
4) 결과 비교(Before/After)와 적용 확정
5) 요금/등급 배지(PRO 등) + 실패 시 재시도

핵심 UX 패턴:
- 즉시 실행보다 “요약 예상시간 + 배터리/네트워크 안내 + 백그라운드 지속”이 중요
- AI 결과는 비파괴 상태로 보관하고, 최종 적용 전 되돌리기 가능하게 유지

---

## 4. 우리 앱 권장 구성안 (구현 전 설계)

## 4-1. 공통 아키텍처 원칙
1) **비파괴 편집 유지**: 원본 클립 변경 없이 편집 메타만 누적
2) **모드 분리**: Text/Sticker/Transform/AI 진입 시 하단 서브패널 교체
3) **트랙 중심 상태 관리**: 오버레이를 배열이 아닌 트랙 아이템 컬렉션으로 관리
4) **Undo/Redo 일관성**: 모든 모드 변경을 동일 명령 단위로 커밋

## 4-2. 하단 정보구조(IA) 제안
- 1단(글로벌 툴): Edit / Text / Sticker / Speed / Transform / Sound / Effects
- 2단(모드 패널): 선택 툴의 속성 패널
- 3단(타임라인): 현재 선택 객체 또는 클립의 시간 범위 편집

> 현재 툴 구조는 이미 존재하므로 [`_buildToolbarSection()`](lib/screens/video_edit_screen.dart:1839) 확장 중심이 합리적.

## 4-3. 자막 권장 구성
### A. 최소완성(MVP)
- 텍스트 추가/수정 + 위치/크기 + in/out 시간 편집
- 스타일 프리셋 6~10종(가독성 우선)
- 자막 리스트 패널(선택/삭제/복제)

### B. 확장
- 자동자막(STT) import
- 단어 강조/애니메이션 템플릿
- 다국어/줄바꿈 규칙

## 4-4. 스티커 권장 구성
### A. 최소완성(MVP)
- 카테고리 탭 + 최근 사용
- 이동/확대 + 회전 핸들
- in/out 시간 편집 + 레이어 앞뒤

### B. 확장
- 템플릿 스티커 팩(계절/감정)
- 사용자 이미지 스티커화

## 4-5. Transform 권장 구성
### A. 최소완성(MVP)
- 회전(90°), 좌우반전, Fit/Fill 토글
- X/Y/Scale 슬라이더 + Reset
- 클립 단위 적용

### B. 확장
- 키프레임 transform
- 자동 리프레임(피사체 추적)

## 4-6. AI 권장 구성
### A. 최소완성(MVP)
- AI 패널을 토글 리스트로 구성(벤치마크 UI 계승): [`AI Magic Tools`](benchmark/Design_Spec_Edit_AI_v1.md:58)
- 기능별 상태: Off / Pending / Applied / Failed
- 처리 중 진행률/예상시간/취소, 실패 재시도
- PRO 배지와 기능 잠금 정책 일관화

### B. 확장
- Before/After 스플릿 뷰
- 클립 범위 선택 적용
- 서버형 모델과 온디바이스 모델 혼합 운용

---

## 5. 데이터/상태 설계 제안 (개념)

## 5-1. 오버레이 공통 엔티티
- 공통 필드: id, type(text/sticker), clipId or global, startMs/endMs, zIndex, transform(x,y,scale,rotation), style
- 자막/스티커를 별도 배열로 두기보다 “공통 오버레이 컬렉션 + 타입별 상세” 구조 권장

## 5-2. Transform 엔티티
- perClipTransform: rotation90Step, flipX, flipY, fitMode, offsetX, offsetY, scale

## 5-3. AI 작업 엔티티
- aiJobs: jobId, toolType, targetClipIds, params, status, progress, errorCode, createdAt

---

## 6. 화면/인터랙션 규칙 제안

1) 객체 선택 상태를 시각적으로 통일(하이라이트 링/핸들/컨텍스트 액션)
2) 모드 진입 시 상단 제목 + 우측 적용/닫기 패턴 통일
3) 하단 패널 높이 2단계(Compact/Expanded) 제공
4) 편집 중 실수 방지: 삭제는 즉시 반영 + Undo 토스트

---

## 7. 우선순위 로드맵 (구현 전 합의안)

### Phase 1 (빠른 완성도 확보)
1. Transform MVP (현재 공백 기능 채우기)
2. 자막 리스트 + 스타일 프리셋
3. 스티커 회전/레이어/in-out

### Phase 2 (차별화)
1. AI 패널 정식화(작업 상태/실패복구)
2. 자동자막/AI 보정의 범위 적용
3. Before/After 비교 UX

### Phase 3 (고급)
1. 키프레임
2. 템플릿/프리셋 마켓 성격 확장

---

## 7-A. Transform 상세 실행계획 (기획)

### 7-A-1. 목표/범위
- 목표: 현재 공백 액션인 Transform을 **클립 단위 비파괴 편집**으로 완성한다.
- 기준 액션 위치: [`_buildToolbarItem(Icons.crop_rotate, "Transform", () {})`](lib/screens/video_edit_screen.dart:1857)
- 제외 범위(이번 단계): 키프레임, 피사체 자동추적, 원근 왜곡.

추가 정책(첨언 반영):
- **캔버스 화면비(가로/세로 비율)는 프로젝트 전역(Global) 설정**으로 동작.
- 회전/반전/확대/이동/각도는 **클립 단위(Local)** 로 동작.

### 7-A-2. 사용자 시나리오
1) 사용자가 하단 `Transform` 진입
2) 프리셋(회전/반전/맞춤) 즉시 적용
3) 필요 시 미세조정(Scale/X/Y/Angle)
4) `Reset` 또는 `Apply`로 확정
5) Undo/Redo에서 1단위 명령으로 되돌림

### 7-A-3. IA/패널 구조
- 혼선 방지를 위해 Transform을 **2개 하위 패널로 분리**한다.

1) **Canvas 패널(전역)**
   - 항목: 화면비(9:16 / 1:1 / 16:9), 배경 채움 규칙
   - 적용 범위: 프로젝트 전체 클립 일괄

2) **Clip Transform 패널(클립 단위)**
   - 상단: 제목 `Clip Transform`, 우측 `Reset`, `Apply`
   - 본문 1행(퀵 액션): Rotate 90°, Flip H/V, Fit/Fill
   - 본문 2행(정밀 슬라이더): Scale, X, Y, Angle(선택)

권장 진입 동선:
- 하단 `Transform` 탭 진입 후 `Canvas | Clip` 세그먼트 탭으로 분기
- 또는 하단 툴 자체를 `Canvas`와 `Transform`으로 분리(대안)

### 7-A-3A. 상단 Canvas 아이콘 배치/Overflow 대응
- 첨언 반영 기본안: **Canvas는 상단 헤더 우측 아이콘으로 분리**, 하단에는 `Clip Transform`만 유지.
- 상단 헤더 우선순위(좌→우): 닫기(X) / 제목 / Undo / Redo / Canvas / Done
- 공간 부족 시 규칙:
  1) 아이콘 라벨은 미표시(아이콘만)
  2) `Undo/Redo`를 하나의 `History` 아이콘 메뉴로 축약
  3) `Canvas`를 1차 우선 유지, `History`를 오버플로우 메뉴로 이동
  4) 최소 너비 임계치 미만일 때는 `Done`을 텍스트→아이콘 체크로 축약
- 태블릿/가로모드 규칙:
  - 헤더 1열 고정, 기능 숨김 없이 모두 노출
  - 하단은 `Clip Transform`의 슬라이더 레이아웃만 2열 확장
- 접근성 규칙:
  - 헤더 아이콘 터치 타깃 44dp 이상
  - `Canvas` 진입 시 현재 화면비 프리셋을 보조 텍스트로 읽어주기

### 7-A-4. 상태 모델 제안
- 엔티티를 전역/클립으로 분리한다.

1) `projectCanvas` (Global)
   - `aspectRatioPreset: r9_16 | r1_1 | r16_9`
   - `backgroundMode: blur_fill | solid_fill | crop_fill`

2) `perClipTransform` (Local)
   - `rotation90Step: int` (0,1,2,3)
   - `flipX: bool`
   - `flipY: bool`
   - `fitMode: fit | fill`
   - `offsetX: double`
   - `offsetY: double`
   - `scale: double`
   - `angle: double` (선택)

> 기존 개념 정의는 [`5-2. Transform 엔티티`](plans/edit_bottom_features_research_plan_v1.md:191)를 따른다.

### 7-A-5. 상호작용 규칙
- 회전/반전은 탭 즉시 프리뷰 반영
- 슬라이더는 `onChanged` 실시간 미리보기, `onChangeEnd` 커밋
- `Reset`은 해당 클립 transform만 초기화
- `Apply`는 모드 종료 + 커밋 보장
- 화면비 불일치 시 잘림 가이드를 프리뷰에 표시

### 7-A-6. Undo/Redo 커밋 단위
- 퀵 액션 1회 = 커밋 1회
- 슬라이더 드래그 1세션 = 커밋 1회
- 여러 컨트롤 연속 변경 후 `Apply` 시 배치 커밋(선호안) 또는 컨트롤별 커밋(대안) 중 하나로 고정

전역/클립 구분 규칙:
- `Canvas` 변경은 프로젝트 전역 커밋 1회
- `Clip Transform` 변경은 현재 클립 커밋 1회

### 7-A-7. 품질 기준(AC)
1) 5초 내 초보 사용자도 회전/반전/fit-fill 완료 가능
2) Undo 2회 이내 직전 상태 복원 가능
3) 클립 전환 후 transform 상태 일관 유지
4) 내보내기 결과가 프리뷰와 동일

### 7-A-8. 릴리즈 단계
- T1(MVP): Canvas(화면비 프리셋) + Clip Transform(Rotate90/Flip/Fit-Fill/Scale/X/Y) + Reset/Apply
- T2: Angle + Canvas/Clip 패널 고도화(가이드/프리셋)
- T3: 키프레임/자동 리프레임(별도 PRD)

---

## 7-B. AI 상세 실행계획 (기획)

### 7-B-1. 목표/범위
- 목표: `Effects`를 단순 필터 선택에서 **AI 작업 파이프라인**으로 확장.
- 현재 진입점: [`_showFilterDialog()`](lib/screens/video_edit_screen.dart:2951)
- 벤치마크 패턴: [`AI Magic Tools`](benchmark/Design_Spec_Edit_AI_v1.md:58)
- 제외 범위(이번 단계): 생성형 비디오 편집(텍스트-투-비디오), 고비용 클라우드 추론.

### 7-B-2. 기능 카탈로그(우선순위)
MVP 후보(토글형):
1) Auto Color
2) Audio Cleanup
3) Video Denoise
4) Smart Moments 추천 (신규)

확장 후보:
5) Smart Moments 자동 편집(원탭 초안 생성)
6) 추천 결과 공유/재추천 루프

기능 상세 설명:
- **Auto Color**
  - 입력 영상의 노출/화이트밸런스/채도 균형을 자동 보정
  - 파라미터: 강도(0~100), 톤 프로필(Neutral/Vivid/Warm)
  - 출력: 색감만 수정된 비파괴 보정 레이어

- **Audio Cleanup**
  - 배경 노이즈(바람/허밍/환경음) 감쇠 + 음성 대역 보존
  - 파라미터: 노이즈 제거 강도, 음성 우선 모드
  - 출력: 오디오 클린업 처리본(원본 롤백 가능)

- **Video Denoise**
  - 저조도 노이즈/그레인 완화
  - 파라미터: 강도, 디테일 보존 레벨
  - 출력: 프레임 노이즈 감소 결과

- **Smart Moments 추천 (신규, MVP 포함)**
  - 각 클립의 메타데이터(위치/인물/날짜/중요도)를 결합해 추천 시나리오를 생성
  - 추천 타입:
    1) 여행 요약(위치+날짜 기반)
    2) 인물 모음(얼굴 군집 기반)
    3) 하이라이트(중요도/반응도 기반)
  - 파라미터:
    - 기간(최근 7일/30일/사용자 지정)
    - 대상 인물(전체/특정 인물)
    - 길이(15s/30s/60s)
  - 출력:
    - “추천 프로젝트 초안” 목록(원본 비파괴)
    - 사용자 선택 후 편집 화면으로 즉시 진입

### 7-B-2B. Smart Moments 메타데이터 설계
- 클립별 저장 필드(개념):
  - `capturedAt` (촬영 일시)
  - `geo` (위도/경도/장소명)
  - `faceClusterIds` (인물 군집 ID 목록)
  - `importanceScore` (0~1)
  - `motionScore`, `audioClarityScore` (선택)
- 프라이버시 원칙:
  - 얼굴 임베딩/민감 메타는 로컬 우선 저장
  - 클라우드 업로드 시 사용자 동의 기반으로 익명화/축약값만 전송
- 추천 점수식(개념):
  - `recommendScore = recency * w1 + importance * w2 + personMatch * w3 + locationNovelty * w4`
  - 가중치는 앱 버전별 실험값으로 관리

### 7-B-2A. AI 기능 설명(사용자 안내 문구)
- AI 패널 상단에 “AI가 해주는 일” 요약 카드 제공:
  - 영상 색감 자동 보정
  - 잡음 감소 및 음성 선명화
  - 저조도 화질 개선
  - 메타데이터 기반 자동 영상 추천(Smart Moments)
- 각 기능 row의 보조 설명 문구는 [`benchmark/Design_Spec_Edit_AI_v1.md`](benchmark/Design_Spec_Edit_AI_v1.md) 톤을 따른다.

### 7-B-2C. Smart Moments UX 흐름
1) 사용자가 `Effects` 또는 라이브러리의 `추천` 엔트리에서 `Smart Moments` 진입
2) 추천 카드(여행/인물/하이라이트)와 예상 길이, 사용 클립 수 확인
3) 카드 선택 후 `초안 생성` 실행
4) 생성된 추천 프로젝트를 프리뷰
5) `편집하기`로 [`VideoEditScreen`](lib/screens/video_edit_screen.dart:158) 진입
6) 사용자가 채택/폐기/재추천 선택

### 7-B-3. UX 흐름
1) `Effects` 진입 → AI 툴 리스트 표시
2) 각 툴 토글 + 세부 강도 선택
3) `Apply` 시 작업 생성
4) 작업 상태 표시(Pending/Running/Applied/Failed)
5) 완료 시 Before/After 비교 후 확정

### 7-B-4. 작업 상태 머신
- 상태: `off` → `pending` → `running` → `applied`
- 예외: `running` → `failed` → `retry_pending` → `running`
- 취소: `pending|running` → `canceled`

### 7-B-5. 데이터 모델 제안
- 엔티티: `aiJobs`
- 필드:
  - `jobId`
  - `toolType`
  - `targetClipIds`
  - `params` (강도/모드)
  - `status`
  - `progress` (0~100)
  - `errorCode`
  - `createdAt`, `updatedAt`

추가 엔티티(추천 기능):
- `clipAiMeta`
  - `clipId`, `capturedAt`, `geo`, `faceClusterIds`, `importanceScore`, `version`
- `smartMomentRecommendations`
  - `recommendationId`, `type`, `targetClipIds`, `score`, `reasonTags`, `createdAt`, `status`

> 기존 개념 정의는 [`5-3. AI 작업 엔티티`](plans/edit_bottom_features_research_plan_v1.md:194)를 따른다.

### 7-B-6. 요금/권한 정책
- FREE/STANDARD: AI 실행 잠금
- PREMIUM: AI 기능 사용 가능(정식 적용)
- 툴별 배지 정책 고정:
  - 잠금 상태(FREE/STANDARD): `PREMIUM` 배지 + 잠금 아이콘
  - 사용 가능(PREMIUM): 배지 제거 또는 `AI ON` 상태 칩

정책 고지 위치:
- AI 패널 상단: “Premium 전용 기능” 1줄 안내
- 잠금 툴 탭 시: 페이월 진입 전 기능 설명 모달 1회 노출

비용/처리 전략(질문 반영):
- 비용이 커지는 지점은 **얼굴 분석/클러스터링 + 대량 추천 재계산 + 서버 추론**이다.
- 비용 최적화 기본 전략:
  1) 1차 메타 추출은 온디바이스 우선(촬영 시/유휴 시 분산 처리)
  2) 추천 스코어링은 로컬 우선, 서버는 고급 추천/동기화 시에만 사용
  3) 서버 호출은 배치 처리(예: 하루 1회) + 변경분(증분)만 업로드
  4) FREE/STANDARD는 추천 미리보기 카드만 제한 제공, PREMIUM에서 전체 생성 허용

### 7-B-7. 실패/복구 전략
- 실패 원인 그룹: 리소스 부족, 파일 손상, 타임아웃, 권한/구독
- 사용자 메시지 원칙:
  - 기술코드 노출 최소화
  - 즉시 행동 가능한 버튼 제공(`재시도`, `원본으로 유지`)
- 재시도 정책:
  - 동일 파라미터로 1회 즉시 재시도
  - 연속 실패 시 가이드 모달

### 7-B-8. 성능/안정성 가드레일
- 장시간 작업은 백그라운드 지속 가능 설계
- 앱 이탈 후 복귀 시 작업 상태 복원
- 배터리 저전력/네트워크 불안정 상황에서 시작 전 경고

### 7-B-9. 품질 기준(AC)
1) 사용자는 AI 실행 상태를 항상 확인 가능
2) 실패 시 2탭 이내 재시도 가능
3) 작업 완료 후 결과 비교(전/후) 경로 제공
4) 구독 등급과 노출 기능이 불일치하지 않음

### 7-B-10. 릴리즈 단계
- A1(MVP): 3개 AI 툴 + Smart Moments(여행/인물/하이라이트 카드) + 상태머신 + 실패재시도
- A2: Smart Moments 초안 생성/편집 연동 + Before/After + 범위 적용
- A3: 온디바이스/서버 하이브리드 최적화 + 추천 품질 피드백 루프

---

## 8. 완료 기준(기획/설계 단계)
- 본 문서 기준으로 기능별 **IA, 상태모델, UX 규칙, 단계별 우선순위**가 모두 정의되어야 한다.
- 코드 구현/리팩터링은 본 문서 범위에서 제외한다.

---

## 9. 요약
- 현재 앱은 자막/스티커의 “기초 조작”은 있으나, 트랙·시간·스타일·레이어·AI 작업상태 체계가 약하다.
- 가장 큰 공백은 Transform 기능의 미구현과 AI 패널의 상태 관리 부재다.
- 따라서 단기적으로는 “Transform MVP + 자막/스티커 시간축/레이어 강화”, 중기적으로는 “AI 작업 파이프라인”이 최적 경로다.

Phase 1 테스트 후 소감
1. X, Y, Scale, Angle 은 프리뷰에서 손가락 액션으로 바로 적용할 수 있으면 좋겠다. 토글버튼으로 on, off해서 on 일 때만 움직일 수 있게
2. 그럴려면 모드 버튼과 토글 버튼으로 양분해야할 것 같다.
3. 상단에 버튼이 많아져서 번잡하다. 최상단에 X, 제목, 만들기 버튼만 두고, 그 아래에 나머지 버튼을 배치하여 좀 더 깔끔하게 보이게 하자.

---

## 10. Phase 1 소감 반영 추가 개선 계획 (구현 전)

### 10-1. 개선 목표 요약
- 목표 A: Transform 정밀 조정(X/Y/Scale/Angle)을 **슬라이더 중심 + 제스처 직조작**의 하이브리드로 개선한다.
- 목표 B: 상호작용 충돌을 줄이기 위해 `모드(선택)`와 `조작 활성화(토글)`를 분리한다.
- 목표 C: 상단 액션 과밀을 해소하기 위해 헤더를 **2단 구조**로 재편한다.

### 10-2. 정보구조(IA) 재정의
#### A) 상단 1열 (글로벌 헤더)
- 좌: `X`(닫기)
- 중: 화면 제목(예: `편집`, `Transform`)
- 우: `만들기`(완료/내보내기)

#### B) 상단 2열 (컨텍스트 액션 바)
- 기본 노출: Undo, Redo, Canvas, 기타 모드별 액션
- 원칙: 1열은 항상 고정(최소 인지 부하), 2열은 모드별 가변
- Overflow: 공간 부족 시 2열 액션만 우측 더보기로 축약

> 기존 7-A-3A의 헤더 우선순위를 “단일 행 우선순위”에서 “2행 분리 우선순위”로 업데이트한다.

### 10-3. Transform 조작 모델(모드 vs 토글 분리)
#### A) 모드 버튼
- `Move`, `Scale`, `Rotate` 3개 모드 버튼 제공
- 선택 모드에 따라 제스처 해석 규칙 고정:
  - Move: 1손가락 드래그 = X/Y 이동
  - Scale: 2손가락 핀치(또는 1손가락 세로 드래그 대체 옵션)
  - Rotate: 2손가락 회전(또는 다이얼 제스처)

#### B) 조작 토글
- `직접 조작` 토글(ON/OFF) 도입
- OFF: 프리뷰 제스처 비활성, 슬라이더/스텝퍼만 동작
- ON: 선택 모드의 제스처만 활성화(나머지 제스처는 무시)

#### C) UX 안전장치
- 토글 ON 진입 시 1회 코치마크: “현재 Move 모드, 드래그로 위치 조정”
- 토글 ON 상태에서 객체 미선택 시 “대상을 먼저 선택하세요” 토스트
- 토글 자동 복귀 옵션(권장): Apply 또는 모드 이탈 시 OFF

### 10-4. 제스처/슬라이더 동기화 규칙
- 제스처 변경값은 슬라이더 값에 즉시 반영(양방향 동기화)
- 커밋 단위:
  - 제스처 1회 연속 동작(start~end) = 커밋 1회
  - 슬라이더 1회 드래그(start~end) = 커밋 1회
- 동시 입력 충돌 방지:
  - 제스처 활성 중 슬라이더 입력 잠금 또는 큐잉(택1, 정책 고정)

### 10-5. 상태 모델 확장(개념)
- `transformUiState` 추가:
  - `activeMode: move | scale | rotate`
  - `directManipulationEnabled: bool`
  - `showGestureCoachmark: bool`
  - `lastInputSource: gesture | slider | quickAction`
- 저장 범위:
  - `activeMode`, `directManipulationEnabled`는 세션 UI 상태(영속 저장 비권장)
  - 실제 결과값(X/Y/Scale/Angle)은 기존 `perClipTransform`에만 저장

### 10-6. 상단 2행 구조 상세 가이드
- 1행 높이: 고정(브랜드/핵심 액션 안정성 확보)
- 2행 높이: Compact/Expanded 전환 가능
- 스크롤/패널 상호작용:
  - 하단 패널 확장 시 2행을 아이콘-only Compact로 축약
  - 프리뷰 집중 모드에서는 2행 자동 숨김(1행은 유지)

### 10-7. 접근성/학습비용 대응
- 모든 아이콘에 텍스트 대체 레이블 제공(스크린리더)
- 모드 전환 시 햅틱 + 짧은 상태 안내(예: “Rotate 모드”)
- 왼손/오른손 사용자 고려: 2행 액션 좌우 스왑 옵션(확장 단계)

### 10-8. 단계별 반영 로드맵(추가)
#### P1-UX Hotfix
1) 상단 2행 레이아웃 적용(1행: X/제목/만들기)
2) Transform에 `직접 조작` 토글 추가
3) Move 모드 제스처 우선 도입(X/Y)

#### P1.5-Usability
1) Scale/Rotate 모드 제스처 확장
2) 코치마크/토스트/자동 OFF 정책 정교화
3) 제스처-슬라이더 충돌 정책 확정

#### P2-Polish
1) 입력 소스별 미세 진동/가이드 개선
2) 2행 Overflow/Compact 애니메이션 고도화
3) 편집 세션 로그 기반 사용성 튜닝

### 10-9. 수용 기준(AC) 추가
1) 초보 사용자가 10초 내에 `직접 조작 ON → Move 드래그 → Apply`를 완료할 수 있다.
2) 모드/토글 오동작으로 인한 의도치 않은 화면 이동이 재현되지 않는다.
3) 상단 1행은 모든 모드에서 동일한 시각 구조를 유지한다.
4) Undo/Redo 시 제스처 편집 1세션이 1단위로 일관 복원된다.
5) 접근성 리더가 모드/토글 상태를 정확히 읽어준다.

### 10-10. 오픈 이슈(구현 전 의사결정 필요)
- 쟁점 1: `직접 조작` 토글의 기본값(항상 OFF vs 최근 상태 기억) - 항상 OFF
- 쟁점 2: Rotate 제스처를 2손가락 회전으로 고정할지, 1손가락 대체 UI를 병행할지 - 2손가락 회전
- 쟁점 3: 2행 액션의 최대 아이콘 수(권장 4~5개)와 Overflow 임계치 - 5개

Phase1 2차 테스트 소감
1. 갤럭시 갤러리 편집모드에서 보면 Transform 버튼을 선택했을 때 프리뷰 위에 반투명 버튼 모음이 뜬다. 반전, 회전, 비율, 각도. 이걸 상세히 분석해서 그대로 차용해라.

Phase1 3차 테스트 소감
1. 더이상 하단 팝업은 필요없다. 제거해라. 반투명 버튼 모음으로만 동작시킨다.
2. 반투명 버튼 모음은 아이콘만 남기고, 글자는 지워라.
3. 크기는 갤럭시 갤러리를 참고해서 다듬어라.

---

## 11. Phase 1 3차 소감 반영 추가 계획 (구현 전)

### 11-1. 목표 재정의
- Transform UX를 **하단 시트 기반**에서 **프리뷰 상단 반투명 퀵바 기반**으로 전환한다.
- 텍스트 라벨을 제거하고 **아이콘-only 인터랙션**으로 단순화한다.
- 갤럭시 갤러리 편집모드 레퍼런스를 따라, 퀵바 크기/간격/투명도/배치를 모바일 한손 조작 기준으로 재튜닝한다.

### 11-2. IA 변경안 (중요)
#### A) 제거
- 기존 `Clip Transform` 하단 팝업(바텀시트) 진입/유지 플로우 제거.
- 관련 `Apply/Reset`를 시트 헤더에서 수행하던 패턴 제거.

#### B) 유지 + 재배치
- Transform 핵심 액션은 프리뷰 상단 반투명 컨테이너에 고정:
  1) Flip
  2) Rotate 90°
  3) Fit/Fill
  4) Angle

#### C) 라벨 정책
- 버튼 하단 텍스트는 모두 제거하고 **아이콘만 노출**.
- 접근성은 `tooltip`, `semanticLabel`로 보완.

### 11-3. 상호작용 규칙
1) Transform 진입 시: 퀵바 즉시 표시, 다른 모드 진입 시 자동 숨김.
2) Flip/Rotate/Fit-Fill: 탭 즉시 반영 + 커밋 1회.
3) Angle: 탭 시 `Rotate` 제스처 모드 활성(직접조작 ON), 재탭 시 OFF(토글).
4) Undo/Redo: 퀵바 액션도 기존 명령 스택 규칙과 동일하게 기록.
5) 하단 팝업이 없어도 사용자가 상태를 인지할 수 있게, 현재 활성 상태(예: Angle active)는 아이콘 강조 상태로 표시.

### 11-4. 레이아웃/비주얼 스펙 (이미지 참고 반영)
- 컨테이너:
  - 위치: 프리뷰 상단 내부, SafeArea 하단 여백 확보
  - 배경: 검정 반투명(`~40~48%`)
  - 모서리: 라운드 12~16dp
  - 높이: 터치 타깃 기준 최소 44dp 이상
- 아이콘 버튼:
  - 아이콘 크기: 20~24dp
  - 터치 타깃: 44dp 이상
  - 기본 상태: 흰색 85~100%
  - 활성 상태: 브랜드 컬러 하이라이트 + 은은한 배경칩
- 간격:
  - 좌우 패딩 10~14dp
  - 액션 간 간격 12~18dp

### 11-5. 충돌/가드레일
- 프리뷰 탭 재생 토글과 Transform 제스처 충돌 방지:
  - Transform 모드 ON 시 단일 탭 재생 토글 비활성 유지(현행 유지)
- Trim 모드 진입 시 퀵바 강제 숨김.
- 클립 미선택/없음 상태에서는 퀵바 비노출.

### 11-6. 상태 모델 업데이트
- `transformUiState` 보강:
  - `isTransformModeActive`
  - `quickBarVisible`
  - `activeQuickAction: none | flip | rotate90 | fitFill | angle`
- 영속 정책:
  - 위 UI 상태는 세션 상태(저장 제외)
  - 실제 변환 결과는 기존 `perClipTransform`만 저장

### 11-7. 단계별 실행 계획 (Plan)
#### P1-3A (구조 전환)
1) 하단 Transform 바텀시트 제거
2) Transform 진입/이탈 상태를 퀵바 중심으로 재배선

#### P1-3B (아이콘-only 전환)
1) 퀵바 텍스트 완전 제거
2) semantics/tooltip 추가로 접근성 보완

#### P1-3C (갤러리 레퍼런스 폴리싱)
1) 크기/간격/투명도 튜닝
2) 활성/비활성 대비 보정
3) 다양한 화면 폭(소형/일반/태블릿)에서 배치 검증

### 11-8. 수용 기준(AC) 추가
1) Transform 사용 시 하단 팝업이 나타나지 않는다.
2) 프리뷰 상단 퀵바는 아이콘만 표시된다(텍스트 0개).
3) 4개 액션(Flip/Rotate/FitFill/Angle)을 2탭 이내로 접근/실행할 수 있다.
4) 퀵바 사용 중 의도치 않은 재생/정지 오동작이 발생하지 않는다.
5) 접근성 리더에서 각 아이콘 기능명이 정확히 읽힌다.

### 11-9. 오픈 이슈 (구현 전 확정 필요)
- 쟁점 1: `Angle`을 단일 아이콘 토글로 둘지, 길게 누르기에서 민감도 옵션 노출할지- 단일 아이콘 토글로 두고, 선택 시 슬라이드 바를 나타나게해서 각도조절하게 해라.
- 쟁점 2: Fit/Fill 상태를 아이콘만으로 충분히 인지 가능한지(선택 윤곽선 강도 기준 정의 필요)- fit/fill은 손가락 액션으로 조절할 수 있으므로 별도 아이콘 필요없다.
- 쟁점 3: 헤더 2행과 퀵바 동시 노출 시 시각적 혼잡 임계치(어느 폭부터 축약할지) - 큰 문제 없을 것 같으나 추천값으로 가겠다.

### Phase 1 4차 테스트 소감
1. 버튼을 지금의 50% 크기로 줄이고, 간격도 줄여라 배경 도형도 맞춰서 줄여라.
2. 3번째 버튼은 삭제. 
3. Rotate 버튼은 선택하면 바로 아래 슬라이더 바가 나오고 그걸 좌우로 끌면 -180도 ~ +180도 회전할 수 있게 해라.
4. Transform을 눌러 활성화 된 순간부터 화면에서 손가락 액션을 하면 확대, 이동이 가능하게 해라.
5. Transform이 활성화되면 클립이 일시정지되고, 완료 순간까지 재생되지 않게해라.

---

## 12. Phase 1 4차 소감 반영 추가 계획 (구현 전)

### 12-1. 변경 목표
- Transform 퀵바를 **초소형 아이콘 툴바**로 재정의(현재 대비 약 50% 시각 크기).
- 액션 구성을 `Flip / Rotate` 중심으로 단순화하고, 기존 3번째 버튼(Fit/Fill)을 제거.
- `Rotate` 선택 시 즉시 하단에 각도 슬라이더를 노출해 `-180° ~ +180°`를 정밀 조절.
- Transform 활성화 시점부터 프리뷰 제스처(이동/확대)를 기본 허용.
- Transform 활성화 동안 재생을 강제 중지하고, 완료 전까지 재생 잠금.

### 12-2. IA/액션 구성 변경
#### A) 상단 반투명 퀵바 (아이콘-only)
1) Flip
2) Rotate
3) (삭제) Fit/Fill
4) 필요 시 확장 슬롯(예약)만 유지

#### B) Rotate 보조 컨트롤
- Rotate 아이콘 탭 시 퀵바 바로 아래에 **가로 슬라이더 1줄** 노출.
- 슬라이더 범위: `-180 ~ +180`, 중앙 `0` 스냅.
- 슬라이더 숨김 조건: Rotate 비활성/Transform 종료/다른 모드 진입.

### 12-3. 시각 스펙(4차 피드백 반영)
- 퀵바 컨테이너:
  - 높이/패딩/라운드 모두 현재 대비 약 50% 축소(최소 터치타깃은 별도 보장)
  - 투명도/배경 톤은 유지하되, 도형 자체 크기만 축소
- 버튼:
  - 아이콘 시각 크기 축소(예: 22 → 18dp)
  - 버튼 간 간격 축소(예: 12~18dp → 6~10dp)
  - 접근성 터치 영역은 44dp 내외 유지(시각 크기와 히트박스 분리)

### 12-4. 인터랙션 규칙
1) Transform ON 즉시:
   - 현재 클립 재생 `pause`
   - 프리뷰 제스처에서 기본적으로 `move + scale` 허용
2) Transform ON 상태:
   - 재생 토글 탭/자동재생 루프 차단
   - Rotate 활성 시 각도 슬라이더로 즉시 각도 반영(실시간 프리뷰)
3) Transform OFF(완료) 시:
   - 마지막 상태 커밋
   - 재생 잠금 해제(자동 재생은 하지 않고 사용자 입력으로 재개)

### 12-5. 상태 모델 보강(개념)
- `transformUiState` 확장:
  - `isTransformModeActive: bool`
  - `isRotateSliderVisible: bool`
  - `activeQuickAction: none | flip | rotate`
  - `playbackLockedByTransform: bool`
- 저장 정책:
  - UI 상태(`isRotateSliderVisible`, `playbackLockedByTransform`)는 세션 상태로만 유지
  - 결과값(`offsetX/Y`, `scale`, `angle`)은 기존 `perClipTransform`에 저장

### 12-6. 충돌 방지 가드레일
- Trim 모드 진입 시 Transform UI(퀵바/슬라이더) 강제 종료.
- 클립 미존재/누락 상태에서 Transform ON 금지.
- Undo/Redo 단위:
  - Flip 1탭 = 1커밋
  - Rotate 슬라이더 1드래그 세션 = 1커밋
  - Move/Scale 제스처 1세션 = 1커밋

### 12-7. 단계별 실행 계획
#### P1-4A (UI 축소/단순화)
1) 퀵바 50% 축소 비율 적용
2) Fit/Fill 버튼 제거
3) 간격/도형 동시 축소

#### P1-4B (Rotate 슬라이더)
1) Rotate 선택 시 인라인 슬라이더 노출
2) -180~+180 범위 및 0 스냅 적용
3) 드래그 세션 커밋 규칙 반영

#### P1-4C (Transform 잠금 모드)
1) Transform ON 시 재생 일시정지 + 재생잠금
2) Move/Scale 제스처 기본 활성
3) 완료 시 잠금 해제 + 상태 정리

### 12-8. 수용 기준(AC)
1) 퀵바 버튼/배경이 현재 대비 체감 50% 수준으로 축소된다.
2) 퀵바 3번째 버튼(Fit/Fill)이 제거된다.
3) Rotate 탭 후 즉시 슬라이더가 나타나며 `-180°~+180°` 회전이 가능하다.
4) Transform ON 동안 프리뷰에서 이동/확대 제스처가 즉시 동작한다.
5) Transform ON 동안 클립 재생이 중지되고 완료 전까지 재생되지 않는다.

### 12-9. 오픈 이슈(구현 전 확정)
- 쟁점 1: 50% 축소 시 가독성 저하가 발생할 경우의 하한치(예: 60%)를 둘지 여부 - 하한치 두자.
- 쟁점 2: Rotate 슬라이더 노출 위치(퀵바 바로 아래 고정 vs 프리뷰 하단) 최종 확정 - 퀵바 바로 아래 고정
- 쟁점 3: Transform 종료 동작을 `명시적 완료 버튼`만 허용할지, 토글 OFF도 허용할지 - 토글 OFF만 허용.

### Phase 1 5차 소감
1. Transform ON, 직접조작 ON 글자는 없애자.
2. 아이콘 크기를 30% 키워라. 그리고 반투명 배경도형오 아이콘에 맞춰 가로 길이를 줄여라.
3. Angle 슬라이더바의 가로 길이를 30% 줄여라.
4. 확대, 축소 이동 을 위해서 클릭을 할때마다 새로고침이 돌아가서 제대로 동작이 안된다. 매끄럽게 움직이도록 UX를 조정해라.
5. 하단 버튼 기능 중 속도 버튼도 이  Trnasform 안에 넣어버리자. Angle처럼 속도버튼 선택 시 퀵 바 바로 아래에 띄워서 설정할 수 있게 해줘.

---

## 13. Phase 1 5차 소감 반영 추가 계획 (구현 전)

### 13-1. 변경 목표
- Transform UX에서 상태 텍스트 배지를 제거해 프리뷰 시야를 확보한다.
- 퀵바 아이콘을 현행 대비 약 30% 확대하고, 반투명 배경 컨테이너는 내용 폭에 맞춰 가로 길이를 축소한다.
- Angle 슬라이더의 가로 길이를 현행 대비 약 30% 축소해 시각적 밀도를 맞춘다.
- Move/Scale 제스처 조작 시 발생하는 체감 “새로고침/끊김”을 줄여 연속 조작감을 개선한다.
- `Speed`를 Transform 퀵바로 편입하고, `Angle`과 동일하게 인라인 보조 컨트롤로 노출한다.

### 13-2. IA/퀵바 구조 개편
#### A) 퀵바 1행 (아이콘-only)
1) Flip
2) Rotate
3) Speed

#### B) 퀵바 2행 (선택형 인라인 컨트롤)
- Rotate 선택 시: Angle 슬라이더 노출(`-180° ~ +180°`)
- Speed 선택 시: Speed 슬라이더(또는 단계형 선택 바) 노출
- 동시 노출 금지: `Rotate`/`Speed` 보조 컨트롤은 항상 하나만 열림

### 13-3. 시각 스펙 조정
- 배지 제거:
  - 프리뷰 상단의 `Transform ON`, `직접조작 ON` 텍스트 칩 제거
  - 상태 인지는 아이콘 active 스타일(색/배경칩)로만 전달
- 퀵바:
  - 아이콘 시각 크기: 현행 대비 `+30%`
  - 버튼 간 간격: 아이콘 확대분을 반영해 소폭 재조정(과밀 방지)
  - 반투명 배경 도형: 좌우 패딩 최소화 + `intrinsic width` 기준으로 내용 폭에 맞춰 축소
- Angle 슬라이더:
  - 트랙 가로 길이: 현행 대비 `-30%`
  - 좌/우 최소·최대 라벨은 유지하되 타이포/간격 축소로 전체 폭 절감

### 13-4. 인터랙션/성능 UX 개선 원칙
- 제스처 중 불필요한 전체 위젯 리빌드를 억제하고, transform 대상 레이어만 갱신하는 구조를 우선한다.
- 제스처 프리뷰 업데이트는 “연속 입력 경로”와 “커밋 경로”를 분리한다.
  - 연속 입력: 가벼운 프리뷰 반영(프레임 드랍 최소화)
  - 세션 종료: 1회 커밋(Undo/Redo 단위 유지)
- 슬라이더/제스처 동시 충돌 시 우선순위 규칙을 고정한다.
  - 동일 시점에는 마지막 입력 소스 1개만 활성
  - 소스 전환 시 이전 소스 세션 즉시 종료 후 커밋

### 13-5. Speed 인라인 편입 규칙
- `Speed`는 Transform 모드 내부의 보조 액션으로 동작한다.
- Speed 아이콘 탭 시 퀵바 바로 아래에 인라인 컨트롤 노출:
  - 권장 범위: `0.25x ~ 2.0x`
  - 기본 프리셋: `0.5x / 1.0x / 1.5x / 2.0x`
- 적용 범위는 기존 정책과 동일하게 “현재 클립 단위”를 기본으로 유지한다.
- Rotate 패널과 Speed 패널은 상호 배타적으로 토글된다.

### 13-6. 상태 모델 보강(개념)
- `transformUiState` 확장:
  - `activeInlinePanel: none | rotate | speed`
  - `showTransformBadgeText: false` (고정 정책)
  - `lastInputSource: gesture | angleSlider | speedSlider | quickAction`
- 저장 정책:
  - UI 상태(`activeInlinePanel`, 배지 노출 여부)는 세션 상태만 사용
  - 결과값(`angle`, `speed`, `offset/scale`)만 편집 상태에 저장

### 13-7. 단계별 실행 계획
#### P1-5A (레이아웃/가시성)
1) Transform/직접조작 텍스트 배지 제거
2) 퀵바 아이콘 30% 확대
3) 컨테이너 가로 폭 축소(내용 맞춤)

#### P1-5B (인라인 컨트롤 재배치)
1) Angle 슬라이더 가로 길이 30% 축소
2) Rotate/Speed 상호배타 인라인 패널 구조 도입
3) Speed 인라인 컨트롤(슬라이더 또는 단계형) 추가

#### P1-5C (매끄러운 조작감)
1) 제스처 프리뷰 갱신 경량화(전체 리빌드 최소화)
2) 입력 소스 전환 시 세션 경계/커밋 규칙 고정
3) 저사양 단말에서 프레임 안정성 점검

### 13-8. 수용 기준(AC)
1) Transform ON 중 텍스트 배지(`Transform ON`, `직접조작 ON`)가 노출되지 않는다.
2) 퀵바 아이콘이 기존 대비 체감 30% 확대되고, 배경 도형 가로 길이가 내용 폭에 맞게 축소된다.
3) Angle 슬라이더 길이가 기존 대비 체감 30% 축소된다.
4) Move/Scale 조작 중 끊김/튐 현상이 완화되어 연속 제스처가 자연스럽게 동작한다.
5) Transform 퀵바에서 Speed를 선택해 인라인으로 속도 설정이 가능하다.

### 13-9. 오픈 이슈(구현 전 확정)
- 쟁점 1: Speed UI를 연속 슬라이더로 통일할지, 프리셋 칩(단계형) 병행할지.
- 쟁점 2: Speed 적용 범위를 클립 단위로 고정할지, 추후 전체 적용 토글을 열어둘지.
- 쟁점 3: Angle/Speed 인라인 패널 높이 증가로 인한 프리뷰 가림 임계치(소형 화면 기준) 확정.

### Phase1 6차 테스트 소감
1. Speed UI는 슬라이더를 없애고 프리셋칩(단계형)으로만 만든다.
2. Angle이 0도 90도를 딱 맞출 수 있고, 그외의 원하는 각도도 자연스럽게 움질일 수 있으면 좋겠다. UX적으로 UI적으로 보기좋은 배치를 계획해라.
3. Speed 적용 범위는 클립 단위이다.
4. 퀵바와 인라인 패널을 프리뷰 하단으로 내린다. Transform 동안은 재생바와 클립리스트를 숨기고 클립 리스트 위치에 퀵바와 인라인 패널이 나오게 해라. Transform을 한번더 눌러서 빠져나오면 재생바와 클립 리스트를 복귀시킨다.
5. Transform 동안은 활성화되어있다는 표시를 주도록 Transform 버튼에 색을 넣어라.속도 옆에 원복 버튼을 만들어줘라. 원복은 Transform 시작 전 단계로 되돌린다.(Transform 활성화 이후 Flip, Angle, Speed 적용했던 것을 모두 한번에 원복)
6. 여전히 프리뷰 화면을 클릭하자마자 새로고침이 돌아가면서 확대, 축소가 어렵다. 대안을 찾아라.

---

## 14. Phase 1 6차 소감 반영 추가 계획 (구현 전)

### 14-1. 변경 목표
- Transform 내부 속도 조절 UI를 **슬라이더 제거 + 프리셋 칩(단계형) 전용**으로 단순화한다.
- Angle 조절 UX를 `0°/90°` 정밀 스냅과 자유 각도 미세 조정을 동시에 만족하도록 재설계한다.
- Transform 편집 레이아웃을 프리뷰 상단이 아니라 **프리뷰 하단(기존 재생바/클립리스트 영역)** 중심으로 재배치한다.
- Transform 편집 세션 동안의 변경을 한 번에 되돌리는 **원복(세션 리셋)** 액션을 도입한다.
- 여전히 남아있는 확대/축소 조작 끊김(탭 직후 리빌드 체감)을 줄이기 위한 대안 입력 모델을 확정한다.

### 14-2. IA 재배치 (하단 집중형)
#### A) Transform ON 시 화면 구성
1) 프리뷰 하단의 기존 `재생바` 숨김
2) 기존 `클립 리스트` 숨김
3) 해당 위치에 `Transform 퀵바 + 인라인 패널` 노출

#### B) Transform OFF(토글 재탭) 시 화면 복귀
1) 퀵바/인라인 패널 제거
2) 재생바/클립 리스트 원위치 복귀
3) Transform 버튼 활성 강조 해제

### 14-3. 퀵바 액션 재정의
- 구성: `Flip | Angle | Speed | 원복`
- 상태 표기:
  - Transform ON 동안 하단 `Transform` 버튼에 활성 색상(배경 또는 아이콘 강조) 적용
  - Angle/Speed 선택 상태는 퀵바 내 active 스타일로 표기

### 14-4. Speed UI 정책 (확정 반영)
- Speed는 슬라이더를 제거하고 **프리셋 칩만 제공**한다.
- 권장 칩: `0.5x / 0.75x / 1.0x / 1.25x / 1.5x / 2.0x`
- 적용 범위: **클립 단위(Local)** 고정
- 칩 선택 즉시 미리보기 반영, 세션 단위 Undo와 연동

### 14-5. Angle UX 재설계
- 핵심 목표:
  1) `0°`, `90°`를 빠르고 정확하게 맞춤
  2) 그 외 각도는 부드럽게 연속 조정
- 제안 패턴(하이브리드):
  - 상단: `0° / 90° / -90° / 180°` 스냅 칩(원탭)
  - 하단: 미세 각도 슬라이더(연속)
- 스냅 규칙:
  - 슬라이더 이동 중 임계치 근접 시 소프트 스냅(자석 효과)
  - 사용자 저항(빠른 드래그) 시 스냅 해제 가능
- 시각 규칙:
  - 현재 각도 숫자값 표시(`+12°` 형식)
  - 기준각(0/±90/180) 눈금 강조

### 14-6. 원복(세션 리셋) 동작 정의
- 원복 버튼은 `Speed` 옆에 배치한다.
- 리셋 범위:
  - Transform ON 진입 시점의 스냅샷으로 즉시 복귀
  - ON 이후 변경한 `Flip/Angle/Speed/(이동/확대 포함)`을 한 번에 취소
- 커밋 규칙:
  - 원복 1회 = 커밋 1회
  - OFF 시 최종 상태를 일반 커밋 규칙으로 반영

### 14-7. 조작 끊김 대응 대안 (핵심)
- 문제 정의: 프리뷰 탭 직후 전체 레이아웃 리빌드가 체감되어 핀치 시작이 끊기는 현상.
- 대안 A(우선):
  - Transform 중 탭 기반 재생 토글 완전 비활성
  - 제스처 수신 레이어를 프리뷰 변환 전용으로 단순화
  - 프레임 스로틀링 + dirty 영역만 갱신
- 대안 B(보완):
  - 핀치 시작 임계 프레임 동안 UI 오버레이 애니메이션 동결
  - 미리보기 외 영역(setState 유발 영역) 업데이트 지연 반영
- 검증 지표:
  - 핀치 시작 지연 체감 감소
  - 급격한 scale jump(튀는 확대) 재현률 감소

### 14-8. 상태 모델 보강(개념)
- `transformUiState` 확장:
  - `isTransformModeActive: bool`
  - `activeInlinePanel: none | angle | speed`
  - `transformSessionSnapshot: perClipTransform + playbackSpeed`
  - `isTimelineHiddenByTransform: bool`
  - `isTransformButtonHighlighted: bool`
- 저장 정책:
  - UI 상태/세션 스냅샷은 세션 메모리
  - 결과값만 편집 상태(클립 메타)에 반영

### 14-9. 단계별 실행 계획
#### P1-6A (레이아웃 전환)
1) Transform ON 중 재생바/클립리스트 숨김
2) 동일 위치에 퀵바+인라인 패널 배치
3) OFF 시 원상 복귀

#### P1-6B (Speed/Angle UX 확정)
1) Speed 슬라이더 제거, 프리셋 칩 전환
2) Angle 스냅칩 + 미세 슬라이더 하이브리드 적용
3) `0°/90°` 정밀 스냅 튜닝

#### P1-6C (세션 원복/성능 안정화)
1) Transform 진입 시 세션 스냅샷 캡처
2) 원복 버튼 1탭 전체 복구
3) 핀치 시작 끊김 완화(입력 레이어 단순화/리빌드 최소화)

### 14-10. 수용 기준(AC)
1) Transform ON 동안 하단 재생바/클립리스트가 숨겨지고, 그 자리에 퀵바+패널이 표시된다.
2) Speed는 슬라이더 없이 프리셋 칩으로만 조절된다.
3) Speed 적용 범위는 현재 클립 단위로 동작한다.
4) Angle에서 `0°/90°`를 빠르게 맞출 수 있고, 임의 각도 미세 조정도 가능하다.
5) 원복 버튼 1회로 Transform ON 이후 변경사항(Flip/Angle/Speed/이동/확대)이 진입 시점으로 복귀한다.
6) 확대/축소 시작 시 끊김 체감이 기존 대비 완화된다.

### 14-11. 오픈 이슈(구현 전 확정)
- 쟁점 1: Speed 프리셋 칩 구성을 6단계로 고정할지, 프로젝트 템포에 따라 동적 추천칩을 추가할지. - 0.5/1.0/1.5/2.0/3.0 5개로 고정한다.
- 쟁점 2: Angle 스냅 강도(자석 임계치)를 고정값으로 둘지, 저사양/고주사율 기기별로 적응형으로 둘지. - 기기별 적응형으로 둔다.
- 쟁점 3: 원복 대상에 `Transform ON 이후 이동한 재생헤드 위치`까지 포함할지 제외할지.- 재생헤드 위치 포함한다.


### Phase1 7차 테스트 소감
1. 퀵 바는 프리뷰 하단에 겹쳐보이게 넣어라. 그리고 Angle을 선택했을 때 
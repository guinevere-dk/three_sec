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

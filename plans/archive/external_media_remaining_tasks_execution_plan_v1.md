# 외부 미디어 UX 개선 잔여 과제 실행 계획 v1

## 1. 목적

- 이미 완료된 Phase 1~5 구현/검증 이후 남은 안정화 항목을 짧은 기간 내 마무리한다.
- 릴리스 게이트에서 `PASS` 판정을 받을 수 있도록 코드/문서/실측 지표를 확정한다.

---

## 2. 범위

- 코드 안정화
  - 취소 토큰 분리(임포트/클립 저장)
  - Notifier/Listener 라이프사이클 정리
  - 1.5초 반복 재생 seek 지터 계측/튜닝
- 검증/문서화
  - 대량 임포트/취소/다중 저장/위치 표시/1.5초 반복 실측
  - QA/릴리스 체크리스트 수치 업데이트

---

## 3. 작업 항목

### Task A. 취소 토큰 분리 (우선순위 P1)

#### 목표
- 임포트 취소와 클립 저장 취소를 독립 제어한다.

#### 대상
- `lib/managers/video_manager.dart`
- `lib/main.dart`
- `lib/screens/clip_extractor_screen.dart`

#### 구현 계획
1. 공용 취소 플래그를 내부적으로 `importCancelRequested`, `clipSaveCancelRequested`로 분리.
2. 기존 전체 취소 API는 유지하되, 내부에서 두 토큰을 각각 제어하도록 분기.
3. 임포트 루프/저장 워커의 중단 조건을 각 토큰으로 분리 체크.

#### 수락 기준
- 저장 취소 시 임포트는 지속.
- 임포트 취소 시 저장 큐는 정책대로 별도 동작(유지 또는 명시 중단).

---

### Task B. Notifier 생명주기 정리 (우선순위 P1)

#### 목표
- 화면 재진입 반복에도 리스너 중복/누수 없이 동작한다.

#### 대상
- `lib/managers/video_manager.dart`
- `lib/screens/clip_extractor_screen.dart`

#### 구현 계획
1. `VideoManager`에 `dispose()`를 추가해 내부 `ValueNotifier`를 정리.
2. 화면 단 listener 등록/해제 경로를 재검토해 중복 등록 방지 가드 추가.
3. 재진입 시나리오(열기→닫기→열기)에서 콜백 횟수 확인.

#### 수락 기준
- listener 중복 호출 없음.
- 메모리 증가 추세(누수) 없음.

---

### Task C. 1.5초 반복 재생 계측/튜닝 (우선순위 P2)

#### 목표
- 저사양 단말에서도 루프 재생의 seek 지터를 허용 범위로 낮춘다.

#### 대상
- `lib/screens/clip_extractor_screen.dart`
- `lib/widgets/trim_editor_modal.dart`

#### 구현 계획
1. 루프 enforce 구간에 계측 로그 포인트 추가(재진입 간격, seek latency).
2. 디바운스 주기(현재 값)를 기기군 기준으로 튜닝.
3. 1.5초 구간 드래그 중/후 반복 재생 안정성 확인.

#### 수락 기준
- 반복 재생 중 비정상 seek 폭주 없음.
- 체감 끊김 감소(저사양 포함).

---

### Task D. 실측 KPI 채움 (우선순위 P1)

#### 목표
- QA/릴리스 문서의 수치를 실측값으로 채워 배포 판단 가능 상태로 만든다.

#### 대상 문서
- `plans/external_media_phase5_qa_checklist_v1.md`
- `plans/external_media_phase5_release_checklist_v1.md`
- `plans/external_media_multi_import_phase5_validation_report_v1.md`

#### 실행 시나리오
1. 100개 임포트: 첫 미리보기 2초 내, 진행률 정합성 확인.
2. 50% 취소: 즉시 정지 여부 확인.
3. 단일 영상 10클립 저장: 재시도 포함 성공률 확인.
4. 위치 표시: 임의 탐색/자동 전환 시 `현재/총` 정합성 확인.
5. 1.5초 반복: 윈도우 이동 후 루프 정확성 확인.

#### 수락 기준
- 목표 KPI(첫 미리보기, 저장 성공률, 취소 즉시성) 수치 입력 완료.
- PASS/HOLD 판정 근거 문서화 완료.

---

### Task E. 최종 게이트 (우선순위 P1)

#### 목표
- 최종 통합 품질 판정 및 릴리스 결정.

#### 실행
1. `flutter analyze`
2. `flutter test`
3. 체크리스트 최종 판정 반영

#### 수락 기준
- 신규 error 0
- 릴리스 체크리스트 판정 완료

---

## 4. 일정(2영업일)

- Day 1 오전: Task A
- Day 1 오후: Task B + Task C
- Day 2 오전: Task D 실측/문서 반영
- Day 2 오후: Task E 최종 게이트 및 릴리스 판정

---

## 5. 리스크 및 대응

- 리스크: 토큰 분리 중 기존 취소 UX 회귀
  - 대응: 임포트/저장 독립 취소 회귀 케이스 추가
- 리스크: 저사양에서 seek 지터 잔존
  - 대응: 디바운스/루프 조건값 기기군별 가이드화
- 리스크: 실측 시나리오 시간 초과
  - 대응: 우선 KPI 3종(첫 미리보기, 취소 즉시성, 저장 성공률) 선완료

---

## 6. 최종 완료 조건

- 코드 안정화 3항목(Task A~C) 반영 완료
- QA/릴리스 문서 실측 수치 업데이트 완료
- 최종 게이트 결과(`PASS` 또는 `HOLD` 사유 포함) 기록 완료

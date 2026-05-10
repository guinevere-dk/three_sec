# PROJECT_CONTEXT.md

## 1. 제품 개요

MOA는 2초 촬영으로 일상의 순간을 모아 Vlog/영상 앨범을 만드는 Flutter/Dart 모바일 앱입니다. 핵심 가치는 짧은 클립을 부담 없이 저장하고, 선택한 클립을 자동 또는 반자동으로 Vlog 프로젝트로 구성하는 것입니다.

## 2. 브랜드 기준

- 현재 사용자 노출 브랜드: `MOA`.
- 제품 설명: `2초 촬영 + Vlog`.
- 사용자 노출에서 확산을 피할 표현: `원세컨`, `One Second Vlog`, `1s Vlog`, `Three Sec Vlog`, `3s`.
- 내부 레거시 식별자는 호환성 유지를 위해 보존합니다.

## 3. 핵심 사용자 가치

- 빠른 촬영: 카메라 기반 짧은 클립 촬영.
- 정리: `일상`, `휴지통`, 사용자 앨범 기반 클립 관리.
- 제작: 선택한 클립으로 Vlog 프로젝트 생성, 편집, 내보내기.
- 외부 미디어 활용: 이미지/동영상 가져오기와 클립 추출.
- 계정/구독: Firebase Auth, 게스트 모드, 구독 등급별 기능 제한.
- 클라우드: Standard 이상 사용자의 영상 백업/다운로드 및 동기화 상태 관리.

## 4. 현재 MVP 목표

- 기존 기능 안정화.
- MOA 브랜드 정렬.
- 촬영, 저장, 불러오기, Vlog 생성 안정성 확보.
- 클라우드 이동과 로컬 데이터 호환성 유지.
- 로그인/게스트/구독 흐름 회귀 방지.
- 크래시 감소와 Android 릴리스 품질 확보.

## 5. 운영 원칙

- 사용자 데이터 보존이 최우선입니다.
- 기존 앱 동작과 레거시 호환을 브랜드 정리보다 우선합니다.
- 위험한 변경은 분석, 승인, dry-run, 백업, 롤백 계획 후 수행합니다.
- 문서와 코드는 실제 파일명, 실제 key, 실제 경로 기준으로 유지합니다.

## 6. 주요 근거 문서

- `plans/moa_rebrand_phase_plan_interactive_v1.html`: 리브랜딩 Phase와 영향도 기준.
- `plans/firestore_usage_rules_and_sync_contract_v1.md`: Firestore 사용과 동기화 계약.
- `plans/three_sec_local_cloud_release_plan_v1.md`: 로컬/클라우드 릴리스 계획.
- `plans/ver1_free_initial_launch_plan_v1.md`: MVP/무료 초기 출시 기준.
- `plans/external_media_phase5_release_checklist_v1.md`: 외부 미디어 Phase 5 릴리스 체크.
- `plans/google_play_console_release_guide.md`: Android/Play Console 릴리스 운영.
- `plans/ios_app_store_release_plan_v1.md`: iOS 릴리스 계획.

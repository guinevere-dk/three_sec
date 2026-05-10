# Google Play 경고(버전코드 131) 대응 계획 v1

## 1) 현재 경고 요약

- 가독화 파일 누락 경고
  - 릴리즈 빌드에서 난독화 매핑 파일(`mapping.txt`)이 연결되지 않음
- 사진/동영상 권한 정책 경고
  - 선언 권한: `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`
  - Play Console에서 권한 사용 목적(빈번 접근 필요성) 또는 Photo Picker 전환을 요구

근거 코드:
- 권한 선언: `android/app/src/main/AndroidManifest.xml`
- 권한 요청 로직: `lib/managers/video_manager.dart`
- 난독화 비활성: `android/app/build.gradle.kts` (`isMinifyEnabled = false`)

---

## 2) 목표

1. Play Console 심사 차단 요소 제거
2. 정책 리스크가 높은 미디어 읽기 권한 최소화
3. 크래시/ANR 분석 가능한 릴리즈 산출물 확보

---

## 3) 실행 계획

### Phase A. 즉시 제출 대응(이번 배포)

1) Play Console 권한 설명 문구 입력(임시)

- 미디어 이미지 읽기(250자 이내)

```text
사용자가 갤러리에서 사진을 선택해 3초 영상으로 변환하거나 편집 프로젝트에 삽입하는 기능에 사용합니다. 접근은 사용자가 명시적으로 선택한 항목으로 제한되며, 백그라운드 수집/전체 스캔/광고 목적 처리는 하지 않습니다.
```

- 미디어 동영상 읽기(250자 이내)

```text
사용자가 갤러리 동영상을 선택해 구간 추출, 병합, 편집 후 저장/업로드하는 핵심 기능에 사용합니다. 접근 대상은 사용자가 선택한 파일로 한정되며, 전체 라이브러리의 지속적 수집이나 비선택 파일 접근은 수행하지 않습니다.
```

2) 가독화 파일 대응

- 이번 릴리즈에서 난독화를 사용하지 않을 경우: 경고는 정보성으로 남을 수 있으나 출시 가능
- 난독화 사용으로 전환할 경우:
  - `android/app/build.gradle.kts`의 release 빌드에서 `isMinifyEnabled = true`, `isShrinkResources = true` 적용
  - AAB 빌드 후 생성된 `build/app/outputs/mapping/release/mapping.txt`를 Play Console에 업로드

---

### Phase B. 근본 해결(다음 배포, 권장)

1) Photo Picker 중심 구조로 정리

- 앱 외부 미디어 접근은 "사용자 선택 기반"으로만 동작하도록 고정
- Android 13+ `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` 제거 목표

2) 권한 요청 코드 정리

- `Permission.photos`, `Permission.videos` 직접 요청 제거 검토
- 필요 시 Android 12 이하 예외 처리만 최소 유지

3) 매니페스트 최소 권한화

- `AndroidManifest.xml`에서 미디어 읽기 권한 제거 후 회귀 테스트
- 기능 영향(클립 불러오기/프로필 이미지 선택/편집 진입) 확인

---

## 4) 검증 체크리스트

- [ ] 내부 테스트 트랙 업로드 성공
- [ ] Play Console 권한 정책 경고 해소 또는 수용 가능한 수준으로 축소
- [ ] 갤러리에서 사진 1건 선택 → 프로젝트 반영 성공
- [ ] 갤러리에서 영상 1건 선택 → 구간 추출/편집 진입 성공
- [ ] 내보내기/저장/클라우드 업로드 정상
- [ ] Proguard/R8 사용 시 `mapping.txt` 업로드 완료

---

## 5) 릴리즈 오너 액션 아이템

1. 콘솔 문구 입력 후 검토 제출
2. 다음 스프린트에서 권한 제거 PR 분리
3. 난독화 적용 여부 확정 후 빌드 파이프라인에 `mapping.txt` 업로드 절차 고정

---

## 6) 결론

이번 릴리즈는 **권한 목적 설명 + 내부 테스트 검증**으로 통과 가능성을 확보하고,
다음 릴리즈에서 **Photo Picker 전환/권한 제거**로 정책 리스크를 구조적으로 해소합니다.

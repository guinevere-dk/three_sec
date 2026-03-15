# Google Play Console 최신 버전/번들(AAB) 배포 가이드

이 문서는 현재 프로젝트(`three_sec_vlog`)를 **Google Play Console에 최신 버전으로 업로드하고 출시**하기 위한 실무 절차를 정리한 문서입니다.

---

## 0. 현재 프로젝트 기준 확인 포인트

- 패키지명(`applicationId`): `com.dk.three_sec`
- 안드로이드 버전 소스: `pubspec.yaml`의 `version`
- 릴리즈 서명 설정: `android/app/build.gradle.kts`에서 `key.properties` 기반 `signingConfigs.release`

> 즉, Play Console에 올릴 때 핵심은 **버전 코드 증가 + 릴리즈 서명 + AAB 생성 + 트랙 업로드**입니다.

---

## 1. 배포 전 사전 준비

### 1-1. 계정/권한
- Google Play Console에서 해당 앱에 대해 `Release to production` 권한이 있는 계정인지 확인

### 1-2. 서명 파일 점검
- 프로젝트 루트에 `android/key.properties` 파일 존재 확인
- `key.properties`에 아래 값이 정확해야 함
  - `storeFile`
  - `storePassword`
  - `keyAlias`
  - `keyPassword`

### 1-3. 버전 정책 점검
- Play Console은 **기존보다 큰 versionCode**만 허용
- 현재 값이 `1.2.0+120`이면, 다음 빌드는 예: `1.2.1+121` 또는 `1.3.0+121`

---

## 2. 버전 올리기

`pubspec.yaml`의 `version`을 수정합니다.

예시:

```yaml
version: 1.2.1+121
```

규칙:
- 앞쪽(`1.2.1`) = 사용자 노출 버전명 (`versionName`)
- 뒤쪽(`121`) = 내부 빌드 번호 (`versionCode`) 

---

## 3. 릴리즈 번들(AAB) 생성

프로젝트 루트에서 CMD 기준으로 실행:

```cmd
flutter clean
flutter pub get
flutter build appbundle --release
```

생성 경로:

```text
build\app\outputs\bundle\release\app-release.aab
```

권장 추가 검증:
- 빌드 오류 없음
- 앱 실행 스모크 테스트(실기기)
- 로그인/촬영/편집/저장 핵심 플로우 확인

---

## 4. Play Console 업로드

1. Google Play Console 접속
2. 앱 선택 (`com.dk.three_sec`)
3. 왼쪽 메뉴: `릴리즈` → `테스트`(내부/클로즈드) 또는 `프로덕션`
4. `새 릴리즈 만들기`
5. `앱 번들` 업로드에서 `app-release.aab` 업로드
6. 릴리즈 노트 입력 (한국어/영어 권장)
7. 저장 후 `검토` 진행

---

## 5. 권장 출시 순서 (안전 배포)

### 5-1. 내부 테스트 트랙 선배포
- 내부 테스트에 먼저 배포
- 설치/업데이트/핵심 기능/크래시 유무 확인

### 5-2. 프로덕션 단계적 출시
- 프로덕션 릴리즈 시 `100% 즉시 배포` 대신 단계적 롤아웃 권장
  - 예: 5% → 20% → 50% → 100%

---

## 6. 출시 체크리스트

### 빌드 전
- [ ] `pubspec.yaml` 버전 증가 완료
- [ ] `android/key.properties` 정상
- [ ] 릴리즈 노트 초안 준비

### 빌드 후
- [ ] `app-release.aab` 생성 확인
- [ ] 실기기 스모크 테스트 완료
- [ ] 크래시/ANR 즉시 발생 없음

### 콘솔 업로드 후
- [ ] 릴리즈 노트 입력
- [ ] 정책/콘텐츠 경고 없음
- [ ] 검토 제출 완료

---

## 7. 자주 발생하는 이슈

### 이슈 A: "version code already used"
- 원인: 기존과 동일/낮은 `versionCode`
- 해결: `pubspec.yaml`의 `+숫자`를 더 크게 올리고 재빌드

### 이슈 B: 서명 관련 실패
- 원인: `key.properties` 값 불일치 또는 키스토어 경로 오류
- 해결: `storeFile` 경로/비밀번호/alias 재검증

### 이슈 C: 업로드는 됐는데 릴리즈 불가
- 원인: 정책/데이터 안전/콘텐츠 등 Play Console 미완료 항목
- 해결: 콘솔의 `정책 상태` 및 `앱 콘텐츠` 누락 항목 먼저 완료

---

## 8. 실제 배포용 명령어 템플릿

아래 순서 그대로 사용하면 됩니다.

```cmd
flutter --version
flutter pub get
flutter build appbundle --release
```

필요 시 캐시 정리 포함:

```cmd
flutter clean && flutter pub get && flutter build appbundle --release
```

---

## 9. 이번 릴리즈 작업 요약(실행 순서)

1. `pubspec.yaml` 버전 증가
2. `flutter build appbundle --release`로 AAB 생성
3. Play Console 내부 테스트 업로드/검증
4. 프로덕션 릴리즈 생성
5. 단계적 롤아웃으로 공개

이 순서대로 진행하면 최신 버전 번들 배포를 안정적으로 완료할 수 있습니다.

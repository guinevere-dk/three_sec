# Cloud Clip Project Cloud Save Phase A Report v1

## 1. 범위

`cloud_clip_direct_edit_export_project_cloud_save_plan_v1.md`의 Phase A만 수행했다.

목표:

- `vlog_projects` upsert가 프로젝트 생성, 편집 진입 autosave에서 실제 호출되는지 확인.
- Cloud-only clip이 포함된 프로젝트 저장 시 `cloud_only://...` 참조가 프로젝트 상태에 남는지 확인.
- session/export cache path가 프로젝트에 섞이지 않는지 확인할 수 있는 계측 추가.

구현하지 않은 것:

- Cloud Clip direct preview.
- Cloud Clip export materialization.
- session cache resolver.

## 2. 변경 파일

- `lib/managers/video_manager.dart`
  - `saveProject()`에 `[VideoManager][ProjectCloudSave]` 요약 로그 추가.
  - 로그 항목:
    - `isGuest`
    - `clipCount`
    - `cloudOnlyClipCount`
    - `cacheLikeClipCount`
    - `hasCloudProjectId`
    - `hasCloudSyncedAt`
    - `cloudSaveStatus`
  - Cloud upsert 성공 시 호출자가 가진 `VlogProject` 객체에도 `cloudProjectId`, `cloudSyncedAt`을 즉시 반영하도록 수정.

## 3. 발견한 문제와 수정

### 문제

초기 QA에서 프로젝트 생성 직후 Cloud 저장은 성공했지만, 편집 화면 진입 후 autosave가 같은 프로젝트를 새 `vlog_projects` 문서로 다시 생성했다.

관찰 로그:

```text
[ProjectCloudSave][start] ... hasCloudProjectId=false
[vlogMeta][upsert][start] projectDocId=zKXt...3jDe localProjectId=1779...0565
[ProjectCloudSave][done] ... hasCloudProjectId=true

[ProjectCloudSave][start] ... hasCloudProjectId=false
[vlogMeta][upsert][start] projectDocId=7C1Q...Uetl localProjectId=1779...0565
```

원인:

- `saveProject()`가 Cloud upsert 결과를 `projectToSave` copy와 내부 리스트에는 반영했지만, 호출자가 계속 들고 있는 `widget.project` 객체에는 `cloudProjectId/cloudSyncedAt`을 즉시 반영하지 않았다.
- 편집 화면 autosave가 같은 local project를 다시 저장할 때 `cloudProjectId == null`로 판단되어 새 Cloud 문서를 생성했다.

수정:

- Cloud upsert 성공 시 `project.cloudProjectId`와 `project.cloudSyncedAt`을 직접 갱신한다.

## 4. QA 결과

### 4.1 Local clip 2개 프로젝트

절차:

1. Library > 일상 진입.
2. local clip 2개 선택.
3. 프로젝트 생성 버튼 실행.
4. 편집 화면 진입 및 autosave 로그 확인.

결과:

```text
[ProjectCloudSave][start] isGuest=false clipCount=2 cloudOnlyClipCount=0 cacheLikeClipCount=0 hasCloudProjectId=false hasCloudSyncedAt=false
[vlogMeta][upsert][start] projectDocId=oiTk...tJLA localProjectId=1779...8455 clipCount=2
[vlogMeta][upsert][ok] projectDocId=oiTk...tJLA localProjectId=1779...8455
[ProjectCloudSave][done] localWrite=success cloudSaveStatus=success clipCount=2 cloudOnlyClipCount=0 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true

[ProjectCloudSave][start] isGuest=false clipCount=2 cloudOnlyClipCount=0 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
[vlogMeta][upsert][start] projectDocId=oiTk...tJLA localProjectId=1779...8455 clipCount=2
[vlogMeta][upsert][ok] projectDocId=oiTk...tJLA localProjectId=1779...8455
[ProjectCloudSave][done] localWrite=success cloudSaveStatus=success clipCount=2 cloudOnlyClipCount=0 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
```

판정:

- 통과.
- 프로젝트 생성 저장과 편집 진입 autosave가 같은 `projectDocId`를 재사용한다.
- cache-like path 오염 없음.

### 4.2 Local clip 1개 + Cloud-only clip 1개 프로젝트

절차:

1. Library > 일상 진입.
2. local clip 1개와 Cloud-only clip 1개 선택.
3. 프로젝트 생성 버튼 실행.
4. 편집 화면 진입 및 autosave 로그 확인.

결과:

```text
MergeFlow calling createProject ... paths=/data/.../clip_1779167081750.mp4,cloud_only://일상/eA5YIecPjHdgAEtMyDsx/clip_1779275872421.mp4

[ProjectCloudSave][start] isGuest=false clipCount=2 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=false hasCloudSyncedAt=false
[vlogMeta][upsert][start] projectDocId=PSqv...bNGV localProjectId=1779...7392 clipCount=2
[vlogMeta][upsert][ok] projectDocId=PSqv...bNGV localProjectId=1779...7392
[ProjectCloudSave][done] localWrite=success cloudSaveStatus=success clipCount=2 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true

[ProjectCloudSave][start] isGuest=false clipCount=2 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
[vlogMeta][upsert][start] projectDocId=PSqv...bNGV localProjectId=1779...7392 clipCount=2
[vlogMeta][upsert][ok] projectDocId=PSqv...bNGV localProjectId=1779...7392
[ProjectCloudSave][done] localWrite=success cloudSaveStatus=success clipCount=2 cloudOnlyClipCount=1 cacheLikeClipCount=0 hasCloudProjectId=true hasCloudSyncedAt=true
```

판정:

- Phase A 기준 통과.
- Cloud-only 참조가 프로젝트 저장 흐름에 포함된다.
- `cacheLikeClipCount=0`으로 임시 cache path 오염은 관찰되지 않았다.
- 편집 preview는 아직 `cloud_only://...`를 `Missing`으로 처리한다. 이는 Phase C 대상이다.

## 5. 검증 명령

```powershell
dart format lib\managers\video_manager.dart
flutter analyze
flutter run -d emulator-5554 --no-resident --dart-define=SOCIAL_AUTH_EXCHANGE_URL=https://asia-northeast3-fir-3s-8edb9.cloudfunctions.net/social/exchange
adb logcat -d -t 4500
```

검증 결과:

- `dart format`: 성공.
- `flutter run`: debug APK 빌드/설치 성공.
- Runtime QA: local-only 프로젝트와 cloud-only 포함 프로젝트 모두 Cloud project metadata 저장 성공.
- `flutter analyze`: 기존 warning/info가 많아 전체 명령은 실패 상태를 유지한다. 새 `ProjectCloudSave` 로그 관련 analyzer 매칭 문제는 확인되지 않았다.

## 6. 남은 리스크

- QA 중 발견된 기존 중복 `vlog_projects` 문서가 이미 몇 개 생성되어 있을 수 있다. 실제 삭제/정리는 별도 승인과 dry-run 없이는 수행하지 않았다.
- Cloud-only clip은 프로젝트 metadata에는 저장되지만, 편집 preview와 export는 아직 직접 지원하지 않는다.
- Firestore 문서 실제 field 값은 로그 기반으로 간접 확인했다. Console/Emulator document inspection은 이번 범위에서 수행하지 않았다.

## 7. Phase A 판정

Phase A는 통과로 본다.

단, 이 통과는 “프로젝트 Cloud metadata 저장 계약과 중복 upsert 방지” 기준이다. Cloud-only clip의 직접 편집/내보내기 UX는 다음 Phase에서 resolver와 export materialization을 구현해야 한다.

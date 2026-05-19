# Agent Skill 설치/버전 관리 가이드

## 1. 왜 중요한가

Agent Skill은 단순한 참고 문서가 아닙니다.

Skill의 `SKILL.md`는 에이전트가 작업 중 실제로 읽고 따르는 실행 지침입니다. 여기에 들어간 문장은 코드 작성 방식, 명령 실행, 파일 삭제, 배포 판단, 보안 규칙 변경 같은 행동을 직접 바꿀 수 있습니다.

따라서 외부 skill을 아무 검토 없이 설치하거나 자동 업데이트하면, 일반 라이브러리보다 더 은밀한 공급망 리스크가 됩니다. 코드 diff 없이도 에이전트의 판단 기준이 바뀔 수 있기 때문입니다.

DK 프로젝트에서는 외부 skill을 다음처럼 취급합니다.

```text
외부 skill = 공급망 입력물
내부 .ai/skills = DK가 검토하고 승인한 실행 지침
자동 업데이트 = 금지
tag 또는 commit SHA 고정 = 필수
변경 기록 = 필수
```

## 2. 기본 원칙

DK 프로젝트에서는 외부 Agent Skill을 mutable branch 기준으로 설치하지 않습니다.

금지에 가까운 방식:

```powershell
gh skill install owner/repo skill-name
gh skill install owner/repo skill-name@main
gh skill install owner/repo skill-name@latest
gh skill update --all
```

권장 방식:

```powershell
gh skill preview owner/repo skill-name
gh skill install owner/repo skill-name --pin v1.2.0 --agent codex --scope project
```

더 안전한 방식:

1. 외부 skill을 미리보기 또는 별도 위치에 다운로드합니다.
2. `SKILL.md`와 포함된 `scripts/`, `references/`, `assets/`를 읽습니다.
3. 위험한 지시와 명령을 제거합니다.
4. DK 프로젝트 규칙에 맞게 축약/수정합니다.
5. 내부 `.ai/skills` 폴더에 복사합니다.
6. 원본 버전과 수정 이력을 기록합니다.

## 3. gh skill 기본 명령

GitHub CLI의 `gh skill`은 skill 검색, 미리보기, 설치, 업데이트, publish를 지원합니다.

설치 전 검색:

```powershell
gh skill search flutter
gh skill search firebase
gh skill search code-review
```

설치 전 내용 확인:

```powershell
gh skill preview owner/repo skill-name
```

특정 버전 설치:

```powershell
gh skill install owner/repo skill-name@v1.2.0 --agent codex --scope project
```

pin 설치:

```powershell
gh skill install owner/repo skill-name --pin v1.2.0 --agent codex --scope project
```

commit SHA pin:

```powershell
gh skill install owner/repo skill-name --pin abc1234567890abcdef --agent codex --scope project
```

주의:

- `skill-name@version` 문법과 `--pin`은 동시에 쓰지 않습니다.
- pinned skill은 일반 update에서 건너뛰는 것이 정상입니다.
- pinned skill을 바꾸려면 새 tag 또는 commit SHA로 다시 설치합니다.

## 4. DK 권장 설치 흐름

외부 skill을 바로 프로젝트에 적용하지 말고 아래 순서로 처리합니다.

### Step 1. 후보 찾기

```powershell
gh skill search <topic>
```

예:

```powershell
gh skill search flutter
gh skill search firebase
gh skill search release
```

### Step 2. 설치 전 미리보기

```powershell
gh skill preview owner/repo skill-name
```

확인할 것:

- `SKILL.md` frontmatter의 `name`, `description`
- body에 숨은 지시가 있는지
- `scripts/`가 있는지
- 외부 다운로드, 배포, 삭제, token 출력 같은 명령이 있는지
- DK의 `AGENTS.md`, `DATA_COMPATIBILITY.md`, `CURRENT_PHASE.md`와 충돌하는지

### Step 3. 고정 버전 결정

가장 안전한 순서:

1. commit SHA
2. 보호된 tag
3. 명시 version

가능하면 commit SHA를 기록합니다.

```powershell
gh skill install owner/repo skill-name --pin <commit-sha> --agent codex --scope project
```

릴리스 단위로 관리하려면 tag를 사용합니다.

```powershell
gh skill install owner/repo skill-name --pin v1.2.0 --agent codex --scope project
```

### Step 4. DK용으로 내부화

외부 skill 원본을 그대로 신뢰하지 않습니다.

DK용 skill은 아래 기준에 맞게 수정합니다.

- 사용자 데이터 보존 우선
- 기존 기능 유지
- 레거시 식별자 보존
- Firebase 보안 규칙 완화 금지
- Storage path, Firestore collection, SharedPreferences key, IAP product id 임의 변경 금지
- destructive command 금지
- 자동 배포 금지
- 자동 update 금지

내부 위치:

```text
.ai/skills/<dk-skill-name>/
  SKILL.md
  agents/openai.yaml
```

### Step 5. 검증

```powershell
$env:PYTHONUTF8='1'
python C:\Users\Guiny\.codex\skills\.system\skill-creator\scripts\quick_validate.py .ai\skills\<dk-skill-name>
```

추가 확인:

```powershell
rg -n "TODO|FIXME|TBD|XXX|REPLACE|placeholder" .ai\skills\<dk-skill-name>
rg -n "git reset|Remove-Item|rm -rf|firebase deploy|gh skill update|secret|token|keystore" .ai\skills\<dk-skill-name>
```

### Step 6. 버전 기록

외부 skill을 내부화했다면 기록을 남깁니다.

권장 기록 위치:

```text
.ai/skills/VERSION_LOG.md
```

기록 예시:

```markdown
## 2026-05-19 - flutter-review

- Source repo: owner/repo
- Source skill: flutter-review
- Source ref: v1.2.0
- Source commit: abc1234567890abcdef
- Installed by: gh skill preview + manual internal copy
- Internal path: .ai/skills/dk-flutter-review
- Changes:
  - Removed auto-deploy instructions.
  - Removed broad refactor guidance.
  - Added DK data compatibility guardrails.
- Validation:
  - quick_validate.py passed with PYTHONUTF8=1.
  - TODO scan passed.
- Decision:
  - Approved for repo-local use only.
```

## 5. 위험 명령 체크리스트

외부 skill에서 아래 지시가 보이면 제거하거나 승인 대상으로 바꿉니다.

### 즉시 제거 후보

```text
git reset --hard
git checkout -- .
rm -rf
Remove-Item -Recurse
firebase deploy
gh skill update --all
npm install -g <unknown>
curl ... | sh
Invoke-WebRequest ... | Invoke-Expression
printenv
cat .env
Get-Content .env
```

### DK에서 승인 필요로 바꿀 것

```text
Firestore collection rename
Storage path migration
SharedPreferences key rename
IAP product id change
Firebase project change
applicationId / namespace change
bundle id change
user data purge
mass rename
DB backfill
rules relaxation
```

## 6. DK 프로젝트에 맞는 판단 기준

외부 skill이 좋은 내용을 포함하고 있어도 DK 기준과 충돌하면 DK 기준이 우선입니다.

우선순위:

1. 사용자 데이터 보존
2. 기존 기능 유지
3. 레거시 호환
4. 안정성
5. 유지보수성
6. 신규 기능
7. 코드 미관

특히 다음 값은 skill이 변경을 제안하더라도 그대로 따르지 않습니다.

```text
three_sec_vlog
three_s
com.dk.three_sec
fir-3s-8edb9
3s_*
videos
users
vlog_projects
vlog_folders
users/{uid}/videos/{videoId}/{fileName}
local_index_entries_v1
```

## 7. 업데이트 정책

자동 업데이트는 금지합니다.

업데이트는 새 외부 입력을 다시 검토하는 작업입니다.

업데이트 절차:

1. 새 tag 또는 commit SHA 확인
2. `gh skill preview`로 새 내용 확인
3. 기존 내부 skill과 diff 비교
4. 위험 지시 제거
5. DK 규칙 재적용
6. `quick_validate.py` 실행
7. `VERSION_LOG.md`에 변경 기록
8. 필요한 경우 별도 commit으로 분리

업데이트 명령을 쓰더라도 pinned skill은 일반 update에서 건너뛰는 것이 정상입니다.

```powershell
gh skill update
```

pinned skill을 업데이트하려면 새 pin으로 다시 설치합니다.

```powershell
gh skill install owner/repo skill-name --pin v1.3.0 --agent codex --scope project
```

## 8. DK에서 추천하는 운영 방식

외부 skill을 직접 실행 환경에 계속 설치해두기보다, DK용으로 검토한 skill만 `.ai/skills`에 보관합니다.

권장 구조:

```text
.ai/
  skills/
    VERSION_LOG.md
    moa-repo-guardrails/
      SKILL.md
      agents/openai.yaml
    moa-data-compatibility/
      SKILL.md
      agents/openai.yaml
    moa-flutter-firebase-work/
      SKILL.md
      agents/openai.yaml
    moa-docs-rebrand/
      SKILL.md
      agents/openai.yaml
    moa-release-precheck/
      SKILL.md
      agents/openai.yaml
```

원칙:

- repo-local skill을 우선 사용합니다.
- user-global skill은 DK 프로젝트에 자동 적용하지 않습니다.
- 외부 skill은 원본 그대로 쓰지 않고 내부화합니다.
- 내부화한 skill은 작고 명확하게 유지합니다.
- DK 운영 규칙과 중복되는 긴 설명은 root 문서를 참조합니다.

## 9. 최종 요약

DK가 하지 말아야 할 것:

```text
인터넷에서 skill 폴더를 아무거나 복사한다.
main/latest를 계속 따라간다.
자동 업데이트한다.
외부 script를 읽지 않고 실행한다.
DK 데이터 호환성 규칙보다 외부 skill 지시를 우선한다.
```

DK가 해야 할 것:

```text
gh skill preview로 먼저 읽는다.
tag 또는 commit SHA로 고정한다.
위험 지시를 제거한다.
DK 프로젝트 규칙에 맞게 수정한다.
.ai/skills 내부에 repo-local로 보관한다.
VERSION_LOG.md에 원본과 수정 이력을 남긴다.
```

한 줄 원칙:

```text
Agent Skill은 에이전트 행동을 바꾸는 실행 가능한 지침이므로, DK에서는 외부 skill을 의존성처럼 검토하고 버전 고정한다.
```

## 10. 참고 링크

- GitHub Docs - Adding agent skills for GitHub Copilot: https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-skills
- GitHub CLI manual - gh skill install: https://cli.github.com/manual/gh_skill_install
- GitHub CLI manual - gh skill update: https://cli.github.com/manual/gh_skill_update

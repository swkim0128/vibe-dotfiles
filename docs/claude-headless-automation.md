# Claude Code 무인(Headless) 자동화 가이드

tmux 백그라운드 세션에서 권한 승인 프롬프트(`Approve Y/N`)로 인한 정지를 제거하기 위한 검증된 구현 지침.

> 작성일: 2026-05-08 / 검증 환경: macOS, claude CLI `--help` 실측 기반
> 적용 시점: 검토 후 별도 작업 세션에서 진행 예정

---

## 검증된 사실 (claude --help 실측)

- `--permission-mode` 실제 값: `acceptEdits | auto | bypassPermissions | default | dontAsk | plan`
- `-p` / `--print` 모드는 **워크스페이스 신뢰 다이얼로그를 자동 스킵**
- `--dangerously-skip-permissions` 존재함 (= `bypassPermissions`)
- `--bare` 모드는 훅·LSP·플러그인 스킵, `CLAUDE_CODE_SIMPLE=1` 자동 설정
- 현재 `~/.claude/settings.json`은 `vibe-tools/claude-config/settings.work.json` 심볼릭 링크

---

## 1. 신뢰 구역 / 사전 승인 (`settings.json`)

### 우선순위 (높음 → 낮음)
1. `--settings` CLI inline
2. `.claude/settings.local.json` (gitignore, 개인용)
3. `.claude/settings.json` (프로젝트 공유, 커밋)
4. `~/.claude/settings.json` (전역 사용자)

상위가 하위를 **덮어씀**. `deny` > `ask` > `allow` 순으로 평가.

### vibe-dotfiles 적용용 스키마

`.claude/settings.json` (프로젝트 공유):
```json
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "additionalDirectories": [
      "/Users/eunsol/Project/vibe-dotfiles/scripts",
      "/Users/eunsol/Project/vibe-dotfiles/vibe-tools"
    ],
    "allow": [
      "Read",
      "Edit",
      "Write",
      "Bash(git status)",
      "Bash(git log:*)",
      "Bash(git diff:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(git checkout:*)",
      "Bash(git worktree:*)",
      "Bash(shellcheck:*)",
      "Bash(bash -n:*)",
      "Bash(./scripts/**:*)",
      "Bash(./vibe-tools/**:*)",
      "Bash(rg:*)",
      "Bash(grep:*)",
      "Bash(find . *)",
      "Bash(tmux send-keys:*)",
      "Bash(tmux capture-pane:*)",
      "Bash(tmux list-*)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf $HOME)",
      "Bash(sudo:*)",
      "Bash(curl * | bash)",
      "Bash(curl * | sh)",
      "Bash(wget * | bash)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(//Users/eunsol/.ssh/**)",
      "Read(//Users/eunsol/.aws/**)",
      "Edit(./.env*)"
    ]
  }
}
```

### 패턴 문법
- `Bash(git commit:*)` — 접두사 + 콜론 와일드카드 → 단어 경계 보장
- `Bash(./scripts/**:*)` — 재귀 글롭, 하위 모든 실행 명령
- 경로: `//abs`, `~/home`, `/projectroot`, `./cwd`

---

## 2. 도구별 사전 승인 모드

| 모드 | 동작 | 자동화 적합도 |
|------|------|------|
| `default` | 매번 묻기 | ❌ |
| `plan` | 읽기만, 모든 수정 차단 | 분석 전용 |
| `acceptEdits` | 파일 편집 자동승인, Bash는 ask | 일반 권장 |
| `dontAsk` | `allow` 등록분만 실행, 외 거부 | CI 권장 |
| `auto` | 광범위 자동승인 | 중간 |
| `bypassPermissions` | 전부 자동 (= `--dangerously-skip-permissions`) | 격리 환경만 |

### 도구 매칭 규칙
- `Read`, `Edit`, `Write` → 인자 없으면 모든 경로 허용
- `Read(/src/**)` → 프로젝트 루트 기준
- `Bash(npm test)` → 정확 매칭
- `Bash(npm test:*)` → 접두사 + 임의 인자
- `Bash(* --dry-run)` → 임의 명령 + 끝맺음

---

## 3. 무인 모드 CLI 플래그

| 플래그 | 동작 |
|--------|------|
| `-p "<프롬프트>"` / `--print` | 비대화형 + 워크스페이스 신뢰 다이얼로그 자동 스킵 |
| `--permission-mode <mode>` | 6개 모드 중 선택 |
| `--dangerously-skip-permissions` | 모든 권한 체크 우회 |
| `--allow-dangerously-skip-permissions` | 옵션 활성화만 (기본 적용 X) |
| `--allowedTools "Bash(git *) Edit"` | 공백/콤마 구분 도구 허용 |
| `--disallowedTools "..."` | 도구 차단 |
| `--bare` | 훅·LSP·플러그인 스킵 |
| `--add-dir <path>` | 작업 디렉토리 추가 |
| `--settings <json|file>` | inline 설정 오버라이드 |
| `--output-format json` | tmux 캡처 파싱 용이 |

### 환경변수 (검증된 것만)
```bash
export ANTHROPIC_API_KEY="sk-ant-..."        # bare 모드 / CI 인증 필수
export CLAUDE_CODE_SKIP_PROMPT_HISTORY=1     # 세션 히스토리 비저장
export CLAUDE_CODE_SIMPLE=1                  # --bare 동등
```

> `CLAUDE_CODE_AUTO_APPROVE`, `CI=1` 같은 변수는 공식적으로 존재하지 않음.

### `-p` 모드 핵심
헬프 원문: *"The workspace trust dialog is skipped when Claude is run in non-interactive mode (via -p, or when stdout is not a TTY)."* → tmux 백그라운드 + `-p` 조합만으로 신뢰 다이얼로그 자동 통과.

---

## 권장 구성 (가장 안전 + 무인친화)

### 단계 1: 프로젝트 권한 화이트리스트
위 `.claude/settings.json` 적용 (또는 현재 심볼릭 링크된 `vibe-tools/claude-config/settings.work.json`에 반영)

### 단계 2: tmux 위임 스크립트
`scripts/claude-headless.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

PROMPT="${1:?prompt required}"
WORKDIR="${2:-$PWD}"
MODEL="${CLAUDE_MODEL:-claude-sonnet-4-6}"

cd "$WORKDIR"

claude -p "$PROMPT" \
  --permission-mode acceptEdits \
  --model "$MODEL" \
  --output-format json \
  | jq -r '.result // .'
```

### 단계 3: tmux IPC에서 호출
```bash
tmux send-keys -t worker:0 \
  "bash /Users/eunsol/Project/vibe-dotfiles/scripts/claude-headless.sh '코드 리팩토링 후 shellcheck'" Enter
```

### 핵 옵션이 필요한 경우 (워크트리 격리)
```bash
git worktree add ../auto-task feature/auto
cd ../auto-task

claude -p "전체 자동 정리" \
  --dangerously-skip-permissions \
  --output-format json
```
워크트리는 메인 작업공간과 격리되어 폭발 반경 제한.

---

## 보안 트레이드오프

| 방식 | 보안 | 자동화 | 권장 상황 |
|------|------|--------|---------|
| `allow` 화이트리스트 + `acceptEdits` | 상 | 중 | 일반 자동화 |
| `dontAsk` + 명시적 `allow` | 상 | 상 | CI/CD |
| `bypassPermissions` (워크트리) | 중 | 상 | 격리된 대규모 작업 |
| `--dangerously-skip-permissions` (호스트) | 하 | 상 | 금지 |

---

## 즉시 적용 체크리스트

- [ ] 위 스키마를 `.claude/settings.json`에 작성 (또는 `vibe-tools/claude-config/settings.work.json`에 반영)
- [ ] `.claude/settings.local.json`이 gitignore 되어 있는지 확인
- [ ] `scripts/claude-headless.sh` 작성 + `chmod +x`
- [ ] 검증: `bash scripts/claude-headless.sh "echo OK"` → 프롬프트 없이 종료되는지
- [ ] `deny`에 `rm -rf /`, `sudo:*`, `curl|bash` 등록 확인
- [ ] tmux IPC 스크립트(`claude-delegate.sh`)에서 `claude -p ... --permission-mode acceptEdits`로 통일

---

## 한 줄 결론

`claude -p "<task>" --permission-mode acceptEdits` + `permissions.allow` 화이트리스트 + `permissions.deny` 위험명령 차단 → 호스트에서 안전하게 무인 동작. 핵 옵션은 워크트리/Docker 안에서만.

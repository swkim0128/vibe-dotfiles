# Vibe Dotfiles Architecture Guide

Mac 개발 환경 **시스템·터미널 인프라** 원클릭 구축 dotfiles.

## 🏗️ 관심사 분리 (SoC)

| 레포 | 책임 |
|---|---|
| **`vibe-dotfiles`** (본 레포) | 시스템·터미널 인프라 — Zsh, Tmux, Neovim, `vibe-tools/`, `setup.sh` |
| **`vibe-claude-plugin`** | AI 하네스 — `CLAUDE-*.md`, `hooks/`, `settings.work.json`, 마켓플레이스 |

⚠️ 본 레포에 추가 금지 (모두 `vibe-claude-plugin` 관리): 스킬·에이전트·커맨드·`CLAUDE-*.md`·Claude Code 훅·`settings.work.json`.

**의존**: 양 레포 코드 의존 금지. 본 레포의 `vibe-tools/claude-*.sh`를 vibe-claude-plugin이 호출은 PATH 의존 (코드 의존 X).

## 🚀 설치 진입점
- **시스템**: `./setup.sh` (zsh/tmux/nvim/vibe-tools deploy)
- **AI 하네스**: `~/Project/vibe-claude-plugin/install.sh` (CLAUDE-*.md / hooks / settings.json 심링크)
- 두 진입점 독립. setup.sh는 vibe-claude-plugin 자산 무수정.

## 🛠️ 구조
- `tmux/`, `nvim/lua/` (NvChad), `vibe-tools/` (셸 스크립트), `zsh/aliases.zsh`

## ⚙️ dotfiles 한정 룰

글로벌 룰(`~/.claude/CLAUDE-*.md`)에 더해 본 레포만 적용 (L3 우선):

- 주요 언어: Bash, Zsh, Lua, Markdown
- 셸 스크립트 시작: `set -euo pipefail`
- 외부 도구 호출 전: `command -v <tool>` 확인

### VERIFY (본 레포 전용)
| 대상 | 명령 |
|---|---|
| `.sh` 변경 | `shellcheck` (미설치 시 `bash -n`) |
| `tests/bats` | `bats tests/` |
| `nvim/lua/` | `luac -p` |
| `settings.work.json` | `jq empty` (Edit 도구만, Write 금지) |

### 세션 인수인계
중단 전 `todo.md` 또는 `harness:handoff` 스킬로 HANDOFF.md 기록. 재개 시 먼저 읽음.

## 🔌 본 레포 우선 호출 컴포넌트

글로벌 매핑은 `~/.claude/CLAUDE-plugins.md` · `CLAUDE-tools.md`. 본 레포에서 자주 쓰는 것만:

- 셸 변경 검증: `harness:verification-loop` / 직접 `shellcheck`
- 커밋: `git-suite:commit` / MR: `git-suite:mr`
- 영향도 검토: `Agent(subagent_type=Explore)`
- tmux 세션: `tmux-suite:{tmux-session-start, tmux-session-done, claude-ipc, tmux-session-comm}`
- `settings.work.json`: **Edit 전용** + `jq empty` (Write 금지)
- 셋업 점검: `vibe-admin:workspace-surface-audit` / 생태계: `vibe-admin:ecosystem-map`

### 비대상 (호출 안 함)
`analyze:*` (백엔드 전용), `harness:php-review` (PHP 전용), `notion-suite:*` / `nworks:*` / `plane-mcp:*` (필요 시만).

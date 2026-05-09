# Vibe Dotfiles Architecture Guide

이 레포지토리는 사용자의 Mac 개발 환경을 원클릭으로 구축하는 핵심 설정(Dotfiles) 저장소입니다.

## 🏗️ 역할 분담 (중요)
- **이 레포지토리 (`vibe-dotfiles`):** 터미널 껍데기, Zsh, Tmux, Neovim 설정, 시스템 스크립트, Claude Code의 '환경 설정(`settings.json`)'을 담당합니다.
- **마켓플레이스 레포지토리 (`vibe-claude-plugin`):** Claude Code의 프롬프트, 스킬, MCP 등 '지능과 페르소나'를 전담합니다.
⚠️ **절대 이 레포지토리 안에 직접 스킬(`SKILL.md`)을 추가하지 마세요. 스킬은 마켓플레이스 레포지토리에서 관리합니다.**

## 🚀 설치 진입점
- 모든 설치와 심볼릭 링크 구성은 `./setup.sh` 단일 스크립트를 통해 이루어집니다.
- 환경 분기: 설치 시 개인용(`settings.json`)과 업무용(`settings.work.json`) 환경을 선택할 수 있습니다.

## 🛠️ 주요 구조
- `tmux/` : `.tmux.conf` 및 세션 설정
- `nvim/lua/` : NvChad 기반 에디터 설정
- `vibe-tools/` : 커스텀 셸 스크립트 (`vibe.sh`, `claude-delegate.sh` 등)
- `zsh/` : `aliases.zsh` 관리

---

## ⚙️ 프로젝트 특화 룰 (dotfiles 한정)

> **글로벌 하네스 파이프라인**(GROUND→APPLY→VERIFY→ADAPT)과 **위임 전략**은
> `~/.claude/CLAUDE-user.md` · `CLAUDE-delegation.md`에 있습니다.
> 본 섹션은 **dotfiles에서만 적용되는 추가·재정의 룰**입니다 (L3 우선).

### 언어 & 스택 제약
- 주요 언어: Bash, Zsh, Lua (Neovim), Markdown
- 모든 셸 스크립트는 `set -euo pipefail`로 시작
- 외부 도구 호출 전 `command -v <tool>`로 존재 여부 확인

### VERIFY 도구 (이 레포 전용)
| 대상 | 명령 |
|------|------|
| `.sh` 작성·수정 후 | `shellcheck <파일>` (미설치 시 `bash -n <파일>`) |
| `tests/bats` 존재 시 | `bats tests/` |
| `nvim/lua/` 변경 시 | `luac -p <파일>` (Lua 구문 검사) |
| `settings.work.json` 수정 시 | `jq empty <파일>` (Edit 도구만, Write 금지) |

### 세션 인수인계 (todo.md)
- **중단 전**: 완료·TODO·에러를 `todo.md`에 기록
- **재개 시**: `todo.md`를 가장 먼저 읽음

`todo.md` 형식:
```markdown
## 완료
- [x] 항목

## TODO
- [ ] 항목

## 에러 / 블로커
- 현상: / 원인: / 해결 여부:
```

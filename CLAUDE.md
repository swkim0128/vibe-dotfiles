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
- **중단 전**: 완료·TODO·에러를 `todo.md`에 기록 (또는 `harness:handoff` 스킬로 HANDOFF.md 생성)
- **재개 시**: `todo.md` / `HANDOFF.md`를 가장 먼저 읽음
- 단일 TASKS.md 운영은 `task-mgmt:task-management` 스킬 활용 가능

`todo.md` 형식:
```markdown
## 완료
- [x] 항목

## TODO
- [ ] 항목

## 에러 / 블로커
- 현상: / 원인: / 해결 여부:
```

---

## 🔌 플러그인 컴포넌트 매핑 (이 레포 전용)

> 글로벌 매핑은 `~/.claude/CLAUDE-plugins.md`. 본 섹션은 **dotfiles 레포에서 우선 호출**할 컴포넌트만.

### 코드 작업
| 작업 | 컴포넌트 |
|---|---|
| 셸 스크립트 변경 후 검증 | `harness:verification-loop` 스킬 / 직접 `bash -n` + `shellcheck` |
| 첫 Edit/Write/Bash 전 사실 조사 게이트 | `harness:gateguard` 스킬 (자동) |
| 커밋 | `git-suite:commit` 스킬 |
| MR 생성 | `git-suite:mr` / `git-suite:git-mr-creator` 스킬 |
| 변경 영향도 검토 (스크립트·설정 광범위 수정 시) | `Agent(subagent_type=Explore)` |

### 개발 환경 / tmux
| 작업 | 컴포넌트 |
|---|---|
| 새 작업 세션 (PARA 7:3) | `tmux-suite:tmux-session-start` 스킬 |
| 세션 종료 / PARA 복귀 | `tmux-suite:tmux-session-done` 스킬 |
| 패널 간 위임/콜백 | `tmux-suite:claude-ipc` 스킬 |
| 다른 세션에 알림/위임 | `tmux-suite:tmux-session-comm` 스킬 |

### 메타 / 진단
| 작업 | 컴포넌트 |
|---|---|
| `settings.work.json` 수정 | **Edit 도구만** + `jq empty` 검증 / `update-config` 스킬 |
| 셋업 표면 점검 (MCP·플러그인·환경) | `vibe-admin:workspace-surface-audit` 스킬 |
| 플러그인 생태계 비교 | `vibe-admin:ecosystem-map` 스킬 |
| 스킬 작업 후 백업 | `vibe-admin:skill-backup` (자동) |
| 라이브러리/도구 공식 문서 | Context7 MCP (`mcp__plugin_context7_context7__*`) |

### 자동 발동 훅 (참고)
- `harness/bash-guard.sh` — `curl|sh`/`rm -rf`/포그라운드 dev 서버/워크트리 런타임 테스트 차단
- `harness/write-guard.sh` — 시크릿 보호
- `harness/session-start.sh` — 하네스 5조항 주입

### 비대상 (이 레포에서 호출하지 않음)
- `analyze:*` (Spring Boot/FastAPI/SQL 등) — 백엔드 레포 전용
- `harness:php-review` / `analyze:file-encoding-converter` — PHP 레포 전용
- `notion-suite:*`, `nworks:*`, `plane-mcp:*` — 외부 시스템 연동 (필요 시 호출)

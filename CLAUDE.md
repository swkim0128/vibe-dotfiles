# Vibe Dotfiles Architecture Guide

Mac 개발 환경 **시스템·터미널 인프라** 원클릭 구축 dotfiles.

본 파일은 **자기 완결적(self-contained)** 이다. 전역 룰(`~/.claude/CLAUDE-*.md`)이 없는 환경에서도 본 레포만으로 빌드·VERIFY 가능. 글로벌 룰은 상위 컨텍스트로 우선 적용되되, **부재 시 본 파일이 진실 공급원**.

> **전역 규칙 항상 우선**: `~/.claude/CLAUDE.md` (L1 운영 원칙 6개) + `CLAUDE-user.md` / `CLAUDE-paths.md` / `CLAUDE-delegation*.md`(core·discipline·overnight 3분할) / `CLAUDE-workflows.md` / `CLAUDE-plugins.md` / `CLAUDE-tools.md`를 따른다. Subagent-First는 L1에서 강제. 본 레포는 self-contained 보장을 위해 핵심 절차도 자체 수록 — 전역 룰 부재 환경에서도 빌드·VERIFY 가능.
> 전역 KB (선택적): `${KB_PATH:-<repo>/docs/knowledge-base}` — 본 레포 내부 `docs/knowledge-base/` 자체가 SSoT 이므로 항상 존재. `<repo>` 는 본 레포 루트(`setup.sh` 가 있는 디렉토리).

---

## 블록 1 — 외부 통합 (선택적 의존성 / Optional Integrations)

본 레포는 다음 외부 자산의 **물리적 존재에 의존하지 않는다**. 환경변수로 위치를 명시 가능, 부재 시 자동 skip / 폴백.

| 환경 변수 | 폴백 | 용도 | 부재 시 동작 |
|---|---|---|---|
| `PARA_PATH` | `$HOME/Project/para` | 외부 PARA 볼트 (단기 작업·회고) | `overnight_worker.sh` 가 PARA 통합 skip + 블루프린트는 `$TMPDIR/overnight-blueprints/` 폴백 |
| `REPO_SCAN_ROOT` | `$HOME/Project` | git 활동 스캔 루트 | 디렉토리 부재 시 빈 분석으로 진행 |
| `VIBE_CLAUDE_PLUGIN_PATH` | `$HOME/Project/vibe-claude-plugin` | 외부 AI 하네스 레포 | `setup.sh` 가 안내만 출력. 본 레포는 정상 동작 |
| `CLAUDE_BIN` | PATH 자동 탐색 | claude CLI | 미존재 시 `overnight_worker.sh` 만 fail (다른 모든 기능 정상) |

**완벽한 독립성 약속**: 이 폴더 통째로 다른 Mac 에 복사 → `./setup.sh` → 시스템·터미널 인프라 100% 동작. 외부 레포 없이도 모든 VERIFY 통과.

---

## 블록 2 — 기술 스택 컨텍스트

- **주요 언어**: Bash, Zsh, Lua, Markdown
- **빌드 도구**: 없음 — 셸 스크립트 직접 실행 (`./setup.sh`)
- **외부 의존 (필수)**: Homebrew (CLI 도구 설치), Git
- **외부 의존 (선택)**: bats-core (테스트), shellcheck (lint), luac (Lua 문법 검증)
- **DB / 인프라 의존**: 없음
- **인코딩**: UTF-8 (LF). EUC-KR / CRLF 없음.
- **디렉토리 구조 (1줄 요약)**:
  ```
  setup.sh / CLAUDE.md / tmux/ / nvim/lua/ (NvChad) / vibe-tools/ (사용자 설정 데이터·overnight·issue-start) /
  zsh/aliases.zsh / glow/ / docs/ / tests/bats/ / docs/knowledge-base/ (KB SSoT)
  ```

---

## 블록 3 — VERIFY 툴셋 (단일 명령어 분해)

하네스 7조항 #6 준수 — 세미콜론·`&&`·`||`·파이프·`2>&1` redirect 회피. 각 명령 독립 실행.

```bash
# 셸 스크립트 문법 검증 (필수 — 모든 .sh 변경 시)
shellcheck setup.sh
shellcheck vibe-tools/*.sh

# shellcheck 미설치 환경 폴백
bash -n setup.sh
bash -n vibe-tools/overnight_worker.sh

# bats 테스트 (선택)
bats tests/bats/

# Lua 문법 검증 (nvim 설정 변경 시)
luac -p nvim/lua/options.lua

# JSON 문법 검증 (settings.json 류 변경 시 — Edit 도구로만 수정)
jq empty path/to/settings.json

# 야간 워커 dry-run (외부 의존 fallback 검증 포함)
DRY_RUN=1 bash vibe-tools/overnight_worker.sh
```

복합 체이닝(`./gradlew clean build test`)·redirect/파이프 포함 명령은 **금지** — Bash 권한 패턴 매칭 실패로 매번 프롬프트 발생.

---

## 🏗️ 관심사 분리 (SoC)

| 레포 | 책임 |
|---|---|
| **`vibe-dotfiles`** (본 레포) | 시스템·터미널 인프라 — Zsh, Tmux, Neovim, `vibe-tools/`, `setup.sh` |
| **외부 AI 하네스 레포** (선택적) | `CLAUDE-*.md`, `hooks/`, `settings.work.json`, 마켓플레이스 |

본 레포에 추가 금지: AI 스킬·에이전트·커맨드·`CLAUDE-*.md` 신설·Claude Code 훅·`settings.work.json`. 이런 자산은 별도 AI 하네스 레포로 분리.

**코드 의존 0**: 본 레포 `vibe-tools/` 는 사용자 설정 데이터(`sessionizer-paths.txt`, `project-paths.txt`, `commands_*.txt` 등) + `overnight_worker.sh`, `issue-start.sh`, `com.swkim0128.overnight.plist` 만 보관. tmux/CLI 통합 셸(`vibe.sh`, `claude-{send,delegate,callback,switch}.sh`, `my-tools.sh`, `vhelp.sh`, `claude-skills.sh`, `cheatsheet.md`)은 vibe-claude-plugin/plugins/tmux-suite/scripts/ 가 SSoT (2026-06-02 이관, Skill Internal-Dependency Rule).

## 🚀 설치 진입점
- **시스템**: `./setup.sh` (zsh/tmux/nvim/vibe-tools deploy) — 본 레포 단독 실행 가능
- **AI 하네스** (선택): `VIBE_CLAUDE_PLUGIN_PATH=<레포경로> ./setup.sh` 재실행 또는 외부 레포의 `install.sh` 별도 실행
- 두 진입점 독립. `setup.sh` 는 외부 AI 하네스 자산을 절대 수정하지 않음.

## 🛠️ 구조
- `tmux/`, `nvim/lua/` (NvChad), `vibe-tools/` (사용자 설정 데이터·overnight·issue-start), `zsh/aliases.zsh`, `docs/knowledge-base/` (KB SSoT)

## 세션 인수인계
중단 전 `todo.md` 또는 (외부 하네스 설치 시) `harness:handoff` 스킬로 `HANDOFF.md` 기록. 재개 시 먼저 읽음.

## 🔌 본 레포 우선 호출 컴포넌트 (외부 AI 하네스가 설치된 경우)

- 셸 변경 검증: 직접 `shellcheck` / (있으면) `harness:verification-loop`
- 커밋: (있으면) `git-suite:commit` / MR: `git-suite:mr` / 미설치 시 일반 `git commit`
- 영향도 검토: (있으면) `Agent(subagent_type=Explore)` / 미설치 시 `grep` 직접
- tmux 세션: (있으면) `tmux-suite:*` / 미설치 시 `tmux` 직접
- `settings.work.json`: **Edit 전용** + `jq empty` (Write 금지) — 외부 레포 자산이므로 본 레포 작업과 무관

### 비대상 (본 레포에서 호출 안 함)
백엔드 분석(`analyze:*`), PHP(`harness:php-review`), 노션/그룹웨어/이슈트래커(`notion-suite:*`/`nworks:*`/`plane-mcp:*`) — 본 레포는 인프라 전용.

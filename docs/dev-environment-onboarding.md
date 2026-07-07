# 개발환경 셋업 온보딩 가이드 (vibe-dotfiles)

> Mac 개발 환경의 **시스템·터미널 인프라**를 한 번에 구축하는 dotfiles 셋업 가이드입니다.
> 신규 팀원이 이 문서만 따라가면 동일한 터미널·에디터·자동화 환경을 30분 내에 재현할 수 있습니다.
>
> - 대상 OS: macOS (Apple Silicon 기준, Intel은 Homebrew PATH 수동 조정)
> - 필수 의존: Homebrew, Git
> - 선택 의존: Claude Code CLI, PARA 볼트, 사내 AI 하네스 (없어도 전부 정상 동작)

---

## 1. 이 환경이 무엇인가

`vibe-dotfiles`는 아래를 **하나의 원클릭 설치(`setup.sh`)로 통합**한 개인 개발 환경 셋업입니다.

| 레이어 | 구성 | 테마/특징 |
|---|---|---|
| **셸** | Zsh + Oh My Zsh + Zinit + Starship | alias·함수·cmux 런처 |
| **멀티플렉서** | Tmux (TPM 플러그인) | Catppuccin, IME-safe 키맵 |
| **에디터** | Neovim (NvChad + LSP) | Catppuccin, transparency |
| **터미널** | Ghostty + cmux | 테마 상속, 워크스페이스 |
| **런처** | `vibe-tools/` cmux 런처 6종 | 프로젝트별 워크스페이스 |
| **자동화** | launchd 야간 워커 3종 | overnight · skill-audit · notion-diary |
| **AI 하네스** (선택) | Claude Code + 플러그인 | 룰셋·스킬·에이전트 위임 |

### 설계 원칙 — 관심사 분리 (SoC)

- **본 레포 (`vibe-dotfiles`)**: 시스템·터미널 인프라 전용 (Zsh/Tmux/Nvim/`vibe-tools`/`setup.sh`)
- **AI 하네스 (별도 레포, 선택)**: `CLAUDE-*.md` 룰셋, hooks, 플러그인 마켓플레이스
- 본 레포는 **자기완결적**: AI 설정·PARA 볼트가 없어도 100% 정상 동작. 통째로 다른 Mac에 복사 → `./setup.sh` → 인프라 완성.

---

## 2. 사전 준비

```bash
# Homebrew (없으면 setup.sh가 자동 설치하지만, 미리 두면 안전)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Git 확인
git --version
```

---

## 3. 설치 (Quick Start)

```bash
# 1. 레포 클론 (사내 Git 호스트 경로는 팀 위키/담당자 확인)
git clone <레포_URL> ~/Project/vibe-dotfiles

# 2. 원클릭 설치
cd ~/Project/vibe-dotfiles
./setup.sh

# 3. 셸 리로드
source ~/.zshrc
```

### `setup.sh`가 하는 일 (요약)

`setup.sh`는 멱등(idempotent)하게 아래를 순서대로 수행합니다. 이미 설치·링크된 항목은 자동 skip.

| 단계 | 대상 | 동작 |
|---|---|---|
| 0 | Homebrew | 미설치 시 설치 + PATH 등록 |
| 1 | CLI 도구 | lsd, bat, fzf, fd, ripgrep, git-delta, btop, lazygit, neovim, tmux, zoxide, starship, yazi, gh, jq, glow, shellcheck, bats-core 등 |
| 2~3 | Zsh 생태계 | Oh My Zsh + Zinit |
| 4 | AI CLI (선택) | Claude Code, Gemini CLI (`brew install`) |
| 4b | GUI 터미널 | Ghostty, cmux (cask) + 설정 심볼릭 링크 |
| 5~6 | Tmux | TPM clone + `~/.tmux.conf` 링크 |
| 7 | vibe-tools | `~/.config/vibe-tools` 링크 + 스크립트 실행권한 |
| 8 | Neovim | `~/.config/nvim/lua` 링크 |
| 11~14 | Zsh alias / Git Delta / (선택)플러그인 / Glow | 각 설정 배포 |

### 심볼릭 링크 매핑

| 시스템 위치 | ← 레포 소스 |
|---|---|
| `~/.tmux.conf` | `tmux/.tmux.conf` |
| `~/.config/vibe-tools/` | `vibe-tools/` |
| `~/.config/nvim/lua/` | `nvim/lua/` |
| `~/.config/ghostty/config` | `ghostty/config` |
| `~/.config/cmux/cmux.json` | `cmux/cmux.json` |

> 역방향 백업: `./backup.sh` — 현재 시스템 dotfiles를 레포로 복사 (이미 링크된 항목은 skip).

### 설치 후 마무리

```bash
# NvChad 부트스트랩 (에디터)
git clone https://github.com/NvChad/starter ~/.config/nvim
nvim   # 실행 후 :MasonInstallAll 로 LSP 서버 일괄 설치

# 동작 확인
cmux-proj vibe-dotfiles
```

---

## 4. cmux 런처 — 프로젝트별 워크스페이스

raw cmux 명령을 즉흥 조합하는 대신, **정규화 런처**(zsh 함수)를 사용합니다.

| 명령 | 용도 |
|---|---|
| `cmux-proj <name>` | 단일 프로젝트 워크스페이스 + tmux 세션(claude/edit/verify 3창) |
| `cmux-dual <a> <b>` | 두 프로젝트를 tmux split으로 동시 |
| `cmux-ops <name>` | 수동처리/서버 ops 워크스페이스 (SSH 호스트 선택 가능) |
| `cmux-review <name> [--branch\|--staged\|--unstaged]` | diff 리뷰 워크스페이스 |
| `cmux-pair <app> <manifest>` | 앱 + k8s 매니페스트 페어 |
| `cmux-close <name>` | 워크스페이스만 종료 (tmux 세션은 유지) |

### 프로젝트 등록

프로젝트 목록은 `vibe-tools/cmux-projects.txt` 에 pipe-delimited로 등록합니다.

```
# name|path|hexcolor|description|pin(선택)
vibe-dotfiles|$HOME/Project/vibe-dotfiles|#196F3D|Mac dev 환경 dotfiles|pin
para|$HOME/Project/para|#006B6B|작업 허브|pin
```

- **회사 경로 등 머신별 항목**은 `cmux-projects.local.txt` (gitignore, 비커밋)에만 등록 → 커밋 레포에 사내 경로가 남지 않습니다.
- 워크스페이스 없이 tmux 세션만 원하는 프로젝트는 `cmux-no-workspace.txt` 에 등록.

> 키맵·CLI 소켓 제어 상세는 [`docs/cmux-cheatsheet.md`](./cmux-cheatsheet.md) 참조.

---

## 5. 야간 자동화 3종 (launchd)

`vibe-tools/`의 셸 워커 + `com.swkim0128.*.plist` 조합. 모두 `caffeinate`(슬립 방지) + 로그인 셸로 실행되며, 로그는 `~/Library/Logs/<이름>/` 에 남습니다.

| 워커 | 스케줄 | 역할 | LLM 의존 |
|---|---|---|---|
| **overnight** | 매일 02:00 | PARA 프로젝트 git 활동 스캔 → 다음 날 1순위 과제 블루프린트 생성 | 선택 (claude CLI) |
| **skill-audit** | 매일 22:00 | 당일 스킬/에이전트 호출 집계 vs 설정 인벤토리 비교 → 제거 후보 리포트 | 없음 (순수 셸) |
| **notion-diary** | 매일 18:00 | 오늘 git 커밋을 시간대별 수집 → Notion 다이어리에 append-only 기록 | 있음 (`claude --print` 헤드리스) |

### 등록 방법 (기본은 비활성 — 수동 bootstrap 필요)

```bash
# 예: skill-audit
cp vibe-tools/com.swkim0128.skill-audit.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.skill-audit.plist
launchctl print gui/$(id -u)/com.swkim0128.skill-audit
```

> plist 내 사용자 경로(`$HOME/...`)와 `CLAUDE_BIN` 등은 각자 환경에 맞게 조정합니다.
> 안전 가드: overnight은 소스 Read + 블루프린트 Write만, notion-diary는 git Read + Notion append-only(멱등).

---

## 6. AI 하네스 (선택 통합)

Claude Code 기반 룰셋·스킬·에이전트 위임 워크플로우를 쓰려면 별도 AI 하네스 레포를 통합합니다.

```bash
# 외부 하네스 레포 위치를 환경변수로 명시 후 재실행
VIBE_AI_CONFIG_PATH=<하네스_레포_경로> ./setup.sh
```

- 부재 시 `setup.sh`는 안내만 출력하고 정상 완료합니다 (본 레포 기능에 영향 없음).
- 상세는 사내 AI 하네스 레포 문서 참조.

---

## 7. 검증 (VERIFY)

변경 후 아래 단일 명령으로 검증합니다 (체이닝 없이 각각 실행).

```bash
shellcheck setup.sh
shellcheck vibe-tools/*.sh
bash -n setup.sh              # shellcheck 미설치 폴백
luac -p nvim/lua/options.lua  # Lua 문법
jq empty cmux/cmux.json       # JSON 문법
bats tests/bats/              # (선택) 테스트
DRY_RUN=1 bash vibe-tools/overnight_worker.sh   # 야간 워커 dry-run
```

---

## 8. 팀 도입 체크리스트

- [ ] Homebrew·Git 준비 → `git clone` → `./setup.sh`
- [ ] `source ~/.zshrc` → `cmux-proj vibe-dotfiles` 로 동작 확인
- [ ] NvChad 부트스트랩 + `:MasonInstallAll`
- [ ] 개인 프로젝트를 `cmux-projects.local.txt` (비커밋)에 등록
- [ ] (선택) 야간 자동화 워커 `launchctl bootstrap`
- [ ] (선택) AI 하네스 `VIBE_AI_CONFIG_PATH` 통합

---

## 9. 디렉토리 맵 (참고)

```
vibe-dotfiles/
├── setup.sh / backup.sh          # 설치 / 역방향 백업
├── CLAUDE.md / README.md          # 아키텍처 지침 / 사용 가이드
├── tmux/.tmux.conf                # Tmux (Catppuccin, TPM)
├── nvim/lua/                      # Neovim (NvChad + LSP)
├── zsh/aliases.zsh                # alias·함수·cmux 런처
├── ghostty/config, cmux/cmux.json # 터미널 설정
├── vibe-tools/                    # cmux 런처 6종 + 야간 워커 3종 + 설정 데이터
├── docs/                          # 문서 + knowledge-base/ (KB SSoT)
└── tests/bats/                    # bats-core 테스트
```

---

## 부록 — 공유 시 주의 (민감정보)

본 문서/레포를 외부 공유할 때 아래는 각 환경 고유값이므로 커밋/공유 전 확인합니다.

- **사내 Git 호스트·마켓플레이스 URL**: 문서에서 `<레포_URL>` 등 플레이스홀더로 대체 (실제 사내 주소 미포함).
- **회사 경로·서버 호스트**: `*.local.txt` (gitignore)에만 두어 커밋 레포에서 격리.
- **회사 도메인 설정** (`git-template-config.json`의 `work_domain`): 각 조직 값으로 교체.
- **토큰/API 키**: 본 레포에 일절 미포함 — Claude CLI·환경변수로만 관리.
- **사용자 절대경로** (`$HOME`/`/Users/<id>`): plist·스크립트에서 각자 환경에 맞게 조정.

---

_최종 업데이트: 2026-07-07_

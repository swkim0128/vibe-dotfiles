# Vibe Dotfiles

Tmux + Neovim (NvChad) + Claude Code IPC + 커스텀 CLI 도구로 구성된 **Vibe Coding 환경** 설정 파일 모음입니다.

---

## 📁 디렉토리 구조

```
vibe-dotfiles/
├── setup.sh                  # 원클릭 설치 스크립트
├── tmux/
│   └── .tmux.conf            # Tmux 전체 설정
├── vibe-tools/               # ~/.config/vibe-tools/ 로 심볼릭 링크
│   ├── cheatsheet.md         # 단축키 통합 매뉴얼 (Prefix+? 또는 vhelp)
│   ├── commands.txt          # 커스텀 명령어 목록 (Prefix+M 팝업)
│   ├── claude-skills.txt     # Claude 스킬 목록 (Prefix+C 팝업)
│   ├── my-tools.sh           # fzf 명령어 팝업 메뉴
│   ├── tmux-sessionizer.sh   # 프로젝트 세션 매니저 (Prefix+F)
│   ├── claude-delegate.sh    # 패널 간 클로드 작업 위임 (IPC)
│   ├── claude-callback.sh    # 작업 완료 보고 (IPC)
│   ├── claude-config/        # Claude Code 설정 (→ ~/.claude/ symlink)
│   │   ├── settings.json     # 플러그인, hooks 설정
│   │   └── hooks/
│   │       └── mac-notify.sh # 작업 완료 macOS 알림
│   └── claude-plugin/        # 개인 Claude Code 플러그인 (vibe-config@swkim0128)
│       ├── package.json
│       ├── hooks/hooks.json  # Stop/Notification 훅
│       └── skills/claude-ipc/SKILL.md
├── nvim/
│   └── lua/                  # ~/.config/nvim/lua/ 로 심볼릭 링크
│       ├── chadrc.lua        # NvChad 테마/UI 설정
│       ├── options.lua       # 기본 옵션
│       ├── mappings.lua      # 키 매핑
│       ├── plugins/init.lua  # 추가 플러그인
│       └── configs/          # LSP, 포매터 설정
└── zsh/
    └── aliases.zsh           # alias, bindkey, tools 함수
```

---

## 🚀 새 Mac에서 설치하기

### 1단계 — 사전 요구사항 설치

```bash
# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 필수 CLI 도구
brew install neovim tmux lsd bat fzf fd ripgrep git-delta btop \
             dust duf fastfetch zoxide lazygit navi starship mise

# 터미널
brew install --cask ghostty

# Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Claude Code
curl -fsSL https://claude.ai/install.sh | bash
```

### 2단계 — Dotfiles 클론

```bash
mkdir -p ~/Project
git clone <repo-url> ~/Project/vibe-dotfiles
```

### 3단계 — 원클릭 설치

```bash
cd ~/Project/vibe-dotfiles
./setup.sh
```

setup.sh가 수행하는 작업:
- `~/.tmux.conf` → `tmux/.tmux.conf` 심볼릭 링크
- `~/.config/vibe-tools/` → `vibe-tools/` 심볼릭 링크
- `~/.config/nvim/lua/` → `nvim/lua/` 심볼릭 링크
- `~/.claude/settings.json`, `~/.claude/hooks` 심볼릭 링크
- `~/.claude/plugins/cache/swkim0128/vibe-config` 심볼릭 링크 (개인 플러그인)
- `~/.zshrc` 에 `aliases.zsh` source 라인 자동 추가

### 4단계 — NvChad 설치 (Neovim 처음 설정 시)

```bash
# NvChad starter 설치 (lua/ 는 setup.sh가 이미 심볼릭 링크로 연결함)
git clone https://github.com/NvChad/starter ~/.config/nvim && nvim
# nvim 안에서 플러그인 설치 완료 후:
# :MasonInstallAll  ← LSP 서버 일괄 설치
```

### 5단계 — Alias 적용

```bash
source ~/.zshrc
```

---

## ⌨️ 주요 단축키 요약

| 단축키 | 기능 |
|--------|------|
| `Prefix + ?` | 전체 단축키 매뉴얼 팝업 |
| `Prefix + f` | 프로젝트 세션 매니저 |
| `Prefix + C` | Claude 스킬 팝업 |
| `Prefix + M` | 커스텀 명령어 팝업 |
| `Prefix + Tab` | yazi 파일 탐색기 |
| `Ctrl + F` | 명령어 팝업 (셸에서) |
| `vhelp` | 단축키 매뉴얼 열기 |
| `lg` | lazygit |

> 전체 단축키는 `vhelp` 또는 `Prefix + ?` 로 확인하세요.

---

## 🔄 설정 업데이트

dotfiles 파일을 수정하면 심볼릭 링크로 연결된 시스템에 즉시 반영됩니다.

```bash
# tmux 설정 변경 후 즉시 적용
tmux source-file ~/.tmux.conf

# 변경사항 커밋
cd ~/Project/vibe-dotfiles
git add .
git commit -m "chore: update config"
git push
```

---

## 📦 Claude Code 개인 플러그인 (`vibe-config@swkim0128`)

설치 후 Claude Code를 재시작하면 자동으로 로드됩니다.

- **Stop 훅**: 작업 완료 시 Glass.aiff 사운드
- **Notification 훅**: Ping.aiff + macOS 알림
- **claude-ipc 스킬**: 패널 간 작업 위임 워크플로우

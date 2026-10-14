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
│   └── claude-plugin/        # 개인 Claude Code 플러그인 (vibe-config@personal)
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
├── zsh/
│   └── aliases.zsh           # alias, bindkey, tools 함수
├── ghostty/
│   └── config                # ~/.config/ghostty/config 로 심볼릭 링크 (cmux 가 테마·폰트 상속)
└── cmux/
    └── cmux.json             # ~/.config/cmux/cmux.json 로 심볼릭 링크 (cmux 자체 동작 설정)
```

---

## 🚀 새 Mac에서 설치하기

### 개발 설계·소스 조사 도구 (개인·업무 Mac 공통, 선택 설치)

기존 `setup.sh`를 재실행하지 않고 [Brewfile.dev](Brewfile.dev)의 도구만 설치합니다. 각 Mac에서 저장소를 최신화한 뒤 아래 명령을 **각각** 실행하세요. `brew bundle check`는 설치 상태 검사이며 패키지를 설치하지 않습니다. 업무컴에서는 회사 소프트웨어 설치 정책을 먼저 확인하세요.

```bash
env HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --verbose --file /path/to/vibe-dotfiles/Brewfile.dev
brew bundle --file /path/to/vibe-dotfiles/Brewfile.dev
```

`/path/to/vibe-dotfiles`는 해당 기기의 실제 저장소 경로로 바꿉니다. `ast-grep`은 구조적 소스 검색, `graphviz`는 그래프 렌더링, `plantuml`은 텍스트 UML, `drawio`는 기존 설계 원본의 편집·내보내기에 사용합니다. PlantUML의 Java 의존성은 Homebrew가 관리합니다. 프로젝트별 구현·테스트는 기존 빌드 도구와 테스트 러너를 그대로 사용하며 이 목록에 런타임을 일괄 설치하지 않습니다.

Claude Code·Codex에서 별도 MCP 없이 터미널 명령으로 사용할 수 있습니다. draw.io 공식 cask는 `drawio` 명령을 제공하며 앱 직접 실행 경로는 `/Applications/draw.io.app/Contents/MacOS/draw.io`입니다. 설치 후 `ast-grep --version`, `dot -V`, `plantuml -version`, `drawio --help`를 각각 확인하세요. draw.io는 Desktop 기반이므로 표시 세션이 없는 서버용 headless CLI로 가정하지 않습니다. 회사 코드·설계는 로컬에서 처리하며 외부 렌더 서버나 업로드 서비스를 사용하지 않습니다.

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
- `~/.claude/plugins/cache/personal/vibe-config` 심볼릭 링크 (개인 플러그인)
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

## 📦 Claude Code 개인 플러그인 (`vibe-config@personal`)

설치 후 Claude Code를 재시작하면 자동으로 로드됩니다.

- **Stop 훅**: 작업 완료 시 Glass.aiff 사운드
- **Notification 훅**: Ping.aiff + macOS 알림
- **claude-ipc 스킬**: 패널 간 작업 위임 워크플로우

# Vibe Dotfiles

Tmux + Neovim (NvChad) + Claude Code IPC + 커스텀 CLI 도구로 구성된 **Vibe Coding 환경** 설정 파일 모음입니다.

---

## 📁 디렉토리 구조

```
vibe-dotfiles/
├── install.sh                # 원클릭 설치 스크립트
├── Brewfile                  # Homebrew 패키지 정본 (install.sh 가 brew bundle 로 설치)
├── tmux/
│   └── .tmux.conf            # Tmux 전체 설정
├── vibe-tools/               # ~/.config/vibe-tools/ 로 심볼릭 링크
│   ├── cheatsheet.md         # 단축키 통합 매뉴얼 (Prefix+? 또는 vhelp)
│   ├── commands.txt          # 커스텀 명령어 목록 (Prefix+M 팝업)
│   ├── claude-skills.txt     # Claude 스킬 목록 (Prefix+C 팝업)
│   ├── my-tools.sh           # fzf 명령어 팝업 메뉴
│   ├── tmux-sessionizer.sh   # 프로젝트 세션 매니저 (Prefix+F)
│   ├── claude-delegate.sh    # 패널 간 클로드 작업 위임 (IPC)
│   └── claude-callback.sh    # 작업 완료 보고 (IPC)
├── nvim/
│   └── lua/                  # ~/.config/nvim/lua/ 로 심볼릭 링크
│       ├── chadrc.lua        # NvChad 테마/UI 설정
│       ├── options.lua       # 기본 옵션
│       ├── mappings.lua      # 키 매핑
│       ├── plugins/init.lua  # 추가 플러그인
│       └── configs/          # LSP, 포매터 설정
├── zsh/
│   ├── aliases.zsh           # alias, bindkey, tools 함수
│   └── env.zsh               # 공용 환경변수 (~/.zshenv 에서 source, 텔레메트리 끄기 등)
├── git/
│   └── gitignore_global      # ~/.gitignore_global 로 심볼릭 링크 (전역 core.excludesfile)
├── ghostty/
│   └── config                # ~/.config/ghostty/config 로 심볼릭 링크 (cmux 가 테마·폰트 상속)
└── cmux/
    └── cmux.json             # ~/.config/cmux/cmux.json 로 심볼릭 링크 (cmux 자체 동작 설정)
```

---

## 🚀 새 Mac에서 설치하기

### 1단계 — 클론 후 원클릭 설치

```bash
git clone <repo-url> ~/Project/vibe-dotfiles
~/Project/vibe-dotfiles/install.sh
```

**[Brewfile](Brewfile)이 패키지 정본입니다.** `install.sh`는 Homebrew가 없으면 설치한 뒤 `brew bundle --file Brewfile`로 CLI 도구·AI CLI·GUI 터미널·개발 설계 도구를 설치합니다. 이미 설치된 항목은 건너뛰므로 다시 실행해도 됩니다. 패키지를 추가·삭제할 때는 Brewfile만 고치고 `install.sh`를 다시 실행하세요. 설치 없이 상태만 보려면 `brew bundle check --verbose --file Brewfile`을 씁니다. 업무컴에서는 회사 소프트웨어 설치 정책을 먼저 확인하세요.
Ghostty·draw.io·cmux는 brew 밖에서 수동 설치한 앱이 `/Applications`에 이미 있으면 Brewfile이 건너뜁니다(관리자 권한 없는 Mac에서 brew가 기존 앱을 넘겨받다 실패하는 것을 막음). brew로 설치한 앱은 계속 업그레이드 대상입니다.
Homebrew cask가 없는 수동 앱 Catchtype(한/영 자동 전환)은 [catchtype/README.md](catchtype/README.md) 절차로 설치합니다.

install.sh가 수행하는 작업:
- Homebrew 설치 확인 → `Brewfile` 패키지 설치
- Oh My Zsh·Zinit·Tmux TPM 설치 확인
- `~/.tmux.conf` → `tmux/.tmux.conf` 심볼릭 링크
- `~/.config/vibe-tools/` → `vibe-tools/` 심볼릭 링크
- `~/.config/nvim/lua/` → `nvim/lua/` 심볼릭 링크
- `~/.zshrc` 에 `aliases.zsh`, `~/.zshenv` 에 `env.zsh` source 라인 자동 추가
- `~/.gitignore_global` → `git/gitignore_global` 심볼릭 링크 + `git config --global core.excludesfile` 지정 (Serena·OpenSpec·ast-grep 자동 생성물을 모든 레포에서 비추적)

`openspec`(스펙 주도 개발 CLI)은 익명 텔레메트리가 기본으로 켜져 있습니다. [zsh/env.zsh](zsh/env.zsh)의 `OPENSPEC_TELEMETRY=0`·`DO_NOT_TRACK=1`로 끕니다(둘 다 켜면 업데이트 확인도 꺼짐).
`openspec init`이 만드는 `openspec/`·`.claude/skills/openspec-*`·`.claude/commands/opsx/`·`.agents/skills/openspec-*`는 [git/gitignore_global](git/gitignore_global)이 전역으로 무시합니다. 새 도구가 레포에 파일을 만들면 이 파일에 도구명 주석과 함께 추가하세요.

### 2단계 — NvChad 설치 (Neovim 처음 설정 시)

```bash
# NvChad starter 설치 (lua/ 는 install.sh가 이미 심볼릭 링크로 연결함)
git clone https://github.com/NvChad/starter ~/.config/nvim && nvim
# nvim 안에서 플러그인 설치 완료 후:
# :MasonInstallAll  ← LSP 서버 일괄 설치
```

### 3단계 — Alias 적용

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

## 📦 Claude Code 플러그인·MCP·스킬

이 레포는 설치하지 않습니다. vibe-ai-config 레포의 `install.sh work|personal`이 마켓플레이스 등록·플러그인·MCP·스킬·훅·settings를 설치합니다.

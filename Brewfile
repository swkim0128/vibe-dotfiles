# Vibe Dotfiles 패키지 정본 — install.sh 가 `brew bundle --file Brewfile` 로 설치한다.
# 패키지 추가·삭제는 이 파일에서만 한다. 상태 검사만: brew bundle check --file Brewfile

# ── CLI 기본 도구 ─────────────────────────────────────────────────────────────
brew "lsd"
brew "bat"
brew "fzf"
brew "fd"
brew "ripgrep"
brew "git-delta"
brew "btop"
brew "dust"
brew "duf"
brew "fastfetch"
brew "zoxide"
brew "lazygit"
brew "navi"
brew "starship"
brew "mise"
brew "yazi"
brew "gh"
brew "jq"
brew "thefuck"
brew "glow"

# ── 에디터·터미널 멀티플렉서 ─────────────────────────────────────────────────
brew "neovim"
brew "tmux"
brew "tmuxinator"

# ── 린트·테스트 ───────────────────────────────────────────────────────────────
brew "ktlint"
brew "detekt"
brew "shellcheck"
brew "bats-core"

# ── 개발 설계·소스 조사 ───────────────────────────────────────────────────────
# AST 패턴 기반 소스 검색·규칙 검사. 언어별 지원 범위를 먼저 확인한다.
brew "ast-grep"
# DOT 그래프와 PlantUML 레이아웃 렌더링.
brew "graphviz"
# 유스케이스·시퀀스·도메인·클래스·데이터 모델 UML. Java는 Homebrew 의존성으로 관리한다.
brew "plantuml"
# 스펙 주도 개발(변경 제안·스펙 문서) CLI. 텔레메트리는 zsh/env.zsh 에서 끈다.
brew "openspec"
# 기존 .drawio XML 설계 원본 편집·로컬 내보내기. 공식 cask가 drawio CLI도 제공한다.
cask "drawio"

# ── AI CLI ───────────────────────────────────────────────────────────────────
cask "claude-code"
# Google Antigravity CLI (명령: agy). deprecated 된 gemini-cli 의 공식 대체.
cask "antigravity-cli"

# ── GUI 터미널 앱 (cmux 는 ghostty config 의 테마·폰트를 상속) ────────────────
cask "ghostty"
cask "cmux"

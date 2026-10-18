# Vibe Dotfiles 패키지 정본 — install.sh 가 `brew bundle --file Brewfile` 로 설치한다.
# 패키지 추가·삭제는 이 파일에서만 한다. 상태 검사만: brew bundle check --file Brewfile

# .app 을 만드는 cask 는 brew 밖에서 수동 설치한 앱이 /Applications 에 있으면 건너뛴다.
# 관리자 권한 없는 Mac 에서 brew 가 수동 설치 앱을 adopt 하다 sudo chgrp 로 실패해 bundle 전체가 멈추기 때문.
# brew 가 이미 관리 중인 cask(Caskroom 에 있음)는 그대로 포함되어 upgrade 대상이 된다.
def manual_app?(token, app)
  caskroom = File.join(ENV.fetch("HOMEBREW_PREFIX", "/opt/homebrew"), "Caskroom", token)
  File.exist?("/Applications/#{app}") && !File.directory?(caskroom)
end

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
cask "drawio" unless manual_app?("drawio", "draw.io.app")

# ── AI CLI ───────────────────────────────────────────────────────────────────
cask "claude-code"
# Codex·Claude 사용량 표시. 인증정보는 앱/Keychain에서 관리하고 저장소에 보관하지 않는다.
cask "codexbar" unless manual_app?("codexbar", "CodexBar.app")

# ── GUI 터미널 앱 (cmux 는 ghostty config 의 테마·폰트를 상속) ────────────────
cask "ghostty" unless manual_app?("ghostty", "Ghostty.app")
cask "cmux" unless manual_app?("cmux", "cmux.app")

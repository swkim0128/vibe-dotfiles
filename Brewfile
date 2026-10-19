# Vibe Dotfiles 패키지 정본 — install.sh 가 `brew bundle --file Brewfile` 로 설치한다.
# 패키지 추가·삭제는 이 파일에서만 한다. 상태 검사만: brew bundle check --file Brewfile

# .app 을 만드는 cask 는 brew 밖에서 수동 설치한 앱이 /Applications 또는 ~/Applications 에 있으면 건너뛴다.
# 관리자 권한 없는 Mac 에서 brew 가 수동 설치 앱을 adopt 하다 sudo chgrp 로 실패해 bundle 전체가 멈추기 때문.
# brew 가 이미 관리 중인 cask(Caskroom 에 있음)는 그대로 포함되어 upgrade 대상이 된다.
def manual_app?(token, app)
  caskroom = File.join(ENV.fetch("HOMEBREW_PREFIX", "/opt/homebrew"), "Caskroom", token)
  installed = ["/Applications", File.expand_path("~/Applications")].any? { |dir| File.exist?(File.join(dir, app)) }
  installed && !File.directory?(caskroom)
end

# 관리자 아닌 계정은 /Applications 에 쓸 수 없어(sudo 불가) 신규 .app cask 를 ~/Applications 에 설치한다.
def user_appdir?
  !File.writable?("/Applications")
end

# ── CLI 기본 도구 ─────────────────────────────────────────────────────────────
# 셸·하네스 전반의 git. PATH 에서 macOS 시스템 git 보다 앞에 온다.
brew "git"
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
# nvim 포매터(css·html·markdown). mason 에 없어 brew 로 둔다.
brew "prettier"
# mlr — nvim CSV 정렬·필터 키맵이 호출한다.
brew "miller"
# nvim-treesitter main 브랜치의 파서 빌드에 필수.
brew "tree-sitter-cli"

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

# ── AI 하네스 런타임·연동 CLI ─────────────────────────────────────────────────
# MCP 서버 npx 실행·vibe-ai-config npx skills·install.sh 의 npm 전역 패키지 단계.
brew "node"
# Serena MCP 를 uvx 로 실행.
brew "uv"
# gws — 노션 주간 일정 스킬의 Google Calendar 조회 폴백.
brew "googleworkspace-cli"
# GitLab MR 생성·배포 준비 판정 스크립트(deploy-ready.sh).
brew "glab"

# ── 업무 인프라 (두 기기 공통) ───────────────────────────────────────────────
# kubectl OIDC 로그인 플러그인(kubectl oidc-login).
brew "kubelogin"
# Java 백엔드 빌드.
brew "maven"
# Python CLI 도구를 격리 venv 로 전역 설치.
brew "pipx"
# gcloud — GCP 인증·kubectl 자격 증명.
cask "gcloud-cli"
# 로컬 컨테이너·k8s. docker·kubectl·helm CLI 를 ~/.rd/bin 으로 제공하므로 brew "docker" 는 선언하지 않는다.
cask "rancher" unless manual_app?("rancher", "Rancher Desktop.app")

# ── AI CLI ───────────────────────────────────────────────────────────────────
cask "claude-code"
# OpenAI Codex CLI. cmux 안에서는 shim 이 PATH 앞에 오므로 설치 확인은 /opt/homebrew/bin/codex --version.
cask "codex"
# Codex·Claude 사용량 표시. 인증정보는 앱/Keychain에서 관리하고 저장소에 보관하지 않는다.
cask "codexbar" unless manual_app?("codexbar", "CodexBar.app")

# ── GUI 터미널 앱 (cmux 는 ghostty config 의 테마·폰트를 상속) ────────────────
cask "ghostty" unless manual_app?("ghostty", "Ghostty.app")
cask "cmux" unless manual_app?("cmux", "cmux.app")
# ghostty/config 의 font-family. 글꼴은 ~/Library/Fonts 에 놓여 .app adopt(sudo) 문제가 없어 가드 불필요.
cask "font-d2coding"

# ── 메뉴 막대 관리 (macOS 26 이상, 프로필 적용은 수동 — thaw/README.md) ──────
unless manual_app?("thaw", "Thaw.app")
  if user_appdir?
    cask "thaw", args: { appdir: "~/Applications" }
  else
    cask "thaw"
  end
end

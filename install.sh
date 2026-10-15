#!/bin/bash
# install.sh — Vibe Dotfiles 원클릭 설치 스크립트
#
# 사용법:
#   git clone <repo-url> ~/Project/vibe-dotfiles
#   cd ~/Project/vibe-dotfiles && ./install.sh

set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 심볼릭 링크 실경로 해석
real_path() {
  if command -v realpath &>/dev/null; then
    realpath "$1" 2>/dev/null || echo "$1"
  else
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"
  fi
}

# safe_link <target> <source>
# 타겟이 이미 source를 가리키는 링크면 스킵,
# 다른 링크/실파일/실폴더이면 타임스탬프 백업 후 링크 교체.
safe_link() {
  local target="$1"
  local source="$2"
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"

  if [[ ! -e "$source" ]]; then
    warn "소스 없음: $source — 링크 건너뜀"
    return
  fi

  if [[ -L "$target" ]]; then
    local resolved
    resolved=$(real_path "$target")
    if [[ "$resolved" == "$(real_path "$source")" ]]; then
      success "$target — 이미 연결됨"
      return
    fi
    mv "$target" "${target}.bak.${ts}"
    warn "기존 링크 백업 → ${target}.bak.${ts}"
  elif [[ -e "$target" ]]; then
    mv "$target" "${target}.bak.${ts}"
    warn "기존 파일/폴더 백업 → ${target}.bak.${ts}"
  fi

  ln -s "$source" "$target"
  success "$target → $source"
}

echo ""
echo "============================================================"
echo "  🚀 Vibe Dotfiles 설치 시작"
echo "  경로: $DOTFILES"
echo "============================================================"
echo ""

# ── 0. Homebrew ───────────────────────────────────────────────────────────────
info "Homebrew 확인 중..."
if ! command -v brew &>/dev/null; then
  info "Homebrew 설치 중..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ $(uname -m) == "arm64" ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  success "Homebrew 설치 완료"
else
  success "Homebrew 이미 설치됨"
fi

# ── 1. Brewfile 패키지 (CLI·AI CLI·GUI 터미널 — 정본: Brewfile) ─────────────
# brew bundle 은 이미 설치된 항목을 건너뛰므로 재실행해도 멱등이다.
info "Brewfile 패키지 설치 중..."
brew bundle --file "$DOTFILES/Brewfile"
success "Brewfile 패키지 설치 완료"

# ── 2. Oh My Zsh ──────────────────────────────────────────────────────────────
info "Oh My Zsh 확인 중..."
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "Oh My Zsh 설치 중..."
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  success "Oh My Zsh 설치 완료"
else
  success "Oh My Zsh 이미 설치됨"
fi

# ── 3. Zinit ──────────────────────────────────────────────────────────────────
info "Zinit 확인 중..."
if [[ ! -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]]; then
  info "Zinit 설치 중..."
  mkdir -p "$HOME/.local/share/zinit"
  git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"
  success "Zinit 설치 완료"
else
  success "Zinit 이미 설치됨"
fi

# ── 4. GUI 터미널 앱 설정 (Ghostty · cmux — 설치는 1단계 Brewfile) ──────────
info "GUI 터미널 앱 설정 중..."
if command -v cmux &>/dev/null; then
  success "cmux CLI 사용 가능"
else
  warn "cmux CLI 미노출 — cmux 앱 Settings 에서 CLI(\"cmux\") 설치 필요"
fi

# ghostty config 적용 (cmux 가 ~/.config/ghostty/config 의 테마·폰트를 자동 상속)
mkdir -p "$HOME/.config/ghostty"
safe_link "$HOME/.config/ghostty/config" "$DOTFILES/ghostty/config"

# cmux config 적용 (cmux 자체 동작 설정 — 테마/폰트/색상은 ghostty config 에서 상속)
mkdir -p "$HOME/.config/cmux"
safe_link "$HOME/.config/cmux/cmux.json" "$DOTFILES/cmux/cmux.json"

success "GUI 터미널 앱 설정 완료"

# tmux ↔ cmux 소켓 제어 안내 (socketControlMode=full 활성 조건 — SoC: 안내만)
echo ""
info "tmux 안에서 cmux CLI 소켓 명령(new-split·send·read-screen 등)을 쓰려면:"
echo "    socketControlMode=full(cmux.json 에 이미 적용) 상태로 cmux 앱을 1회 재시작하세요."
echo "  (재시작 전에는 tmux 내부에서 cmux 소켓 명령이 broken pipe 로 실패합니다.)"

# AI 툴 알림 연동 안내 (SoC: 본 레포는 실행하지 않음 — 선택적 수동 단계)
echo ""
info "AI 툴(Claude Code 등) 알림을 cmux 로 받으려면 아래를 1회 실행하세요:"
echo "    cmux hooks setup"
echo "  (이 명령은 Claude Code 설정을 수정합니다 — 터미널 인프라 범위 밖이라 자동 실행하지 않습니다.)"
echo ""

# ── 5. Tmux TPM ───────────────────────────────────────────────────────────────
info "Tmux TPM 확인 중..."
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
  info "TPM 설치 중..."
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  success "TPM 설치 완료"
else
  success "TPM 이미 설치됨"
fi

# ── 6. Tmux 심볼릭 링크 ──────────────────────────────────────────────────────
info "Tmux 설정 적용 중..."
safe_link "$HOME/.tmux.conf" "$DOTFILES/tmux/.tmux.conf"

# ── 7. Vibe Tools ────────────────────────────────────────────────────────────
info "Vibe Tools 적용 중..."
mkdir -p "$HOME/.config"
safe_link "$HOME/.config/vibe-tools" "$DOTFILES/vibe-tools"

# 스크립트 실행 권한 보장
chmod +x "$DOTFILES/vibe-tools/"*.sh

# ── 8. Neovim (NvChad) Lua 설정 ──────────────────────────────────────────────
info "Neovim lua 설정 적용 중..."
mkdir -p "$HOME/.config/nvim"
safe_link "$HOME/.config/nvim/lua" "$DOTFILES/nvim/lua"

# ── 9. Claude Code AI 자산 안내 (선택적 통합 — 별도 레포 관리) ──────────────
# SoC: 본 레포는 시스템·터미널 인프라만 책임. AI 하네스(CLAUDE-*.md, hooks/,
#      settings.work.json) 가 필요하면 외부 레포를 별도 설치 (선택적).
#
# 환경변수 VIBE_AI_CONFIG_PATH 로 위치 명시 가능 (구 VIBE_CLAUDE_PLUGIN_PATH 도 하위호환). 미설정 시 안내만 출력.
VIBE_AI_CONFIG_DIR="${VIBE_AI_CONFIG_PATH:-${VIBE_CLAUDE_PLUGIN_PATH:-$HOME/Project/vibe-ai-config}}"
info "Claude Code AI 하네스 자산은 외부 레포에서 별도 관리됩니다 (선택적 통합)."
echo ""
if [[ -x "${VIBE_AI_CONFIG_DIR}/install.sh" ]]; then
  echo "  감지됨: ${VIBE_AI_CONFIG_DIR}/install.sh"
  echo "  AI 룰·훅·settings.json·Claude 플러그인·MCP·스킬 설치/갱신 (work|personal 중 택1):"
  echo "    \"${VIBE_AI_CONFIG_DIR}/install.sh\" work|personal"
else
  echo "  Claude 플러그인·MCP·스킬은 vibe-ai-config install.sh work|personal 로 설치합니다."
  echo "  AI 하네스가 필요하면 별도 레포를 설치 후:"
  echo "    VIBE_AI_CONFIG_PATH=<레포경로> ./install.sh  (재실행)"
  echo "  (본 레포는 AI 하네스 없이도 정상 동작합니다.)"
fi
echo ""
echo "  자세한 SoC 분담:"
echo "    - vibe-dotfiles      : 시스템·터미널 인프라 (tmux/nvim/zsh, vibe-tools/claude-*.sh)"
echo "    - 외부 AI 하네스 레포 : CLAUDE-*.md, hooks/, settings.work.json, plugins/"

# ── 10. Claude 사용자 스킬 (마켓플레이스로 이관됨) ──────────────────────────
# 스킬은 vibe-ai-config 레포에서 관리하며 그쪽 install.sh 가 설치합니다.

# ── 11. Zsh aliases 자동 등록 ────────────────────────────────────────────────
info "Zsh aliases 등록 확인 중..."
ALIASES_SOURCE="source \"$DOTFILES/zsh/aliases.zsh\""
if ! grep -qF "$ALIASES_SOURCE" "$HOME/.zshrc" 2>/dev/null; then
  echo "" >> "$HOME/.zshrc"
  echo "# Vibe Dotfiles aliases" >> "$HOME/.zshrc"
  echo "$ALIASES_SOURCE" >> "$HOME/.zshrc"
  success "~/.zshrc 에 aliases.zsh source 라인 추가 완료"
else
  success "~/.zshrc 에 이미 aliases.zsh 가 등록되어 있습니다."
fi

# 공용 환경변수는 비대화형 셸에도 적용되도록 ~/.zshenv 에 등록한다.
ENV_SOURCE="source \"$DOTFILES/zsh/env.zsh\""
if ! grep -qF "$ENV_SOURCE" "$HOME/.zshenv" 2>/dev/null; then
  echo "" >> "$HOME/.zshenv"
  echo "# Vibe Dotfiles env" >> "$HOME/.zshenv"
  echo "$ENV_SOURCE" >> "$HOME/.zshenv"
  success "~/.zshenv 에 env.zsh source 라인 추가 완료"
else
  success "~/.zshenv 에 이미 env.zsh 가 등록되어 있습니다."
fi

# ── 12. Git Delta 설정 ───────────────────────────────────────────────────────
info "Git Delta 설정 중..."
current_pager=$(git config --global --get core.pager 2>/dev/null || echo "")
if [[ -z "$current_pager" ]]; then
  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.side-by-side true
  git config --global delta.line-numbers true
  success "Git Delta 설정 완료"
elif [[ "$current_pager" == "delta" ]]; then
  success "Git Delta 이미 설정됨 — 유지"
else
  warn "기존 git core.pager='$current_pager' 감지 — 덮어쓰지 않고 Delta 설정 건너뜀 (원하면 수동 적용)"
fi

# ── 13. Claude Code 플러그인 (vibe-ai-config 로 이관됨) ─────────────────────
# 플러그인 설치는 vibe-ai-config install.sh 담당 (마켓플레이스 등록·개인/업무 플러그인 목록 포함).

# ── 14. Glow 설정 심볼릭 링크 ────────────────────────────────────────────────
info "Glow 설정 적용 중..."
mkdir -p "$HOME/Library/Preferences/glow"
safe_link "$HOME/Library/Preferences/glow/glow.yml"                  "$DOTFILES/glow/glow.yml"
safe_link "$HOME/Library/Preferences/glow/catppuccin-macchiato.json" "$DOTFILES/glow/catppuccin-macchiato.json"

# ── 15. Tmux 설정 리로드 ─────────────────────────────────────────────────────
if command -v tmux &>/dev/null && tmux info &>/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf" 2>/dev/null && \
    success "tmux 설정 즉시 리로드 완료" || \
    warn "tmux 리로드 실패 (tmux 세션 없음 — 다음 실행 시 자동 적용)"
fi

# ── 완료 ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  ✅ Vibe Coding 환경 세팅이 완료되었습니다!"
echo "============================================================"
echo ""
echo "  다음 명령어로 alias를 즉시 적용하세요:"
echo "    source ~/.zshrc"
echo ""
echo "  Neovim 첫 실행 전 NvChad가 설치되어 있어야 합니다:"
echo "    git clone https://github.com/NvChad/starter ~/.config/nvim && nvim"
echo ""

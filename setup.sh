#!/bin/bash
# setup.sh — Vibe Dotfiles 원클릭 설치 스크립트
#
# 사용법:
#   git clone <repo-url> ~/Project/vibe-dotfiles
#   cd ~/Project/vibe-dotfiles && ./setup.sh

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

# ── 1. CLI 도구 ───────────────────────────────────────────────────────────────
info "CLI 도구 설치 중..."
FORMULAS=(
  lsd bat fzf fd ripgrep git-delta
  btop dust duf fastfetch
  neovim tmux tmuxinator
  zoxide lazygit navi starship mise
  yazi gh jq thefuck glow
)
for formula in "${FORMULAS[@]}"; do
  if ! brew list --formula "$formula" &>/dev/null 2>&1; then
    info "  설치 중: $formula"
    brew install "$formula"
  else
    info "  이미 설치됨: $formula"
  fi
done
success "CLI 도구 설치 완료"

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

# ── 4. AI 도구 ────────────────────────────────────────────────────────────────
info "Claude Code 확인 중..."
if ! command -v claude &>/dev/null; then
  info "Claude Code 설치 중..."
  brew install claude-code
  success "Claude Code 설치 완료"
else
  success "Claude Code 이미 설치됨 ($(claude --version 2>/dev/null))"
fi

info "Gemini CLI 확인 중..."
if ! command -v gemini &>/dev/null; then
  info "Gemini CLI 설치 중..."
  brew install gemini-cli
  success "Gemini CLI 설치 완료"
else
  success "Gemini CLI 이미 설치됨"
fi

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

# ── 9. Claude Code AI 자산 안내 (vibe-claude-plugin 별도 관리) ──────────────
# SoC: AI 하네스 자산(CLAUDE-*.md, hooks/, settings.work.json)은
#      vibe-claude-plugin 레포에서 관리됩니다 (단계 2 마이그레이션 2026-05-10 완료).
info "Claude Code AI 하네스 자산은 vibe-claude-plugin 레포에서 별도 관리됩니다."
echo ""
echo "  AI 룰·훅·settings.json 설치/갱신:"
echo "    cd ~/Project/vibe-claude-plugin && ./install.sh"
echo ""
echo "  자세한 SoC 분담:"
echo "    - vibe-dotfiles      : 시스템·터미널 인프라 (tmux/nvim/zsh, vibe-tools/claude-*.sh)"
echo "    - vibe-claude-plugin : AI 하네스 (CLAUDE-*.md, hooks/, settings.work.json, plugins/)"

# ── 10. Claude 사용자 스킬 (마켓플레이스로 이관됨) ──────────────────────────
# 스킬은 vibe-claude-plugin 마켓플레이스 레포지토리에서 플러그인 단위로 관리합니다.
# 13단계에서 claude plugin install 로 자동 설치됩니다.

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

# ── 13. Claude Code 플러그인 ────────────────────────────────────────────────
info "Claude Code 플러그인 설치 중..."
if ! command -v claude &>/dev/null; then
  warn "Claude Code 미설치 — 플러그인 설치 건너뜀"
else
  # 마켓플레이스 등록 (이름|URL) — 공용 + 환경별
  MARKETPLACES=(
    "omc|https://github.com/Yeachan-Heo/oh-my-claudecode.git"
    "swkim0128|https://github.com/swkim0128/vibe-claude-plugin.git"
  )
  # 업무 환경: 사내 cc-claude 마켓플레이스 추가 (외부망에선 접근 불가)
  if [[ "$ENV_TYPE" == "w" ]]; then
    MARKETPLACES+=("cc-claude|https://labs.cowave.kr/consumer-commerce-dev/cc-claude/marketplace.git")
  fi
  for entry in "${MARKETPLACES[@]}"; do
    mp_name="${entry%%|*}"
    mp_url="${entry##*|}"
    if ! claude plugin marketplace list 2>/dev/null | grep -q "$mp_name"; then
      claude plugin marketplace add "$mp_url" 2>/dev/null && \
        success "$mp_name 마켓플레이스 등록 완료" || warn "$mp_name 마켓플레이스 등록 실패"
    else
      success "$mp_name 마켓플레이스 이미 등록됨"
    fi
  done

  # 공용 플러그인 (개인·업무 공통, 2026-05-20 실 설치 상태 반영)
  BASE_PLUGINS=(
    # claude-plugins-official
    "superpowers@claude-plugins-official"
    "github@claude-plugins-official"
    "context7@claude-plugins-official"
    "php-lsp@claude-plugins-official"
    # omc (오케스트레이션 프레임워크)
    "oh-my-claudecode@omc"
    # swkim0128 마켓플레이스 (도메인 스킬 + 워크플로우 도구)
    "analyze@swkim0128"
    "git-suite@swkim0128"
    "google-workspace@swkim0128"
    "harness@swkim0128"
    "notify@swkim0128"
    "notion-suite@swkim0128"
    "nworks@swkim0128"
    "task-mgmt@swkim0128"
    "test@swkim0128"
    "tmux-suite@swkim0128"
    "vibe-admin@swkim0128"
  )
  # 개인 환경 전용 (현재 없음 — BASE가 개인 환경 커버)
  PERSONAL_PLUGINS=()
  # 업무 환경 전용 플러그인 (사내 cc-claude 마켓플레이스)
  # NOTE: analyze/harness/test/nworks는 swkim0128 BASE로 이전됐으므로 여기서 제거 (충돌 방지)
  WORK_PLUGINS=(
    "backend@cc-claude"
    "beginner@cc-claude"
    "cc-utils@cc-claude"
    "context-architect@cc-claude"
    "enterprise-base@cc-claude"
    "plane-mcp@cc-claude"
    "workflow@cc-claude"
    "legacy@cc-claude"
    "prompt-search@cc-claude"
  )

  # 환경에 맞는 플러그인 조합
  CLAUDE_PLUGINS=("${BASE_PLUGINS[@]}")
  if [[ "$ENV_TYPE" == "w" ]]; then
    CLAUDE_PLUGINS+=("${WORK_PLUGINS[@]}")
  else
    CLAUDE_PLUGINS+=("${PERSONAL_PLUGINS[@]}")
  fi

  for plugin in "${CLAUDE_PLUGINS[@]}"; do
    claude plugin install "$plugin" --scope user 2>/dev/null && \
      success "$plugin 설치 완료" || info "$plugin 이미 설치됨"
  done
fi

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

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
  yazi gh jq thefuck
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
  npm install -g @anthropic-ai/claude-code
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
ln -sf "$DOTFILES/tmux/.tmux.conf" "$HOME/.tmux.conf"
success "~/.tmux.conf → $DOTFILES/tmux/.tmux.conf"

# ── 7. Vibe Tools ────────────────────────────────────────────────────────────
info "Vibe Tools 적용 중..."
mkdir -p "$HOME/.config"
# 기존 디렉토리가 실제 폴더이면 제거 후 심볼릭 링크로 교체
if [[ -d "$HOME/.config/vibe-tools" && ! -L "$HOME/.config/vibe-tools" ]]; then
  warn "기존 ~/.config/vibe-tools/ 디렉토리를 ~/.config/vibe-tools.bak 으로 백업합니다."
  mv "$HOME/.config/vibe-tools" "$HOME/.config/vibe-tools.bak"
fi
ln -sf "$DOTFILES/vibe-tools" "$HOME/.config/vibe-tools"
success "~/.config/vibe-tools → $DOTFILES/vibe-tools"

# 스크립트 실행 권한 보장
chmod +x "$DOTFILES/vibe-tools/"*.sh
chmod +x "$DOTFILES/vibe-tools/claude-config/hooks/mac-notify.sh"
chmod +x "$DOTFILES/vibe-tools/claude-plugin/hooks/mac-notify.sh"

# ── 8. Neovim (NvChad) Lua 설정 ──────────────────────────────────────────────
info "Neovim lua 설정 적용 중..."
mkdir -p "$HOME/.config/nvim"
if [[ -d "$HOME/.config/nvim/lua" && ! -L "$HOME/.config/nvim/lua" ]]; then
  warn "기존 ~/.config/nvim/lua/ 디렉토리를 백업합니다."
  mv "$HOME/.config/nvim/lua" "$HOME/.config/nvim/lua.bak"
fi
ln -sf "$DOTFILES/nvim/lua" "$HOME/.config/nvim/lua"
success "~/.config/nvim/lua → $DOTFILES/nvim/lua"

# ── 9. Claude Code 설정 심볼릭 링크 ─────────────────────────────────────────
info "Claude Code 설정 심볼릭 링크 적용 중..."
mkdir -p "$HOME/.claude/plugins/cache/personal"
ln -sf "$DOTFILES/vibe-tools/claude-config/settings.json" "$HOME/.claude/settings.json"
ln -sf "$DOTFILES/vibe-tools/claude-config/hooks"         "$HOME/.claude/hooks"
ln -sf "$DOTFILES/vibe-tools/claude-plugin"               "$HOME/.claude/plugins/cache/personal/vibe-config"
success "Claude Code 설정 및 플러그인 연결 완료"

# ── 10. Claude 사용자 스킬 복원 ──────────────────────────────────────────────
info "Claude 사용자 스킬 복원 중..."
mkdir -p "$HOME/.claude/skills"
rsync -a --delete "$DOTFILES/claude-skills/" "$HOME/.claude/skills/"
success "Claude 사용자 스킬 복원 완료"

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
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.side-by-side true
git config --global delta.line-numbers true
success "Git Delta 설정 완료"

# ── 13. Vibe Claude Plugin ───────────────────────────────────────────────────
PLUGIN_DIR="$HOME/Project/vibe-claude-plugin"
PLUGIN_REPO="[YOUR_PLUGIN_REPO_URL]"

info "Vibe Claude Plugin 확인 중..."
if [[ ! -d "$PLUGIN_DIR" ]]; then
  info "플러그인 레포지토리 클론 중..."
  git clone "$PLUGIN_REPO" "$PLUGIN_DIR"
  success "vibe-claude-plugin 클론 완료"
else
  success "vibe-claude-plugin 이미 존재함 — 건너뜀"
fi

if [[ -f "$PLUGIN_DIR/install.sh" ]]; then
  info "플러그인 설치 중..."
  bash "$PLUGIN_DIR/install.sh"
  success "vibe-claude-plugin 설치 완료"
else
  warn "install.sh 없음 — 플러그인 설치 건너뜀"
fi

# ── 14. Glow 설정 심볼릭 링크 ────────────────────────────────────────────────
info "Glow 설정 적용 중..."
mkdir -p "$HOME/Library/Preferences/glow"
ln -sf "$DOTFILES/glow/glow.yml"                    "$HOME/Library/Preferences/glow/glow.yml"
ln -sf "$DOTFILES/glow/catppuccin-macchiato.json"   "$HOME/Library/Preferences/glow/catppuccin-macchiato.json"
success "Glow 설정 연결 완료"

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

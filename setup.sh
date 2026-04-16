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

# ── 1. Tmux ──────────────────────────────────────────────────────────────────
info "Tmux 설정 적용 중..."
ln -sf "$DOTFILES/tmux/.tmux.conf" "$HOME/.tmux.conf"
success "~/.tmux.conf → $DOTFILES/tmux/.tmux.conf"

# ── 2. Vibe Tools ────────────────────────────────────────────────────────────
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

# ── 3. Neovim (NvChad) Lua 설정 ──────────────────────────────────────────────
info "Neovim lua 설정 적용 중..."
mkdir -p "$HOME/.config/nvim"
if [[ -d "$HOME/.config/nvim/lua" && ! -L "$HOME/.config/nvim/lua" ]]; then
  warn "기존 ~/.config/nvim/lua/ 디렉토리를 백업합니다."
  mv "$HOME/.config/nvim/lua" "$HOME/.config/nvim/lua.bak"
fi
ln -sf "$DOTFILES/nvim/lua" "$HOME/.config/nvim/lua"
success "~/.config/nvim/lua → $DOTFILES/nvim/lua"

# ── 4. Claude Code 설정 심볼릭 링크 ─────────────────────────────────────────
info "Claude Code 설정 심볼릭 링크 적용 중..."
mkdir -p "$HOME/.claude/plugins/cache/personal"
ln -sf "$DOTFILES/vibe-tools/claude-config/settings.json" "$HOME/.claude/settings.json"
ln -sf "$DOTFILES/vibe-tools/claude-config/hooks"         "$HOME/.claude/hooks"
ln -sf "$DOTFILES/vibe-tools/claude-plugin"               "$HOME/.claude/plugins/cache/personal/vibe-config"
success "Claude Code 설정 및 플러그인 연결 완료"

# ── 5. Zsh aliases 자동 등록 ─────────────────────────────────────────────────
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

# ── 6. Tmux 설정 리로드 ──────────────────────────────────────────────────────
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

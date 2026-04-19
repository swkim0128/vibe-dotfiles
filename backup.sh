#!/bin/bash
# backup.sh — 현재 시스템 설정을 vibe-dotfiles 프로젝트로 복사
#
# 사용법:
#   ./backup.sh
#
# 이미 프로젝트 심볼릭 링크로 연결된 항목은 자동으로 건너뜁니다.

set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC} $1"; }

# 심볼릭 링크를 따라 실제 경로를 반환
real_path() {
  if command -v realpath &>/dev/null; then
    realpath "$1" 2>/dev/null || echo "$1"
  else
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"
  fi
}

# 파일 백업: 이미 프로젝트 내 심볼릭 링크이면 건너뜀
backup_file() {
  local src="$1"
  local dst="$2"

  if [[ ! -e "$src" ]]; then
    warn "$src — 없음"
    return
  fi

  if [[ -L "$src" ]]; then
    local resolved
    resolved=$(real_path "$src")
    if [[ "$resolved" == "$DOTFILES"* ]]; then
      warn "$src — 이미 프로젝트 링크"
      return
    fi
  fi

  cp -f "$src" "$dst"
  success "$src → $dst"
}

# 디렉토리 백업: 이미 프로젝트 내 심볼릭 링크이면 건너뜀
backup_dir() {
  local src="$1"
  local dst="$2"

  if [[ ! -e "$src" ]]; then
    warn "$src — 없음"
    return
  fi

  if [[ -L "$src" ]]; then
    local resolved
    resolved=$(real_path "$src")
    if [[ "$resolved" == "$DOTFILES"* ]]; then
      warn "$src — 이미 프로젝트 링크"
      return
    fi
  fi

  mkdir -p "$dst"
  rsync -a --delete "${src%/}/" "$dst/"
  success "$src/ → $dst/"
}

echo ""
echo "============================================================"
echo "  📦 Vibe Dotfiles 백업 시작"
echo "  경로: $DOTFILES"
echo "============================================================"
echo ""

# ── 1. Tmux ──────────────────────────────────────────────────────────────────
info "Tmux 설정 백업 중..."
backup_file "$HOME/.tmux.conf" "$DOTFILES/tmux/.tmux.conf"

# ── 2. Neovim ────────────────────────────────────────────────────────────────
info "Neovim lua 설정 백업 중..."
backup_dir "$HOME/.config/nvim/lua" "$DOTFILES/nvim/lua"

# ── 3. Claude Code settings.json ─────────────────────────────────────────────
info "Claude Code settings.json 백업 중..."
backup_file "$HOME/.claude/settings.json" "$DOTFILES/vibe-tools/claude-config/settings.json"

# ── 4. Claude Code hooks ──────────────────────────────────────────────────────
info "Claude Code hooks 백업 중..."
backup_dir "$HOME/.claude/hooks" "$DOTFILES/vibe-tools/claude-config/hooks"

# ── 5. Claude 개인 플러그인 (vibe-config) ────────────────────────────────────
info "Claude 개인 플러그인 백업 중..."
backup_dir "$HOME/.claude/plugins/cache/personal/vibe-config" "$DOTFILES/vibe-tools/claude-plugin"

# ── 6. Vibe Tools ────────────────────────────────────────────────────────────
info "Vibe Tools 백업 중..."
backup_dir "$HOME/.config/vibe-tools" "$DOTFILES/vibe-tools"

# ── 완료 ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  ✅ 백업 완료!"
echo "============================================================"
echo ""
echo "  변경사항 확인:"
echo "    git diff --stat"
echo ""
echo "  커밋:"
echo "    git add . && git commit -m \"backup: \$(date +%Y-%m-%d)\""
echo ""

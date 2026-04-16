# ~/.config/vibe-dotfiles/zsh/aliases.zsh
# ~/.zshrc 에서 다음 줄로 불러오세요:
#   source ~/Project/vibe-dotfiles/zsh/aliases.zsh

# ── 에디터 ────────────────────────────────────────────
alias vim="nvim"
alias vi="nvim"
export EDITOR="nvim"

# ── Git TUI ───────────────────────────────────────────
alias lg="lazygit"

# ── Vibe Coding ───────────────────────────────────────
alias vhelp="nvim -R ~/.config/vibe-tools/cheatsheet.md"

# ── Ctrl+F: 커스텀 명령어 팝업 ────────────────────────
bindkey -s '^f' '~/.config/vibe-tools/my-tools.sh\n'

# ── fzf 기반 도구 런처 ────────────────────────────────
function tools() {
  local cmds=(
    "btop:🖥️  시스템 모니터링"
    "lazygit:📦 Git UI"
    "duf:💾 디스크 사용량"
    "dust:📁 폴더 크기 분석"
    "fastfetch:ℹ️  시스템 정보"
  )
  local selected=$(printf '%s\n' "${cmds[@]}" | fzf --delimiter=: --with-nth=2 \
    --height=40% --reverse --border --prompt="도구 선택: ")
  local cmd="${selected%%:*}"
  [[ -n "$cmd" ]] && eval "$cmd"
}

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
alias vhelp='~/.config/vibe-tools/vhelp.sh'
alias vibe="~/.config/vibe-tools/vibe.sh"

# ── Ctrl+F: 커스텀 명령어 팝업 ────────────────────────
# tmux 안: my-tools.sh 가 직접 send-keys 로 입력
# tmux 밖: 위젯이 stdout 을 BUFFER 에 채워 prompt 에 반영, placeholder 없으면 즉시 실행
vibe-tools-widget() {
  local cmd
  cmd=$(~/.config/vibe-tools/my-tools.sh)
  zle reset-prompt
  if [[ -n "$cmd" ]]; then
    BUFFER="$cmd"
    CURSOR=${#BUFFER}
    if [[ "$cmd" != *"<"*">"* ]]; then
      zle accept-line
    fi
  fi
}
zle -N vibe-tools-widget
bindkey '^f' vibe-tools-widget

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

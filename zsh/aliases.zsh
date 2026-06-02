# ~/.config/vibe-dotfiles/zsh/aliases.zsh
# ~/.zshrc 에서 다음 줄로 불러오세요:
#   source ~/Project/vibe-dotfiles/zsh/aliases.zsh

# ── 에디터 ────────────────────────────────────────────
alias vim="nvim"
alias vi="nvim"
export EDITOR="nvim"

# ── Git TUI ───────────────────────────────────────────
alias lg="lazygit"

# ── Git 브랜치 fzf ────────────────────────────────────
unalias gco 2>/dev/null
function gco() {
  local branch
  branch=$(git branch --sort=-committerdate -a \
    | sed 's/^[* ]*//' \
    | sed 's|remotes/origin/||' \
    | grep -v '^HEAD' \
    | awk '!seen[$0]++' \
    | fzf --height=50% --reverse --border \
          --prompt="브랜치 전환: " \
          --preview='git log --oneline --color=always -10 {} 2>/dev/null')
  [[ -n "$branch" ]] && git checkout "$branch"
}

unalias gbd 2>/dev/null
function gbd() {
  local branches
  branches=$(git branch | sed 's/^[* ]*//' \
    | fzf --multi --height=50% --reverse --border \
          --prompt="삭제할 브랜치 (Tab: 다중선택): " \
          --preview='git log --oneline --color=always -10 {}')
  [[ -n "$branches" ]] && git branch -d ${(f)branches}
}

# ── Vibe Coding ───────────────────────────────────────
# vibe/vhelp/claude-{delegate,callback,switch} alias 와 Ctrl+F 위젯은
# vibe-claude-plugin/plugins/tmux-suite/install.sh 가 등록한다.
# (해당 install.sh 가 ~/.zshrc 에 source 라인을 멱등 추가)

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

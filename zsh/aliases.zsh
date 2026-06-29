# ~/.config/vibe-dotfiles/zsh/aliases.zsh
# ~/.zshrc 에서 다음 줄로 불러오세요:
#   source ~/Project/vibe-dotfiles/zsh/aliases.zsh

# ── 에디터 ────────────────────────────────────────────
alias vim="nvim"
alias vi="nvim"
export EDITOR="nvim"

# ── PARA 환경변수 (vibe-ai-config CLAUDE-delegation.md SSoT) ─────────
# 회사컴/개인컴 양쪽에서 git pull 로 자동 동기화. 머신별 차이는 PERSONAL_PARA_ROOT 만.
export KB_ROOT="${KB_ROOT:-$HOME/Project/vibe-dotfiles/docs/knowledge-base}"
export PARA_PROJECTS_ROOT="${PARA_PROJECTS_ROOT:-$HOME/Project/para/01.Projects}"
export PLUGIN_CONFIG_ROOT="${PLUGIN_CONFIG_ROOT:-$HOME/Project/vibe-ai-config/claude-config}"
# PERSONAL_PARA_ROOT — 개인용 LLM 지식 위키 (머신별 자율 export, 기본값 없음)
#   개인컴 예시: export PERSONAL_PARA_ROOT="$HOME/Project/personal-para"
#   회사컴: 미설정 유지 — 이중 볼트 가드레일 자동 활성화

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
# vibe-ai-config/claude-config/plugins/tmux-suite/install.sh 가 등록한다.
# (해당 install.sh 가 ~/.zshrc 에 source 라인을 멱등 추가)

# ── cmux per-project 워크스페이스 런처 ────────────────
cmux-proj() { bash "$HOME/.config/vibe-tools/cmux-proj.sh" "$@"; }
# cmux 듀얼-프로젝트 워크스페이스 런처
cmux-dual() { bash "$HOME/.config/vibe-tools/cmux-proj-dual.sh" "$@"; }
# cmux 수동처리 스크립트 작업 런처 (서버 실행용)
cmux-ops() { bash "$HOME/.config/vibe-tools/cmux-proj-ops.sh" "$@"; }
# cmux diff 리뷰 래퍼 (ws/surface 자동 해석)
cmux-review() { bash "$HOME/.config/vibe-tools/cmux-proj-review.sh" "$@"; }
# cmux 워크스페이스 닫기 (tmux 세션 유지 — cmux-proj 로 설정 그대로 재오픈)
cmux-close() { bash "$HOME/.config/vibe-tools/cmux-proj-close.sh" "$@"; }

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

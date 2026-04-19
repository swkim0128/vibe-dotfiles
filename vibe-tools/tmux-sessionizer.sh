#!/bin/bash

PATHS_FILE="$HOME/.config/vibe-tools/sessionizer-paths.txt"

# ---------------------------------------------------------
# [1] 경로 목록 파일 존재 여부 확인
# ---------------------------------------------------------
if [ ! -f "$PATHS_FILE" ]; then
    echo -e "\033[0;31m[오류]\033[0m 경로 목록 파일이 없습니다: $PATHS_FILE"
    exit 1
fi

# ---------------------------------------------------------
# [2] 파일에서 경로 읽기 (주석/빈 줄 제외)
# ---------------------------------------------------------
mapfile -t paths < <(grep -v '^\s*#' "$PATHS_FILE" | grep -v '^\s*$' | sed "s|~|$HOME|g")

# ---------------------------------------------------------
# [3] fzf로 프로젝트 폴더 선택
# ---------------------------------------------------------
selected=$(find "${paths[@]}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
  | fzf --prompt="📂 프로젝트 선택 > " --height=100% --layout=reverse --border=rounded)

if [[ -z $selected ]]; then
    exit 0
fi

base_name=$(basename "$selected" | tr . _)

# ---------------------------------------------------------
# [4] 동일 프로젝트 내 여러 작업 세션 분기
# ---------------------------------------------------------
existing_sessions=$(tmux list-sessions -F "#S" | grep "^${base_name}" | tr '\n' ' ')

if [[ -n $existing_sessions ]]; then
    target=$(echo -e "🆕 [New Task Session]\n${existing_sessions// /\\n}" | grep -v '^$' \
      | fzf --prompt="🎯 접속할 세션 선택 (또는 새 작업 생성) > " --height=40% --layout=reverse --border=rounded)

    if [[ -z $target ]]; then exit 0; fi

    if [[ "$target" == "🆕 [New Task Session]" ]]; then
        task_name=$(tmux command-prompt -p "작업 명칭을 입력하세요 (예: fix, feature, refactor):" "run-shell 'echo %%'")
        if [[ -n $task_name ]]; then
            session_name="${base_name}:${task_name}"
        else
            session_name="${base_name}_$(date +%H%M%S)"
        fi
    else
        session_name="$target"
    fi
else
    session_name="$base_name"
fi

# ---------------------------------------------------------
# [5] 세션 생성 (nvim 70% + claude 30%) 및 전환
# ---------------------------------------------------------
if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" -c "$selected"
    tmux send-keys -t "$session_name" "nvim ." C-m
    tmux split-window -h -p 30 -t "$session_name" -c "$selected"
    tmux send-keys -t "$session_name" "claude" C-m
    tmux select-pane -t 1
fi

if [[ -z $TMUX ]]; then
    tmux attach-session -t "$session_name"
else
    tmux switch-client -t "$session_name"
fi

#!/bin/bash

PATHS_FILE="$HOME/.config/vibe-tools/sessionizer-paths.txt"

# ---------------------------------------------------------
# [0] CLI 플래그 파싱 (--project, --task)
# ---------------------------------------------------------
cli_project=""
cli_task=""
cli_mode=0

print_usage() {
    cat <<EOF
사용법:
  $(basename "$0")                                      # 인터랙티브 모드 (fzf)
  $(basename "$0") --project <경로> [--task <이슈ID>]   # CLI 비인터랙티브 모드

옵션:
  --project  프로젝트 경로 (예: ~/Project/danawa/ashop)
  --task     이슈 ID 또는 작업명 (예: DWDEV-4010) — 지정 시 해당 브랜치 체크아웃
  -h,--help  도움말 표시
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            if [[ -z "${2:-}" ]]; then
                echo -e "\033[0;31m[오류]\033[0m --project 는 값이 필요합니다." >&2
                exit 1
            fi
            cli_project="$2"
            cli_mode=1
            shift 2
            ;;
        --task)
            if [[ -z "${2:-}" ]]; then
                echo -e "\033[0;31m[오류]\033[0m --task 는 값이 필요합니다." >&2
                exit 1
            fi
            cli_task="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "\033[0;31m[오류]\033[0m 알 수 없는 인자: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------
# [1] 프로젝트 경로 / 작업명 결정 (CLI vs 인터랙티브)
# ---------------------------------------------------------
selected=""
base_name=""
task_name=""
session_name=""

if [[ $cli_mode -eq 1 ]]; then
    # --- CLI 비인터랙티브 모드 ---
    selected="${cli_project/#\~/$HOME}"
    if [[ ! -d "$selected" ]]; then
        echo -e "\033[0;31m[오류]\033[0m 프로젝트 경로가 존재하지 않습니다: $selected" >&2
        exit 1
    fi
    base_name=$(basename "$selected" | tr . _)
    task_name="$cli_task"
    if [[ -n "$task_name" ]]; then
        session_name="${base_name}_${task_name}"
    else
        session_name="$base_name"
    fi
else
    # --- 인터랙티브 모드 (기존 로직 유지) ---
    if [[ ! -f "$PATHS_FILE" ]]; then
        echo -e "\033[0;31m[오류]\033[0m 경로 목록 파일이 없습니다: $PATHS_FILE"
        exit 1
    fi

    paths=()
    while IFS= read -r line; do
        paths+=("$line")
    done < <(grep -v '^\s*#' "$PATHS_FILE" | grep -v '^\s*$' | sed "s|~|$HOME|g")

    selected=$(find "${paths[@]}" -mindepth 1 -maxdepth 3 -type d -not -path '*/.*' 2>/dev/null \
      | fzf --prompt="📂 프로젝트 선택 > " --height=100% --layout=reverse --border=rounded)

    if [[ -z $selected ]]; then
        exit 0
    fi

    base_name=$(basename "$selected" | tr . _)

    existing_sessions=$(tmux list-sessions -F "#S" 2>/dev/null | grep "^${base_name}" | tr '\n' ' ')

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
            task_name=""
        fi
    else
        target=$(echo -e "🚀 바로 시작 (${base_name})\n🆕 [New Task Session]" \
          | fzf --prompt="🎯 세션 생성 방식 > " --height=40% --layout=reverse --border=rounded)

        if [[ -z $target ]]; then exit 0; fi

        if [[ "$target" == "🆕 [New Task Session]" ]]; then
            task_name=$(tmux command-prompt -p "이슈 ID 또는 작업 명칭 (예: BILL-123, fix, feature):" "run-shell 'echo %%'")
            if [[ -n $task_name ]]; then
                session_name="${base_name}_${task_name}"
            else
                session_name="$base_name"
            fi
        else
            session_name="$base_name"
        fi
    fi
fi

# ---------------------------------------------------------
# [2] 세션 생성 전 Git 브랜치 체크아웃 (task_name 지정 & Git 저장소)
# ---------------------------------------------------------
checkout_branch() {
    local repo="$1"
    local branch="$2"

    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        return 0
    fi

    # 다른 세션이 남긴 잔여 index.lock 제거 (병렬 작업 시 checkout 실패 방지)
    local lock_file="$repo/.git/index.lock"
    if [[ -f "$lock_file" ]]; then
        echo -e "\033[0;33m[경고]\033[0m git index.lock 감지 — 제거 후 진행"
        rm -f "$lock_file"
    fi

    echo -e "\033[0;36m[git]\033[0m fetch origin ..."
    if ! git -C "$repo" fetch origin; then
        echo -e "\033[0;33m[경고]\033[0m origin fetch 실패 — 브랜치 체크아웃을 건너뜁니다." >&2
        return 0
    fi

    if git -C "$repo" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        echo -e "\033[0;36m[git]\033[0m 원격 브랜치 존재: $branch → 체크아웃"
        git -C "$repo" checkout "$branch" || \
            echo -e "\033[0;33m[경고]\033[0m $branch 체크아웃 실패" >&2
    else
        echo -e "\033[0;36m[git]\033[0m 원격 브랜치 없음: origin/develop 기준으로 $branch 생성"
        git -C "$repo" checkout -b "$branch" origin/develop || \
            echo -e "\033[0;33m[경고]\033[0m $branch 생성 실패 (origin/develop 미존재?)" >&2
    fi
}

# ---------------------------------------------------------
# [3] 세션 생성 및 전환
#     윈도우 1 "develop": nvim 70% | claude 30%
#     윈도우 2 (task_name 또는 "terminal"): 개발 작업용 zsh
# ---------------------------------------------------------
if ! tmux has-session -t "$session_name" 2>/dev/null; then
    if [[ -n "$task_name" ]]; then
        checkout_branch "$selected" "$task_name"
    fi

    if [[ -n "$task_name" ]]; then
        win2_name="$task_name"
    else
        win2_name="terminal"
    fi

    # 윈도우 1: develop (nvim + claude)
    tmux new-session -d -s "$session_name" -n "develop" -c "$selected"
    tmux send-keys -t "${session_name}:develop" "nvim ." C-m
    tmux split-window -h -p 30 -t "${session_name}:develop" -c "$selected"
    tmux send-keys -t "${session_name}:develop" "claude" C-m

    # 윈도우 2: 개발 작업용 터미널
    tmux new-window -t "$session_name" -n "$win2_name" -c "$selected"

    # 첫 화면은 윈도우 1(develop)로 복귀 — 활성 패널은 직전의 claude pane 유지
    tmux select-window -t "${session_name}:develop"
fi

# CLI 모드: 세션 생성만 하고 전환하지 않음
if [[ $cli_mode -eq 1 ]]; then
    echo -e "\033[0;32m[완료]\033[0m 세션 '$session_name' 생성됨"
    exit 0
fi

# 인터랙티브 모드: 기존대로 전환
if [[ -z $TMUX ]]; then
    tmux attach-session -t "$session_name"
else
    tmux switch-client -t "$session_name"
fi

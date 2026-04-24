#!/bin/bash
# claude-switch.sh — 다른 tmux 패널의 클로드를 종료하고 새 프로젝트 경로로 재시작한다.
#
# 사용법:
#   claude-switch.sh                           # 패널/경로 모두 fzf 로 선택
#   claude-switch.sh <pane-id>                 # 경로만 fzf 로 선택
#   claude-switch.sh <pane-id> <project-path>  # 완전 비인터랙티브
#
# 예시:
#   claude-switch.sh %3 ~/Project/danawa/ashop
#   claude-switch.sh worker ~/Project/vibe-dotfiles
#
# 동작:
#   1. 타깃 패널에 `/exit` 을 보내 claude 를 안전 종료 (쉘 프롬프트 복귀까지 대기)
#   2. `cd <project-path>` 전송
#   3. `claude` 재기동 — 패널 번호/레이아웃은 그대로 유지

set -euo pipefail

PATHS_FILE="$HOME/.config/vibe-tools/sessionizer-paths.txt"

die() {
    echo "❌ $1" >&2
    exit 1
}

# ────────────────────────────────────────────────────────────
# [1] 타깃 패널 해석
# ────────────────────────────────────────────────────────────
pick_target_pane() {
    # claude 실행 중인 패널만 후보로 노출
    local -a cands=()
    while IFS='|' read -r pid ptty plabel; do
        if ps -t "$ptty" 2>/dev/null | grep -iq "[c]laude"; then
            cands+=("$pid|$plabel")
        fi
    done < <(tmux list-panes -a -F '#{pane_id}|#{pane_tty}|#{session_name}:#{window_index}.#{pane_index}')

    [[ ${#cands[@]} -eq 0 ]] && die "클로드가 실행 중인 패널이 없습니다."

    if [[ ${#cands[@]} -eq 1 ]]; then
        echo "${cands[0]%%|*}"
        return
    fi

    local selected
    selected=$(printf '%s\n' "${cands[@]}" | fzf \
        --prompt="🎯 재기동할 Claude 패널 선택 > " \
        --with-nth=2 --delimiter='|' \
        --height=40% --layout=reverse --border=rounded)
    [[ -z "$selected" ]] && exit 0
    echo "${selected%%|*}"
}

TARGET="${1:-}"
PROJECT_PATH="${2:-}"

if [[ -z "$TARGET" ]]; then
    TARGET_PANE_ID=$(pick_target_pane)
elif [[ "$TARGET" =~ ^%[0-9]+$ ]]; then
    TARGET_PANE_ID="$TARGET"
    tmux list-panes -t "$TARGET_PANE_ID" >/dev/null 2>&1 \
        || die "타겟 패널 '$TARGET_PANE_ID' 이 존재하지 않습니다."
else
    TARGET_PANE_ID=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
        | awk -v t="$TARGET" '$2 == t {print $1}' | head -1)
    [[ -z "$TARGET_PANE_ID" ]] && die "타겟 패널 '$TARGET' 을 찾을 수 없습니다."
fi

# ────────────────────────────────────────────────────────────
# [2] 프로젝트 경로 해석 (인자 없으면 fzf — sessionizer 와 동일 경로 풀 사용)
# ────────────────────────────────────────────────────────────
pick_project_path() {
    [[ -f "$PATHS_FILE" ]] || die "경로 목록 파일이 없습니다: $PATHS_FILE"

    local -a paths=()
    local seen=$'\n' line key
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ -d "$line" ]] || continue
        key=$(stat -f '%d:%i' "$line" 2>/dev/null || stat -c '%d:%i' "$line" 2>/dev/null)
        [[ -z "$key" ]] && continue
        case "$seen" in
            *$'\n'"$key"$'\n'*) continue ;;
        esac
        seen="${seen}${key}"$'\n'
        paths+=("$line")
    done < <(grep -v '^\s*#' "$PATHS_FILE" | grep -v '^\s*$' | sed "s|~|$HOME|g")

    [[ ${#paths[@]} -eq 0 ]] && die "유효한 검색 경로가 없습니다: $PATHS_FILE"

    find "${paths[@]}" -mindepth 1 -maxdepth 3 -type d -not -path '*/.*' 2>/dev/null \
        | fzf --prompt="📂 새 프로젝트 경로 선택 > " \
              --height=100% --layout=reverse --border=rounded
}

if [[ -z "$PROJECT_PATH" ]]; then
    PROJECT_PATH=$(pick_project_path)
    [[ -z "$PROJECT_PATH" ]] && exit 0
fi

PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"
[[ -d "$PROJECT_PATH" ]] || die "프로젝트 경로가 존재하지 않습니다: $PROJECT_PATH"

TARGET_LABEL=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
    | awk -v id="$TARGET_PANE_ID" '$1 == id {print $2}')

# ────────────────────────────────────────────────────────────
# [3] Claude 종료 → cd → 재기동
# ────────────────────────────────────────────────────────────
current_tty=$(tmux display-message -p -t "$TARGET_PANE_ID" '#{pane_tty}')
is_claude_running=0
if ps -t "$current_tty" 2>/dev/null | grep -iq "[c]laude"; then
    is_claude_running=1
fi

if [[ $is_claude_running -eq 1 ]]; then
    # vim 모드 등 상태에 관계없이 안전하게 insert 모드로 진입 후 /exit 전송
    tmux send-keys -t "$TARGET_PANE_ID" Escape
    sleep 0.1
    tmux send-keys -t "$TARGET_PANE_ID" i
    sleep 0.1
    tmux send-keys -t "$TARGET_PANE_ID" "/exit" Enter

    # 쉘 프롬프트 복귀 대기 (최대 10초)
    for _ in $(seq 1 50); do
        if ! ps -t "$current_tty" 2>/dev/null | grep -iq "[c]laude"; then
            break
        fi
        sleep 0.2
    done

    if ps -t "$current_tty" 2>/dev/null | grep -iq "[c]laude"; then
        echo "⚠️  claude 가 10초 내에 종료되지 않았습니다. 수동 종료 후 다시 시도하세요." >&2
        exit 1
    fi
fi

# printf %q 로 공백·특수문자 안전 처리
PROJECT_PATH_ESC=$(printf '%q' "$PROJECT_PATH")
tmux send-keys -t "$TARGET_PANE_ID" "cd $PROJECT_PATH_ESC" Enter
tmux send-keys -t "$TARGET_PANE_ID" "claude" Enter

echo "✅ 전환 완료"
echo "   타겟 패널 : $TARGET_PANE_ID ($TARGET_LABEL)"
echo "   새 경로   : $PROJECT_PATH"
echo "   클로드 재기동 요청됨"

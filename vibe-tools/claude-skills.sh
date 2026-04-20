#!/bin/bash
set -u

PROMPT_DIR="$HOME/.config/vibe-tools/prompts"

# 팝업이 바로 닫히지 않도록 키 입력까지 대기하며 에러 출력
die() {
    echo ""
    echo "❌ $1"
    echo ""
    echo "아무 키나 누르면 닫힙니다..."
    read -r -n 1
    exit 1
}

# 1. tmux 서버 전체에서 claude 실행 패널 수집 (-a: 모든 세션/윈도우 대상)
declare -a CANDIDATES=()
while IFS='|' read -r pane_id pane_tty pane_target; do
    if ps -t "$pane_tty" 2>/dev/null | grep -iq "[c]laude"; then
        CANDIDATES+=("$pane_id|$pane_target")
    fi
done < <(tmux list-panes -a -F '#{pane_id}|#{pane_tty}|#{session_name}:#{window_index}.#{pane_index}')

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    die "클로드 코드가 실행 중인 패널을 찾을 수 없습니다. 다른 패널에서 'claude' 를 실행한 후 다시 시도하세요."
fi

# 2. 단일 매칭은 자동 선택, 복수면 fzf 로 선택
if [[ ${#CANDIDATES[@]} -eq 1 ]]; then
    TARGET_PANE="${CANDIDATES[0]%%|*}"
else
    selected=$(printf '%s\n' "${CANDIDATES[@]}" | fzf \
      --prompt="🎯 전송할 Claude 패널 선택 > " \
      --with-nth=2 --delimiter='|' \
      --height=40% --layout=reverse --border=rounded)
    [[ -z "$selected" ]] && exit 0
    TARGET_PANE="${selected%%|*}"
fi

# 3. 프롬프트 폴더 확인
mkdir -p "$PROMPT_DIR"
if [[ -z "$(ls -A "$PROMPT_DIR" 2>/dev/null)" ]]; then
    die "프롬프트 파일이 없습니다. $PROMPT_DIR 에 .txt 파일을 추가하세요."
fi

# 4. fzf로 프롬프트 선택 (우측 미리보기)
cd "$PROMPT_DIR" || exit 1
SELECTED=$(ls *.txt 2>/dev/null | sed 's/\.txt$//' | fzf \
  --prompt="🤖 클로드 프롬프트 선택 > " \
  --preview "cat '$PROMPT_DIR/{}.txt'" \
  --preview-window=right:50%:wrap \
  --height=100% --layout=reverse --border=rounded)

[[ -z "$SELECTED" ]] && exit 0

# 5. 선택한 프롬프트 내용 전체를 literal 모드로 전송 후 Enter
PROMPT_CONTENT=$(cat "$PROMPT_DIR/${SELECTED}.txt")
tmux send-keys -l -t "$TARGET_PANE" "$PROMPT_CONTENT"
tmux send-keys -t "$TARGET_PANE" C-m

#!/bin/bash

PROMPT_DIR="$HOME/.config/vibe-tools/prompts"

# 1. 클로드 코드가 실행 중인 패널 자동 찾기
TARGET_PANE=""
for info in $(tmux list-panes -F "#{pane_id},#{pane_tty}"); do
    PANE_ID="${info%,*}"
    PANE_TTY="${info#*,}"

    if ps -t "$PANE_TTY" | grep -iq "[c]laude"; then
        TARGET_PANE="$PANE_ID"
        break
    fi
done

if [ -z "$TARGET_PANE" ]; then
    tmux display-message "❌ 클로드 코드가 실행 중인 패널을 찾을 수 없습니다!"
    exit 1
fi

# 2. 프롬프트 폴더 확인
mkdir -p "$PROMPT_DIR"
if [ -z "$(ls -A "$PROMPT_DIR" 2>/dev/null)" ]; then
    tmux display-message "❌ 프롬프트 파일이 없습니다! $PROMPT_DIR 에 .txt 파일을 추가하세요."
    exit 1
fi

# 3. fzf로 목록 표시 및 우측 미리보기(Preview) 띄우기
cd "$PROMPT_DIR" || exit 1

# 파일명에서 .txt 확장자를 제거하고 화면에 표시, 커서를 올리면 우측에 파일 내용 출력
SELECTED=$(ls *.txt | sed 's/\.txt$//' | fzf \
  --prompt="🤖 클로드 프롬프트 선택 > " \
  --preview "cat '$PROMPT_DIR/{}.txt'" \
  --preview-window=right:50%:wrap \
  --height=100% --layout=reverse --border=rounded)

if [ -z "$SELECTED" ]; then
    exit 0
fi

# 4. 선택한 파일의 전체 내용을 변수에 담기
PROMPT_CONTENT=$(cat "$PROMPT_DIR/${SELECTED}.txt")

# 5. 여러 줄의 텍스트를 깨짐 없이(literal) 전송 후 엔터
tmux send-keys -l -t "$TARGET_PANE" "$PROMPT_CONTENT"
tmux send-keys -t "$TARGET_PANE" C-m

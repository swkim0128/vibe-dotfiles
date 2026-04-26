#!/bin/bash

CONFIG_DIR="$HOME/.config/vibe-tools"
CURRENT_SESSION=$(tmux display-message -p '#S')
TMP_FILE=$(mktemp)

# 1. 공통 명령어 추가
cat "$CONFIG_DIR/commands_common.txt" > "$TMP_FILE"

# 2. 현재 세션에 따라 전용 명령어 결합
if [ "$CURRENT_SESSION" = "para" ]; then
    cat "$CONFIG_DIR/commands_main.txt" >> "$TMP_FILE"
    PROMPT_TITLE="👑 [MAIN - para] Tools: "
else
    cat "$CONFIG_DIR/commands_sub.txt" >> "$TMP_FILE"
    PROMPT_TITLE="🤖 [SUB - $CURRENT_SESSION] Tools: "
fi

# 3. fzf로 팝업 띄우기
SELECTED=$(cat "$TMP_FILE" | fzf --prompt="$PROMPT_TITLE" --reverse)
rm -f "$TMP_FILE"

# 4. 명령어 추출 및 실행
if [ -n "$SELECTED" ]; then
    # 파이프(|) 기준 첫 번째 필드(명령어) 추출 후 공백 제거
    CMD=$(echo "$SELECTED" | awk -F '|' '{print $1}' | xargs)
    tmux send-keys "$CMD" C-m
fi

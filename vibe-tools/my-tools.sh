#!/bin/bash

CONFIG_DIR="$HOME/.config/vibe-tools"
TMP_FILE=$(mktemp)

# tmux 컨텍스트 확인 (popup 또는 일반 tmux 패널)
if [[ -n "${TMUX:-}" || -n "${VIBE_IN_POPUP:-}" ]]; then
    IN_TMUX=1
    CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
else
    IN_TMUX=0
    CURRENT_SESSION=""
fi

# 1. 공통 명령어 추가
cat "$CONFIG_DIR/commands_common.txt" > "$TMP_FILE"

# 2. 컨텍스트별 전용 명령어 결합
if [ "$CURRENT_SESSION" = "para" ]; then
    cat "$CONFIG_DIR/commands_main.txt" >> "$TMP_FILE"
    PROMPT_TITLE="👑 [MAIN - para] Tools: "
elif [[ "$IN_TMUX" -eq 1 ]]; then
    cat "$CONFIG_DIR/commands_sub.txt" >> "$TMP_FILE"
    PROMPT_TITLE="🤖 [SUB - $CURRENT_SESSION] Tools: "
else
    cat "$CONFIG_DIR/commands_sub.txt" >> "$TMP_FILE"
    PROMPT_TITLE="💻 [Shell] Tools: "
fi

# 3. fzf로 팝업 띄우기
SELECTED=$(cat "$TMP_FILE" | fzf --prompt="$PROMPT_TITLE" --reverse)
rm -f "$TMP_FILE"

# 4. 명령어 추출 및 전달
if [ -n "$SELECTED" ]; then
    # 파이프(|) 기준 첫 번째 필드(명령어) 추출 후 공백 제거
    CMD=$(echo "$SELECTED" | awk -F '|' '{print $1}' | xargs)

    if [[ "$IN_TMUX" -eq 1 ]]; then
        # tmux 환경: 활성 패널에 키 전송 (placeholder 있으면 엔터 없이)
        if [[ "$CMD" == *"<"*">"* ]]; then
            tmux send-keys "$CMD"
        else
            tmux send-keys "$CMD" C-m
        fi
    else
        # tmux 밖: stdout 으로 출력 (zle 위젯이 prompt 버퍼에 채움)
        printf '%s\n' "$CMD"
    fi
fi

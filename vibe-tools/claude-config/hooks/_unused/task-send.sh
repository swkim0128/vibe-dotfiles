#!/bin/bash
# task-send.sh — A가 B에게 작업 요청 시 사용하는 유틸리티
#
# 사용법:
#   task-send.sh <target_pane> "<message>"
#   task-send.sh <target_pane> "<message>" [sender_pane]
#
# 예시:
#   task-send.sh "%33" "소스코드를 분석해줘"
#   task-send.sh "BillingMPAdmin:1.2" "분석 요청..."
#
# 출력:
#   task_id, sender_pane, result 파일 경로

set -euo pipefail

TARGET_PANE="${1:-}"
MESSAGE="${2:-}"
SENDER_PANE="${3:-${TMUX_PANE:-$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")}}"

if [ -z "$TARGET_PANE" ] || [ -z "$MESSAGE" ]; then
    echo "사용법: task-send.sh <target_pane> \"<message>\" [sender_pane]" >&2
    echo "예시:   task-send.sh \"%33\" \"분석해줘\"" >&2
    exit 1
fi

if [ -z "$SENDER_PANE" ]; then
    echo "오류: sender_pane을 감지할 수 없습니다. tmux 환경에서 실행하세요." >&2
    exit 1
fi

# 태스크 디렉토리 초기화
TASK_DIR="/tmp/claude-tasks"
mkdir -p "$TASK_DIR"

# 태스크 ID 생성 (timestamp + random 6자)
TASK_ID="$(date +%Y%m%d_%H%M%S)_$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c6)"
TASK_FILE="$TASK_DIR/${TASK_ID}.json"
RESULT_FILE="$TASK_DIR/${TASK_ID}.result.md"

# target_pane ID 정규화 (session:window.pane → pane_id %xx 변환)
if [[ "$TARGET_PANE" == %* ]]; then
    TARGET_PANE_ID="$TARGET_PANE"
else
    # session:window.pane 형식 → pane_id 조회
    TARGET_PANE_ID=$(tmux display-message -t "$TARGET_PANE" -p '#{pane_id}' 2>/dev/null || echo "$TARGET_PANE")
fi

# 태스크 파일 생성
cat > "$TASK_FILE" << EOF
{
  "task_id": "${TASK_ID}",
  "sender_pane": "${SENDER_PANE}",
  "target_pane": "${TARGET_PANE_ID}",
  "result_file": "${RESULT_FILE}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "pending",
  "message_preview": "$(echo "$MESSAGE" | head -c100 | tr '\n' ' ')"
}
EOF

# 대상 패널에 메시지 전송
tmux send-keys -t "$TARGET_PANE_ID" "$MESSAGE" Enter

echo "✅ 태스크 전송 완료"
echo "   task_id   : $TASK_ID"
echo "   sender    : $SENDER_PANE"
echo "   target    : $TARGET_PANE_ID"
echo "   결과 파일 : $RESULT_FILE"

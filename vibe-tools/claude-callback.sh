#!/bin/bash
# claude-callback.sh — 작업 완료 후 지휘관 패널에 결과를 보고한다.
#
# 사용법:
#   claude-callback.sh <도착지_패널_ID> <"알림 메시지">
#
# 예시:
#   claude-callback.sh '%1' 'auth 모듈 테스트 12개 작성 완료. 전부 통과.'

set -euo pipefail

DEST_PANE_ID="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$DEST_PANE_ID" || -z "$MESSAGE" ]]; then
  echo "사용법: $0 <도착지_패널_ID> <\"알림 메시지\">" >&2
  exit 1
fi

# ── 송신자(현재 패널) 표시 이름 ─────────────────────────────────────────────
SENDER_LABEL=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
  | awk -v id="$(tmux display-message -p '#{pane_id}')" '$1 == id {print $2}')

# ── 도착지 패널이 존재하는지 확인 ──────────────────────────────────────────
if ! tmux list-panes -a -F '#{pane_id}' | grep -qF "$DEST_PANE_ID"; then
  echo "오류: 도착지 패널 '$DEST_PANE_ID'을 찾을 수 없습니다." >&2
  echo "현재 열린 패널 목록:" >&2
  tmux list-panes -a -F '  #{pane_id}  #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' >&2
  exit 1
fi

# ── 보고 메시지 전송 ─────────────────────────────────────────────────────────
REPORT="🔔 [$SENDER_LABEL] 작업 완료 보고: $MESSAGE"

tmux send-keys -t "$DEST_PANE_ID" "$REPORT" Enter

echo "📨 보고 전송 완료 → 패널 $DEST_PANE_ID"

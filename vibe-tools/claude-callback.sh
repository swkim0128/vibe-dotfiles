#!/bin/bash
# claude-callback.sh — 작업 완료 후 지휘관 패널에 결과를 보고한다.
#
# 사용법:
#   claude-callback.sh <도착지_패널_ID_또는_이름> <"알림 메시지">
#
# 예시:
#   claude-callback.sh '%1' 'auth 모듈 테스트 12개 작성 완료. 전부 통과.'
#   claude-callback.sh 'para:2.1' 'DWDEV-2959 분석 완료.'

set -euo pipefail

TARGET="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$TARGET" || -z "$MESSAGE" ]]; then
  echo "사용법: $0 <도착지_패널_ID_또는_이름> <\"알림 메시지\">" >&2
  echo "  패널 ID 확인: tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'" >&2
  exit 1
fi

# ── 도착지 패널 ID 해석 (%숫자 형식이면 그대로, 아니면 session:window.pane 으로 탐색) ─
if [[ "$TARGET" =~ ^%[0-9]+$ ]]; then
  DEST_PANE_ID="$TARGET"
  if ! tmux list-panes -a -F '#{pane_id}' | grep -qFx "$DEST_PANE_ID"; then
    echo "오류: 도착지 패널 '$TARGET'을 찾을 수 없습니다." >&2
    echo "현재 열린 패널 목록:" >&2
    tmux list-panes -a -F '  #{pane_id}  #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' >&2
    exit 1
  fi
else
  DEST_PANE_ID=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
    | awk -v t="$TARGET" '$2 == t {print $1}' | head -1)

  if [[ -z "$DEST_PANE_ID" ]]; then
    echo "오류: 도착지 패널 '$TARGET'을 찾을 수 없습니다." >&2
    echo "현재 열린 패널 목록:" >&2
    tmux list-panes -a -F '  #{pane_id}  #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' >&2
    exit 1
  fi
fi

# ── 송신자(현재 패널) 표시 이름 ─────────────────────────────────────────────
SENDER_LABEL=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
  | awk -v id="$(tmux display-message -p '#{pane_id}')" '$1 == id {print $2}')

# ── 보고 메시지 전송 ─────────────────────────────────────────────────────────
REPORT="🔔 [$SENDER_LABEL] 작업 완료 보고: $MESSAGE"

tmux send-keys -t "$DEST_PANE_ID" "$REPORT" Enter

echo "📨 보고 전송 완료 → 패널 $DEST_PANE_ID"

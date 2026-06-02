#!/bin/bash
# claude-send.sh — tmux 패널 간 Claude 메시지 전송 (위임/콜백 통합)
#
# delegate 모드 (claude-delegate.sh):
#   claude-delegate.sh <타겟_패널_ID_또는_이름> <"작업 내용">
#   claude-send.sh delegate <타겟_패널_ID_또는_이름> <"작업 내용">
#
# callback 모드 (claude-callback.sh):
#   claude-callback.sh <도착지_패널_ID_또는_이름> <"알림 메시지">
#   claude-send.sh callback <도착지_패널_ID_또는_이름> <"알림 메시지">

set -euo pipefail

# $0 basename 으로 모드 자동 감지, 직접 호출 시 첫 인자로 지정
SCRIPT_NAME=$(basename "$0" .sh)
case "$SCRIPT_NAME" in
  claude-delegate) MODE="delegate" ;;
  claude-callback) MODE="callback" ;;
  *)
    MODE="${1:-}"
    shift || true
    if [[ "$MODE" != "delegate" && "$MODE" != "callback" ]]; then
      echo "사용법: $0 <delegate|callback> <패널_ID> <\"메시지\">" >&2
      exit 1
    fi
    ;;
esac

TARGET="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$TARGET" || -z "$MESSAGE" ]]; then
  echo "사용법: $(basename "$0") <패널_ID_또는_이름> <\"메시지\">" >&2
  echo "  패널 ID 확인: tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'" >&2
  echo "  자동 submit 비활성: AUTO_SUBMIT=0 $(basename "$0") ..." >&2
  exit 1
fi

# ── 현재 패널 ID 캡처 ────────────────────────────────────────────────────────
CURRENT_PANE_ID=$(tmux display-message -p '#{pane_id}')

# ── 타겟 패널 ID 해석 ─────────────────────────────────────────────────────────
if [[ "$TARGET" =~ ^%[0-9]+$ ]]; then
  DEST_PANE_ID="$TARGET"
  if ! tmux list-panes -a -F '#{pane_id}' | grep -qFx "$DEST_PANE_ID"; then
    echo "오류: 패널 '$TARGET'을 찾을 수 없습니다." >&2
    tmux list-panes -a -F '  #{pane_id}  #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' >&2
    exit 1
  fi
else
  DEST_PANE_ID=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
    | awk -v t="$TARGET" '$2 == t {print $1}' | head -1)
  if [[ -z "$DEST_PANE_ID" ]]; then
    echo "오류: 패널 '$TARGET'을 찾을 수 없습니다." >&2
    tmux list-panes -a -F '  #{pane_id}  #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' >&2
    exit 1
  fi
fi

# ── 패널 표시 이름 ────────────────────────────────────────────────────────────
DEST_LABEL=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
  | awk -v id="$DEST_PANE_ID" '$1 == id {print $2}')

# ── 모드별 메시지 구성 및 전송 ────────────────────────────────────────────────
if [[ "$MODE" == "delegate" ]]; then
  PAYLOAD="요청 작업: ${MESSAGE}

[시스템 지시사항] 이 작업이 완전히 끝나면 반드시 터미널에서 다음 명령어를 실행하여 완료를 보고할 것:
~/.config/vibe-tools/claude-callback.sh '${CURRENT_PANE_ID}' '작업 결과 요약을 여기에 입력'"

  # vim 모드 대응: literal paste → insert 종료(Escape) → submit(Enter) 4단 패턴
  # AUTO_SUBMIT=0 으로 호출 시 메시지만 주입, Enter 생략 (사용자가 검토 후 수동 전송)
  tmux send-keys -l -t "$DEST_PANE_ID" "$PAYLOAD"
  if [[ "${AUTO_SUBMIT:-1}" == "1" ]]; then
    sleep 0.1
    tmux send-keys -t "$DEST_PANE_ID" Escape
    sleep 0.05
    tmux send-keys -t "$DEST_PANE_ID" Enter
  fi

  echo "✅ 위임 완료"
  echo "   호출자 패널 : $CURRENT_PANE_ID"
  echo "   타겟 패널   : $DEST_PANE_ID ($DEST_LABEL)"
  echo "   작업 내용   : $MESSAGE"
  echo ""
  echo "💡 타겟 클로드가 작업을 마치면 이 패널($CURRENT_PANE_ID)로 자동 보고됩니다."
else
  SENDER_LABEL=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
    | awk -v id="$CURRENT_PANE_ID" '$1 == id {print $2}')
  PAYLOAD="🔔 [$SENDER_LABEL] 작업 완료 보고: $MESSAGE"

  # vim 모드 대응: 동일 4단 패턴 적용
  tmux send-keys -l -t "$DEST_PANE_ID" "$PAYLOAD"
  if [[ "${AUTO_SUBMIT:-1}" == "1" ]]; then
    sleep 0.1
    tmux send-keys -t "$DEST_PANE_ID" Escape
    sleep 0.05
    tmux send-keys -t "$DEST_PANE_ID" Enter
  fi

  echo "📨 보고 전송 완료 → 패널 $DEST_PANE_ID ($DEST_LABEL)"
fi

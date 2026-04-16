#!/bin/bash
# claude-delegate.sh — 다른 tmux 패널의 클로드에게 작업을 위임하고 콜백을 요청한다.
#
# 사용법:
#   claude-delegate.sh <타겟_패널_ID_또는_이름> <"작업 내용">
#
# 예시:
#   claude-delegate.sh %3 "auth 모듈 유닛 테스트를 작성해줘"
#   claude-delegate.sh worker "API 문서를 마크다운으로 정리해줘"

set -euo pipefail

TARGET="${1:-}"
TASK="${2:-}"

if [[ -z "$TARGET" || -z "$TASK" ]]; then
  echo "사용법: $0 <타겟_패널_ID_또는_이름> <\"작업 내용\">" >&2
  echo "  타겟 패널 ID 확인: tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'" >&2
  exit 1
fi

# ── 호출자 패널 ID 저장 ──────────────────────────────────────────────────────
CALLER_PANE_ID=$(tmux display-message -p '#{pane_id}')

# ── 타겟 패널 ID 해석 (%숫자 형식이면 그대로, 아니면 이름으로 탐색) ───────────
if [[ "$TARGET" =~ ^%[0-9]+$ ]]; then
  TARGET_PANE_ID="$TARGET"
else
  # 세션명:창번호.패널번호 형식 또는 pane_title 이름으로 탐색
  TARGET_PANE_ID=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
    | awk -v t="$TARGET" '$2 == t {print $1}' | head -1)

  if [[ -z "$TARGET_PANE_ID" ]]; then
    echo "오류: 타겟 패널 '$TARGET'을 찾을 수 없습니다." >&2
    echo "현재 열린 패널 목록:" >&2
    tmux list-panes -a -F '  #{pane_id}  #{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' >&2
    exit 1
  fi
fi

# ── 타겟 패널 표시 이름 (보고 메시지용) ────────────────────────────────────
TARGET_LABEL=$(tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index}' \
  | awk -v id="$TARGET_PANE_ID" '$1 == id {print $2}')

# ── 클로드에게 전송할 프롬프트 구성 ─────────────────────────────────────────
PROMPT="요청 작업: ${TASK}

[시스템 지시사항] 이 작업이 완전히 끝나면 반드시 터미널에서 다음 명령어를 실행하여 완료를 보고할 것:
~/.config/vibe-tools/claude-callback.sh '${CALLER_PANE_ID}' '작업 결과 요약을 여기에 입력'"

# ── 타겟 패널로 프롬프트 전송 ────────────────────────────────────────────────
tmux send-keys -t "$TARGET_PANE_ID" "$PROMPT" Enter

echo "✅ 위임 완료"
echo "   호출자 패널 : $CALLER_PANE_ID"
echo "   타겟 패널   : $TARGET_PANE_ID ($TARGET_LABEL)"
echo "   작업 내용   : $TASK"
echo ""
echo "💡 타겟 클로드가 작업을 마치면 이 패널($CALLER_PANE_ID)로 자동 보고됩니다."

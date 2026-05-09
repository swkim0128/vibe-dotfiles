#!/bin/bash
# task-stop.sh — Stop 훅: 현재 패널이 target인 pending 태스크 완료 처리
#
# 동작:
#   1. /tmp/claude-tasks/ 에서 target_pane = 현재 패널인 pending 태스크 탐색
#   2. 해당 태스크의 last_assistant_message를 result 파일에 저장
#   3. 태스크 상태를 completed로 업데이트
#   4. sender 패널에 완료 알림 주입 (tmux send-keys)
#   5. macOS 알림 발송

INPUT=$(cat)

# ── 무한루프 방지 ──────────────────────────────────────────
STOP_HOOK_ACTIVE=$(python3 -c "
import sys, json
try:
    d = json.loads('''${INPUT}''')
    print('true' if d.get('stop_hook_active', False) else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")

[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

# ── 현재 패널 ID 확인 ──────────────────────────────────────
CURRENT_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")
[ -z "$CURRENT_PANE" ] && exit 0

# ── 태스크 디렉토리 확인 ───────────────────────────────────
TASK_DIR="/tmp/claude-tasks"
[ ! -d "$TASK_DIR" ] && exit 0

# ── 현재 패널이 target인 pending 태스크 탐색 ──────────────
TASK_FILE=""
for f in $(ls -t "$TASK_DIR"/*.json 2>/dev/null); do
    INFO=$(python3 -c "
import json
try:
    with open('$f') as fp:
        d = json.load(fp)
    print(d.get('target_pane', ''))
    print(d.get('status', ''))
except:
    print('')
    print('')
" 2>/dev/null)
    FILE_TARGET=$(echo "$INFO" | sed -n '1p')
    FILE_STATUS=$(echo "$INFO" | sed -n '2p')

    if [ "$FILE_TARGET" = "$CURRENT_PANE" ] && [ "$FILE_STATUS" = "pending" ]; then
        TASK_FILE="$f"
        break
    fi
done

[ -z "$TASK_FILE" ] && exit 0

# ── 태스크 정보 파싱 ───────────────────────────────────────
TASK_INFO=$(python3 -c "
import json
with open('$TASK_FILE') as f:
    d = json.load(f)
print(d.get('task_id', ''))
print(d.get('sender_pane', ''))
print(d.get('result_file', ''))
" 2>/dev/null)

TASK_ID=$(echo "$TASK_INFO" | sed -n '1p')
SENDER_PANE=$(echo "$TASK_INFO" | sed -n '2p')
RESULT_FILE=$(echo "$TASK_INFO" | sed -n '3p')

[ -z "$TASK_ID" ] && exit 0

# ── 결과 저장 ──────────────────────────────────────────────
LAST_MSG=$(python3 -c "
import sys, json
try:
    d = json.loads('''${INPUT}''')
    print(d.get('last_assistant_message', ''))
except:
    pass
" 2>/dev/null || echo "")

if [ -n "$LAST_MSG" ] && [ -n "$RESULT_FILE" ]; then
    {
        echo "# Claude 작업 결과"
        echo "task_id: ${TASK_ID}"
        echo "완료 시각: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "---"
        echo ""
        echo "$LAST_MSG"
    } > "$RESULT_FILE"
fi

# ── 태스크 완료 처리 ───────────────────────────────────────
python3 -c "
import json
with open('$TASK_FILE') as f:
    d = json.load(f)
d['status'] = 'completed'
d['completed_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$TASK_FILE', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null

# ── sender 패널에 완료 알림 주입 ───────────────────────────
if [ -n "$SENDER_PANE" ]; then
    NOTIFY_MSG="[작업완료] task_id=${TASK_ID} | 결과 파일을 읽어주세요: ${RESULT_FILE}"
    tmux send-keys -t "$SENDER_PANE" "$NOTIFY_MSG" Enter 2>/dev/null || true
fi

# ── macOS 알림 ─────────────────────────────────────────────
osascript -e "display notification \"task=${TASK_ID} 완료 → ${SENDER_PANE}에 알림 전송\" with title \"Claude 작업 완료\"" 2>/dev/null || true

exit 0

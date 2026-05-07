#!/usr/bin/env bash
# tmux new-session 직접 호출을 차단하고 vibe.sh start 사용을 강제한다.
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || true)

if printf '%s' "$cmd" | grep -q 'tmux new-session'; then
    printf '{"continue":false,"stopReason":"tmux new-session 직접 호출 금지.\n\n반드시 vibe.sh 를 사용하세요:\n  ~/.config/vibe-tools/vibe.sh start <세션명> <절대경로>\n\n또는 tmux-session-start 스킬을 먼저 호출하세요."}'
else
    printf '{"continue":true}'
fi

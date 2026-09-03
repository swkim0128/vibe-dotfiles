#!/usr/bin/env bash
# ai-usage-poll.sh — ai-usage.sh 를 주기 실행해 tmux 상태바 캐시를 갱신
#
# 사용: bash bin/ai-usage-poll.sh   (.tmux.conf 의 run-shell -b 로 자동 기동)
#
# 주기 기본 180초 — 조회기(claude-dashboard check-usage)가 자체 300초 캐시를 두므로
# 더 짧게 돌려도 대부분 캐시 히트다. 한도는 그렇게 빨리 움직이지 않는다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${VIBE_CACHE_DIR:-$HOME/.cache/vibe}"
PID_FILE="$CACHE_DIR/ai-usage-poll.pid"
INTERVAL="${VIBE_AI_USAGE_INTERVAL:-180}"

mkdir -p "$CACHE_DIR"

# 중복 기동 방지 — 살아있는 폴러가 있으면 조용히 종료 (source-file 반복에 안전)
if [ -f "$PID_FILE" ]; then
	old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
	if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
		exit 0
	fi
fi
printf '%s' "$$" >"$PID_FILE"

cleanup() {
	rm -f "$PID_FILE"
}
# INT/TERM 은 exit 까지 해야 한다 — 핸들러만 돌고 루프로 복귀하면 pidfile 만 사라진
# 좀비 폴러가 남아 중복 기동 방지가 무력화된다 (dock-badges-poll.sh 와 동일 규율).
terminate() {
	cleanup
	exit 0
}
trap cleanup EXIT
trap terminate INT TERM

while true; do
	bash "$SCRIPT_DIR/ai-usage.sh" >/dev/null 2>&1
	sleep "$INTERVAL"
done

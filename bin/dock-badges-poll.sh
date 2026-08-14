#!/usr/bin/env bash
# dock-badges-poll.sh — dock-badges.sh 를 주기 실행하고 Slack 뱃지 카운트가 증가하면 tmux 팝업 통지
#
# 사용: bash bin/dock-badges-poll.sh   (.tmux.conf 의 run-shell -b 로 자동 기동)
#
# LaunchAgent 로 만들지 말 것 — 접근성 권한은 터미널 responsible process 로 상속되며,
# tmux 서버에서 기동하는 현재 경로가 검증된 방식이다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${VIBE_CACHE_DIR:-$HOME/.cache/vibe}"
RAW_FILE="$CACHE_DIR/dock-badges.raw"
PID_FILE="$CACHE_DIR/dock-badges-poll.pid"
INTERVAL="${VIBE_DOCK_POLL_INTERVAL:-5}"

mkdir -p "$CACHE_DIR"

# 중복 기동 방지 — 살아있는 폴러가 있으면 조용히 종료
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
# INT/TERM 은 반드시 exit 까지 해야 한다 — 핸들러만 돌고 루프로 복귀하면
# pidfile 만 사라진 좀비 폴러가 남아 중복 기동 방지가 무력화된다.
terminate() {
	cleanup
	exit 0
}
trap cleanup EXIT
trap terminate INT TERM

# 전체 tmux 클라이언트에 팝업 통지
notify() {
	tmux list-clients -F '#{client_name}' 2>/dev/null | while IFS= read -r client; do
		[ -n "$client" ] || continue
		tmux display-message -d 4000 -c "$client" "$1"
	done
}

slack_count() {
	awk -F= '$1 == "Slack" { print $2; exit }' "$RAW_FILE" 2>/dev/null
}

prev=0
while true; do
	bash "$SCRIPT_DIR/dock-badges.sh" >/dev/null 2>&1
	cur="$(slack_count)"
	# 뱃지가 "9+" 처럼 숫자가 아닐 수 있다 — 숫자가 아니면 0 으로 취급
	case "$cur" in
	'' | *[!0-9]*) cur=0 ;;
	esac
	if [ "$cur" -gt "$prev" ]; then
		notify "🔔 Slack 미확인 $cur 건"
	fi
	prev="$cur"
	sleep "$INTERVAL"
done

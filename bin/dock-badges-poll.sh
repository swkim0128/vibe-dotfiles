#!/usr/bin/env bash
# dock-badges-poll.sh — dock-badges.sh 를 주기 실행하고 Slack 뱃지 카운트가 증가하면 tmux 팝업 통지
#
# 사용: bash bin/dock-badges-poll.sh   (.tmux.conf 의 run-shell -b 로 자동 기동)
#
# LaunchAgent 로 만들지 말 것 — 접근성 권한은 터미널 responsible process 로 상속되며,
# tmux 서버에서 기동하는 현재 경로가 검증된 방식이다.
set -uo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
CONFIG_FILE="${VIBE_DOCK_CONFIG:-$SCRIPT_DIR/../vibe-tools/dock-badges.json}"
CACHE_BASE="${VIBE_CACHE_DIR:-$HOME/.cache/vibe}"
CACHE_DIR="$CACHE_BASE/$(jq -er '.backends.tmux' "$CONFIG_FILE")" || exit 2
RAW_FILE="$CACHE_DIR/$(jq -er '.files.raw' "$CONFIG_FILE")" || exit 2
PID_FILE="$CACHE_DIR/$(jq -er '.files.pid' "$CONFIG_FILE")" || exit 2
INTERVAL="${VIBE_DOCK_POLL_INTERVAL:-$(jq -er '.refresh_seconds' "$CONFIG_FILE")}" || exit 2
LOCK_DIR="$PID_FILE.lock"

if [ -z "${TMUX:-}" ]; then
	printf '%s\n' 'Dock tmux 폴러는 tmux run-shell -b 경로에서 시작하세요.' >&2
	exit 2
fi

mkdir -p "$CACHE_DIR"

# 중복 기동 방지 — 살아있는 폴러가 있으면 조용히 종료
if [ -f "$PID_FILE" ]; then
	old_pid="$(cat "$PID_FILE" 2>/dev/null)"
	if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
		exit 0
	fi
fi
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
	printf '%s\n' "Dock tmux 폴러 잠금이 남아 있습니다. PID 확인 뒤 제거: rmdir '$LOCK_DIR'" >&2
	exit 3
fi
printf '%s' "$$" >"$PID_FILE"

cleanup() {
	rm -f "$PID_FILE"
	rmdir "$LOCK_DIR" 2>/dev/null
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

prev=""
while true; do
	if bash "$SCRIPT_DIR/dock-badges.sh" --backend tmux >/dev/null 2>&1; then
		cur="$(slack_count)"
		# 성공한 전체 조회에서 Slack 뱃지가 없으면 0건이다. 숫자 아닌 뱃지는 추정하지 않는다.
		case "$cur" in
		'') cur=0 ;;
		*[!0-9]*) sleep "$INTERVAL"; continue ;;
		esac
		if [ -n "$prev" ] && [ "$cur" -gt "$prev" ]; then
			notify "🔔 Slack 미확인 $cur 건"
		fi
		prev="$cur"
	fi
	sleep "$INTERVAL"
done

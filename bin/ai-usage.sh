#!/usr/bin/env bash
# ai-usage.sh — AI CLI(Claude·Codex·Gemini) 사용량을 조회해 tmux 상태바용 한 줄 캐시에 기록
#
# 사용:
#   bash bin/ai-usage.sh          조회 + 캐시 원자적 갱신
#   bash bin/ai-usage.sh --print  조회 결과를 stdout 으로만 출력 (캐시 미변경)
#
# 캐시:
#   ~/.cache/vibe/ai-usage   표시용 한 줄 (tmux status-format[1] 이 cat 으로만 읽음)
#
# 출력 형식: 선두에 tmux 색 태그를 붙이고 CLI 별 "5시간/주간 사용률(%)" 을 잇는다.
#   예) #[fg=#a6da95]CC 4/12  CX 20/3  → codex
#   색은 전 CLI 중 가장 높은 사용률 기준 (초록 ≤50 · 노랑 ≤80 · 빨강 >80).
#
# 조회기는 claude-dashboard 플러그인의 standalone CLI 를 그대로 쓴다. 세션 JSON 없이
# 동작하고 Claude·Codex·Gemini·z.ai 를 한 번에 읽으므로 별도 구현을 만들지 않는다.
# 경로를 박지 않기 위해 버전 디렉터리는 glob 으로 풀고 VIBE_AI_USAGE_CMD 로 덮어쓸 수 있다.
set -uo pipefail

CACHE_DIR="${VIBE_CACHE_DIR:-$HOME/.cache/vibe}"
DISPLAY_FILE="$CACHE_DIR/ai-usage"

COLOR_OK="#a6da95"
COLOR_WARN="#eed49f"
COLOR_CRIT="#ed8796"
COLOR_DIM="#6e738d"

resolve_cmd() {
	if [ -n "${VIBE_AI_USAGE_CMD:-}" ]; then
		printf '%s' "$VIBE_AI_USAGE_CMD"
		return 0
	fi
	local latest
	latest="$(ls -d "$HOME"/.claude/plugins/cache/claude-dashboard/claude-dashboard/*/dist/check-usage.js 2>/dev/null | sort -V | tail -1)"
	[ -n "$latest" ] || return 1
	printf 'node %s' "$latest"
}

render() {
	local cmd json
	cmd="$(resolve_cmd)" || {
		printf '#[fg=%s]AI ?' "$COLOR_DIM"
		return 0
	}

	json="$($cmd --json 2>/dev/null)"
	if [ -z "$json" ]; then
		printf '#[fg=%s]AI ?' "$COLOR_DIM"
		return 0
	fi

	# 사용 가능하고 error 가 아닌 CLI 만 "라벨 5시간 주간" 3필드로 뽑는다.
	local rows
	rows="$(printf '%s' "$json" | jq -r '
		{CC: .claude, CX: .codex, GM: .gemini}
		| to_entries[]
		| select(.value != null and .value.available == true and .value.error == false)
		| select(.value.fiveHourPercent != null)
		| "\(.key) \(.value.fiveHourPercent) \(.value.sevenDayPercent // 0)"
	' 2>/dev/null)"

	if [ -z "$rows" ]; then
		printf '#[fg=%s]AI ?' "$COLOR_DIM"
		return 0
	fi

	local worst=0 text="" label five seven
	while read -r label five seven; do
		[ -n "$label" ] || continue
		[ "$five" -gt "$worst" ] 2>/dev/null && worst="$five"
		[ "$seven" -gt "$worst" ] 2>/dev/null && worst="$seven"
		text="${text}${label} ${five}/${seven}  "
	done <<EOF
$rows
EOF

	local rec
	rec="$(printf '%s' "$json" | jq -r '.recommendation // empty' 2>/dev/null)"
	[ -n "$rec" ] && text="${text}→ ${rec}"

	local color="$COLOR_OK"
	if [ "$worst" -gt 80 ]; then
		color="$COLOR_CRIT"
	elif [ "$worst" -gt 50 ]; then
		color="$COLOR_WARN"
	fi

	printf '#[fg=%s]%s' "$color" "${text%"${text##*[![:space:]]}"}"
}

line="$(render)"

if [ "${1:-}" = "--print" ]; then
	printf '%s\n' "$line"
	exit 0
fi

mkdir -p "$CACHE_DIR"
tmp="$(mktemp "$CACHE_DIR/.ai-usage.XXXXXX")"
printf '%s' "$line" >"$tmp"
mv "$tmp" "$DISPLAY_FILE"

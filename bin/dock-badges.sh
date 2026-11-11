#!/usr/bin/env bash
# dock-badges.sh — macOS Dock 뱃지(미확인 알림 개수)를 접근성 API(AXStatusLabel)로 열거해 캐시에 기록
#
# 사용:
#   bash bin/dock-badges.sh          전체 열거(~1.0s) + 캐시 2종 원자적 갱신
#   bash bin/dock-badges.sh --slack  Slack 만 조회(~0.2s), stdout 출력만 (캐시 미변경)
#
# 캐시:
#   ~/.cache/vibe/dock-badges      표시용 한 줄 압축 포맷
#   ~/.cache/vibe/dock-badges.raw  원본 NAME=COUNT 라인
#
# 전제: 접근성 권한(System Events 제어)이 호출 터미널의 responsible process 에 부여되어 있어야 한다.
#       FDA(전체 디스크 접근)는 불필요.
set -uo pipefail

if [ "${1:-}" = "--slack" ]; then
	SLACK_ONLY=1
else
	SLACK_ONLY=0
fi
CONFIG_FILE="${VIBE_DOCK_CONFIG:-${BASH_SOURCE[0]%/*}/../vibe-tools/dock-badges.json}"
BACKEND=""
READ_ONLY=0
while [ "$#" -gt 0 ]; do
	case "$1" in
	--backend)
		[ "$#" -ge 2 ] || exit 2
		case "$2" in tmux | herdr) BACKEND="$2" ;; *) exit 2 ;; esac
		shift 2 ;;
	--read) READ_ONLY=1; shift ;;
	--slack) SLACK_ONLY=1; shift ;;
	*) exit 2 ;;
	esac
done

CACHE_DIR="${VIBE_CACHE_DIR:-$HOME/.cache/vibe}"
if [ -n "$BACKEND" ]; then
	CACHE_DIR="$CACHE_DIR/$(jq -er --arg backend "$BACKEND" '.backends[$backend]' "$CONFIG_FILE")" || exit 2
fi
RAW_FILE="$CACHE_DIR/$(jq -er '.files.raw' "$CONFIG_FILE")" || exit 2
DISPLAY_FILE="$CACHE_DIR/$(jq -er '.files.display' "$CONFIG_FILE")" || exit 2
STATUS_FILE="$CACHE_DIR/$(jq -er '.files.status' "$CONFIG_FILE")" || exit 2
DISPLAY_MAX="${VIBE_DOCK_BADGE_MAXLEN:-$(jq -er '.display_max_chars' "$CONFIG_FILE")}" || exit 2
COLLECT_TIMEOUT="$(jq -er '.collector_timeout_seconds' "$CONFIG_FILE")" || exit 2

if [ "$READ_ONLY" -eq 1 ]; then
	if [ ! -r "$STATUS_FILE" ]; then
		jq -r '.labels.unknown' "$CONFIG_FILE"
		exit 0
	fi
	if ! jq -er --slurpfile config "$CONFIG_FILE" --argjson at "$(date +%s)" '
		$config[0] as $c | if .ok == false then $c.labels.failed
		elif .ok != true then $c.labels.unknown
		elif $at - .last_success_at > $c.stale_seconds then $c.labels.stale
		elif .badges == "" then $c.labels.empty else .display end' "$STATUS_FILE"; then
		jq -r '.labels.failed' "$CONFIG_FILE"
		exit 1
	fi
	exit 0
fi

# Dock 의 모든 아이템에서 뱃지 라벨을 수집한다.
# - AXStatusLabel 이 없는 아이템은 속성 목록으로 건너뛴다. 다른 접근성 오류는 실패로 반환한다.
# - UI element 를 변수에 담아 재사용하면 System Events 가 -10000(AppleEvent 처리 실패)로 죽는다.
#   반드시 'of UI element idx of list 1' 인라인 접근을 쓸 것.
# - AppleScript 예약어 'it' 은 사용하지 않는다. 누산기 변수명으로 'outLines' 도 쓰지 말 것 —
#   tell process 블록 안에서 terminology 로 해석되어 -10000 으로 죽는다(acc 사용).
enumerate_all() {
	osascript - "$COLLECT_TIMEOUT" <<'APPLESCRIPT'
on run argv
with timeout of (item 1 of argv as integer) seconds
tell application "System Events"
	if UI elements enabled is false then error "Accessibility permission required" number -1719
	tell process "Dock"
		set acc to ""
		set itemCount to count of UI elements of list 1
		repeat with idx from 1 to itemCount
			set attributeNames to name of attributes of UI element idx of list 1
			if attributeNames contains "AXStatusLabel" then
				set badgeValue to value of attribute "AXStatusLabel" of UI element idx of list 1
				set itemName to name of UI element idx of list 1
				if badgeValue is not missing value and itemName is not missing value then
					set badgeText to badgeValue as text
					if badgeText is not "" then
						set acc to acc & itemName & "=" & badgeText & linefeed
					end if
				end if
			end if
		end repeat
		return acc
	end tell
end tell
end timeout
end run
APPLESCRIPT
}

# Slack 단독 조회 (전체 열거보다 5배 이상 빠름)
enumerate_slack() {
	osascript - "$COLLECT_TIMEOUT" <<'APPLESCRIPT'
on run argv
with timeout of (item 1 of argv as integer) seconds
tell application "System Events"
	if UI elements enabled is false then error "Accessibility permission required" number -1719
	tell process "Dock"
		set acc to ""
		if exists UI element "Slack" of list 1 then
			set badgeValue to value of attribute "AXStatusLabel" of UI element "Slack" of list 1
			if badgeValue is not missing value then
				set badgeText to badgeValue as text
				if badgeText is not "" then
					set acc to "Slack=" & badgeText & linefeed
				end if
			end if
		end if
		return acc
	end tell
end tell
end timeout
end run
APPLESCRIPT
}

if [ "$SLACK_ONLY" -eq 1 ]; then
	enumerate_slack
	exit "$?"
fi

mkdir -p "$CACHE_DIR" || exit 1
umask 077
attempted_at="$(date +%s)"
tmp_status="$(mktemp "$CACHE_DIR/.dock-status.XXXXXX")" || exit 1
tmp_error="$(mktemp "$CACHE_DIR/.dock-error.XXXXXX")" || exit 1
trap 'rm -f "$tmp_status" "$tmp_error"' EXIT

if ! raw="$(enumerate_all 2>"$tmp_error")"; then
	previous='{}'
	if [ -r "$STATUS_FILE" ]; then previous="$(cat "$STATUS_FILE")"; fi
	if ! jq -n --argjson previous "$previous" --argjson at "$attempted_at" \
		'{ok:false,attempted_at:$at,last_success_at:($previous.last_success_at // null),badges:($previous.badges // null),display:($previous.display // null),error:"accessibility_or_collection_failed"}' >"$tmp_status"; then
		printf '{"ok":false,"attempted_at":%s,"error":"collection_failed"}\n' "$attempted_at" >"$tmp_status"
	fi
	mv -f "$tmp_status" "$STATUS_FILE"
	cat "$tmp_error" >&2
	exit 1
fi

# NAME=COUNT → "NAME:COUNT NAME:COUNT" 한 줄로 압축. 뱃지가 없으면 빈 문자열.
display="$(printf '%s\n' "$raw" | awk -F= 'NF == 2 && $1 != "" && $2 != "" { printf "%s%s:%s", sep, $1, $2; sep = " " }')"

# status-right-length 를 잡아먹지 않도록 표시용 문자열 길이 제한
if [ "${#display}" -gt "$DISPLAY_MAX" ]; then
	display="${display:0:$((DISPLAY_MAX - 1))}+"
fi

# 임시파일 + mv 로 원자적 기록 (tmux/dock 이 반쯤 쓰인 파일을 읽지 않도록)
tmp_raw="$(mktemp "$CACHE_DIR/.dock-badges.raw.XXXXXX")" || exit 1
printf '%s' "$raw" >"$tmp_raw" || exit 1
mv -f "$tmp_raw" "$RAW_FILE" || exit 1

tmp_display="$(mktemp "$CACHE_DIR/.dock-badges.XXXXXX")" || exit 1
printf '%s' "$display" >"$tmp_display" || exit 1
mv -f "$tmp_display" "$DISPLAY_FILE" || exit 1

jq -n --arg raw "$raw" --arg display "$display" --argjson at "$attempted_at" \
	'{ok:true,attempted_at:$at,last_success_at:$at,badges:$raw,display:$display,error:null}' >"$tmp_status" || exit 1
mv -f "$tmp_status" "$STATUS_FILE" || exit 1

printf '%s' "$raw"

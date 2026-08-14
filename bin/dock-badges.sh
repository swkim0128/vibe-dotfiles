#!/usr/bin/env bash
# dock-badges.sh — macOS Dock 뱃지(미확인 알림 개수)를 접근성 API(AXStatusLabel)로 열거해 캐시에 기록
#
# 사용:
#   bash bin/dock-badges.sh          전체 열거(~1.0s) + 캐시 2종 원자적 갱신
#   bash bin/dock-badges.sh --slack  Slack 만 조회(~0.2s), stdout 출력만 (캐시 미변경)
#
# 캐시:
#   ~/.cache/vibe/dock-badges      표시용 한 줄 압축 포맷 (tmux status-right 가 cat 으로만 읽음)
#   ~/.cache/vibe/dock-badges.raw  원본 NAME=COUNT 라인
#
# 전제: 접근성 권한(System Events 제어)이 호출 터미널의 responsible process 에 부여되어 있어야 한다.
#       FDA(전체 디스크 접근)는 불필요.
set -uo pipefail

CACHE_DIR="${VIBE_CACHE_DIR:-$HOME/.cache/vibe}"
RAW_FILE="$CACHE_DIR/dock-badges.raw"
DISPLAY_FILE="$CACHE_DIR/dock-badges"
DISPLAY_MAX="${VIBE_DOCK_BADGE_MAXLEN:-24}"

# Dock 의 모든 아이템에서 뱃지 라벨을 수집한다.
# - AXStatusLabel 이 없는 아이템(구분자·미알림 앱)은 'missing value as text' 강제 변환 실패를 try 로 건너뛴다.
# - UI element 를 변수에 담아 재사용하면 System Events 가 -10000(AppleEvent 처리 실패)로 죽는다.
#   반드시 'of UI element idx of list 1' 인라인 접근을 쓸 것.
# - AppleScript 예약어 'it' 은 사용하지 않는다. 누산기 변수명으로 'outLines' 도 쓰지 말 것 —
#   tell process 블록 안에서 terminology 로 해석되어 -10000 으로 죽는다(acc 사용).
enumerate_all() {
	osascript <<'APPLESCRIPT'
tell application "System Events"
	tell process "Dock"
		set acc to ""
		set itemCount to count of UI elements of list 1
		repeat with idx from 1 to itemCount
			try
				set badgeValue to value of attribute "AXStatusLabel" of UI element idx of list 1
				set itemName to name of UI element idx of list 1
				if badgeValue is not missing value and itemName is not missing value then
					set badgeText to badgeValue as text
					if badgeText is not "" then
						set acc to acc & itemName & "=" & badgeText & linefeed
					end if
				end if
			end try
		end repeat
		return acc
	end tell
end tell
APPLESCRIPT
}

# Slack 단독 조회 (전체 열거보다 5배 이상 빠름)
enumerate_slack() {
	osascript <<'APPLESCRIPT'
tell application "System Events"
	tell process "Dock"
		set acc to ""
		try
			set badgeValue to value of attribute "AXStatusLabel" of UI element "Slack" of list 1
			if badgeValue is not missing value then
				set badgeText to badgeValue as text
				if badgeText is not "" then
					set acc to "Slack=" & badgeText & linefeed
				end if
			end if
		end try
		return acc
	end tell
end tell
APPLESCRIPT
}

if [ "${1:-}" = "--slack" ]; then
	enumerate_slack
	exit 0
fi

mkdir -p "$CACHE_DIR"

raw="$(enumerate_all)"

# NAME=COUNT → "NAME:COUNT NAME:COUNT" 한 줄로 압축. 뱃지가 없으면 빈 문자열.
display="$(printf '%s\n' "$raw" | awk -F= 'NF == 2 && $1 != "" && $2 != "" { printf "%s%s:%s", sep, $1, $2; sep = " " }')"

# status-right-length 를 잡아먹지 않도록 표시용 문자열 길이 제한
if [ "${#display}" -gt "$DISPLAY_MAX" ]; then
	display="${display:0:$((DISPLAY_MAX - 1))}+"
fi

# 임시파일 + mv 로 원자적 기록 (tmux/dock 이 반쯤 쓰인 파일을 읽지 않도록)
tmp_raw="$(mktemp "$CACHE_DIR/.dock-badges.raw.XXXXXX")"
printf '%s' "$raw" >"$tmp_raw"
mv -f "$tmp_raw" "$RAW_FILE"

tmp_display="$(mktemp "$CACHE_DIR/.dock-badges.XXXXXX")"
printf '%s' "$display" >"$tmp_display"
mv -f "$tmp_display" "$DISPLAY_FILE"

printf '%s' "$raw"

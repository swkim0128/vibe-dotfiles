#!/usr/bin/env bash
# tmux-hud-session-hook.sh — codex-hud 세션에서만 tmux 상태바를 끈다
#
# 사용: bash bin/tmux-hud-session-hook.sh <세션명>
#       (.tmux.conf 의 session-created 훅이 run-shell 로 호출)
#
# HUD 가 모델·컨텍스트·git·토큰을 이미 그리므로 그 세션에서 tmux 상태바는 중복이다.
#
# ⚠️ 반드시 세션 단위(set-option -t)로 끈다. 전역 status/status-format 을 건드리면
#    모든 세션의 상태바가 같이 죽는다 (2026-09-04 사고).
# ⚠️ if-shell 의 명령 문자열 안에서는 #{...} 포맷이 확장되지 않는다 — 조건(-F)만 확장된다.
#    그래서 훅에서 세션명을 넘기려면 run-shell(확장됨) + 이 스크립트 조합을 쓴다.
set -uo pipefail

session="${1:-}"
[ -n "$session" ] || exit 0

case "$session" in
codex-hud-*)
	tmux set-option -t "$session" status off 2>/dev/null || true
	;;
esac

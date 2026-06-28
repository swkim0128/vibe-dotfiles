#!/usr/bin/env bash
# cmux-proj-review.sh — cmux diff 리뷰 래퍼 (tmux 안에서 --workspace/--surface 자동 해석)
# 사용: cmux-review <name> [--branch|--unstaged|--staged]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cmux-lib.sh disable=SC1091
source "$SCRIPT_DIR/cmux-lib.sh"
CONFIG="$SCRIPT_DIR/cmux-projects.txt"

NAME="${1:-}"
SRC="${2:---branch}"

if [[ -z "$NAME" || "$NAME" == "-h" || "$NAME" == "--help" ]]; then
  echo "사용법: $(basename "$0") <name> [--branch|--unstaged|--staged]" >&2
  cmux_print_projects "$CONFIG"
  exit 0
fi

match="$(cmux_lookup "$CONFIG" "$NAME")"
if [[ -z "$match" ]]; then
  echo "오류: '$NAME' 미등록" >&2
  cmux_print_projects "$CONFIG"
  exit 1
fi

IFS='|' read -r _name raw_path _color _desc _ssh <<< "$match"
path="$(cmux_expand_home "$raw_path")"

if ! cmux_has_cli; then
  echo "⚠️  cmux CLI 미설치" >&2
  exit 1
fi

ws="$(cmux current-workspace --json 2>/dev/null | awk -F'"' '/workspace_ref/{print $4; exit}')"
surf="$(cmux list-pane-surfaces --workspace "$ws" 2>/dev/null | awk '/^\*/{print $2; exit}')"

if [[ -z "$ws" || -z "$surf" ]]; then
  echo "오류: 현재 cmux 워크스페이스/surface 해석 실패 (cmux 터미널에서 실행 필요)" >&2
  exit 1
fi

cmux diff "$SRC" --cwd "$path" --workspace "$ws" --surface "$surf" --focus false
echo "✅ $NAME diff 뷰어 열림 ($SRC, ws=$ws)"

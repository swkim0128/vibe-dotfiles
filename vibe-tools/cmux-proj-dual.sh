#!/usr/bin/env bash
# cmux-proj-dual.sh — 듀얼-프로젝트 cmux 워크스페이스 런처
#
# 사용법:
#   cmux-dual <nameA> <nameB>   # cmux-projects.txt 에 등록된 두 프로젝트
#   cmux-dual                    # 등록 프로젝트 목록
#
# 구성 (세션 미존재 시 생성):
#   win1 claude : claude@A | claude@B
#   win2 edit   : nvim@A   | nvim@B
#   win3 verify : shell@A
#   패널 제목 자동 설정 (claude 패널 제목은 claude 실행 후 덮일 수 있음).
#   세션명 = 첫 프로젝트(A). 인덱스 가정 없이 활성 패널 타겟팅으로 이식성 확보.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cmux-lib.sh disable=SC1091
source "$SCRIPT_DIR/cmux-lib.sh"
CONFIG="$SCRIPT_DIR/cmux-projects.txt"

# $1=name → "path|color|desc" (path 의 $HOME 전개). 미등록 시 return 1.
lookup() {
  local match _name path color desc
  match="$(cmux_lookup "$CONFIG" "$1")"
  [[ -z "$match" ]] && return 1
  IFS='|' read -r _name path color desc <<< "$match"
  printf '%s|%s|%s' "$(cmux_expand_home "$path")" "$color" "$desc"
}

A="${1:-}"
B="${2:-}"

if [[ -z "$A" || -z "$B" || "$A" == "-h" || "$A" == "--help" ]]; then
  echo "사용법: $(basename "$0") <nameA> <nameB>" >&2
  cmux_print_projects "$CONFIG"
  exit 0
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "오류: 설정 파일 없음: $CONFIG" >&2
  exit 1
fi

infoA="$(lookup "$A")" || { echo "오류: '$A' 미등록" >&2; cmux_print_projects "$CONFIG"; exit 1; }
infoB="$(lookup "$B")" || { echo "오류: '$B' 미등록" >&2; cmux_print_projects "$CONFIG"; exit 1; }
IFS='|' read -r pathA colorA _descA <<< "$infoA"
IFS='|' read -r pathB _colorB _descB <<< "$infoB"

[[ -d "$pathA" ]] || { echo "오류: 경로 없음 $pathA" >&2; exit 1; }
[[ -d "$pathB" ]] || { echo "오류: 경로 없음 $pathB" >&2; exit 1; }

SESS="$A"

created=false
if ! tmux has-session -t "$SESS" 2>/dev/null; then
  # win1 claude (활성 패널 타겟팅)
  tmux new-session -d -s "$SESS" -n claude -c "$pathA"
  tmux send-keys -t "$SESS:claude" 'claude' Enter
  tmux select-pane -t "$SESS:claude" -T "$A · claude"
  tmux split-window -h -t "$SESS:claude" -c "$pathB"
  tmux send-keys -t "$SESS:claude" 'claude' Enter
  tmux select-pane -t "$SESS:claude" -T "$B · claude"
  # win2 edit
  tmux new-window -t "$SESS" -n edit -c "$pathA"
  tmux send-keys -t "$SESS:edit" 'nvim .' Enter
  tmux select-pane -t "$SESS:edit" -T "$A · nvim"
  tmux split-window -h -t "$SESS:edit" -c "$pathB"
  tmux send-keys -t "$SESS:edit" 'nvim .' Enter
  tmux select-pane -t "$SESS:edit" -T "$B · nvim"
  # win3 verify
  tmux new-window -t "$SESS" -n verify -c "$pathA"
  tmux select-pane -t "$SESS:verify" -T "verify · shellcheck/bats"
  # 기본 포커스 = win1 좌측 패널
  tmux select-window -t "$SESS:claude"
  tmux select-pane -t "$SESS:claude" -L
  created=true
fi

if ! cmux_has_cli; then
  echo "⚠️  cmux CLI 미설치 — tmux 세션 '$SESS' 만 구성." >&2
  echo "   attach: tmux attach -t $SESS" >&2
  exit 0
fi

ref="$(cmux_create_workspace "$SESS" "$pathA" "$colorA" "$A + $B (듀얼)")" || { echo "오류: cmux 워크스페이스 생성 실패" >&2; exit 1; }

echo "✅ 듀얼-프로젝트 워크스페이스 기동"
echo "   cmux workspace: $ref / tmux 세션: $SESS"
if [[ "$created" == true ]]; then
  echo "   win1 claude($A|$B) / win2 edit(nvim $A|$B) / win3 verify (신규 생성)"
else
  echo "   기존 세션 '$SESS' 재사용 (레이아웃 유지)"
fi

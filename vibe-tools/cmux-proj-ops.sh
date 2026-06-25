#!/usr/bin/env bash
# cmux-proj-ops.sh — 수동처리 스크립트 작업용 cmux 워크스페이스 런처
#
# 사용법:
#   cmux-ops <name>   # cmux-ops.txt 등록 항목 기동
#   cmux-ops          # 등록 목록
#
# 레이아웃 (세션 미존재 시):
#   win1 claude : 스크립트 작성·개선 보조 (claude)
#   win2 edit   : nvim — 스크립트 편집
#   win3 run    : 서버 실행용. sshhost 설정 시 'ssh <host>' 를 미리 타이핑(미실행)·제목 표시,
#                 없으면 로컬 셸.
#   각 윈도우 단일 패널 + 패널 제목. 세션명 = name.
#   작업 관리용 para 와 분리된 ops 전용 워크스페이스.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/cmux-ops.txt"

print_ops() {
  echo "등록된 ops 작업:" >&2
  grep -vE '^[[:space:]]*(#|$)' "$CONFIG" | while IFS='|' read -r n _p _c d _s; do
    printf '  %-18s %s\n' "$n" "$d" >&2
  done || true
}

NAME="${1:-}"

if [[ -z "$NAME" || "$NAME" == "-h" || "$NAME" == "--help" ]]; then
  echo "사용법: $(basename "$0") <name>" >&2
  print_ops
  exit 0
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "오류: 설정 파일 없음: $CONFIG" >&2
  exit 1
fi

MATCH="$(grep -vE '^[[:space:]]*(#|$)' "$CONFIG" | awk -F'|' -v n="$NAME" '$1==n {print; exit}')"

if [[ -z "$MATCH" ]]; then
  echo "오류: '$NAME' 미등록" >&2
  print_ops
  exit 1
fi

IFS='|' read -r name raw_path color desc sshhost <<< "$MATCH"
path="${raw_path/#\$HOME/$HOME}"

if [[ ! -d "$path" ]]; then
  echo "오류: 경로 없음: $path" >&2
  exit 1
fi

created=false
if ! tmux has-session -t "$name" 2>/dev/null; then
  tmux new-session -d -s "$name" -n claude -c "$path"
  tmux send-keys -t "$name:claude" 'claude' Enter
  tmux select-pane -t "$name:claude" -T "$name · claude"

  tmux new-window -t "$name" -n edit -c "$path"
  tmux send-keys -t "$name:edit" 'nvim .' Enter
  tmux select-pane -t "$name:edit" -T "$name · nvim"

  tmux new-window -t "$name" -n run -c "$path"
  if [[ -n "${sshhost:-}" ]]; then
    tmux send-keys -t "$name:run" "ssh $sshhost"
    tmux select-pane -t "$name:run" -T "run · ssh $sshhost (Enter 로 접속)"
  else
    tmux select-pane -t "$name:run" -T "run · local"
  fi

  tmux select-window -t "$name:claude"
  created=true
fi

if ! command -v cmux >/dev/null 2>&1; then
  echo "⚠️  cmux CLI 미설치 — tmux 세션 '$name' 만 구성. attach: tmux attach -t $name" >&2
  exit 0
fi

ref="$(CMUX_QUIET=1 cmux workspace create --name "$name" --cwd "$path" --command "tmux new-session -A -s $name" --focus true | awk '/workspace:/{print $NF}')"

if [[ -z "$ref" ]]; then
  echo "오류: cmux 워크스페이스 생성 실패" >&2
  exit 1
fi

cmux workspace-action --action set-color --color "$color" --workspace "$ref" || true
cmux workspace-action --action set-description --description "$desc" --workspace "$ref" || true
cmux workspace-action --action pin --workspace "$ref" || true

echo "✅ ops 워크스페이스 기동: $ref / tmux 세션: $name"
if [[ "$created" == true ]]; then
  echo "   win1 claude / win2 edit(nvim) / win3 run$([[ -n "${sshhost:-}" ]] && echo " (ssh $sshhost 대기)") (신규 생성)"
else
  echo "   기존 세션 재사용 (레이아웃 유지)"
fi

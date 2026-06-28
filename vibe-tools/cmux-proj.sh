#!/usr/bin/env bash
# cmux-proj.sh — per-project cmux 워크스페이스 런처
#
# 사용법:
#   cmux-proj <name>   # cmux-projects.txt 에 등록된 프로젝트 워크스페이스 기동
#   cmux-proj          # 등록된 프로젝트 목록 출력
#   cmux-proj -h        # 도움말
#
# 동작:
#   1. cmux-projects.txt 에서 name 매칭 (name|path|hexcolor|description).
#   2. tmux 세션(claude/edit/review/verify 4창) 미존재 시 생성 — edit=nvim, review=lazygit 자동 실행.
#   3. cmux 워크스페이스 생성 후 tmux attach + 메타(색/설명/pin) 적용.
#   cmux CLI 미설치 시 tmux 세션만 만들고 안내 후 종료 (graceful degradation).

set -euo pipefail

# 스크립트 자기 디렉토리 (심볼릭 링크 환경에서도 동작)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cmux-lib.sh disable=SC1091
source "$SCRIPT_DIR/cmux-lib.sh"
CONFIG="$SCRIPT_DIR/cmux-projects.txt"

NAME="${1:-}"

if [[ -z "$NAME" || "$NAME" == "-h" || "$NAME" == "--help" ]]; then
  echo "사용법: $(basename "$0") <name>" >&2
  cmux_print_projects "$CONFIG"
  exit 0
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "오류: 설정 파일이 없습니다: $CONFIG" >&2
  exit 1
fi

# name 매칭 (주석/빈 줄 무시)
MATCH="$(cmux_lookup "$CONFIG" "$NAME")"

if [[ -z "$MATCH" ]]; then
  echo "오류: '$NAME' 프로젝트를 찾을 수 없습니다." >&2
  cmux_print_projects "$CONFIG"
  exit 1
fi

IFS='|' read -r name raw_path color desc <<< "$MATCH"

# $HOME 전개 (eval 대신 안전 치환)
path="$(cmux_expand_home "$raw_path")"

if [[ ! -d "$path" ]]; then
  echo "오류: 경로가 존재하지 않습니다: $path" >&2
  exit 1
fi

# tmux 세션 미존재 시 레이아웃 생성 (리뷰 지향: claude / edit / review / verify)
session_created=false
if ! tmux has-session -t "$name" 2>/dev/null; then
  case "$name" in
    vibe-dotfiles)
      tmux new-session -d -s "$name" -n main -c "$path"
      tmux send-keys -t "$name:main" 'nvim .' Enter
      tmux split-window -h -l 30% -t "$name:main" -c "$path"
      tmux send-keys -t "$name:main" 'claude' Enter
      tmux select-pane -L -t "$name:main"
      tmux new-window -t "$name" -n review -c "$path"
      tmux send-keys -t "$name:review" 'lazygit' Enter
      tmux new-window -t "$name" -n verify -c "$path"
      tmux select-window -t "$name:main"
      layout_desc='main(nvim+claude) / review(lazygit) / verify'
      ;;
    para)
      tmux new-session -d -s "$name" -n main -c "$path"
      tmux send-keys -t "$name:main" 'nvim .' Enter
      tmux split-window -h -l 30% -t "$name:main" -c "$path"
      tmux send-keys -t "$name:main" 'claude' Enter
      tmux select-pane -L -t "$name:main"
      tmux select-window -t "$name:main"
      layout_desc='main(nvim+claude) 단일 창'
      ;;
    *)
      tmux new-session -d -s "$name" -n claude -c "$path"
      tmux new-window -t "$name" -n edit -c "$path"
      tmux send-keys -t "$name:edit" 'nvim .' Enter
      tmux new-window -t "$name" -n review -c "$path"
      tmux send-keys -t "$name:review" 'lazygit' Enter
      tmux new-window -t "$name" -n verify -c "$path"
      tmux select-window -t "$name:claude"
      layout_desc='claude / edit(nvim) / review(lazygit) / verify'
      ;;
  esac
  session_created=true
fi

# cmux CLI 미설치 — tmux 세션만 만들고 종료 (이식성 정책)
if ! cmux_has_cli; then
  echo "⚠️  cmux CLI 미설치 — tmux 세션 '$name' 만 생성했습니다." >&2
  echo "   attach: tmux attach -t $name" >&2
  exit 0
fi

# cmux 워크스페이스 생성 + 메타(색/설명/pin) 적용
ref="$(cmux_create_workspace "$name" "$path" "$color" "$desc")" || { echo "오류: cmux 워크스페이스 생성 실패" >&2; exit 1; }

echo "✅ 워크스페이스 기동 완료"
echo "   cmux workspace: $ref"
echo "   tmux 세션: $name"
if [[ "$session_created" == true ]]; then
  echo "   창 구성: $layout_desc (신규 생성)"
else
  echo "   기존 tmux 세션 재사용 (창 구성 유지)"
fi

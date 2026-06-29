#!/usr/bin/env bash
# cmux-proj-close.sh — cmux 워크스페이스 닫기 (tmux 세션은 유지)
#
# 사용법:
#   cmux-close <name>                 # 제목==name cmux 워크스페이스를 닫음 (tmux 세션 유지)
#   cmux-close <name> --kill-session  # 워크스페이스 + tmux 세션까지 완전 정리
#   cmux-close                        # 열린 워크스페이스 목록 + 사용법
#   cmux-close -h | --help            # 도움말
#
# 동작:
#   cmux 워크스페이스(래퍼)만 닫고 tmux 세션은 서버에 남긴다.
#   색·설명·경로는 cmux-projects.txt 가 SSoT 이므로 `cmux-proj <name>` 로 설정 그대로 재오픈.
#   실행 중이던 nvim/claude/lazygit 도 tmux 세션이 살아있어 그대로 복귀.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cmux-lib.sh disable=SC1091
source "$SCRIPT_DIR/cmux-lib.sh"

NAME=""
KILL_SESSION=false
for arg in "$@"; do
  case "$arg" in
    -h | --help)
      echo "사용법: $(basename "$0") <name> [--kill-session]" >&2
      cmux workspace list || true
      exit 0
      ;;
    --kill-session)
      KILL_SESSION=true
      ;;
    *)
      if [[ -z "$NAME" ]]; then NAME="$arg"; fi
      ;;
  esac
done

# tmux 세션 정리 헬퍼
kill_tmux_session() {
  if tmux has-session -t "$NAME" 2>/dev/null; then
    tmux kill-session -t "$NAME"
    echo "   tmux 세션 '$NAME' 종료 — 재오픈 시 레이아웃 신규 생성" >&2
  fi
}

if [[ -z "$NAME" ]]; then
  echo "사용법: $(basename "$0") <name> [--kill-session]" >&2
  echo "현재 열린 cmux 워크스페이스:" >&2
  cmux workspace list || true
  exit 0
fi

# cmux CLI 미설치 — tmux 세션만 처리 가능 (이식성 정책)
if ! cmux_has_cli; then
  echo "⚠️  cmux CLI 미설치 — cmux 워크스페이스는 닫을 수 없습니다." >&2
  if [[ "$KILL_SESSION" == true ]]; then kill_tmux_session; fi
  exit 0
fi

ref="$(cmux_workspace_ref_by_title "$NAME")"

if [[ -z "$ref" ]]; then
  echo "ℹ️  열린 cmux 워크스페이스 '$NAME' 가 없습니다." >&2
  if [[ "$KILL_SESSION" == true ]]; then kill_tmux_session; fi
  exit 0
fi

cmux workspace close "$ref"
echo "✅ 워크스페이스 '$NAME' ($ref) 닫음 — tmux 세션은 유지됩니다."
echo "   재오픈: cmux-proj $NAME  (cmux-projects.txt 의 색·설명·경로 그대로 복원)"

if [[ "$KILL_SESSION" == true ]]; then kill_tmux_session; fi

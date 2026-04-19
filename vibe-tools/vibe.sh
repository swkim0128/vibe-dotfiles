#!/bin/bash
# vibe.sh — PARA 방식 프로젝트 워크플로우 CLI
#
# 사용법:
#   vibe start <프로젝트폴더명> <작업명>   세션 생성 (nvim 70% + claude 30%)
#   vibe cast  <타겟세션> <"메시지">       타겟 클로드에게 원격 지시
#   vibe done                             현재 세션 종료 → para 세션 복귀

set -euo pipefail

PARA_SESSION="para"
VIBE_TOOLS="$HOME/.config/vibe-tools"
SEARCH_PATHS_FILE="$VIBE_TOOLS/sessionizer-paths.txt"

# ── 프로젝트 검색 경로 로드 ──────────────────────────────────────────────────
get_search_paths() {
  local paths=()
  if [[ -f "$SEARCH_PATHS_FILE" ]]; then
    while IFS= read -r line; do
      [[ "$line" =~ ^\s*# || -z "$line" ]] && continue
      paths+=("$(echo "$line" | sed "s|~|$HOME|g")")
    done < "$SEARCH_PATHS_FILE"
  fi
  # 기본 경로 fallback
  [[ ${#paths[@]} -eq 0 ]] && paths=("$HOME/Projects" "$HOME/project" "$HOME/work")
  printf '%s\n' "${paths[@]}"
}

CMD="${1:-}"

case "$CMD" in

  # ── start ────────────────────────────────────────────────────────────────
  start)
    PROJECT_NAME="${2:-}"
    TASK_NAME="${3:-main}"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "사용법: vibe start <프로젝트폴더명> <작업명>" >&2; exit 1
    fi

    # 프로젝트 폴더 탐색
    PROJECT_DIR=""
    while IFS= read -r search_path; do
      [[ -d "$search_path/$PROJECT_NAME" ]] && PROJECT_DIR="$search_path/$PROJECT_NAME" && break
    done < <(get_search_paths)

    if [[ -z "$PROJECT_DIR" ]]; then
      echo "오류: '$PROJECT_NAME' 프로젝트 폴더를 찾을 수 없습니다." >&2
      echo "검색 경로:" >&2; get_search_paths | sed 's/^/  /' >&2; exit 1
    fi

    # tmux 세션 이름 (콜론은 tmux 예약어라 하이픈으로 대체)
    SESSION_NAME="${PROJECT_NAME}-${TASK_NAME}"

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
      echo "세션 '$SESSION_NAME' 이미 존재 — 전환합니다."
      tmux switch-client -t "$SESSION_NAME" 2>/dev/null || tmux attach-session -t "$SESSION_NAME"
      exit 0
    fi

    # 백그라운드 세션 생성 → nvim 실행
    tmux new-session -ds "$SESSION_NAME" -c "$PROJECT_DIR"
    tmux send-keys -t "${SESSION_NAME}:.1" "nvim ." Enter

    # 오른쪽 30% 패널 → claude 실행
    tmux split-window -t "${SESSION_NAME}:.1" -h -l 30% -c "$PROJECT_DIR"
    tmux send-keys -t "${SESSION_NAME}:.2" "claude" Enter

    # nvim 패널로 포커스 복귀
    tmux select-pane -t "${SESSION_NAME}:.1"

    echo "✅ 세션 생성: $SESSION_NAME  ($PROJECT_DIR)"
    echo "   전환: tmux switch-client -t '$SESSION_NAME'"
    echo "   지시: vibe cast '$SESSION_NAME' '작업 내용'"
    ;;

  # ── cast ─────────────────────────────────────────────────────────────────
  cast)
    TARGET="${2:-}"
    MESSAGE="${3:-}"

    if [[ -z "$TARGET" || -z "$MESSAGE" ]]; then
      echo "사용법: vibe cast <타겟세션> <\"메시지\">" >&2; exit 1
    fi

    if ! tmux has-session -t "$TARGET" 2>/dev/null; then
      echo "오류: 세션 '$TARGET' 을 찾을 수 없습니다." >&2
      echo "현재 세션:" >&2; tmux list-sessions -F '  #{session_name}' >&2; exit 1
    fi

    # claude 실행 중인 패널 탐색 → 없으면 마지막 패널
    CLAUDE_PANE=$(tmux list-panes -t "$TARGET" -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
      | awk '/claude/{print $1}' | head -1)
    [[ -z "$CLAUDE_PANE" ]] && \
      CLAUDE_PANE=$(tmux list-panes -t "$TARGET" -F '#{pane_id}' 2>/dev/null | tail -1)

    # 호출자 패널 ID (콜백용)
    CALLER_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")

    PROMPT="$MESSAGE"
    if [[ -n "$CALLER_PANE" ]]; then
      PROMPT="${MESSAGE}

[시스템 지시사항] 작업이 끝나면 반드시 터미널에서 다음 명령어를 실행하여 완료를 보고할 것:
~/.config/vibe-tools/claude-callback.sh '${CALLER_PANE}' '작업 결과 요약'"
    fi

    tmux send-keys -t "$CLAUDE_PANE" "$PROMPT" Enter
    echo "📡 전송 완료 → 세션: $TARGET  패널: $CLAUDE_PANE"
    ;;

  # ── done ─────────────────────────────────────────────────────────────────
  done)
    CURRENT_SESSION=$(tmux display-message -p '#{session_name}')

    if [[ "$CURRENT_SESSION" == "$PARA_SESSION" ]]; then
      echo "이미 '$PARA_SESSION' 세션입니다."; exit 0
    fi

    # para 세션이 없으면 새로 생성
    if ! tmux has-session -t "$PARA_SESSION" 2>/dev/null; then
      echo "⚠️  '$PARA_SESSION' 세션 없음 → 새로 생성합니다."
      tmux new-session -ds "$PARA_SESSION"
    fi

    tmux switch-client -t "$PARA_SESSION"
    tmux kill-session -t "$CURRENT_SESSION"
    echo "✅ '$CURRENT_SESSION' 종료 → '$PARA_SESSION' 복귀"
    ;;

  # ── help ─────────────────────────────────────────────────────────────────
  *)
    cat <<'HELP'
Vibe Coding CLI — PARA 워크플로우 관리

사용법:
  vibe start <프로젝트폴더명> <작업명>   세션 생성 (nvim 70% + claude 30%)
  vibe cast  <타겟세션> <"메시지">       타겟 세션 클로드에게 원격 지시 + 콜백
  vibe done                             현재 세션 종료 후 para 세션 복귀

Tmux 단축키:
  Prefix + p   para 세션으로 즉시 이동
  Prefix + d   원격 지시 입력창 (vibe cast)
  Prefix + x   현재 세션 종료 후 para 복귀 (vibe done)

예시:
  vibe start my-app feature-login
  vibe cast my-app-feature-login "로그인 API 유닛 테스트 작성해줘"
  vibe done
HELP
    ;;
esac

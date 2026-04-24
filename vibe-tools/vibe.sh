#!/bin/bash
# vibe.sh — PARA 방식 프로젝트 워크플로우 CLI
#
# 사용법:
#   vibe main                              메인 지휘소(para) 세션 생성 [nvim 70% + claude 30%]
#   vibe start <프로젝트명> <절대경로>      서브 프로젝트 현장 세션 생성 [nvim 70% + claude 30%]
#   vibe cast  <타겟세션> <"메시지">        타겟 클로드에게 원격 지시
#   vibe done                              현재 세션 종료 → para 세션 복귀

set -euo pipefail

PARA_SESSION="para"
VIBE_TOOLS="$HOME/.config/vibe-tools"

CMD="${1:-}"

case "$CMD" in

  # ── main ─────────────────────────────────────────────────────────────────
  main)
    if tmux has-session -t "$PARA_SESSION" 2>/dev/null; then
      echo "세션 '$PARA_SESSION' 이미 존재 — 전환합니다."
      tmux switch-client -t "$PARA_SESSION" 2>/dev/null || tmux attach-session -t "$PARA_SESSION"
      exit 0
    fi

    # 백그라운드 세션 생성 (윈도우 이름: control-tower)
    tmux new-session -d -s "$PARA_SESSION" -n "control-tower"

    # 왼쪽 패널(1번): nvim
    tmux send-keys -t "${PARA_SESSION}:control-tower.1" "nvim" Enter
    tmux select-pane -t "${PARA_SESSION}:control-tower.1" -T "📝 Main Note"

    # 오른쪽 패널(2번, 30%): claude
    tmux split-window -t "${PARA_SESSION}:control-tower.1" -h -p 30
    tmux send-keys -t "${PARA_SESSION}:control-tower.2" "claude" Enter
    tmux select-pane -t "${PARA_SESSION}:control-tower.2" -T "👑 Main Agent"

    # nvim 패널로 포커스 복귀
    tmux select-pane -t "${PARA_SESSION}:control-tower.1"

    echo "✅ 메인 세션 생성: $PARA_SESSION"
    tmux switch-client -t "$PARA_SESSION" 2>/dev/null || tmux attach-session -t "$PARA_SESSION"
    ;;

  # ── start ────────────────────────────────────────────────────────────────
  start)
    PROJECT_NAME="${2:-}"
    PROJECT_DIR="${3:-}"

    if [[ -z "$PROJECT_NAME" || -z "$PROJECT_DIR" ]]; then
      echo "사용법: vibe start <프로젝트명> <절대경로>" >&2; exit 1
    fi

    PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"

    if [[ ! -d "$PROJECT_DIR" ]]; then
      echo "오류: 경로가 존재하지 않습니다: $PROJECT_DIR" >&2; exit 1
    fi

    if tmux has-session -t "$PROJECT_NAME" 2>/dev/null; then
      echo "세션 '$PROJECT_NAME' 이미 존재 — 전환합니다."
      tmux switch-client -t "$PROJECT_NAME" 2>/dev/null || tmux attach-session -t "$PROJECT_NAME"
      exit 0
    fi

    # 백그라운드 세션 생성 (윈도우 이름: workspace)
    tmux new-session -d -s "$PROJECT_NAME" -n "workspace" -c "$PROJECT_DIR"

    # 왼쪽 패널(1번): nvim
    tmux send-keys -t "${PROJECT_NAME}:workspace.1" "nvim ." Enter
    tmux select-pane -t "${PROJECT_NAME}:workspace.1" -T "💻 Sub Editor"

    # 오른쪽 패널(2번, 30%): claude
    tmux split-window -t "${PROJECT_NAME}:workspace.1" -h -p 30 -c "$PROJECT_DIR"
    tmux send-keys -t "${PROJECT_NAME}:workspace.2" "claude" Enter
    tmux select-pane -t "${PROJECT_NAME}:workspace.2" -T "🤖 Sub Agent"

    # nvim 패널로 포커스 복귀
    tmux select-pane -t "${PROJECT_NAME}:workspace.1"

    echo "✅ 서브 세션 생성: $PROJECT_NAME  ($PROJECT_DIR)"
    tmux switch-client -t "$PROJECT_NAME" 2>/dev/null || tmux attach-session -t "$PROJECT_NAME"
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
  vibe main                              메인 지휘소(para) 세션 생성 [nvim 70% + claude 30%]
  vibe start <프로젝트명> <절대경로>      서브 프로젝트 현장 세션 생성 [nvim 70% + claude 30%]
  vibe cast  <타겟세션> <"메시지">        타겟 세션 클로드에게 원격 지시 + 콜백
  vibe done                              현재 세션 종료 후 para 세션 복귀

Tmux 단축키:
  Prefix + p   para 세션으로 즉시 이동
  Prefix + x   현재 세션 종료 후 para 복귀 (vibe done)

예시:
  vibe main
  vibe start my-app ~/Project/my-app
  vibe cast my-app "로그인 API 유닛 테스트 작성해줘"
  vibe done
HELP
    ;;
esac

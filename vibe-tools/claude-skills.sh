#!/bin/bash
set -u

PROMPT_DIR="$HOME/.config/vibe-tools/prompts"
SKILL_DIR="$HOME/.claude/skills"

# 팝업이 바로 닫히지 않도록 키 입력까지 대기하며 에러 출력
die() {
    echo ""
    echo "❌ $1"
    echo ""
    echo "아무 키나 누르면 닫힙니다..."
    read -r -n 1
    exit 1
}

# 1. tmux 서버 전체에서 claude 실행 패널 수집 (-a: 모든 세션/윈도우 대상)
declare -a CANDIDATES=()
while IFS='|' read -r pane_id pane_tty pane_target; do
    if ps -t "$pane_tty" 2>/dev/null | grep -iq "[c]laude"; then
        CANDIDATES+=("$pane_id|$pane_target")
    fi
done < <(tmux list-panes -a -F '#{pane_id}|#{pane_tty}|#{session_name}:#{window_index}.#{pane_index}')

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    die "클로드 코드가 실행 중인 패널을 찾을 수 없습니다. 다른 패널에서 'claude' 를 실행한 후 다시 시도하세요."
fi

# 2. 단일 매칭은 자동 선택, 복수면 fzf 로 선택
if [[ ${#CANDIDATES[@]} -eq 1 ]]; then
    TARGET_PANE="${CANDIDATES[0]%%|*}"
else
    selected=$(printf '%s\n' "${CANDIDATES[@]}" | fzf \
      --prompt="🎯 전송할 Claude 패널 선택 > " \
      --with-nth=2 --delimiter='|' \
      --height=40% --layout=reverse --border=rounded)
    [[ -z "$selected" ]] && exit 0
    TARGET_PANE="${selected%%|*}"
fi

# 3. 메뉴 구성 — 프롬프트 + 스킬 병합
#   라인 형식: "표시용 라벨|종류|경로 또는 스킬명"
#     종류: prompt | skill
declare -a ITEMS=()

if [[ -d "$PROMPT_DIR" ]]; then
    while IFS= read -r f; do
        name="${f%.txt}"
        ITEMS+=("📝 ${name}|prompt|${PROMPT_DIR}/${f}")
    done < <(cd "$PROMPT_DIR" 2>/dev/null && ls *.txt 2>/dev/null | sort)
fi

if [[ -d "$SKILL_DIR" ]]; then
    while IFS= read -r d; do
        # SKILL.md 없는 디렉토리는 스킬이 아님 (플레인 폴더/깨진 심링크 제외)
        [[ -f "$d/SKILL.md" ]] || continue
        name=$(basename "$d")
        ITEMS+=("🎯 ${name}|skill|${d}/SKILL.md")
    done < <(find -L "$SKILL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
fi

if [[ ${#ITEMS[@]} -eq 0 ]]; then
    die "사용 가능한 프롬프트/스킬이 없습니다. $PROMPT_DIR 에 .txt 파일을 추가하거나 $SKILL_DIR 에 스킬을 설치하세요."
fi

# 4. fzf 선택 (프리뷰: 프롬프트 전체 또는 SKILL.md 상단)
SELECTED=$(printf '%s\n' "${ITEMS[@]}" | fzf \
  --prompt="🤖 프롬프트 / 스킬 선택 > " \
  --with-nth=1 --delimiter='|' \
  --preview 'path=$(echo {} | awk -F"|" "{print \$3}"); head -80 "$path"' \
  --preview-window=right:60%:wrap \
  --height=100% --layout=reverse --border=rounded)

[[ -z "$SELECTED" ]] && exit 0

KIND=$(echo "$SELECTED" | awk -F'|' '{print $2}')
ARG=$(echo "$SELECTED" | awk -F'|' '{print $3}')

# 5. 종류별 전송 처리
#    prompt → 파일 내용 전체 + Enter (즉시 실행)
#    skill  → "<skill-name> 스킬 실행해줘: " 뒤에 커서만 두고 Enter 없이 대기
#             (사용자가 구체 지시 입력 후 직접 Enter)
if [[ "$KIND" == "prompt" ]]; then
    CONTENT=$(cat "$ARG")
    tmux send-keys -l -t "$TARGET_PANE" "$CONTENT"
    tmux send-keys -t "$TARGET_PANE" C-m
else
    SKILL_NAME=$(basename "$(dirname "$ARG")")
    TRIGGER="${SKILL_NAME} 스킬 실행해줘: "
    tmux send-keys -l -t "$TARGET_PANE" "$TRIGGER"
    # Enter 없음 — 사용자가 상세 지시를 덧붙이고 직접 전송
fi

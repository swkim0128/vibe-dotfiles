#!/bin/bash
set -u

PLUGIN_CACHE="$HOME/.claude/plugins/cache"
PROMPT_DIR="$PLUGIN_CACHE/swkim0128/vibe-config/prompts"
SKILL_DIR="$HOME/.claude/skills"

# ITEMS 목록 캐시 — 플러그인 스킬 find 가 무거워 첫 실행 이후에는 재사용
ITEMS_CACHE_DIR="$HOME/.cache/vibe-tools"
ITEMS_CACHE_FILE="$ITEMS_CACHE_DIR/claude-skills-items.cache"

# --refresh 플래그: 캐시 강제 재빌드 후 평상시와 동일하게 진행
FORCE_REFRESH=0
if [[ "${1:-}" == "--refresh" ]]; then
    FORCE_REFRESH=1
    shift
fi

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

# 3. 메뉴 구성 — 프롬프트 + 스킬 병합 (캐시 사용)
#   캐시 라인 형식: "표시용 라벨|종류|경로 또는 스킬명"
#     종류: prompt | skill | plugin-skill
build_items_cache() {
    mkdir -p "$ITEMS_CACHE_DIR" || return 1
    local tmp
    tmp=$(mktemp "$ITEMS_CACHE_FILE.XXXXXX") || return 1

    {
        if [[ -d "$PROMPT_DIR" ]]; then
            while IFS= read -r f; do
                local name="${f%.txt}"
                echo "📝 ${name}|prompt|${PROMPT_DIR}/${f}"
            done < <(cd "$PROMPT_DIR" 2>/dev/null && ls *.txt 2>/dev/null | sort)
        fi

        if [[ -d "$SKILL_DIR" ]]; then
            while IFS= read -r d; do
                # SKILL.md 없는 디렉토리는 스킬이 아님 (플레인 폴더/깨진 심링크 제외)
                [[ -f "$d/SKILL.md" ]] || continue
                local name
                name=$(basename "$d")
                echo "🎯 ${name}|skill|${d}/SKILL.md"
            done < <(find -L "$SKILL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
        fi

        # 플러그인 스킬 — 경로: $PLUGIN_CACHE/<marketplace>/<plugin>/<version>/skills/<skill>/SKILL.md
        # 동일 plugin:skill 이 여러 버전으로 설치된 경우 최신 버전 1개만 노출 (sort -V -r 로 우선)
        if [[ -d "$PLUGIN_CACHE" ]]; then
            # bash 3.2 (macOS 기본) 호환: 연관배열(declare -A) 대신 개행 구분 문자열로 중복 체크
            local seen=$'\n'
            local skill_md skill_dir skill_name plugin_name key
            while IFS= read -r skill_md; do
                skill_dir=$(dirname "$skill_md")
                skill_name=$(basename "$skill_dir")
                plugin_name=$(basename "$(dirname "$(dirname "$(dirname "$skill_dir")")")")
                key="${plugin_name}:${skill_name}"
                case "$seen" in
                    *$'\n'"$key"$'\n'*) continue ;;
                esac
                seen="${seen}${key}"$'\n'
                echo "🔌 ${key}|plugin-skill|${skill_md}"
            done < <(find -L "$PLUGIN_CACHE" -path "*/skills/*/SKILL.md" -type f 2>/dev/null | sort -V -r)
        fi
    } > "$tmp"

    mv "$tmp" "$ITEMS_CACHE_FILE"
}

if [[ $FORCE_REFRESH -eq 1 ]]; then
    rm -f "$ITEMS_CACHE_FILE"
fi

if [[ ! -f "$ITEMS_CACHE_FILE" ]]; then
    echo "📦 프롬프트/스킬 목록 캐시 생성 중... (최초 1회)"
    build_items_cache || die "캐시 생성 실패: $ITEMS_CACHE_DIR 에 쓰기 권한이 있는지 확인하세요."
fi

declare -a ITEMS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && ITEMS+=("$line")
done < "$ITEMS_CACHE_FILE"

if [[ ${#ITEMS[@]} -eq 0 ]]; then
    die "사용 가능한 프롬프트/스킬이 없습니다. $PROMPT_DIR 에 .txt 파일을 추가하거나 $SKILL_DIR 에 스킬을 설치한 뒤 '$0 --refresh' 로 갱신하세요."
fi

# 4. fzf 선택 (맨 위 '새로 고침' 항목 포함, 프리뷰는 빈 경로 가드)
REFRESH_ITEM="🔄 [목록 새로 고침]|refresh|"

SELECTED=$(printf '%s\n%s\n' "$REFRESH_ITEM" "$(printf '%s\n' "${ITEMS[@]}")" | fzf \
  --prompt="🤖 프롬프트 / 스킬 선택 > " \
  --with-nth=1 --delimiter='|' \
  --preview 'p=$(echo {} | awk -F"|" "{print \$3}"); [ -n "$p" ] && head -80 "$p" || echo "캐시를 새로 고칩니다."' \
  --preview-window=right:60%:wrap \
  --height=100% --layout=reverse --border=rounded)

[[ -z "$SELECTED" ]] && exit 0

KIND=$(echo "$SELECTED" | awk -F'|' '{print $2}')
ARG=$(echo "$SELECTED" | awk -F'|' '{print $3}')

# 새로 고침 선택 시: 캐시 삭제 후 스크립트 재실행
if [[ "$KIND" == "refresh" ]]; then
    rm -f "$ITEMS_CACHE_FILE"
    exec "$0" "$@"
fi

# 5. 종류별 전송 처리
#    prompt → 파일 내용 전체 + Enter (즉시 실행)
#    skill  → "<skill-name> 스킬 실행해줘: " 뒤에 커서만 두고 Enter 없이 대기
#             (사용자가 구체 지시 입력 후 직접 Enter)
if [[ "$KIND" == "prompt" ]]; then
    CONTENT=$(cat "$ARG")
    tmux send-keys -l -t "$TARGET_PANE" "$CONTENT"
    tmux send-keys -t "$TARGET_PANE" C-m
elif [[ "$KIND" == "plugin-skill" ]]; then
    # ARG = .../skills/<skill>/SKILL.md → plugin:skill 형식으로 재구성
    skill_dir=$(dirname "$ARG")
    skill_name=$(basename "$skill_dir")
    plugin_name=$(basename "$(dirname "$(dirname "$(dirname "$skill_dir")")")")
    TRIGGER="${plugin_name}:${skill_name} 스킬 실행해줘: "
    tmux send-keys -l -t "$TARGET_PANE" "$TRIGGER"
    # Enter 없음 — 사용자가 상세 지시를 덧붙이고 직접 전송
else
    SKILL_NAME=$(basename "$(dirname "$ARG")")
    TRIGGER="${SKILL_NAME} 스킬 실행해줘: "
    tmux send-keys -l -t "$TARGET_PANE" "$TRIGGER"
    # Enter 없음 — 사용자가 상세 지시를 덧붙이고 직접 전송
fi

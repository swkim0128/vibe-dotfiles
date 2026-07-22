#!/bin/bash
# sync-skills-to-agents.sh — Skills.sh agent skill sync for Antigravity (agy) & Claude Code

set -euo pipefail

CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
MANIFEST_FILE="$AGENTS_SKILLS_DIR/.marketplace-manifest.txt"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/swkim0128/skills"
FALLBACK_CONFIG_DIR="$HOME/Project/vibe-ai-config/skills"
SKILLS_REPO="swkim0128/vibe-ai-config"

mkdir -p "$AGENTS_SKILLS_DIR"
mkdir -p "$CLAUDE_SKILLS_DIR"
mkdir -p "$HOME/.local/bin"

echo "🔄 Skills.sh 글로벌 에이전트 스킬 동기화 시작 (Antigravity agy + Claude Code)..."

# 1. skills CLI 래퍼 생성 (~/.local/bin/skills)
if [ ! -f "$HOME/.local/bin/skills" ]; then
    cat <<'EOF' > "$HOME/.local/bin/skills"
#!/bin/bash
exec npx -y skills "$@"
EOF
    chmod +x "$HOME/.local/bin/skills"
    echo "  [+] skills CLI 래퍼 생성 완료 (~/.local/bin/skills)"
fi

# 소스 디렉터리 결정 (P3: 스킬 정본은 레포 최상위 skills/ — 마켓플레이스 우선, 레포 폴백)
SRC_DIR=""
if [ -d "$MARKETPLACE_DIR" ]; then
    SRC_DIR="$MARKETPLACE_DIR"
elif [ -d "$FALLBACK_CONFIG_DIR" ]; then
    SRC_DIR="$FALLBACK_CONFIG_DIR"
fi

# 기존 매니페스트 로드 (이전에 마켓플레이스에서 동기화했던 스킬 목록)
PREV_MANIFEST=""
if [ -f "$MANIFEST_FILE" ]; then
    PREV_MANIFEST=$(cat "$MANIFEST_FILE")
fi

# 신규 매니페스트 생성용 임시 파일
NEW_MANIFEST_FILE=$(mktemp)

MP_SKILL_NAMES=" "

if [ -n "$SRC_DIR" ] && [ -d "$SRC_DIR" ]; then
    while IFS= read -r skill_file; do
        [ -n "$skill_file" ] || continue
        skill_dir=$(dirname "$skill_file")
        skill_name=$(basename "$skill_dir")
        MP_SKILL_NAMES="${MP_SKILL_NAMES}${skill_name} "
        echo "$skill_name" >> "$NEW_MANIFEST_FILE"

        # ~/.agents/skills 로 최신 복사 (SSoT 최신화)
        rm -rf "${AGENTS_SKILLS_DIR:?}/${skill_name:?}"
        cp -r "$skill_dir" "$AGENTS_SKILLS_DIR/$skill_name"
        echo "  [📦] 마켓플레이스 스킬 갱신: $skill_name -> ~/.agents/skills/$skill_name"
    done < <(find "$SRC_DIR" -type f -name "SKILL.md" 2>/dev/null || true)
fi

is_mp_skill() {
    local target="$1"
    [[ "$MP_SKILL_NAMES" == *" ${target} "* ]]
}

# 3. 매니페스트 기반 안전한 고아 스킬 정리 (Prune) — ~/.agents/skills 한정:
# 과거 매니페스트에 등록되었으나 현재 최상위 skills/ 소스에서 제거된 스킬만 prune 처리.
# 매니페스트에 존재하지 않는 사용자의 개인 로컬 스킬은 100% 보존.
# ~/.claude/skills 는 npx skills add 가 관리하므로 이 스크립트가 직접 prune 하지 않는다.
if [ -n "$PREV_MANIFEST" ]; then
    for old_skill in $PREV_MANIFEST; do
        [ -n "$old_skill" ] || continue
        if ! is_mp_skill "$old_skill"; then
            echo "  [🧹] 폐기 스킬 정리(Prune - 매니페스트 대상): $old_skill (from ~/.agents/skills)"
            rm -rf "${AGENTS_SKILLS_DIR:?}/${old_skill:?}"
        fi
    done
fi

# 신규 매니페스트 저장
if [ -f "$NEW_MANIFEST_FILE" ]; then
    sort -u "$NEW_MANIFEST_FILE" > "$MANIFEST_FILE"
    rm -f "$NEW_MANIFEST_FILE"
fi

# 4. Claude Code 스킬 배포 — P3: npx skills add 위임 (플러그인 이중 로드 위험 제거로 "Claude 금지" 규칙 폐기).
# ~/.claude/skills 심링크는 skills CLI 가 관리하며, 이 스크립트는 ~/.claude/skills 를 직접 생성/삭제하지 않는다.
if command -v npx >/dev/null 2>&1; then
    echo "  [🔗] Claude Code 스킬 배포 위임: npx skills add $SKILLS_REPO --all -g -y"
    npx -y skills add "$SKILLS_REPO" --all -g -y || echo "  [⚠️] npx skills add 실패 — Claude 스킬 배포 건너뜀 (Antigravity 동기화는 완료)"
else
    echo "  [⚠️] npx 미존재 — Claude 스킬 배포(npx skills add) 건너뜀"
fi

echo "✅ Skills.sh 글로벌 동기화 완료! (Antigravity 복사 + Claude npx 위임)"

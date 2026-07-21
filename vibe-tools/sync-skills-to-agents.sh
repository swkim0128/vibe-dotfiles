#!/bin/bash
# sync-skills-to-agents.sh — Skills.sh agent skill sync for Antigravity (agy) & Claude Code

set -euo pipefail

CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
PLUGIN_CACHE_DIR="$HOME/.claude/plugins/cache/swkim0128"

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

# 2. 마켓플레이스 캐시(swkim0128) 스킬을 ~/.agents/skills 로 정본 동기화
if [ -d "$PLUGIN_CACHE_DIR" ]; then
    find "$PLUGIN_CACHE_DIR" -type f -name "SKILL.md" | while read -r skill_file; do
        skill_dir=$(dirname "$skill_file")
        skill_name=$(basename "$skill_dir")
        
        if [ ! -d "$AGENTS_SKILLS_DIR/$skill_name" ]; then
            cp -r "$skill_dir" "$AGENTS_SKILLS_DIR/$skill_name"
            echo "  [📦] 마켓플레이스 스킬 동기화: $skill_name -> ~/.agents/skills/$skill_name"
        fi
    done
fi

# 3. ~/.agents/skills 스킬들을 ~/.claude/skills 에 심링크 연결
for item in "$AGENTS_SKILLS_DIR"/*; do
    [ -e "$item" ] || continue
    name=$(basename "$item")

    if [ -d "$item" ]; then
        rm -rf "${CLAUDE_SKILLS_DIR:?}/${name:?}"
        ln -sfn "$AGENTS_SKILLS_DIR/$name" "$CLAUDE_SKILLS_DIR/$name"
    fi
done

echo "✅ Skills.sh 글로벌 동기화 완료! (Antigravity CLI agy + Claude Code 매핑)"

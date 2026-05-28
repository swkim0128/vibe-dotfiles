#!/usr/bin/env bash
# PostToolUse:Write|Edit hook
# claude-config/CLAUDE-*.md 또는 hooks/ 변경 시
# install.sh의 4배열(ALWAYS_FILES/ONDEMAND_FILES/IMPORTS/VERIFY_FILES)과
# 실제 파일 목록의 sync 여부를 검증. 불일치 시 stderr 경고만 출력.
# (자동 install.sh 실행은 하지 않음 — 사용자가 직접 ./install.sh 재실행)

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

[[ -n "$FILE_PATH" ]] || exit 0

case "$FILE_PATH" in
    */vibe-claude-plugin/claude-config/CLAUDE-*.md) ;;
    */vibe-claude-plugin/claude-config/hooks/*) ;;
    *) exit 0 ;;
esac

REPO_ROOT="/Users/eunsol/Project/vibe-claude-plugin"
INSTALL_SH="$REPO_ROOT/install.sh"
CONFIG_DIR="$REPO_ROOT/claude-config"

[[ -f "$INSTALL_SH" ]] || exit 0
[[ -d "$CONFIG_DIR" ]] || exit 0

ACTUAL="$(find "$CONFIG_DIR" -maxdepth 1 -name 'CLAUDE-*.md' -type f -exec basename {} \; | sort)"
EXPECTED="$(grep -oE 'CLAUDE-[a-zA-Z0-9_-]+\.md' "$INSTALL_SH" | sort -u)"

MISSING_IN_INSTALL="$(comm -23 <(printf '%s\n' "$ACTUAL") <(printf '%s\n' "$EXPECTED"))"
EXTRA_IN_INSTALL="$(comm -13 <(printf '%s\n' "$ACTUAL") <(printf '%s\n' "$EXPECTED"))"

if [[ -n "$MISSING_IN_INSTALL" || -n "$EXTRA_IN_INSTALL" ]]; then
    {
        echo ""
        echo "⚠️  vibe-claude-plugin/install.sh ↔ claude-config/ sync 불일치 감지"
        if [[ -n "$MISSING_IN_INSTALL" ]]; then
            echo "  실파일 존재, install.sh 배열에 누락:"
            printf '%s\n' "$MISSING_IN_INSTALL" | sed 's/^/    - /'
        fi
        if [[ -n "$EXTRA_IN_INSTALL" ]]; then
            echo "  install.sh 배열에 등록, 실파일 없음:"
            printf '%s\n' "$EXTRA_IN_INSTALL" | sed 's/^/    - /'
        fi
        echo "  → install.sh의 ALWAYS_FILES / ONDEMAND_FILES / IMPORTS / VERIFY_FILES 배열 갱신 후"
        echo "    cd $REPO_ROOT"
        echo "    ./install.sh"
        echo ""
    } >&2
fi

exit 0

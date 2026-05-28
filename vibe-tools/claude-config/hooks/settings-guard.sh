#!/bin/bash
# PreToolUse:Write hook — settings.work.json 핵심 섹션 보호
# Write 도구로 settings.work.json을 덮어쓸 때 필수 섹션 누락 시 차단

FILE_PATH=$(jq -r '.tool_input.file_path // ""' 2>/dev/null)
CONTENT=$(jq -r '.tool_input.content // ""' 2>/dev/null)

# settings.work.json 파일이 아니면 통과
if ! echo "$FILE_PATH" | grep -qE "settings\.work\.json$"; then
  exit 0
fi

# 필수 섹션 존재 여부 검사
MISSING=()
for KEY in "hooks" "worktree" "permissions"; do
  if ! echo "$CONTENT" | jq -e ".$KEY" > /dev/null 2>&1; then
    MISSING+=("$KEY")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  printf '{"continue":false,"stopReason":"❌ settings.work.json 쓰기 차단\\n\\n누락된 필수 섹션: %s\\n\\nsettings.work.json은 Write로 전체 재작성하지 말고 Edit 도구로 특정 필드만 수정하세요."}\n' \
    "$(IFS=', '; echo "${MISSING[*]}")"
  exit 0
fi

exit 0

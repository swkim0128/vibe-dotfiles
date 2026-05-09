#!/bin/bash
# PreToolUse hook — git commit 전 PHP 문법 검사
# 스테이징된 .php 파일에 php -l 실행, 하나라도 실패하면 커밋 차단

COMMAND=$(jq -r '.tool_input.command // ""' 2>/dev/null)

# git commit 명령이 아니면 통과
if ! echo "$COMMAND" | grep -qE "(^|&&|;|\|)\s*git commit"; then
  exit 0
fi

# php 명령 존재 여부 확인
if ! command -v php > /dev/null 2>&1; then
  exit 0
fi

# 스테이징된 PHP 파일 목록
STAGED_PHP=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep '\.php$')
if [[ -z "$STAGED_PHP" ]]; then
  exit 0
fi

FAILED=()
while IFS= read -r file; do
  if [[ -f "$file" ]] && ! php -l "$file" > /dev/null 2>&1; then
    FAILED+=("$file")
  fi
done <<< "$STAGED_PHP"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '{"continue":false,"stopReason":"❌ PHP 문법 오류 — 커밋 차단\\n\\n오류 파일:\\n%s\\n\\nphp -l <파일> 로 확인 후 수정하세요."}\n' \
    "$(printf '  - %s\n' "${FAILED[@]}")"
  exit 0
fi

exit 0

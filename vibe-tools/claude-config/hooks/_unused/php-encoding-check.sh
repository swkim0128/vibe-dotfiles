#!/usr/bin/env bash
# PHP 파일 EUC-KR 인코딩 감지 훅
# PreToolUse: Read|Edit|Write 에서 .php 파일 대상으로 실행
# EUC-KR 감지 시 legacy-suite:file-encoding-converter 스킬 사용을 강제
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# PHP 파일이 아니거나 파일이 없으면 통과
if [[ "$FILE_PATH" != *.php ]] || [[ -z "$FILE_PATH" ]] || [[ ! -f "$FILE_PATH" ]]; then
    printf '{"continue":true}\n'
    exit 0
fi

# 인코딩 확인 (macOS: EUC-KR → ISO-8859 또는 Non-ISO extended-ASCII)
ENCODING=$(file "$FILE_PATH" 2>/dev/null || echo "")

if echo "$ENCODING" | grep -qiE "UTF-8|ASCII"; then
    printf '{"continue":true}\n'
    exit 0
fi

# EUC-KR 감지 — 스킬 사용 지시 후 차단
REASON=$(printf '🚫 EUC-KR PHP 파일 감지: %s\n\n작업 전 반드시 아래 스킬을 먼저 실행하세요:\n\n  /legacy-suite:file-encoding-converter\n\n스킬이 EUC-KR → UTF-8 변환 및 작업 후 재변환을 안내합니다.' \
    "$FILE_PATH")

jq -n --arg reason "$REASON" '{"continue":false,"stopReason":$reason}'

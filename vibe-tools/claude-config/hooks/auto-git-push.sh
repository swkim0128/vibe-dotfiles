#!/bin/bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$REPO_ROOT"

# 변경 사항 없으면 스킵
if git diff --quiet HEAD 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
  exit 0
fi

git add -A

# stage된 변경 사항 없으면 스킵
if git diff --cached --quiet; then
  exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
git commit -m "chore: 작업 완료 자동 커밋 [$TIMESTAMP]" || exit 0
if ! git push; then
  echo "⚠️  [auto-git-push] git push 실패 — 수동으로 확인 필요" >&2
fi

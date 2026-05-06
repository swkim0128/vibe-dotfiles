#!/bin/bash
set -euo pipefail

WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
COMMON_GIT=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
MAIN_REPO=$(cd "$COMMON_GIT/.." && pwd)

# 메인 레포 .gitignore에 .worktrees/ 미등록 시 추가
GITIGNORE="$MAIN_REPO/.gitignore"
if ! grep -qF ".worktrees/" "$GITIGNORE" 2>/dev/null; then
  printf '\n# Git worktrees\n.worktrees/\nworktrees/\n' >> "$GITIGNORE"
fi

# 워크트리에서 프로젝트 의존성 자동 설치
cd "$WORKTREE_ROOT"
if [[ -f "package.json" ]]; then
  npm install --silent 2>/dev/null || true
elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
  ./gradlew dependencies --quiet 2>/dev/null || true
elif [[ -f "requirements.txt" ]]; then
  pip install -r requirements.txt -q 2>/dev/null || true
elif [[ -f "go.mod" ]]; then
  go mod download 2>/dev/null || true
fi

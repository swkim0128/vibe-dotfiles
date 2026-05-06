#!/bin/bash
# issue-start.sh — 이슈 브랜치 생성 및 체크아웃 자동화
#
# 사용법:
#   issue-start.sh <이슈번호>          # 예: issue-start.sh DWDEV-1234
#   issue-start.sh <이슈번호> [타입]   # 타입 기본값: feature

set -euo pipefail

ISSUE="${1:-}"
TYPE="${2:-feature}"

if [[ -z "$ISSUE" ]]; then
  echo "사용법: $(basename "$0") <이슈번호> [feature|fix|hotfix]" >&2
  exit 1
fi

BRANCH="${TYPE}/${ISSUE}"

# git 레포 확인
git rev-parse --git-dir > /dev/null 2>&1 || { echo "오류: git 레포지토리가 아닙니다." >&2; exit 1; }

# develop 최신화
echo "📥 develop 브랜치 최신화 중..."
git fetch origin
git checkout develop
git pull origin develop

# 브랜치 중복 체크
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "⚠️  브랜치 '$BRANCH' 이미 존재 — 체크아웃합니다."
  git checkout "$BRANCH"
else
  echo "🌿 브랜치 생성: $BRANCH"
  git checkout -b "$BRANCH" develop
fi

echo ""
echo "✅ 준비 완료"
echo "   브랜치: $(git branch --show-current)"
echo "   다음: EnterWorktree 로 격리 작업 공간을 생성하세요."

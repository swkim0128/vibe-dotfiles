#!/usr/bin/env bash
# .claude/docs/ 초기화 — 프로젝트 참조 문서 디렉터리 자동 생성

set -euo pipefail

# git 저장소 또는 이미 .claude 디렉터리가 있는 프로젝트에서만 실행
if [[ ! -d ".git" && ! -d ".claude" ]]; then
  exit 0
fi

DOCS_DIR=".claude/docs"

if [[ ! -d "$DOCS_DIR" ]]; then
  mkdir -p "$DOCS_DIR"
  echo '{"systemMessage": ".claude/docs/ 디렉터리가 생성되었습니다. 프로젝트 참조 문서를 이 경로에 추가하고 CLAUDE.md에서 참조하세요."}'
fi

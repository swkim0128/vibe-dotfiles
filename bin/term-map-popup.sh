#!/bin/bash
set -euo pipefail

# AI 명령 지도는 설치된 하네스의 공개 명령으로 연다.
if ! command -v vibe >/dev/null 2>&1; then
  printf 'AI 명령 지도에는 vibe가 필요합니다. 하네스 설치 후 실행: vibe terminal map\n' >&2
  exit 2
fi
exec vibe terminal map

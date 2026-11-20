#!/usr/bin/env bash
# 일반 터미널 CLI. PATH 링크와 소스 직호출 모두 같은 실행기를 사용한다.
set -euo pipefail
source_path="${BASH_SOURCE[0]}"
while [[ -L "$source_path" ]]; do
  source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
  source_path="$(readlink "$source_path")"
  [[ "$source_path" == /* ]] || source_path="$source_dir/$source_path"
done
source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
exec "${VIBE_ROUTE_PYTHON:-python3}" "$source_dir/terminal_runtime.py" "$@"

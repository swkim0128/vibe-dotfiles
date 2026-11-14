#!/bin/bash
set -euo pipefail

# 기존 하네스 설치 링크로 정본 위치를 찾는다. 개인 경로를 고정하지 않는다.
vibe_script=$(readlink "$HOME/.config/vibe-tools/vibe.sh")
config_root=$(cd "$(dirname "$vibe_script")/../.." && pwd)
map_dir=$(node "$config_root/scripts/term-map.mjs" "$config_root/docs/skill-trigger-map.md" "$HOME/.cache/vibe/term-map")
if [[ "${1:-}" == --generate ]]; then
  printf '%s\n' "$map_dir"
  exit 0
fi
export YAZI_CONFIG_HOME="$HOME/.config/herdr/term-map-yazi"
exec yazi "$map_dir"

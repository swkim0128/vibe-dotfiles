#!/bin/bash
set -euo pipefail

# 기존 하네스 설치 링크로 정본 위치를 찾는다. 개인 경로를 고정하지 않는다.
vibe_script=$(readlink "$HOME/.config/vibe-tools/vibe.sh")
config_root=$(cd "$(dirname "$vibe_script")/../.." && pwd)
exec node "$config_root/scripts/term-map.mjs" "$config_root/docs/skill-trigger-map.md"

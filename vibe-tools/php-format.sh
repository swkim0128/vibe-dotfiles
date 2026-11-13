#!/usr/bin/env bash
# 명시한 UTF-8 PHP 파일을 고정 버전 Prettier로 포맷한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TOOL_DIR="$SCRIPT_DIR/php-format"
SELF="$SCRIPT_DIR/php-format.sh"
CONFIG=""
MODE=""

usage() {
  printf '사용법: bash %q --config %q --write|--check <UTF-8 PHP 파일>...\n' "$SELF" "$TOOL_DIR/php53.json" >&2
}

fail() {
  printf '%s\n' "$1" >&2
  usage
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || fail '--config 뒤에 JSON 설정 파일이 필요합니다.'
      CONFIG="$2"
      shift 2
      ;;
    --write|--check)
      [[ -z "$MODE" ]] || fail '--write와 --check 중 하나만 지정하세요.'
      MODE="$1"
      shift
      ;;
    --) shift; break ;;
    -*) fail "지원하지 않는 옵션: $1" ;;
    *) break ;;
  esac
done

[[ -n "$CONFIG" && -f "$CONFIG" && -n "$MODE" && $# -gt 0 ]] || fail '설정·실행 모드·대상 파일을 명시하세요. 디렉터리 일괄 포맷은 지원하지 않습니다.'
for dependency in node jq iconv; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    package="$dependency"
    [[ "$dependency" != iconv ]] || package=libiconv
    printf '필요한 실행 파일이 없습니다: %s. 설치 후 다시 실행하세요: brew install %s\n' "$dependency" "$package" >&2
    exit 2
  fi
done
jq -e 'type == "object" and (.phpVersion | type == "string" and test("^[0-9]+\\.[0-9]+$"))' "$CONFIG" >/dev/null || fail 'phpVersion을 JSON 설정에 명시하세요. auto/composer 추론은 사용하지 않습니다.'

if [[ ! -f "$TOOL_DIR/package-lock.json" || ! -f "$TOOL_DIR/node_modules/prettier/bin/prettier.cjs" || ! -f "$TOOL_DIR/node_modules/@prettier/plugin-php/src/index.mjs" ]]; then
  printf '고정 버전 PHP 포맷터가 설치되지 않았습니다. 잠금 파일 확인 후 실행: npm ci --ignore-scripts --prefix %q\n' "$TOOL_DIR" >&2
  exit 2
fi
for package in prettier @prettier/plugin-php; do
  jq -e --arg package "$package" --slurpfile expected "$TOOL_DIR/package.json" '.version == $expected[0].dependencies[$package]' "$TOOL_DIR/node_modules/$package/package.json" >/dev/null || {
    printf '설정과 설치 버전이 다릅니다. 실행: npm ci --ignore-scripts --prefix %q\n' "$TOOL_DIR" >&2
    exit 2
  }
done

FILES=()
for file in "$@"; do
  [[ "$file" == /* ]] || file="$PWD/$file"
  [[ -f "$file" ]] || fail "일반 파일만 지정할 수 있습니다: $file"
  if ! iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1; then
    printf 'UTF-8이 아닌 원본은 직접 포맷하지 않습니다. 기존 변환 캐시를 준비하세요: bash %q %q --convert --to utf-8\n' "${AGENTS_HOME:-$HOME/.agents}/skills/file-encoding-converter/scripts/check-encoding.sh" "$file" >&2
    exit 2
  fi
  FILES+=("$file")
done

exec node "$TOOL_DIR/node_modules/prettier/bin/prettier.cjs" \
  --plugin "$TOOL_DIR/node_modules/@prettier/plugin-php/src/index.mjs" \
  --config "$CONFIG" --parser php "$MODE" -- "${FILES[@]}"

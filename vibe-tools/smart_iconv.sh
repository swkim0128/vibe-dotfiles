#!/usr/bin/env bash
set -euo pipefail

# smart_iconv.sh — iconv 변환 결과 캐싱 래퍼 (DEPRECATED)
#
# ⚠️ DEPRECATED: 본 스크립트는 analyze:file-encoding-converter 스킬로 일원화되었습니다.
#    스킬 사용:
#      bash "${CLAUDE_PLUGIN_ROOT}/skills/file-encoding-converter/scripts/check-encoding.sh" \
#        <file> --convert --from <enc> --to <enc>
#    캐시 경로: /tmp/iconv-cache/<basename>.<to_enc>  (ICONV_CACHE_DIR 오버라이드 가능)
#    캐시 보존: 삭제하지 않음 (재변환 회피)
#
# (호환성 유지) 같은 SRC 를 매번 변환하지 않고, TGT 가 이미 존재하고 SRC 보다 오래되지 않았으면
# 기존 결과를 재사용한다. 분석 작업에서 EUC-KR/CP949 -> UTF-8 반복 변환을 줄인다.
#
# Usage:
#   smart_iconv.sh <SRC> <TGT> [FROM_ENC] [TO_ENC]
# Defaults:
#   FROM_ENC=CP949, TO_ENC=UTF-8

echo "⚠️  smart_iconv.sh is DEPRECATED — analyze:file-encoding-converter 스킬을 사용하세요." >&2
echo "    스크립트: \${CLAUDE_PLUGIN_ROOT}/skills/file-encoding-converter/scripts/check-encoding.sh" >&2

usage() {
  cat >&2 <<'EOF'
Usage: smart_iconv.sh <SRC> <TGT> [FROM_ENC] [TO_ENC]
  SRC       원본 파일 경로 (필수)
  TGT       변환 결과 파일 경로 (필수)
  FROM_ENC  원본 인코딩 (기본: CP949)
  TO_ENC    대상 인코딩 (기본: UTF-8)
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

SRC="$1"
TGT="$2"
FROM_ENC="${3:-CP949}"
TO_ENC="${4:-UTF-8}"

if ! command -v iconv >/dev/null 2>&1; then
  echo "ERROR: iconv 명령을 찾을 수 없습니다" >&2
  exit 2
fi

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: SRC 파일이 존재하지 않습니다: $SRC" >&2
  exit 3
fi

# TGT 가 없거나 SRC 가 TGT 보다 더 새롭다면 재변환
if [[ ! -f "$TGT" ]] || [[ "$SRC" -nt "$TGT" ]]; then
  mkdir -p "$(dirname "$TGT")"
  iconv -f "$FROM_ENC" -t "$TO_ENC" "$SRC" > "$TGT"
else
  echo "기존 변환 파일을 재사용합니다: $TGT"
fi

# 변환 결과 메타데이터 출력 (절대경로 + 크기 바이트)
abs_tgt="$(cd "$(dirname "$TGT")" && pwd)/$(basename "$TGT")"
size_bytes="$(wc -c < "$TGT" | tr -d ' ')"
echo "변환 결과: $abs_tgt ($size_bytes bytes)"

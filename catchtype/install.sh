#!/bin/bash
# catchtype/install.sh — Catchtype(Homebrew 없음) dmg 다운로드 설치.
# README.md 의 서명 검증 절차를 게이트로 쓴다. 검증 불일치면 설치하지 않거나 설치한 앱을 지운다.
# 설치 위치: /Applications 가 쓰기 가능하면 거기, 아니면(관리자 아닌 계정) ~/Applications.
# 두 위치 중 하나에 이미 Catchtype.app 이 있으면 건너뛴다. 실패는 종료코드 1 (install.sh 는 경고 후 계속).
#
# 사용법: bash catchtype/install.sh

set -euo pipefail

SITE="https://catchtype.com"
APP_NAME="Catchtype.app"
APP=""
TEAM_ID="8L5WFHS4F9"
BUNDLE_ID="com.hebbianai.catchtype"
TMP=""
MNT=""

main() {
  local existing
  for existing in "/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME"; do
    if [[ -d "$existing" ]]; then
      echo "Catchtype 이미 설치됨($existing) — 건너뜀"
      return 0
    fi
  done
  APP="$(app_dir)/$APP_NAME"

  TMP="$(mktemp -d)"
  MNT="$TMP/mnt"
  trap cleanup EXIT

  # 고정 최신 링크가 없어(/download/latest 404) 홈페이지의 dmg 링크를 읽는다.
  local page path dmg bundle
  page="$(curl -fsSL "$SITE")"
  if [[ ! "$page" =~ (/download/Catchtype-[^\"\'\ ]+\.dmg) ]]; then
    fail "홈페이지에서 dmg 링크를 찾지 못함 — catchtype/README.md 수동 절차로 설치"
  fi
  path="${BASH_REMATCH[1]}"
  dmg="$TMP/$(basename "$path")"
  echo "다운로드: $SITE$path"
  curl -fL --progress-bar -o "$dmg" "$SITE$path"

  if ! verify_signature "dmg" "$(spctl -a -vvv -t open --context context:primary-signature "$dmg" 2>&1 || true)"; then
    fail "dmg 서명 불일치 — 설치하지 않음"
  fi

  mkdir -p "$MNT"
  hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$dmg"
  # 복사 도중 실패한 반쪽 앱이 남으면 다음 실행이 '이미 설치됨' 으로 건너뛰므로 지운다.
  if ! cp -R "$MNT/$APP_NAME" "$APP"; then
    rm -rf "$APP"
    fail "$APP 복사 실패"
  fi

  if ! verify_signature "앱" "$(spctl -a -vv "$APP" 2>&1 || true)"; then
    rm -rf "$APP"
    fail "설치한 앱 서명 불일치 — 삭제함"
  fi
  bundle="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")"
  if [[ "$bundle" != "$BUNDLE_ID" ]]; then
    rm -rf "$APP"
    fail "번들 ID 불일치($bundle) — 삭제함"
  fi

  echo "Catchtype 설치 완료 ($APP, 번들 ID $bundle)"
  echo "시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 Catchtype 을 허용하세요."
}

# ── 함수 선언 (본문 호출 순서) ──────────────────────────────────────────────
# app_dir — /Applications 가 쓰기 가능하면 그대로, 아니면 ~/Applications(없으면 생성).
app_dir() {
  if [[ -w /Applications ]]; then
    echo "/Applications"
    return 0
  fi
  mkdir -p "$HOME/Applications"
  echo "$HOME/Applications"
}

cleanup() {
  if [[ -n "$MNT" && -d "$MNT" ]]; then
    hdiutil detach -quiet "$MNT" 2>/dev/null || true
  fi
  if [[ -n "$TMP" ]]; then
    rm -rf "$TMP"
  fi
}

fail() {
  echo "Catchtype 설치 중단: $1" >&2
  exit 1
}

# verify_signature <대상명> <spctl 출력> — accepted·Notarized Developer ID·팀 ID 셋 다 있어야 통과.
verify_signature() {
  local label="$1" out="$2"
  if [[ "$out" == *accepted* && "$out" == *"source=Notarized Developer ID"* && "$out" == *"$TEAM_ID"* ]]; then
    echo "$label 서명 확인: accepted · Notarized Developer ID · $TEAM_ID"
    return 0
  fi
  echo "$out" >&2
  return 1
}

main "$@"

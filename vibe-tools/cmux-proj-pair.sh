#!/usr/bin/env bash
# cmux-proj-pair.sh — 앱 + k8s-manifest 페어 cmux 워크스페이스 런처 (cmux 탭 2개)
#
# 사용법:
#   cmux-pair <app> <manifest>   # cmux-projects.txt 등록된 앱+매니페스트를 한 워크스페이스 2탭으로
#   cmux-pair                     # 등록 프로젝트 목록
#
# 구성:
#   워크스페이스(이름=app, 색/설명/pin = app config) 안에 cmux 탭(surface) 2개:
#     탭 "app"          : tmux new-session -A -s <app>
#     탭 "k8s-manifest" : tmux new-session -A -s <manifest>
#   동명 워크스페이스 존재 시 select 재사용(탭 재구성 안 함).
#   cmux-dual(tmux split 방식)과 달리 cmux 탭(surface) 방식.
#   cmux CLI 미설치 시 두 tmux 세션만 생성하고 종료 (graceful degradation).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cmux-lib.sh disable=SC1091
source "$SCRIPT_DIR/cmux-lib.sh"
CONFIG="$SCRIPT_DIR/cmux-projects.txt"

APP="${1:-}"
MANIFEST="${2:-}"

if [[ -z "$APP" || -z "$MANIFEST" || "$APP" == "-h" || "$APP" == "--help" ]]; then
  echo "사용법: $(basename "$0") <app> <manifest>" >&2
  cmux_print_projects "$CONFIG"
  exit 0
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "오류: 설정 파일 없음: $CONFIG" >&2
  exit 1
fi

appMatch="$(cmux_lookup "$CONFIG" "$APP")"
[[ -z "$appMatch" ]] && { echo "오류: '$APP' 미등록" >&2; cmux_print_projects "$CONFIG"; exit 1; }
mfMatch="$(cmux_lookup "$CONFIG" "$MANIFEST")"
[[ -z "$mfMatch" ]] && { echo "오류: '$MANIFEST' 미등록" >&2; cmux_print_projects "$CONFIG"; exit 1; }

IFS='|' read -r _an appRaw appColor _ad appPin <<< "$appMatch"
IFS='|' read -r _mn mfRaw _rest <<< "$mfMatch"
appPath="$(cmux_expand_home "$appRaw")"
mfPath="$(cmux_expand_home "$mfRaw")"

[[ -d "$appPath" ]] || { echo "오류: 경로 없음: $appPath" >&2; exit 1; }
[[ -d "$mfPath" ]] || { echo "오류: 경로 없음: $mfPath" >&2; exit 1; }

# cmux CLI 미설치 — 두 tmux 세션만 생성 (이식성 정책)
if ! cmux_has_cli; then
  tmux new-session -d -s "$APP" -c "$appPath" 2>/dev/null || true
  tmux new-session -d -s "$MANIFEST" -c "$mfPath" 2>/dev/null || true
  echo "⚠️  cmux CLI 미설치 — tmux 세션 '$APP'·'$MANIFEST' 만 생성." >&2
  echo "   attach: tmux attach -t $APP / tmux attach -t $MANIFEST" >&2
  exit 0
fi

# 동명 워크스페이스 재사용 (중복 탭 생성 방지)
ref="$(cmux_workspace_ref_by_title "$APP")"
if [[ -n "$ref" ]]; then
  cmux workspace select "$ref" >/dev/null 2>&1 || true
  echo "✅ 페어 워크스페이스 '$APP' ($ref) 기존 재사용 (탭 구성 유지)"
  exit 0
fi

# 신규: 워크스페이스 생성 (첫 surface = app 탭, 색/설명/pin = app config)
ref="$(cmux_create_workspace "$APP" "$appPath" "$appColor" "$APP + $MANIFEST 페어 (앱+k8s 매니페스트)" "$appPin")" || { echo "오류: cmux 워크스페이스 생성 실패" >&2; exit 1; }

win="$(cmux current-window 2>/dev/null || true)"
pane="$(cmux list-panes --workspace "$ref" --window "$win" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^pane:/){print $i; exit}}')"

# app 탭(첫 surface) 라벨링
appSurface="$(cmux list-pane-surfaces --workspace "$ref" --window "$win" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^surface:/){print $i; exit}}')"
if [[ -n "$appSurface" ]]; then
  cmux rename-tab --workspace "$ref" --window "$win" --surface "$appSurface" --title "app" >/dev/null 2>&1 || true
fi

# k8s-manifest 탭(새 surface) 추가 + tmux 세션 연결 + 라벨
cmux new-surface --type terminal --workspace "$ref" --window "$win" --pane "$pane" --working-directory "$mfPath" --focus false >/dev/null 2>&1 || true
mfSurface="$(cmux list-pane-surfaces --workspace "$ref" --window "$win" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^surface:/) s=$i} END{print s}')"
if [[ -n "$mfSurface" ]]; then
  cmux send --workspace "$ref" --surface "$mfSurface" "tmux new-session -A -s $MANIFEST\n" >/dev/null 2>&1 || true
  cmux rename-tab --workspace "$ref" --window "$win" --surface "$mfSurface" --title "k8s-manifest" >/dev/null 2>&1 || true
fi

echo "✅ 페어 워크스페이스 기동: $ref"
echo "   탭: app($APP) / k8s-manifest($MANIFEST)"
echo "   전환: cmd+shift+] / [  ·  닫기: cmux-close $APP"

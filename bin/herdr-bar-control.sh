#!/bin/bash
set -euo pipefail

fail() {
  printf '%s\n%s\n' "$1" 'Codex 패널에서 다시 실행: prefix+i (한글: prefix+ㅑ)' >&2
  exit 2
}

caller=${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}
tab=${HERDR_ACTIVE_TAB_ID:-${HERDR_TAB_ID:-}}
workspace=${HERDR_ACTIVE_WORKSPACE_ID:-${HERDR_WORKSPACE_ID:-}}
[[ -n "$caller" && -n "$tab" && -n "$workspace" ]] || fail '호출 패널·탭·작업공간 문맥이 없습니다.'
parent=$(herdr pane get "$caller")
jq -e --arg pane "$caller" --arg tab "$tab" --arg workspace "$workspace" \
  '.result.pane | .pane_id == $pane and .tab_id == $tab and .workspace_id == $workspace' \
  <<<"$parent" >/dev/null || fail '현재 호출 패널의 위치가 바뀌었습니다.'

if action=$(fzf --prompt='TUI 관리 > ' --height=100% --layout=reverse --no-multi <<'CHOICES'
재시작
닫기
CHOICES
); then
  :
else
  result=$?
  [[ "$result" == 1 || "$result" == 130 ]] && exit 0
  fail 'TUI 관리 메뉴를 열지 못했습니다.'
fi

runner="$HOME/.config/herdr/vibe-herdr"
binary=$(realpath "$runner")
panes=$(herdr pane list --workspace "$workspace")
bars=()
while IFS= read -r pane; do
  info=$(herdr pane process-info --pane "$pane")
  while IFS= read -r executable; do
    if [[ "$executable" = /* ]] && [[ "$(realpath "$executable")" == "$binary" ]]; then
      bars+=("$pane")
      break
    fi
  done < <(jq -r '.result.process_info.foreground_processes[]
    | select(.argv[1] == "view") | .argv[0]' <<<"$info")
done < <(jq -r --arg tab "$tab" '.result.panes[] | select(.tab_id == $tab) | .pane_id' <<<"$panes")
[[ ${#bars[@]} -le 1 ]] || fail '같은 탭에 TUI 실행기가 여러 개 있어 변경하지 않았습니다.'

case "$action" in
  닫기)
    [[ ${#bars[@]} -ne 0 ]] || exit 0
    herdr pane close "${bars[0]}"
    ;;
  재시작)
    jq -e '.result.pane.agent == "codex"' <<<"$parent" >/dev/null || fail '재시작은 부모로 연결할 Codex 패널에서 실행해야 합니다.'
    options=(bar ensure --tab "$tab" --parent-pane "$caller")
    [[ ${#bars[@]} -eq 0 ]] || options+=(--relaunch)
    "$runner" "${options[@]}"
    ;;
esac

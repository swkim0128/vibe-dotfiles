#!/usr/bin/env bash
# pane별 작은 상태만 렌더링한다. 제목/구분자/테두리를 제외한 셀 폭을 받는다.
set -u

pane=${1:-}
pane_pid=${2:-}
server_pid=${3:-}
width=${4:-0}
script=${VIBE_DASHBOARD_HUD_SCRIPT:-}

[[ $pane =~ ^%[0-9]+$ && $pane_pid =~ ^[0-9]+$ && $server_pid =~ ^[0-9]+$ ]] || exit 0
[[ $width =~ ^[0-9]+$ ]] || exit 0
(( width >= 6 )) || exit 0

if [[ -f $script ]] && output=$(python3 "$script" render --pane "$pane" --pane-pid "$pane_pid" --server-pid "$server_pid" --width "$width" 2>/dev/null); then
    [[ -n $output ]] && printf '· %s ' "$output"
else
    if (( width >= 11 )); then
        printf '· 상태 미확인 '
    else
        printf '· 미확인 '
    fi
fi

#!/usr/bin/env bash
# cmux-issue.sh — 멀티 레포 이슈 워크스페이스 런처
#
# 하나의 작업 이슈가 2개 이상 프로젝트 레포를 동시에 수정 대상으로 삼을 때
# (예: DWDEV-2959 = BillingMPAdmin 메인 + PHPLib·MAS 서브),
# 이슈 식별자를 이름으로 하는 cmux 워크스페이스+tmux 세션을 만든다.
#
# 사용법:
#   cmux-issue <ISSUE> <proj1> [proj2 ...]   # proj = cmux-projects.txt 등록명 또는 raw 경로
#   cmux-issue                               # 등록 프로젝트 목록
#   cmux-issue -h                            # 도움말
#
# 구성 (win1 = work, main-vertical):
#   좌측 main pane  : para cwd 의 claude (작업 추적·오케스트레이션·PARA 노트 기록)
#   우측 스택       : 수정 대상 프로젝트별 pane, 각 프로젝트 cwd 로 claude 실행
#                     첫 인자(주 작업 레포)가 최상단
#   win2 = view     : 주 작업 레포 cwd 셸 — 파일 육안 확인 시 vim 열람 (cmux 신규 탭도 가능)
#
#   para cwd = ${PARA_PATH:-cmux-projects.txt 의 para 경로:-$HOME/Project/para}
#   proj 인자는 등록명이면 config 경로, 아니면 raw 경로($HOME 전개)로 해석.
#   동명 워크스페이스/세션 존재 시 재사용(레이아웃 유지).
#   cmux CLI 미설치·제외목록 시 tmux 세션만 유지 (graceful degradation).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cmux-lib.sh disable=SC1091
source "$SCRIPT_DIR/cmux-lib.sh"
CONFIG="$SCRIPT_DIR/cmux-projects.txt"

# 이슈 워크스페이스 시각 마커 (앰버) — 등록 프로젝트 색과 구분
ISSUE_COLOR='#B9770E'

ISSUE="${1:-}"

if [[ -z "$ISSUE" || "$ISSUE" == "-h" || "$ISSUE" == "--help" ]]; then
  echo "사용법: $(basename "$0") <ISSUE> <proj1> [proj2 ...]" >&2
  echo "  proj = cmux-projects.txt 등록명 또는 절대/\$HOME 경로" >&2
  cmux_print_projects "$CONFIG"
  exit 0
fi

shift
if [[ "$#" -lt 1 ]]; then
  echo "오류: 수정 대상 프로젝트를 1개 이상 지정하세요." >&2
  echo "사용법: $(basename "$0") <ISSUE> <proj1> [proj2 ...]" >&2
  cmux_print_projects "$CONFIG"
  exit 1
fi

# proj 인자 → "label|path" 해석. 등록명이면 config 경로, 아니면 raw 경로($HOME 전개).
# 경로 미존재 시 return 1.
resolve_proj() {
  local arg="$1" match _name raw path
  match="$(cmux_lookup "$CONFIG" "$arg")"
  if [[ -n "$match" ]]; then
    IFS='|' read -r _name raw _rest <<< "$match"
    path="$(cmux_expand_home "$raw")"
    [[ -d "$path" ]] || return 1
    printf '%s|%s' "$arg" "$path"
    return 0
  fi
  # 등록명 아님 — raw 경로로 취급
  path="$(cmux_expand_home "$arg")"
  [[ -d "$path" ]] || return 1
  printf '%s|%s' "$(basename "$path")" "$path"
}

# 프로젝트 인자 검증 + label/path 수집 (bash 3.2 — 병렬 배열)
labels=()
paths=()
for arg in "$@"; do
  info="$(resolve_proj "$arg")" || {
    echo "오류: '$arg' — 등록명도 아니고 존재하는 경로도 아닙니다." >&2
    cmux_print_projects "$CONFIG"
    exit 1
  }
  labels+=("${info%%|*}")
  paths+=("${info#*|}")
done

# para cwd 해석: PARA_PATH 우선 → cmux-projects.txt para 등록 → $HOME/Project/para
para_path="${PARA_PATH:-}"
if [[ -z "$para_path" ]]; then
  para_match="$(cmux_lookup "$CONFIG" "para")"
  if [[ -n "$para_match" ]]; then
    IFS='|' read -r _pn para_raw _prest <<< "$para_match"
    para_path="$(cmux_expand_home "$para_raw")"
  fi
fi
[[ -z "$para_path" ]] && para_path="$HOME/Project/para"

if [[ ! -d "$para_path" ]]; then
  echo "오류: para 경로가 존재하지 않습니다: $para_path" >&2
  echo "   PARA_PATH 환경변수로 명시하거나 cmux-projects.txt 에 para 를 등록하세요." >&2
  exit 1
fi

main_path="${paths[0]}"
main_label="${labels[0]}"

# 기존 세션 재사용 여부 (이슈명 정확 매칭)
session_created=false
if tmux has-session -t "$ISSUE" 2>/dev/null; then
  echo "ℹ️  기존 세션 '$ISSUE' 재사용 (레이아웃 유지)" >&2
else
  # win1 work — 좌측 main pane = para claude (추적·오케스트레이션)
  tmux new-session -d -s "$ISSUE" -n work -c "$para_path"
  tmux send-keys -t "$ISSUE:work" 'claude' Enter
  tmux select-pane -t "$ISSUE:work" -T "$ISSUE · para(추적)"

  # 첫 프로젝트(주 작업 레포) → 우측 pane
  right_pane="$(tmux split-window -h -P -F '#{pane_id}' -t "$ISSUE:work" -c "$main_path")"
  tmux send-keys -t "$right_pane" 'claude' Enter
  tmux select-pane -t "$right_pane" -T "$main_label · claude (main)"

  # 나머지 프로젝트 → 우측 컬럼에 세로 스택 (직전 pane 아래로)
  prev_pane="$right_pane"
  idx=1
  while [[ "$idx" -lt "${#paths[@]}" ]]; do
    p="$(tmux split-window -v -P -F '#{pane_id}' -t "$prev_pane" -c "${paths[$idx]}")"
    tmux send-keys -t "$p" 'claude' Enter
    tmux select-pane -t "$p" -T "${labels[$idx]} · claude"
    prev_pane="$p"
    idx=$((idx + 1))
  done

  # main-vertical: 좌측 큰 pane(para) 고정 + 우측 세로 스택. main pane 폭 50%.
  tmux set-window-option -t "$ISSUE:work" main-pane-width '50%' >/dev/null 2>&1 || true
  tmux select-layout -t "$ISSUE:work" main-vertical

  # win2 view — 주 작업 레포 셸 (파일 육안 확인 시 vim 열람)
  tmux new-window -t "$ISSUE" -n view -c "$main_path"
  tmux select-pane -t "$ISSUE:view" -T "view · vim 열람 ($main_label)"

  # 기본 포커스 = win1 좌측 para pane
  tmux select-window -t "$ISSUE:work"
  tmux select-pane -t "$ISSUE:work" -L
  session_created=true
fi

# 프로젝트 요약 문자열 (설명·안내용)
proj_summary="$main_label(main)"
i=1
while [[ "$i" -lt "${#labels[@]}" ]]; do
  proj_summary="$proj_summary, ${labels[$i]}"
  i=$((i + 1))
done

# 워크스페이스 제외 목록 — cmux 워크스페이스 생략, tmux 세션만 유지
if cmux_is_excluded "$ISSUE"; then
  echo "ℹ️  '$ISSUE' 은 워크스페이스 제외 목록 — tmux 세션만 생성/유지했습니다." >&2
  echo "   attach: tmux attach -t $ISSUE" >&2
  exit 0
fi

# cmux CLI 미설치 — tmux 세션만 유지 (이식성 정책)
if ! cmux_has_cli; then
  echo "⚠️  cmux CLI 미설치 — tmux 세션 '$ISSUE' 만 구성했습니다." >&2
  echo "   attach: tmux attach -t $ISSUE" >&2
  exit 0
fi

# cmux 워크스페이스 — 동명 존재 시 select 재사용 (중복 누적 방지)
ref="$(cmux_workspace_ref_by_title "$ISSUE")"
if [[ -n "$ref" ]]; then
  cmux workspace select "$ref" >/dev/null 2>&1 || true
  reused_ws=true
else
  # 워크스페이스 cwd = para (오케스트레이션 홈), backing = 이미 만든 이슈 세션에 attach
  ref="$(cmux_create_workspace "$ISSUE" "$para_path" "$ISSUE_COLOR" "이슈 $ISSUE: $proj_summary" "pin")" || {
    echo "오류: cmux 워크스페이스 생성 실패" >&2
    exit 1
  }
  reused_ws=false
fi

echo "✅ 멀티 레포 이슈 워크스페이스 기동: $ISSUE"
if [[ "$reused_ws" == true ]]; then
  echo "   cmux workspace: $ref (기존 재사용)"
else
  echo "   cmux workspace: $ref (신규 생성·pin)"
fi
echo "   tmux 세션: $ISSUE"
echo "   대상 레포: $proj_summary"
if [[ "$session_created" == true ]]; then
  echo "   win1 work: para(좌·추적) | ${#paths[@]}개 레포 스택(우) · win2 view(vim 열람)"
else
  echo "   기존 세션 재사용 (레이아웃 유지)"
fi
echo "   닫기: cmux-close $ISSUE"

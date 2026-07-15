#!/usr/bin/env bash
# cmux-issue.sh — 멀티 레포 이슈 워크스페이스 런처 (단계적 플로우)
#
# 하나의 작업 이슈가 2개 이상 프로젝트 레포를 동시에 수정 대상으로 삼을 때
# (예: DWDEV-2959 = BillingMPAdmin 메인 + PHPLib·MAS 서브),
# 이슈 식별자를 이름으로 하는 cmux 워크스페이스+tmux 세션을 만든다.
#
# 의도된 3단계 플로우:
#   ① cmux-issue <ISSUE>                → para 단독 워크스페이스+세션 생성
#                                          (좌측 para claude 단일 pane 에서 작업 정리·확인)
#   ② para pane 에서 해야 할 작업을 정리·확인
#   ③ cmux-issue --add <ISSUE> <proj…>  → 확인 후 필요한 프로젝트 pane 을 그때 생성
#      (또는 para pane 에서 직접 `vibe delegate <proj>` 로 pane split)
#   * 한 번에 다 필요하면 ①③ 합쳐 cmux-issue <ISSUE> <proj…> 도 가능(선생성).
#
# 사용법:
#   cmux-issue <ISSUE> [proj1 proj2 ...]              # 이슈 워크스페이스 생성/재사용 (proj 생략 = para 단독)
#   cmux-issue --add  <ISSUE> <proj1> [proj2 ...]     # 확인 후 프로젝트 pane 신규 스폰 (우측 스택 append)
#   cmux-issue --join <ISSUE> <pane_id> [pane_id ...] # 실행 중 pane 을 우측 스택에 무중단 이전
#   cmux-issue                                        # 등록 프로젝트 목록
#   cmux-issue -h                                     # 도움말
#
# 구성 (win1 = work, main-vertical):
#   좌측 main pane  : para cwd 의 claude 단일 pane (작업 추적·오케스트레이션·PARA 노트)
#                     — vibe start 현행 동작과 동일하게 메인은 단일 pane 이 기본
#   우측 스택       : 수정 대상 프로젝트별 pane, 각 프로젝트 cwd 로 claude 실행
#                     첫 인자(주 작업 레포)가 최상단
#   win2 = view     : 주 작업 레포 cwd 셸 — 파일 육안 확인 시 vim 열람 (cmux 신규 탭도 가능)
#                     프로젝트 pane 이 처음 생길 때 생성됨(para 단독 단계엔 없음).
#
#   para cwd = ${PARA_PATH:-cmux-projects.txt 의 para 경로:-$HOME/Project/para}
#   proj 인자는 등록명이면 config 경로, 아니면 raw 경로($HOME 전개)로 해석.
#   동명 워크스페이스/세션 존재 시 재사용(레이아웃 유지).
#   cmux CLI 미설치·제외목록 시 tmux 세션만 유지 (graceful degradation).
#
# --add vs --join:
#   --add  = 프로젝트 cwd 에서 claude 를 새로 스폰(신규 pane).
#   --join = 이미 다른 곳(예: para 허브의 vibe delegate pane)에서 돌던 claude pane 을
#            tmux join-pane 으로 프로세스째 이동(실행 중 세션 보존).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cmux-lib.sh disable=SC1091
source "$SCRIPT_DIR/cmux-lib.sh"
CONFIG="$SCRIPT_DIR/cmux-projects.txt"

# 이슈 워크스페이스 시각 마커 (앰버) — 등록 프로젝트 색과 구분
ISSUE_COLOR='#B9770E'
# detached 세션 기본 크기(80x24)에서 main-vertical 이 우측 스택을 1칸으로 붕괴시키는 것을 막기 위한 넓은 베이스.
# 클라이언트(cmux) attach 시 실제 크기로 리플로우됨.
WORK_COLS=250
WORK_ROWS=50

# work 창 레이아웃 정규화 — main-pane-width 를 select-layout 전에 반드시 설정(우측 붕괴 방지).
# 단일 pane(para 단독) 창에서도 안전(no-op). $1 = 세션명
normalize_work_layout() {
  tmux set-window-option -t "$1:work" main-pane-width '50%' >/dev/null 2>&1 || true
  tmux select-layout -t "$1:work" main-vertical
}

# work 창에 view 창(win2)이 이미 있는지 (0=있음, 1=없음). $1 = 세션명
work_has_view() {
  tmux list-windows -t "$1" -F '#{window_name}' 2>/dev/null | grep -qxF view
}

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

# 우측 스택 최하단에 프로젝트 pane 을 append + claude 스폰 + 라벨.
# 항상 마지막 pane 을 분할하므로 인덱스 순서(첫 인자=최상단)가 보존된다.
# $1=세션명 $2=cwd $3=라벨
spawn_proj_pane() {
  local sess="$1" path="$2" label="$3" last p
  last="$(tmux list-panes -t "$sess:work" -F '#{pane_id}' | tail -n1)"
  p="$(tmux split-window -v -P -F '#{pane_id}' -t "$last" -c "$path")"
  tmux send-keys -t "$p" 'claude' Enter
  tmux select-pane -t "$p" -T "$label · claude"
}

# ── --join 서브커맨드: 실행 중 pane 무중단 이전 ──────────────────────────────
if [[ "${1:-}" == "--join" || "${1:-}" == "join" ]]; then
  shift
  ISSUE="${1:-}"
  shift || true
  if [[ -z "$ISSUE" || "$#" -lt 1 ]]; then
    echo "사용법: $(basename "$0") --join <ISSUE> <pane_id> [pane_id ...]" >&2
    echo "  pane_id = tmux pane 식별자(예: %12). 'tmux list-panes -a -F \"#{pane_id} #{pane_current_path}\"' 로 확인." >&2
    exit 1
  fi
  if ! tmux has-session -t "$ISSUE" 2>/dev/null; then
    echo "오류: 이슈 세션 '$ISSUE' 가 없습니다. 먼저 'cmux-issue $ISSUE' 로 생성하세요." >&2
    exit 1
  fi

  # 존재하는 모든 pane_id 집합 (검증용)
  existing_panes="$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null || true)"

  joined=0
  for pid in "$@"; do
    if ! printf '%s\n' "$existing_panes" | grep -qxF "$pid"; then
      echo "⚠️  pane '$pid' 를 찾을 수 없어 건너뜁니다." >&2
      continue
    fi
    # 우측 스택에 세로로 append (프로세스 보존 이동). -d = 포커스 이동 안 함.
    if tmux join-pane -d -v -s "$pid" -t "$ISSUE:work" 2>/dev/null; then
      tmux select-pane -t "$pid" -T "joined · claude" >/dev/null 2>&1 || true
      joined=$((joined + 1))
    else
      echo "⚠️  pane '$pid' 이전 실패 (이미 이동됐거나 대상과 동일 창일 수 있음)." >&2
    fi
  done

  if [[ "$joined" -eq 0 ]]; then
    echo "ℹ️  이전된 pane 이 없습니다." >&2
    exit 0
  fi

  # 좌측 main(para) + 우측 스택으로 재정규화
  normalize_work_layout "$ISSUE"

  # cmux 워크스페이스가 있으면 선택(관찰 표면 활성)
  if cmux_has_cli; then
    ref="$(cmux_workspace_ref_by_title "$ISSUE")"
    [[ -n "$ref" ]] && cmux workspace select "$ref" >/dev/null 2>&1 || true
  fi

  echo "✅ pane $joined개를 이슈 세션 '$ISSUE' work 창 우측 스택으로 무중단 이전"
  echo "   확인: tmux attach -t $ISSUE  (또는 cmux 워크스페이스 '$ISSUE')"
  exit 0
fi

# ── --add 서브커맨드: 확인 후 프로젝트 pane 신규 스폰 ────────────────────────
if [[ "${1:-}" == "--add" || "${1:-}" == "add" ]]; then
  shift
  ISSUE="${1:-}"
  shift || true
  if [[ -z "$ISSUE" || "$#" -lt 1 ]]; then
    echo "사용법: $(basename "$0") --add <ISSUE> <proj1> [proj2 ...]" >&2
    echo "  proj = cmux-projects.txt 등록명 또는 절대/\$HOME 경로" >&2
    cmux_print_projects "$CONFIG"
    exit 1
  fi
  if ! tmux has-session -t "$ISSUE" 2>/dev/null; then
    echo "오류: 이슈 세션 '$ISSUE' 가 없습니다. 먼저 'cmux-issue $ISSUE' 로 생성하세요." >&2
    exit 1
  fi

  add_labels=()
  add_paths=()
  for arg in "$@"; do
    info="$(resolve_proj "$arg")" || {
      echo "오류: '$arg' — 등록명도 아니고 존재하는 경로도 아닙니다." >&2
      cmux_print_projects "$CONFIG"
      exit 1
    }
    add_labels+=("${info%%|*}")
    add_paths+=("${info#*|}")
  done

  idx=0
  while [[ "$idx" -lt "${#add_paths[@]}" ]]; do
    spawn_proj_pane "$ISSUE" "${add_paths[$idx]}" "${add_labels[$idx]}"
    idx=$((idx + 1))
  done

  normalize_work_layout "$ISSUE"

  # view 창이 아직 없으면 첫 추가 프로젝트 기준으로 생성 (파일 육안 열람용)
  if ! work_has_view "$ISSUE"; then
    tmux new-window -t "$ISSUE" -n view -c "${add_paths[0]}"
    tmux select-pane -t "$ISSUE:view" -T "view · vim 열람 (${add_labels[0]})"
    tmux select-window -t "$ISSUE:work"
  fi

  if cmux_has_cli; then
    ref="$(cmux_workspace_ref_by_title "$ISSUE")"
    [[ -n "$ref" ]] && cmux workspace select "$ref" >/dev/null 2>&1 || true
  fi

  echo "✅ 프로젝트 pane ${#add_paths[@]}개를 이슈 세션 '$ISSUE' 우측 스택에 추가"
  echo "   추가: ${add_labels[*]}"
  echo "   확인: tmux attach -t $ISSUE  (또는 cmux 워크스페이스 '$ISSUE')"
  exit 0
fi

# ── 기본: 이슈 워크스페이스 생성/재사용 (proj 인자 선택) ─────────────────────
ISSUE="${1:-}"

if [[ -z "$ISSUE" || "$ISSUE" == "-h" || "$ISSUE" == "--help" ]]; then
  echo "사용법: $(basename "$0") <ISSUE> [proj1 proj2 ...]   # proj 생략 = para 단독" >&2
  echo "        $(basename "$0") --add  <ISSUE> <proj1> [proj2 ...]" >&2
  echo "        $(basename "$0") --join <ISSUE> <pane_id> [pane_id ...]" >&2
  echo "  proj = cmux-projects.txt 등록명 또는 절대/\$HOME 경로" >&2
  cmux_print_projects "$CONFIG"
  exit 0
fi

shift  # 남은 인자 = 프로젝트 목록 (0개 허용 = para 단독)

# 프로젝트 인자 검증 + label/path 수집 (bash 3.2 — 병렬 배열). 0개면 para 단독.
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

# 기존 세션 재사용 여부 (이슈명 정확 매칭)
session_created=false
if tmux has-session -t "$ISSUE" 2>/dev/null; then
  echo "ℹ️  기존 세션 '$ISSUE' 재사용 (레이아웃 유지)" >&2
else
  # win1 work — 좌측 main pane = para claude (단일 pane, 추적·오케스트레이션)
  # -x/-y 로 넓은 베이스를 줘서 main-vertical 우측 스택이 붕괴하지 않게 함.
  tmux new-session -d -s "$ISSUE" -n work -c "$para_path" -x "$WORK_COLS" -y "$WORK_ROWS"
  tmux send-keys -t "$ISSUE:work" 'claude' Enter
  tmux select-pane -t "$ISSUE:work" -T "$ISSUE · para(추적)"

  # 프로젝트 pane 선생성 (0개면 para 단독 — ③ 단계에서 --add 로 추가)
  idx=0
  while [[ "$idx" -lt "${#paths[@]}" ]]; do
    spawn_proj_pane "$ISSUE" "${paths[$idx]}" "${labels[$idx]}"
    idx=$((idx + 1))
  done

  # main-vertical: 좌측 큰 pane(para) 고정 + 우측 세로 스택.
  # main-pane-width 를 select-layout 전에 설정(우측 1칸 붕괴 방지) — normalize_work_layout.
  normalize_work_layout "$ISSUE"

  # win2 view — 프로젝트가 있을 때만 (para 단독 단계엔 열람 대상 레포가 없음)
  if [[ "${#paths[@]}" -ge 1 ]]; then
    tmux new-window -t "$ISSUE" -n view -c "${paths[0]}"
    tmux select-pane -t "$ISSUE:view" -T "view · vim 열람 (${labels[0]})"
  fi

  # 기본 포커스 = win1 좌측 para pane
  tmux select-window -t "$ISSUE:work"
  tmux select-pane -t "$ISSUE:work" -L
  session_created=true
fi

# 프로젝트 요약 문자열 (설명·안내용)
if [[ "${#labels[@]}" -eq 0 ]]; then
  proj_summary="para 단독 (프로젝트 pane 미생성 — --add 로 추가)"
else
  proj_summary="${labels[0]}(main)"
  i=1
  while [[ "$i" -lt "${#labels[@]}" ]]; do
    proj_summary="$proj_summary, ${labels[$i]}"
    i=$((i + 1))
  done
fi

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

echo "✅ 이슈 워크스페이스 기동: $ISSUE"
if [[ "$reused_ws" == true ]]; then
  echo "   cmux workspace: $ref (기존 재사용)"
else
  echo "   cmux workspace: $ref (신규 생성·pin)"
fi
echo "   tmux 세션: $ISSUE"
echo "   대상 레포: $proj_summary"
if [[ "$session_created" == true ]]; then
  if [[ "${#paths[@]}" -eq 0 ]]; then
    echo "   win1 work: para(좌·추적) 단독 — 작업 정리 후 프로젝트 추가"
  else
    echo "   win1 work: para(좌·추적) | ${#paths[@]}개 레포 스택(우) · win2 view(vim 열람)"
  fi
fi
echo "   프로젝트 pane 추가(신규 스폰): cmux-issue --add $ISSUE <proj ...>"
echo "   실행 중 pane 이전(무중단):     cmux-issue --join $ISSUE <pane_id ...>"
echo "   닫기: cmux-close $ISSUE"

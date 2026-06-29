#!/usr/bin/env bash
# cmux-lib.sh — cmux 런처 공통 헬퍼 (cmux-proj/dual/ops/review 가 source). 직접 실행용 아님.

# 설정에서 name 정확 매칭 줄을 stdout 출력 (없으면 빈 문자열, 항상 성공)
cmux_lookup() {
  grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null | awk -F'|' -v n="$2" '$1==n {print; exit}' || true
}

# $HOME 안전 전개 (eval 미사용)
cmux_expand_home() {
  printf '%s' "${1/#\$HOME/$HOME}"
}

# 등록 프로젝트 목록 stderr 출력 (빈 설정에도 exit 0)
cmux_print_projects() {
  echo "등록된 프로젝트:" >&2
  grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null | while IFS='|' read -r n _p _c d _s; do
    printf '  %-20s %s\n' "$n" "$d" >&2
  done || true
}

# cmux CLI 존재 확인
cmux_has_cli() { command -v cmux >/dev/null 2>&1; }

# name 또는 name_ 접두사 tmux 세션을 최근 생성 순으로 stdout 출력 (서버 미기동/무매칭 시 빈 출력, 항상 성공)
cmux_find_sessions() {
  local name="$1"
  tmux list-sessions -F '#{session_created} #{session_name}' 2>/dev/null \
    | sort -rn \
    | awk -v n="$name" '{ s=$2 } s==n || index(s, n"_")==1 { print s }' \
    || true
}

# 제목(custom_title)이 정확히 일치하는 cmux 워크스페이스 ref 를 stdout 출력 (없으면 빈 문자열, 항상 성공)
cmux_workspace_ref_by_title() {
  local title="$1"
  cmux workspace list 2>/dev/null \
    | awk -v t="$title" '{ ref=""; for (i=1;i<=NF;i++) if ($i ~ /^workspace:/) { ref=$i; name=$(i+1) } } ref!="" && name==t { print ref; exit }' \
    || true
}

# 워크스페이스 생성 + 메타(색/설명/pin). ref 를 stdout 출력, 실패 시 비어있음+return 1
# 사용: ref="$(cmux_create_workspace "$name" "$path" "$color" "$desc")" || { 오류처리; }
cmux_create_workspace() {
  local name="$1" path="$2" color="$3" desc="$4" ref
  ref="$(CMUX_QUIET=1 cmux workspace create --name "$name" --cwd "$path" --command "tmux new-session -A -s $name" --focus true | awk '/workspace:/{print $NF}')"
  [[ -z "$ref" ]] && return 1
  cmux workspace-action --action set-color --color "$color" --workspace "$ref" >/dev/null 2>&1 || true
  cmux workspace-action --action set-description --description "$desc" --workspace "$ref" >/dev/null 2>&1 || true
  cmux workspace-action --action pin --workspace "$ref" >/dev/null 2>&1 || true
  printf '%s' "$ref"
}

#!/usr/bin/env bash
# skill_audit_worker.sh — 스킬/플러그인/에이전트 사용현황 vs 설정현황 야간 비교 워커
#
# 매일 밤 22:00 launchd 에 의해 실행됨 (caffeinate -i -s 래핑).
# ~/.claude 트랜스크립트(*.jsonl)에서 당일 스킬·에이전트 호출을 결정론적으로
# 집계하고, 누적 원장(ledger)과 대조한 뒤, 설정 인벤토리(활성 플러그인·설치
# 스킬/에이전트·훅)와 비교하여 "거의 안 씀(제거 후보)" 판정을 마크다운 리포트로
# $HOME/Library/Logs/skill-audit/YYYY-MM-DD.md 에 저장.
#
# 특징:
#   - LLM/claude CLI 의존 없음. 순수 셸(grep/awk/sort/uniq) + (있으면)jq.
#   - 규칙 기반 판정 (누적 사용 0 = 제거 후보 / 사용 있음 = 필요).
#   - 자기완결: PARA·외부 볼트 의존 없음. 데이터·설정 부재 시 graceful(빈 집계).
#
# 데이터 소스:
#   ~/.claude/projects/<프로젝트디렉토리>/<uuid>.jsonl
#     - 한 줄 = 한 JSON 이벤트.
#     - 스킬 호출 줄:   "skill":"<plugin>:<name>" + "timestamp":"YYYY-MM-DDT..."
#     - 에이전트 호출:  "subagent_type":"<name>" + "timestamp":"YYYY-MM-DDT..."
#     - 디렉토리명(-Users-eunsol-Project-...)이 곧 프로젝트 식별자.
#   ~/.claude/settings.json · settings.local.json  → enabledPlugins (값 true)
#   ~/.claude/plugins/marketplaces/*/*/plugins/*/skills/*/SKILL.md → 설치 스킬
#   ~/.claude/plugins/marketplaces/*/*/plugins/*/agents/*.md       → 설치 에이전트
#
# 사용법:
#   직접 실행은 권장하지 않음. launchd 또는 테스트 시 dry-run.
#     DRY_RUN=1 ./skill_audit_worker.sh
#   DRY_RUN=1 이면 트랜스크립트 스캔은 하되 ledger append·최종 파일은 [DRY] 표기.
#
# 수동 부트스트랩 (setup.sh 는 plist 를 배포하지 않음 — SoC):
#   cp vibe-tools/com.swkim0128.skill-audit.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.skill-audit.plist
#   (해제: launchctl bootout gui/$(id -u)/com.swkim0128.skill-audit)

set -euo pipefail

# ── 설정 ─────────────────────────────────────────────────────────────────────
CLAUDE_HOME="${CLAUDE_HOME:-${HOME}/.claude}"
PROJECTS_DIR="${CLAUDE_HOME}/projects"
MARKETPLACES_DIR="${CLAUDE_HOME}/plugins/marketplaces"
LOG_DIR="${HOME}/Library/Logs/skill-audit"
TODAY="$(date +%F)"
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
REPORT="${LOG_DIR}/${TODAY}.md"
LEDGER="${LOG_DIR}/ledger.tsv"
LOG_FILE="${LOG_DIR}/${TODAY}.log"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "${LOG_DIR}"

# 작업용 임시 디렉토리 (당일 집계 중간 산출물)
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/skill-audit.XXXXXX")"
# shellcheck disable=SC2329  # trap 으로 간접 호출됨
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

# jq 존재 여부 (있으면 우선 사용, 없으면 grep/awk 폴백)
HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

# ── 로깅 함수 ────────────────────────────────────────────────────────────────
log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[${ts}] [${level}] ${msg}" | tee -a "${LOG_FILE}"
}
log_info()  { log "INFO " "$@"; }
log_warn()  { log "WARN " "$@"; }
# shellcheck disable=SC2329  # 오류 경로 방어용 헬퍼 (조건부 호출)
log_error() { log "ERROR" "$@"; }

log_info "===== skill_audit_worker 시작 ====="
log_info "실행 시각: ${RUN_DATE}"
log_info "CLAUDE_HOME: ${CLAUDE_HOME}"
log_info "PROJECTS_DIR: ${PROJECTS_DIR}$([[ -d ${PROJECTS_DIR} ]] && echo '' || echo ' (미존재 — 빈 집계)')"
log_info "MARKETPLACES_DIR: ${MARKETPLACES_DIR}$([[ -d ${MARKETPLACES_DIR} ]] && echo '' || echo ' (미존재 — 인벤토리 빈값)')"
log_info "리포트 출력: ${REPORT}"
log_info "누적 원장: ${LEDGER}"
log_info "jq 사용: $([[ ${HAS_JQ} -eq 1 ]] && echo 'yes' || echo 'no (grep/awk 폴백)')"
log_info "DRY_RUN: ${DRY_RUN}"

# ─────────────────────────────────────────────────────────────────────────────
# (A) 당일 사용 집계
#   결과물:
#     ${WORK_DIR}/usage_global.tsv    : type\tname\tcount   (전역 합산)
#     ${WORK_DIR}/usage_by_project.tsv: project\ttype\tname\tcount
# ─────────────────────────────────────────────────────────────────────────────

# 한 트랜스크립트 파일에서 오늘 날짜의 skill/subagent_type 이름을 추출해 표준출력.
#   출력 형식: "<type>\t<name>" (한 줄 = 이벤트 1건)
# jq 폴백 포함. jq 실패/미존재 시 grep/grep -o 로 라인 파싱.
extract_events() {
  local file="$1"
  if [[ ${HAS_JQ} -eq 1 ]]; then
    # timestamp 가 오늘로 시작하고 skill 또는 subagent_type 를 가진 이벤트만.
    # jq 파싱 실패(깨진 줄)는 -R -c 로 라인단위 시도하되 오류는 무시.
    jq -R -r '. as $line | (try (fromjson) catch empty)
      | select((.timestamp // "") | startswith("'"${TODAY}"'"))
      | (.message.content // empty)
      | select(type == "array") | .[]
      | select((.type? // "") == "tool_use")
      | if (.name == "Skill" and (.input.skill // null) != null) then {t:"skill", n:.input.skill}
        elif ((.name == "Agent" or .name == "Task") and (.input.subagent_type // null) != null) then {t:"agent", n:.input.subagent_type}
        else empty end
      | "\(.t)\t\(.n)"' "${file}" 2>/dev/null || true
  else
    # 폴백: 오늘 timestamp 를 포함한 줄만 뽑아 skill / subagent_type 를 추출.
    # 한 줄에 두 필드가 동시에 있을 가능성은 낮으나, 각각 독립 추출한다.
    grep -F "\"timestamp\":\"${TODAY}" "${file}" 2>/dev/null | while IFS= read -r line; do
      local sk ag
      sk="$(printf '%s' "${line}" | grep -o '"skill":"[^"]*"' | head -n1 | sed 's/^"skill":"//; s/"$//')"
      if [[ -n "${sk}" ]]; then
        printf 'skill\t%s\n' "${sk}"
      fi
      ag="$(printf '%s' "${line}" | grep -o '"subagent_type":"[^"]*"' | head -n1 | sed 's/^"subagent_type":"//; s/"$//')"
      if [[ -n "${ag}" ]]; then
        printf 'agent\t%s\n' "${ag}"
      fi
    done
  fi
}

: > "${WORK_DIR}/usage_global.tsv"
: > "${WORK_DIR}/usage_by_project.tsv"
: > "${WORK_DIR}/events_global.tmp"

TRANSCRIPT_COUNT=0
if [[ -d "${PROJECTS_DIR}" ]]; then
  # 프로젝트 디렉토리 단위로 순회
  for proj_path in "${PROJECTS_DIR}"/*/; do
    [[ -d "${proj_path}" ]] || continue
    local_proj="$(basename "${proj_path}")"
    : > "${WORK_DIR}/events_proj.tmp"
    for jf in "${proj_path}"*.jsonl; do
      [[ -f "${jf}" ]] || continue
      TRANSCRIPT_COUNT=$((TRANSCRIPT_COUNT + 1))
      extract_events "${jf}" >> "${WORK_DIR}/events_proj.tmp"
    done
    # 프로젝트별 집계: type\tname 단위 count
    if [[ -s "${WORK_DIR}/events_proj.tmp" ]]; then
      sort "${WORK_DIR}/events_proj.tmp" | uniq -c \
        | awk -v proj="${local_proj}" '{ c=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/,""); print proj"\t"$0"\t"c }' \
        >> "${WORK_DIR}/usage_by_project.tsv"
      cat "${WORK_DIR}/events_proj.tmp" >> "${WORK_DIR}/events_global.tmp"
    fi
  done
else
  log_warn "트랜스크립트 디렉토리 부재 — 당일 사용 집계 빈값."
fi

# 전역 집계: type\tname\tcount (count 내림차순)
if [[ -s "${WORK_DIR}/events_global.tmp" ]]; then
  sort "${WORK_DIR}/events_global.tmp" | uniq -c \
    | awk '{ c=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/,""); print $0"\t"c }' \
    | sort -t"$(printf '\t')" -k3,3nr \
    > "${WORK_DIR}/usage_global.tsv"
fi

log_info "스캔한 트랜스크립트 파일 수: ${TRANSCRIPT_COUNT}"
TODAY_DISTINCT="$(wc -l < "${WORK_DIR}/usage_global.tsv" | tr -d ' ')"
log_info "당일 사용된 distinct 스킬/에이전트 수: ${TODAY_DISTINCT}"

# ─────────────────────────────────────────────────────────────────────────────
# (B) 누적 원장(ledger) — TSV: date\ttype\tname\tcount
#   당일 전역 집계를 append. DRY_RUN 이면 생략.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "[DRY_RUN] ledger append 생략."
else
  if [[ -s "${WORK_DIR}/usage_global.tsv" ]]; then
    # 같은 날짜 중복 append 방지: 오늘 날짜 행이 이미 있으면 재기록하지 않음.
    if [[ -f "${LEDGER}" ]] && grep -q "^${TODAY}"$'\t' "${LEDGER}"; then
      log_warn "ledger 에 오늘(${TODAY}) 행이 이미 존재 — append 생략(중복 방지)."
    else
      awk -v d="${TODAY}" -F"\t" '{ print d"\t"$1"\t"$2"\t"$3 }' \
        "${WORK_DIR}/usage_global.tsv" >> "${LEDGER}"
      log_info "ledger append 완료: ${TODAY} (${TODAY_DISTINCT} 행)."
    fi
  else
    log_info "당일 사용 0 — ledger append 대상 없음."
  fi
fi

# 누적 원장 요약 (name 기준 합산). ledger 부재 시 빈값.
#   결과물: ${WORK_DIR}/ledger_summary.tsv : type\tname\ttotal_count
#           ${WORK_DIR}/ledger_days        : 원장 커버 일수
: > "${WORK_DIR}/ledger_summary.tsv"
LEDGER_DAYS=0
# DRY_RUN 에서 오늘 행 미기록분을 누적 관점에 포함하기 위해 원장+당일을 합쳐 요약.
: > "${WORK_DIR}/ledger_effective.tsv"
if [[ -f "${LEDGER}" ]]; then
  cat "${LEDGER}" >> "${WORK_DIR}/ledger_effective.tsv"
fi
if [[ "${DRY_RUN}" == "1" && -s "${WORK_DIR}/usage_global.tsv" ]]; then
  # DRY 모드에서는 원장에 안 쓰였을 수 있으므로 당일분을 가상으로 합산에 포함.
  if ! { [[ -f "${LEDGER}" ]] && grep -q "^${TODAY}"$'\t' "${LEDGER}"; }; then
    awk -v d="${TODAY}" -F"\t" '{ print d"\t"$1"\t"$2"\t"$3 }' \
      "${WORK_DIR}/usage_global.tsv" >> "${WORK_DIR}/ledger_effective.tsv"
  fi
fi
if [[ -s "${WORK_DIR}/ledger_effective.tsv" ]]; then
  # type\tname 기준 count 합산
  awk -F"\t" 'NF>=4 { key=$2"\t"$3; sum[key]+=$4 }
    END { for (k in sum) print k"\t"sum[k] }' \
    "${WORK_DIR}/ledger_effective.tsv" \
    | sort -t"$(printf '\t')" -k3,3nr > "${WORK_DIR}/ledger_summary.tsv"
  LEDGER_DAYS="$(awk -F"\t" '{ print $1 }' "${WORK_DIR}/ledger_effective.tsv" | sort -u | wc -l | tr -d ' ')"
fi
log_info "누적 원장 커버 일수: ${LEDGER_DAYS}"

# name -> 누적 count 조회 헬퍼 (ledger_summary 참조)
ledger_total_for() {
  local name="$1"
  awk -F"\t" -v n="${name}" '$2==n { s+=$3 } END { print s+0 }' \
    "${WORK_DIR}/ledger_summary.tsv" 2>/dev/null || echo 0
}
# name -> 당일 count 조회 헬퍼
today_count_for() {
  local name="$1"
  awk -F"\t" -v n="${name}" '$2==n { print $3; found=1 } END { if(!found) print 0 }' \
    "${WORK_DIR}/usage_global.tsv" 2>/dev/null | head -n1
}

# ─────────────────────────────────────────────────────────────────────────────
# (C) 설정 인벤토리
# ─────────────────────────────────────────────────────────────────────────────

# (C-1) 활성 플러그인 — enabledPlugins 중 값 true. 플러그인명 = '@' 앞 토큰.
: > "${WORK_DIR}/enabled_plugins.txt"
collect_enabled_plugins() {
  local sfile="$1"
  [[ -f "${sfile}" ]] || return 0
  if [[ ${HAS_JQ} -eq 1 ]]; then
    jq -r '(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key' \
      "${sfile}" 2>/dev/null || true
  else
    # 폴백: "name@marketplace": true 패턴 추출.
    grep -o '"[^"]*@[^"]*"[[:space:]]*:[[:space:]]*true' "${sfile}" 2>/dev/null \
      | sed 's/"\([^"]*\)".*/\1/' || true
  fi
}
for sf in "${CLAUDE_HOME}/settings.json" "${CLAUDE_HOME}/settings.local.json"; do
  collect_enabled_plugins "${sf}" >> "${WORK_DIR}/enabled_plugins.txt"
done
# 프로젝트 로컬 설정(존재 시)도 포함 — cwd 기준.
for sf in ".claude/settings.json" ".claude/settings.local.json"; do
  if [[ -f "${sf}" ]]; then
    collect_enabled_plugins "${sf}" >> "${WORK_DIR}/enabled_plugins.txt"
  fi
done
# 정규화: '@' 앞이 플러그인명. 중복 제거.
if [[ -s "${WORK_DIR}/enabled_plugins.txt" ]]; then
  awk -F'@' '{ print $1 }' "${WORK_DIR}/enabled_plugins.txt" | sort -u \
    > "${WORK_DIR}/enabled_plugin_names.txt"
else
  : > "${WORK_DIR}/enabled_plugin_names.txt"
fi
ENABLED_PLUGIN_COUNT="$(wc -l < "${WORK_DIR}/enabled_plugin_names.txt" | tr -d ' ')"
log_info "활성 플러그인 수: ${ENABLED_PLUGIN_COUNT}"

# (C-2) 설치 스킬 — <plugin>:<skill_dir> 형식.
#   경로: .../plugins/marketplaces/*/*/plugins/<plugin>/skills/<skill>/SKILL.md
: > "${WORK_DIR}/installed_skills.txt"
if [[ -d "${MARKETPLACES_DIR}" ]]; then
  while IFS= read -r skmd; do
    [[ -n "${skmd}" ]] || continue
    # <plugin>/skills/<skill>/SKILL.md 에서 plugin 과 skill 추출
    skill_dir="$(basename "$(dirname "${skmd}")")"
    plugin_dir="$(basename "$(dirname "$(dirname "$(dirname "${skmd}")")")")"
    printf '%s:%s\n' "${plugin_dir}" "${skill_dir}"
  done < <(find "${MARKETPLACES_DIR}" -type f -path '*/plugins/*/skills/*/SKILL.md' 2>/dev/null) \
    | sort -u > "${WORK_DIR}/installed_skills.txt"
fi
INSTALLED_SKILL_COUNT="$(wc -l < "${WORK_DIR}/installed_skills.txt" | tr -d ' ')"
log_info "설치 스킬 수: ${INSTALLED_SKILL_COUNT}"

# (C-3) 설치 에이전트 — agents/<name>.md 의 name.
: > "${WORK_DIR}/installed_agents.txt"
if [[ -d "${MARKETPLACES_DIR}" ]]; then
  while IFS= read -r agmd; do
    [[ -n "${agmd}" ]] || continue
    ag_name="$(basename "${agmd}" .md)"
    printf '%s\n' "${ag_name}"
  done < <(find "${MARKETPLACES_DIR}" -type f -path '*/plugins/*/agents/*.md' 2>/dev/null) \
    | sort -u > "${WORK_DIR}/installed_agents.txt"
fi
INSTALLED_AGENT_COUNT="$(wc -l < "${WORK_DIR}/installed_agents.txt" | tr -d ' ')"
log_info "설치 에이전트 수: ${INSTALLED_AGENT_COUNT}"

# (C-4) 설정 훅 — settings*.json 의 hooks 이벤트 목록 + 플러그인 hooks/ 존재.
: > "${WORK_DIR}/hooks_config.txt"
collect_hook_events() {
  local sfile="$1"
  [[ -f "${sfile}" ]] || return 0
  if [[ ${HAS_JQ} -eq 1 ]]; then
    jq -r '(.hooks // {}) | keys[]' "${sfile}" 2>/dev/null \
      | awk -v s="$(basename "${sfile}")" '{ print s": "$0 }' || true
  else
    # 폴백: hooks 블록 내 이벤트 키(대문자 시작 식별자)를 대략 추출 — 근사치.
    grep -o '"[A-Z][A-Za-z]*"[[:space:]]*:' "${sfile}" 2>/dev/null \
      | sed 's/"\([^"]*\)".*/\1/' | sort -u \
      | awk -v s="$(basename "${sfile}")" '{ print s": "$0" (근사)" }' || true
  fi
}
for sf in "${CLAUDE_HOME}/settings.json" "${CLAUDE_HOME}/settings.local.json"; do
  collect_hook_events "${sf}" >> "${WORK_DIR}/hooks_config.txt"
done
# 플러그인 hooks/ 디렉토리 존재 여부
: > "${WORK_DIR}/plugin_hooks.txt"
if [[ -d "${MARKETPLACES_DIR}" ]]; then
  while IFS= read -r hd; do
    [[ -n "${hd}" ]] || continue
    plugin_dir="$(basename "$(dirname "${hd}")")"
    printf '%s\n' "${plugin_dir}"
  done < <(find "${MARKETPLACES_DIR}" -type d -path '*/plugins/*/hooks' 2>/dev/null) \
    | sort -u > "${WORK_DIR}/plugin_hooks.txt"
fi
HOOK_EVENT_COUNT="$(wc -l < "${WORK_DIR}/hooks_config.txt" | tr -d ' ')"
PLUGIN_HOOK_COUNT="$(wc -l < "${WORK_DIR}/plugin_hooks.txt" | tr -d ' ')"
log_info "설정 훅 이벤트 수: ${HOOK_EVENT_COUNT} / 훅 보유 플러그인 수: ${PLUGIN_HOOK_COUNT}"

# ─────────────────────────────────────────────────────────────────────────────
# (D) 비교/판정 (규칙 기반)
#   설치 스킬/에이전트 각각에 대해 누적 사용 여부로 판정.
#     - 누적 0 → ❌ 거의 안 씀 (제거/비활성 후보)
#     - 누적 > 0 → ✅ 사용 중(필요). 당일 사용도 별도 표기.
#   결과물:
#     ${WORK_DIR}/verdict_skills.tsv : name\tverdict\ttoday\ttotal
#     ${WORK_DIR}/verdict_agents.tsv : name\tverdict\ttoday\ttotal
#     ${WORK_DIR}/unused_candidates.txt : 제거 후보 (type name)
# ─────────────────────────────────────────────────────────────────────────────
: > "${WORK_DIR}/verdict_skills.tsv"
: > "${WORK_DIR}/verdict_agents.tsv"
: > "${WORK_DIR}/unused_candidates.txt"

build_verdict() {
  local inventory="$1" out="$2" typlabel="$3"
  [[ -f "${inventory}" ]] || return 0
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    local total today verdict
    total="$(ledger_total_for "${name}")"
    today="$(today_count_for "${name}")"
    if [[ "${total}" -gt 0 ]]; then
      verdict="✅ 사용 중(필요)"
    else
      verdict="❌ 거의 안 씀 (제거/비활성 후보)"
      printf '%s\t%s\n' "${typlabel}" "${name}" >> "${WORK_DIR}/unused_candidates.txt"
    fi
    printf '%s\t%s\t%s\t%s\n' "${name}" "${verdict}" "${today}" "${total}" >> "${out}"
  done < "${inventory}"
}
build_verdict "${WORK_DIR}/installed_skills.txt" "${WORK_DIR}/verdict_skills.tsv" "skill"
build_verdict "${WORK_DIR}/installed_agents.txt" "${WORK_DIR}/verdict_agents.tsv" "agent"

UNUSED_COUNT="$(wc -l < "${WORK_DIR}/unused_candidates.txt" | tr -d ' ')"
log_info "제거/비활성 후보 수: ${UNUSED_COUNT}"

# ─────────────────────────────────────────────────────────────────────────────
# (E) 리포트 작성 (마크다운)
# ─────────────────────────────────────────────────────────────────────────────
DRY_TAG=""
if [[ "${DRY_RUN}" == "1" ]]; then
  DRY_TAG=" [DRY]"
fi

# 마크다운 테이블 헬퍼: verdict TSV → 표
emit_verdict_table() {
  local tsv="$1"
  if [[ ! -s "${tsv}" ]]; then
    echo "_(설치 항목 없음)_"
    return
  fi
  echo "| 이름 | 판정 | 당일 | 누적 |"
  echo "|---|---|---:|---:|"
  awk -F"\t" '{ printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }' "${tsv}"
}

{
  echo "# 스킬/플러그인/에이전트 사용현황 감사 리포트 — ${TODAY}${DRY_TAG}"
  echo ""
  echo "> 생성: ${RUN_DATE} · 분석기간: 당일(${TODAY}) · 누적 원장 기준일수: ${LEDGER_DAYS}일"
  echo "> 집계 방식: 결정론적(grep/awk$([[ ${HAS_JQ} -eq 1 ]] && echo '+jq')) · LLM 미사용"
  echo ""

  echo "## 당일 사용"
  echo ""
  echo "### 전역 (전체 프로젝트 합산)"
  echo ""
  if [[ -s "${WORK_DIR}/usage_global.tsv" ]]; then
    echo "| 타입 | 이름 | 호출 |"
    echo "|---|---|---:|"
    awk -F"\t" '{ printf "| %s | %s | %s |\n", $1, $2, $3 }' "${WORK_DIR}/usage_global.tsv"
  else
    echo "_(당일 스킬/에이전트 호출 없음)_"
  fi
  echo ""
  echo "### 프로젝트별"
  echo ""
  if [[ -s "${WORK_DIR}/usage_by_project.tsv" ]]; then
    echo "| 프로젝트 | 타입 | 이름 | 호출 |"
    echo "|---|---|---|---:|"
    awk -F"\t" '{ printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }' "${WORK_DIR}/usage_by_project.tsv"
  else
    echo "_(당일 프로젝트별 호출 없음)_"
  fi
  echo ""

  echo "## 누적 사용 Top (원장 기준, 합산 내림차순)"
  echo ""
  if [[ -s "${WORK_DIR}/ledger_summary.tsv" ]]; then
    echo "| 타입 | 이름 | 누적 |"
    echo "|---|---|---:|"
    head -n 30 "${WORK_DIR}/ledger_summary.tsv" \
      | awk -F"\t" '{ printf "| %s | %s | %s |\n", $1, $2, $3 }'
  else
    echo "_(원장 데이터 없음 — 첫 실행이거나 누적 사용 0)_"
  fi
  echo ""

  echo "## 설정 인벤토리"
  echo ""
  echo "### 활성 플러그인 (${ENABLED_PLUGIN_COUNT})"
  echo ""
  if [[ -s "${WORK_DIR}/enabled_plugin_names.txt" ]]; then
    while IFS= read -r p; do
      echo "- ${p}"
    done < "${WORK_DIR}/enabled_plugin_names.txt"
  else
    echo "_(enabledPlugins 없음)_"
  fi
  echo ""
  echo "### 설치 스킬 (${INSTALLED_SKILL_COUNT})"
  echo ""
  if [[ -s "${WORK_DIR}/installed_skills.txt" ]]; then
    while IFS= read -r s; do
      echo "- ${s}"
    done < "${WORK_DIR}/installed_skills.txt"
  else
    echo "_(설치 스킬 없음)_"
  fi
  echo ""
  echo "### 설치 에이전트 (${INSTALLED_AGENT_COUNT})"
  echo ""
  if [[ -s "${WORK_DIR}/installed_agents.txt" ]]; then
    while IFS= read -r a; do
      echo "- ${a}"
    done < "${WORK_DIR}/installed_agents.txt"
  else
    echo "_(설치 에이전트 없음)_"
  fi
  echo ""
  echo "### 훅 (설정 여부만 — 사용 측정 불가)"
  echo ""
  echo "> ⚠️ 훅은 도구호출이 아니라 사용 측정 불가(설정 여부만). 아래는 설정/보유 목록."
  echo ""
  echo "**settings 훅 이벤트 (${HOOK_EVENT_COUNT})**"
  echo ""
  if [[ -s "${WORK_DIR}/hooks_config.txt" ]]; then
    while IFS= read -r h; do
      echo "- ${h}"
    done < "${WORK_DIR}/hooks_config.txt"
  else
    echo "_(settings 훅 없음)_"
  fi
  echo ""
  echo "**hooks/ 디렉토리 보유 플러그인 (${PLUGIN_HOOK_COUNT})**"
  echo ""
  if [[ -s "${WORK_DIR}/plugin_hooks.txt" ]]; then
    while IFS= read -r ph; do
      echo "- ${ph}"
    done < "${WORK_DIR}/plugin_hooks.txt"
  else
    echo "_(hooks/ 보유 플러그인 없음)_"
  fi
  echo ""

  echo "## 비교 결과"
  echo ""
  echo "### 스킬 판정"
  echo ""
  emit_verdict_table "${WORK_DIR}/verdict_skills.tsv"
  echo ""
  echo "### 에이전트 판정"
  echo ""
  emit_verdict_table "${WORK_DIR}/verdict_agents.tsv"
  echo ""

  echo "## 권장 — 비활성/제거 후보 (${UNUSED_COUNT})"
  echo ""
  echo "> 규칙: 설치됐으나 누적 사용 0. 원장 축적일수(${LEDGER_DAYS}일)가 짧으면 신뢰도 낮음 — 며칠 더 관찰 권장."
  echo ""
  if [[ -s "${WORK_DIR}/unused_candidates.txt" ]]; then
    while IFS= read -r line; do
      utype="$(printf '%s' "${line}" | awk -F"\t" '{ print $1 }')"
      uname="$(printf '%s' "${line}" | awk -F"\t" '{ print $2 }')"
      echo "- [${utype}] ${uname}"
    done < "${WORK_DIR}/unused_candidates.txt"
  else
    echo "_(제거 후보 없음 — 모든 설치 항목이 누적 사용 이력 보유)_"
  fi
  echo ""
} > "${WORK_DIR}/report.md"

# 최종 리포트 배치
if [[ "${DRY_RUN}" == "1" ]]; then
  # DRY: 실제 경로 옆에 .dry 접미사로 산출(원본 덮어쓰지 않음).
  DRY_REPORT="${REPORT%.md}.dry.md"
  cp "${WORK_DIR}/report.md" "${DRY_REPORT}"
  log_info "[DRY_RUN] 리포트 생성(비파괴): ${DRY_REPORT}"
else
  cp "${WORK_DIR}/report.md" "${REPORT}"
  REPORT_SIZE="$(wc -c < "${REPORT}" | tr -d ' ')"
  log_info "리포트 생성 완료: ${REPORT} (${REPORT_SIZE} bytes)"
fi

log_info "===== skill_audit_worker 완료 ====="
exit 0

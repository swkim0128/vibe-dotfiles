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
#   ~/.claude/projects/<프로젝트디렉토리>/**/*.jsonl  (서브에이전트 <uuid>/subagents/*.jsonl 포함)
#     - 한 줄 = 한 JSON 이벤트. timestamp 는 UTC(…Z).
#     - 스킬 호출:      Skill tool_use 의 input.skill
#     - 에이전트 호출:  Agent tool_use 의 input.subagent_type (생략 시 general-purpose)
#     - 슬래시 명령:    user 메시지 본문 <command-name>/<name></command-name> (내장 명령 제외)
#     - 디렉토리명(-Users-eunsol-Project-...)이 곧 프로젝트 식별자.
#   집계 구간: 직전 실행 워터마크(${LOG_DIR}/watermark) 초과 ~ 이번 실행 시각 이하.
#     날짜(UTC) 단위로 자르면 22:00 실행 기준 KST 22~09시 사용이 영구 누락된다.
#   ~/.claude/settings.json · settings.local.json  → enabledPlugins (값 true)
#   ~/.claude/plugins/marketplaces/*/*/plugins/*/skills/*/SKILL.md → 설치 스킬
#   ~/.claude/plugins/marketplaces/*/*/plugins/*/agents/*.md       → 설치 에이전트
#
# 사용법:
#   직접 실행은 권장하지 않음. launchd 또는 테스트 시 dry-run.
#     DRY_RUN=1 ./skill_audit_worker.sh
#   DRY_RUN=1 이면 트랜스크립트 스캔은 하되 ledger append·최종 파일은 [DRY] 표기.
#
# 수동 부트스트랩 (install.sh 는 plist 를 배포하지 않음 — SoC):
#   cp vibe-tools/com.swkim0128.skill-audit.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.skill-audit.plist
#   (해제: launchctl bootout gui/$(id -u)/com.swkim0128.skill-audit)

set -euo pipefail

# ── 설정 ─────────────────────────────────────────────────────────────────────
CLAUDE_HOME="${CLAUDE_HOME:-${HOME}/.claude}"
PROJECTS_DIR="${CLAUDE_HOME}/projects"
MARKETPLACES_DIR="${CLAUDE_HOME}/plugins/marketplaces"
PLUGINS_CACHE_DIR="${CLAUDE_HOME}/plugins/cache"
USER_SKILLS_DIR="${CLAUDE_HOME}/skills"
LOG_DIR="${HOME}/Library/Logs/skill-audit"
TODAY="$(date +%F)"
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
REPORT="${LOG_DIR}/${TODAY}.md"
LEDGER="${LOG_DIR}/ledger.tsv"
LOG_FILE="${LOG_DIR}/${TODAY}.log"
DRY_RUN="${DRY_RUN:-0}"

# 보호 마켓플레이스 — 회사 등 외부가 배포한 자산. 제거/비활성 후보 산출에서 원천 배제하되
# 리포트의 '보호 대상' 섹션에 노출해 "왜 후보에 없는지"를 드러낸다.
# 공백 구분 다중 값 허용. 하드코딩 금지 — 기본값만 cc-claude(회사 GitLab 마켓플레이스).
PROTECTED_MARKETPLACES="${PROTECTED_MARKETPLACES:-cc-claude}"
read -r -a PROTECTED_MP_ARR <<< "${PROTECTED_MARKETPLACES}"

# 계절성(저빈도 주기) 스킬 탐지 키워드 — SKILL.md frontmatter description 에서 찾는다.
# 호출 주기가 원장 축적일수보다 길거나 비슷하면 "누적 0"이 미사용의 증거가 되지 못한다.
SEASONAL_PATTERN="${SEASONAL_PATTERN:-주간|weekly|매주|월간|monthly|매월|분기|quarterly|반기|연간|금요일|일요일|월요일|월말|주말}"
# 관측 부족 판정 임계 — 정본 레포에 SKILL.md 가 처음 추가된 시각이 이 일수 이내면 "최근 추가"로 본다
# (git 이력이 없을 때만 파일 mtime 폴백 — 재설치·재배포가 mtime 을 갱신하므로 오탐 가능).
RECENT_DAYS="${RECENT_DAYS:-14}"
# 슬래시 명령 중 사용량 감사 대상이 아닌 Claude Code 내장 명령 (공백 구분, 접두 없는 이름만 비교).
SLASH_BUILTINS="${SLASH_BUILTINS:-add-dir agents artifacts bashes btw bug clear compact config context copy cost doctor effort exit export fast feedback help hooks ide init install-github-app keybindings login logout mcp memory model output-style permissions plan plugin plugins pr-comments privacy-settings release-notes reload-plugins remote-control rename resume review rewind sandbox security-review skills status statusline stats tasks terminal-setup theme todos upgrade usage vim}"

mkdir -p "${LOG_DIR}"

# 집계 구간 — (WIN_START, WIN_END]. 트랜스크립트 timestamp(UTC ISO8601, 밀리초) 와 문자열 비교한다.
WATERMARK="${LOG_DIR}/watermark"
WIN_END="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
WIN_START=""
if [[ -f "${WATERMARK}" ]]; then
  WIN_START="$(tr -d '[:space:]' < "${WATERMARK}")"
fi
if ! [[ "${WIN_START}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]; then
  # 워터마크 부재(첫 실행·이전 버전) → 직전 24시간. 이전 버전은 UTC 당일 0시~실행 시각만 셌으므로 겹치지 않는다.
  WIN_START="$(date -u -v-24H '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null || date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%S.000Z')"
fi

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
log_info "집계 구간(UTC): ${WIN_START} 초과 ~ ${WIN_END} 이하"

# ─────────────────────────────────────────────────────────────────────────────
# (A) 당일 사용 집계
#   결과물:
#     ${WORK_DIR}/usage_global.tsv    : type\tname\tcount   (전역 합산)
#     ${WORK_DIR}/usage_by_project.tsv: project\ttype\tname\tcount
# ─────────────────────────────────────────────────────────────────────────────

# 한 트랜스크립트 파일에서 집계 구간 내 skill/agent/command 이름을 추출해 표준출력.
#   출력 형식: "<type>\t<name>" (한 줄 = 이벤트 1건)
#   - skill   : Skill tool_use (모델 호출)
#   - agent   : Agent(구 Task) tool_use. subagent_type 생략 시 기본값 general-purpose
#   - command : 사용자가 입력한 슬래시 명령(/<name>). 스킬을 슬래시로 부르면 Skill tool_use 가
#               남지 않으므로 이 경로로만 셀 수 있다. 서브에이전트(isSidechain) 줄은 제외.
# jq 폴백 포함. jq 실패/미존재 시 grep/grep -o 로 라인 파싱.
extract_events() {
  local file="$1"
  if [[ ${HAS_JQ} -eq 1 ]]; then
    # jq 파싱 실패(깨진 줄)는 -R 로 라인단위 시도하되 오류는 무시.
    jq -R -r --arg s "${WIN_START}" --arg e "${WIN_END}" '(try (fromjson) catch empty)
      | select(type == "object")
      | select((.timestamp // "") as $ts | $ts > $s and $ts <= $e)
      | . as $ev
      | (.message.content // empty) as $c
      | if ($c | type) == "array" then
          $c[] | select(type == "object" and (.type? // "") == "tool_use")
          | if (.name == "Skill" and (.input.skill // null) != null) then "skill\t\(.input.skill)"
            elif (.name == "Agent") then "agent\t\(.input.subagent_type // "general-purpose")"
            elif (.name == "Task" and (.input.subagent_type // null) != null) then "agent\t\(.input.subagent_type)"
            else empty end
        elif ($c | type) == "string" and ($ev.type // "") == "user" and ($ev.isSidechain // false) != true then
          ($c | capture("^\\s*(<command-message>[^<]*</command-message>\\s*)?<command-name>/(?<n>[^<\\s]+)</command-name>")
            | "command\t\(.n)")
        else empty end' "${file}" 2>/dev/null || true
  else
    # 폴백: timestamp 를 문자열 비교해 구간 내 줄만 남기고 skill / subagent_type / 슬래시 명령을 추출.
    local LC_ALL=C
    grep -F '"timestamp":"' "${file}" 2>/dev/null | while IFS= read -r line; do
      local ts sk ag cm
      ts="$(printf '%s' "${line}" | grep -o '"timestamp":"[^"]*"' | head -n1 | sed 's/^"timestamp":"//; s/"$//')"
      [[ "${ts}" > "${WIN_START}" && ! "${ts}" > "${WIN_END}" ]] || continue
      sk="$(printf '%s' "${line}" | grep -o '"skill":"[^"]*"' | head -n1 | sed 's/^"skill":"//; s/"$//')"
      if [[ -n "${sk}" ]]; then
        printf 'skill\t%s\n' "${sk}"
      fi
      ag="$(printf '%s' "${line}" | grep -o '"subagent_type":"[^"]*"' | head -n1 | sed 's/^"subagent_type":"//; s/"$//')"
      if [[ -n "${ag}" ]]; then
        printf 'agent\t%s\n' "${ag}"
      fi
      if [[ "${line}" == *'"type":"user"'* && "${line}" != *'"isSidechain":true'* ]]; then
        cm="$(printf '%s' "${line}" | grep -o '"content":"[^"]\{0,120\}<command-name>/[^<]*</command-name>' | head -n1 | sed 's/.*<command-name>\///; s/<\/command-name>$//')"
        if [[ -n "${cm}" ]]; then
          printf 'command\t%s\n' "${cm}"
        fi
      fi
    done
  fi
}

# 내장 슬래시 명령(/clear·/mcp 등)은 자산 사용량이 아니므로 원장에 넣지 않는다.
drop_builtin_commands() {
  awk -F"\t" -v b=" ${SLASH_BUILTINS} " '!($1 == "command" && index(b, " "$2" ") > 0)'
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
    # 재귀 — 서브에이전트 트랜스크립트(<uuid>/subagents/agent-*.jsonl)도 포함해야
    # 서브에이전트 안에서 호출된 스킬·에이전트가 집계된다.
    while IFS= read -r jf; do
      [[ -f "${jf}" ]] || continue
      TRANSCRIPT_COUNT=$((TRANSCRIPT_COUNT + 1))
      extract_events "${jf}" | drop_builtin_commands >> "${WORK_DIR}/events_proj.tmp"
    done < <(find "${proj_path}" -type f -name '*.jsonl' 2>/dev/null)
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
#   집계 구간 전역 집계를 실행일(date) 행으로 append. DRY_RUN 이면 생략.
#   워터마크는 append 가 실제로 반영됐을 때만(또는 구간 사용 0일 때) 전진한다 —
#   중복 방지로 append 를 건너뛴 구간은 다음 실행이 다시 센다.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "[DRY_RUN] ledger append·워터마크 갱신 생략."
else
  ADVANCE_WATERMARK=1
  if [[ -s "${WORK_DIR}/usage_global.tsv" ]]; then
    # 같은 날짜 중복 append 방지: 오늘 날짜 행이 이미 있으면 재기록하지 않음.
    if [[ -f "${LEDGER}" ]] && grep -q "^${TODAY}"$'\t' "${LEDGER}"; then
      log_warn "ledger 에 오늘(${TODAY}) 행이 이미 존재 — append 생략(중복 방지), 워터마크 유지."
      ADVANCE_WATERMARK=0
    else
      awk -v d="${TODAY}" -F"\t" '{ print d"\t"$1"\t"$2"\t"$3 }' \
        "${WORK_DIR}/usage_global.tsv" >> "${LEDGER}"
      log_info "ledger append 완료: ${TODAY} (${TODAY_DISTINCT} 행)."
    fi
  else
    log_info "집계 구간 사용 0 — ledger append 대상 없음."
  fi
  if [[ "${ADVANCE_WATERMARK}" -eq 1 ]]; then
    printf '%s\n' "${WIN_END}" > "${WATERMARK}"
    log_info "워터마크 갱신: ${WIN_END}"
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

# name -> 누적 count 조회 헬퍼는 이름 이관 병합(C-5) 이후에 정의된다 — 병합본이 조회 정본.
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
# 정규화. enabledPlugins 키는 이미 '<plugin>@<marketplace>' 형식이므로 그대로 활성 판정 키로 쓴다.
#   플러그인명만으로 판정하면 마켓플레이스가 다른 동명 플러그인(cc-claude/analyze vs analyze@swkim0128)이
#   서로의 활성 여부를 물려받아 귀속이 틀어진다.
: > "${WORK_DIR}/enabled_plugin_keys.txt"
: > "${WORK_DIR}/enabled_plugin_names.txt"
if [[ -s "${WORK_DIR}/enabled_plugins.txt" ]]; then
  sort -u "${WORK_DIR}/enabled_plugins.txt" > "${WORK_DIR}/enabled_plugin_keys.txt"
  awk -F'@' '{ print $1 }' "${WORK_DIR}/enabled_plugins.txt" | sort -u \
    > "${WORK_DIR}/enabled_plugin_names.txt"
fi
ENABLED_PLUGIN_COUNT="$(wc -l < "${WORK_DIR}/enabled_plugin_keys.txt" | tr -d ' ')"
log_info "활성 플러그인 수: ${ENABLED_PLUGIN_COUNT}"

# (C-1a) 인벤토리 필터 헬퍼.
#   마켓플레이스 디렉토리 깊이는 불균일하다 —
#     swkim0128/claude/plugins/... · cc-claude/plugins/utils/... · claude-plugins-official/plugins/...
#   따라서 basename 고정 깊이 역산으로 마켓플레이스를 잡을 수 없다.
#   MARKETPLACES_DIR 접두를 제거한 뒤 첫 경로 세그먼트(${rel%%/*})를 마켓플레이스명으로 쓴다.
#   활성 판정은 '<plugin>@<marketplace>' 키 단위 — 동명 플러그인의 오귀속을 막는다.
is_enabled_plugin() {
  grep -Fxq "$1@$2" "${WORK_DIR}/enabled_plugin_keys.txt"
}
is_protected_marketplace() {
  local mp="$1" p
  for p in "${PROTECTED_MP_ARR[@]}"; do
    [[ "${mp}" == "${p}" ]] && return 0
  done
  return 1
}

# (C-2) 설치 스킬 — 두 소스를 합친다.
#   소스 ① 플러그인 스킬: <marketplace>/**/<plugin>/skills/<skill>/SKILL.md → '<plugin>:<skill>'
#     ⚠️ find -path '*/plugins/*/skills/*/SKILL.md' 는 '*' 가 '/' 를 넘어 매칭돼
#        마켓플레이스 루트의 비-플러그인 스킬트리(~/.claude/plugins/ 의 'plugins' 세그먼트에
#        걸림)까지 빨아들이고 엉뚱한 디렉토리를 플러그인명으로 뽑는다.
#        → MARKETPLACES_DIR 접두를 제거한 상대경로에 'plugins/' 세그먼트가 있는지,
#          그리고 조부모 디렉토리가 정확히 'skills' 인지로 판정한다.
#     산출 단계: 전체 → 활성 플러그인 소속 → 보호 마켓플레이스 제외 → 감사 대상.
#     비활성 플러그인 소속 스킬은 애초에 로드되지 않으므로 "안 씀"으로 계상하면 오탐이다.
#   소스 ② 사용자 스킬: ${CLAUDE_HOME}/skills/<skill>/SKILL.md → 접두 없는 '<skill>'.
#     플러그인 소속이 아니라 항상 활성이므로 활성/보호 필터 대상이 아니다.
#     트랜스크립트·원장이 접두 없는 이름으로 기록하므로 인벤토리 이름도 접두 없이 쓴다.
#   소스 ③ 설치 캐시: ${PLUGINS_CACHE_DIR}/<marketplace>/<plugin>/<version>/skills/<skill>/SKILL.md
#     marketplaces/ 는 레포 체크아웃일 뿐이고 실제 로드되는 페이로드는 캐시에 있다.
#     여기에만 존재하는 플러그인(slack·github·context7·claude-dashboard·php-lsp·
#     andrej-karpathy-skills 등)이 있어 캐시를 빼면 통째로 인벤토리에서 누락된다.
#     ①과 (marketplace, plugin, skill) 키로 중복 제거해 이중 계상하지 않는다.
: > "${WORK_DIR}/all_skills_raw.tsv"
: > "${WORK_DIR}/all_skills.tsv"
: > "${WORK_DIR}/enabled_skills.tsv"
: > "${WORK_DIR}/protected_skills.tsv"
: > "${WORK_DIR}/user_skills.txt"
: > "${WORK_DIR}/installed_skills.txt"
: > "${WORK_DIR}/skill_paths.tsv"
if [[ -d "${MARKETPLACES_DIR}" ]]; then
  while IFS= read -r skmd; do
    [[ -n "${skmd}" ]] || continue
    rel="${skmd#"${MARKETPLACES_DIR}"/}"
    # 마켓플레이스 내부에 plugins/ 세그먼트가 있어야 플러그인 스킬이다.
    [[ "${rel}" == plugins/* || "${rel}" == */plugins/* ]] || continue
    # <plugin>/skills/<skill>/SKILL.md 구조인지 확인 후 plugin 과 skill 추출
    [[ "$(basename "$(dirname "$(dirname "${skmd}")")")" == "skills" ]] || continue
    skill_dir="$(basename "$(dirname "${skmd}")")"
    plugin_dir="$(basename "$(dirname "$(dirname "$(dirname "${skmd}")")")")"
    printf '%s\t%s\t%s\t%s\n' "${rel%%/*}" "${plugin_dir}" "${skill_dir}" "${skmd}"
  done < <(find "${MARKETPLACES_DIR}" -type f -name 'SKILL.md' 2>/dev/null) \
    >> "${WORK_DIR}/all_skills_raw.tsv"
fi
if [[ -d "${PLUGINS_CACHE_DIR}" ]]; then
  while IFS= read -r skmd; do
    [[ -n "${skmd}" ]] || continue
    rel="${skmd#"${PLUGINS_CACHE_DIR}"/}"
    [[ "$(basename "$(dirname "$(dirname "${skmd}")")")" == "skills" ]] || continue
    ca_mp="${rel%%/*}"
    ca_rest="${rel#*/}"
    ca_plugin="${ca_rest%%/*}"
    [[ -n "${ca_mp}" && -n "${ca_plugin}" ]] || continue
    printf '%s\t%s\t%s\t%s\n' "${ca_mp}" "${ca_plugin}" "$(basename "$(dirname "${skmd}")")" "${skmd}"
  done < <(find -L "${PLUGINS_CACHE_DIR}" -type f -name 'SKILL.md' 2>/dev/null) \
    >> "${WORK_DIR}/all_skills_raw.tsv"
fi
# (marketplace, plugin, skill) 3필드 기준 중복 제거 — 같은 자산의 체크아웃/캐시 이중 계상 방지.
sort -t"$(printf '\t')" -k1,3 -u "${WORK_DIR}/all_skills_raw.tsv" > "${WORK_DIR}/all_skills.tsv"
while IFS=$'\t' read -r sk_mp sk_plug sk_name sk_path; do
  [[ -n "${sk_name}" ]] || continue
  if is_enabled_plugin "${sk_plug}" "${sk_mp}"; then
    printf '%s\t%s\t%s\t%s\n' "${sk_mp}" "${sk_plug}" "${sk_name}" "${sk_path}" \
      >> "${WORK_DIR}/enabled_skills.tsv"
  fi
done < "${WORK_DIR}/all_skills.tsv"
while IFS=$'\t' read -r sk_mp sk_plug sk_name sk_path; do
  [[ -n "${sk_name}" ]] || continue
  if is_protected_marketplace "${sk_mp}"; then
    printf '%s\t%s\t%s\n' "${sk_mp}" "${sk_plug}" "${sk_name}" >> "${WORK_DIR}/protected_skills.tsv"
  else
    printf '%s:%s\n' "${sk_plug}" "${sk_name}" >> "${WORK_DIR}/installed_skills.txt"
    printf '%s:%s\t%s\n' "${sk_plug}" "${sk_name}" "${sk_path}" >> "${WORK_DIR}/skill_paths.tsv"
  fi
done < "${WORK_DIR}/enabled_skills.tsv"
if [[ -d "${USER_SKILLS_DIR}" ]]; then
  while IFS= read -r usmd; do
    [[ -n "${usmd}" ]] || continue
    printf '%s\t%s\n' "$(basename "$(dirname "${usmd}")")" "${usmd}"
  done < <(find -L "${USER_SKILLS_DIR}" -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null) \
    | sort -u > "${WORK_DIR}/user_skills.tsv"
  awk -F"\t" '{ print $1 }' "${WORK_DIR}/user_skills.tsv" | sort -u > "${WORK_DIR}/user_skills.txt"
  cat "${WORK_DIR}/user_skills.tsv" >> "${WORK_DIR}/skill_paths.tsv"
fi
cat "${WORK_DIR}/user_skills.txt" >> "${WORK_DIR}/installed_skills.txt"
sort -u -o "${WORK_DIR}/installed_skills.txt" "${WORK_DIR}/installed_skills.txt"
sort -t"$(printf '\t')" -k1,1 -u -o "${WORK_DIR}/skill_paths.tsv" "${WORK_DIR}/skill_paths.tsv"
SKILL_ALL_COUNT="$(wc -l < "${WORK_DIR}/all_skills.tsv" | tr -d ' ')"
SKILL_ENABLED_COUNT="$(wc -l < "${WORK_DIR}/enabled_skills.tsv" | tr -d ' ')"
PROTECTED_SKILL_COUNT="$(wc -l < "${WORK_DIR}/protected_skills.tsv" | tr -d ' ')"
USER_SKILL_COUNT="$(wc -l < "${WORK_DIR}/user_skills.txt" | tr -d ' ')"
INSTALLED_SKILL_COUNT="$(wc -l < "${WORK_DIR}/installed_skills.txt" | tr -d ' ')"
log_info "설치 스킬 수: 플러그인 전체 ${SKILL_ALL_COUNT} → 활성 ${SKILL_ENABLED_COUNT} → 보호제외 ${PROTECTED_SKILL_COUNT} · 사용자 스킬 ${USER_SKILL_COUNT} → 감사대상 ${INSTALLED_SKILL_COUNT}"

# (C-3) 설치 에이전트 — agents/<name>.md 의 name. 스킬과 동일하게 체크아웃+캐시 두 소스를 합친다.
#   캐시 경로: <marketplace>/<plugin>/<version>/agents/<name>.md
#   스킬 내부 에이전트(.../skills/<skill>/agents/<name>.md)는 서브에이전트 타입으로 등록되지
#   않는 스킬 부속 자산이므로 제외한다.
: > "${WORK_DIR}/all_agents_raw.tsv"
: > "${WORK_DIR}/all_agents.tsv"
: > "${WORK_DIR}/enabled_agents.tsv"
: > "${WORK_DIR}/protected_agents.tsv"
: > "${WORK_DIR}/installed_agents.txt"
if [[ -d "${MARKETPLACES_DIR}" ]]; then
  while IFS= read -r agmd; do
    [[ -n "${agmd}" ]] || continue
    rel="${agmd#"${MARKETPLACES_DIR}"/}"
    [[ "${rel}" == plugins/* || "${rel}" == */plugins/* ]] || continue
    [[ "${rel}" != */skills/* ]] || continue
    [[ "$(basename "$(dirname "${agmd}")")" == "agents" ]] || continue
    printf '%s\t%s\t%s\n' "${rel%%/*}" \
      "$(basename "$(dirname "$(dirname "${agmd}")")")" "$(basename "${agmd}" .md)"
  done < <(find "${MARKETPLACES_DIR}" -type f -name '*.md' -path '*/agents/*' 2>/dev/null) \
    >> "${WORK_DIR}/all_agents_raw.tsv"
fi
if [[ -d "${PLUGINS_CACHE_DIR}" ]]; then
  while IFS= read -r agmd; do
    [[ -n "${agmd}" ]] || continue
    rel="${agmd#"${PLUGINS_CACHE_DIR}"/}"
    [[ "${rel}" != */skills/* ]] || continue
    [[ "$(basename "$(dirname "${agmd}")")" == "agents" ]] || continue
    ca_mp="${rel%%/*}"
    ca_rest="${rel#*/}"
    ca_plugin="${ca_rest%%/*}"
    [[ -n "${ca_mp}" && -n "${ca_plugin}" ]] || continue
    printf '%s\t%s\t%s\n' "${ca_mp}" "${ca_plugin}" "$(basename "${agmd}" .md)"
  done < <(find -L "${PLUGINS_CACHE_DIR}" -type f -name '*.md' -path '*/agents/*' 2>/dev/null) \
    >> "${WORK_DIR}/all_agents_raw.tsv"
fi
sort -u "${WORK_DIR}/all_agents_raw.tsv" > "${WORK_DIR}/all_agents.tsv"
while IFS=$'\t' read -r ag_mp ag_plug ag_nm; do
  [[ -n "${ag_nm}" ]] || continue
  if is_enabled_plugin "${ag_plug}" "${ag_mp}"; then
    printf '%s\t%s\t%s\n' "${ag_mp}" "${ag_plug}" "${ag_nm}" >> "${WORK_DIR}/enabled_agents.tsv"
  fi
done < "${WORK_DIR}/all_agents.tsv"
while IFS=$'\t' read -r ag_mp ag_plug ag_nm; do
  [[ -n "${ag_nm}" ]] || continue
  if is_protected_marketplace "${ag_mp}"; then
    printf '%s\t%s\t%s\n' "${ag_mp}" "${ag_plug}" "${ag_nm}" >> "${WORK_DIR}/protected_agents.tsv"
  else
    printf '%s\n' "${ag_nm}" >> "${WORK_DIR}/installed_agents.txt"
  fi
done < "${WORK_DIR}/enabled_agents.tsv"
sort -u -o "${WORK_DIR}/installed_agents.txt" "${WORK_DIR}/installed_agents.txt"
AGENT_ALL_COUNT="$(wc -l < "${WORK_DIR}/all_agents.tsv" | tr -d ' ')"
AGENT_ENABLED_COUNT="$(wc -l < "${WORK_DIR}/enabled_agents.tsv" | tr -d ' ')"
PROTECTED_AGENT_COUNT="$(wc -l < "${WORK_DIR}/protected_agents.tsv" | tr -d ' ')"
INSTALLED_AGENT_COUNT="$(wc -l < "${WORK_DIR}/installed_agents.txt" | tr -d ' ')"
log_info "설치 에이전트 수: 전체 ${AGENT_ALL_COUNT} → 활성 ${AGENT_ENABLED_COUNT} → 보호제외 ${PROTECTED_AGENT_COUNT} → 감사대상 ${INSTALLED_AGENT_COUNT}"

# (C-3a) 보호 대상 요약 — 마켓플레이스·플러그인별 스킬/에이전트 수.
: > "${WORK_DIR}/protected_items.tsv"
awk -F"\t" '{ print $1"\t"$2"\tskill" }' \
  "${WORK_DIR}/protected_skills.tsv" >> "${WORK_DIR}/protected_items.tsv"
awk -F"\t" '{ print $1"\t"$2"\tagent" }' \
  "${WORK_DIR}/protected_agents.tsv" >> "${WORK_DIR}/protected_items.tsv"
awk -F"\t" '{ k=$1"\t"$2; seen[k]=1; if ($3 == "skill") s[k]++; else g[k]++ }
  END { for (k in seen) printf "%s\t%d\t%d\n", k, s[k]+0, g[k]+0 }' \
  "${WORK_DIR}/protected_items.tsv" | sort > "${WORK_DIR}/protected_summary.tsv"

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
#   ⚠️ -path '*/plugins/*/hooks' 는 MARKETPLACES_DIR 자체의 'plugins' 세그먼트에 걸려
#      .git/hooks·src/hooks·dist/hooks 같은 비-플러그인 폴더까지 플러그인으로 잡는다.
#      → 숨김 세그먼트 경로를 배제하고, hooks/ 의 부모가 플러그인 매니페스트
#        (.claude-plugin/plugin.json)를 가진 경우만 플러그인으로 인정한다.
: > "${WORK_DIR}/plugin_hooks.txt"
if [[ -d "${MARKETPLACES_DIR}" ]]; then
  while IFS= read -r hd; do
    [[ -n "${hd}" ]] || continue
    rel="${hd#"${MARKETPLACES_DIR}"/}"
    [[ "${rel}" != .* && "${rel}" != */.* ]] || continue
    [[ -f "$(dirname "${hd}")/.claude-plugin/plugin.json" ]] || continue
    plugin_dir="$(basename "$(dirname "${hd}")")"
    printf '%s\n' "${plugin_dir}"
  done < <(find "${MARKETPLACES_DIR}" -type d -name 'hooks' -not -path '*/node_modules/*' 2>/dev/null) \
    | sort -u > "${WORK_DIR}/plugin_hooks.txt"
fi
HOOK_EVENT_COUNT="$(wc -l < "${WORK_DIR}/hooks_config.txt" | tr -d ' ')"
PLUGIN_HOOK_COUNT="$(wc -l < "${WORK_DIR}/plugin_hooks.txt" | tr -d ' ')"
log_info "설정 훅 이벤트 수: ${HOOK_EVENT_COUNT} / 훅 보유 플러그인 수: ${PLUGIN_HOOK_COUNT}"

# ─────────────────────────────────────────────────────────────────────────────
# (C-5) 이름 이관 병합 — 원장 집계 시점에만 수행. ledger.tsv 는 append-only 이력이라 손대지 않는다.
#   2026-07-31 스킬 이관(플러그인 → 전역)으로 같은 자산이 '<plugin>:<name>' 과 접두 없는
#   '<name>' 두 이름으로 원장에 갈려 사용 빈도가 절반으로 과소평가된다.
#   규칙: '<plugin>:<name>' 의 <name> 이 (원장 또는 인벤토리의) 접두 없는 이름과 일치하면
#         접두 없는 이름으로 합산한다.
#   결과물: ledger_summary_merged.tsv (type\tname\ttotal) · name_merges.tsv (from\tto\tfrom_n\tto_n\tsum)
: > "${WORK_DIR}/merge_targets.txt"
{
  awk -F"\t" '$2 !~ /:/ { print $2 }' "${WORK_DIR}/ledger_summary.tsv"
  cat "${WORK_DIR}/installed_skills.txt"
  cat "${WORK_DIR}/installed_agents.txt"
} >> "${WORK_DIR}/merge_targets.txt"
grep -v ':' "${WORK_DIR}/merge_targets.txt" > "${WORK_DIR}/merge_targets_bare.txt" || true
sort -u -o "${WORK_DIR}/merge_targets_bare.txt" "${WORK_DIR}/merge_targets_bare.txt"
: > "${WORK_DIR}/ledger_canonical.tsv"
while IFS=$'\t' read -r lg_type lg_name lg_total; do
  [[ -n "${lg_name}" ]] || continue
  canon="${lg_name}"
  if [[ "${lg_name}" == *:* ]]; then
    bare="${lg_name##*:}"
    if grep -Fxq "${bare}" "${WORK_DIR}/merge_targets_bare.txt"; then
      canon="${bare}"
    fi
  fi
  printf '%s\t%s\t%s\t%s\n' "${lg_type}" "${canon}" "${lg_total}" "${lg_name}" \
    >> "${WORK_DIR}/ledger_canonical.tsv"
done < "${WORK_DIR}/ledger_summary.tsv"
: > "${WORK_DIR}/ledger_summary_merged.tsv"
: > "${WORK_DIR}/name_merges.tsv"
if [[ -s "${WORK_DIR}/ledger_canonical.tsv" ]]; then
  awk -F"\t" '{ key=$1"\t"$2; sum[key]+=$3 }
    END { for (k in sum) print k"\t"sum[k] }' "${WORK_DIR}/ledger_canonical.tsv" \
    | sort -t"$(printf '\t')" -k3,3nr > "${WORK_DIR}/ledger_summary_merged.tsv"
  # 실제로 이름이 바뀐(=병합된) 행만 뽑아 근거로 남긴다.
  awk -F"\t" '$2 != $4 { print $4"\t"$2"\t"$3 }' "${WORK_DIR}/ledger_canonical.tsv" \
    | sort > "${WORK_DIR}/name_merges_raw.tsv"
  while IFS=$'\t' read -r mg_from mg_to mg_from_n; do
    [[ -n "${mg_from}" ]] || continue
    mg_to_n="$(awk -F"\t" -v n="${mg_to}" '$2==n && $4==n { s+=$3 } END { print s+0 }' \
      "${WORK_DIR}/ledger_canonical.tsv")"
    mg_sum="$(awk -F"\t" -v n="${mg_to}" '$2==n { s+=$3 } END { print s+0 }' \
      "${WORK_DIR}/ledger_canonical.tsv")"
    printf '%s\t%s\t%s\t%s\t%s\n' "${mg_from}" "${mg_to}" "${mg_from_n}" "${mg_to_n}" "${mg_sum}" \
      >> "${WORK_DIR}/name_merges.tsv"
  done < "${WORK_DIR}/name_merges_raw.tsv"
fi
NAME_MERGE_COUNT="$(wc -l < "${WORK_DIR}/name_merges.tsv" | tr -d ' ')"
log_info "이름 이관 병합 쌍: ${NAME_MERGE_COUNT}"

# 병합본을 누적 조회의 정본으로 승격 (원장 파일 자체는 불변).
ledger_total_for() {
  local name="$1"
  awk -F"\t" -v n="${name}" '$2==n { s+=$3 } END { print s+0 }' \
    "${WORK_DIR}/ledger_summary_merged.tsv" 2>/dev/null || echo 0
}

# ─────────────────────────────────────────────────────────────────────────────
# (C-6) 계절성 판정 — 호출 주기가 원장 축적일수보다 길거나 비슷한 스킬은 "누적 0"이
#   미사용의 증거가 되지 못한다(주간 스킬은 38일에 5회, 월간은 1회 남짓).
#   SKILL.md frontmatter 의 description 에서 주기 신호를 찾아 표시한다.
#   결과물: seasonal.tsv : name\tkeyword\tsnippet
: > "${WORK_DIR}/seasonal.tsv"
while IFS=$'\t' read -r sp_name sp_path; do
  [[ -n "${sp_path}" ]] || continue
  [[ -f "${sp_path}" ]] || continue
  desc="$(awk '/^description:/ { found=1 } found { print } /^---[[:space:]]*$/ { if (found) exit }' \
    "${sp_path}" 2>/dev/null | head -c 2000 || true)"
  [[ -n "${desc}" ]] || continue
  kw="$(printf '%s' "${desc}" | grep -oiE "${SEASONAL_PATTERN}" | head -n1 || true)"
  [[ -n "${kw}" ]] || continue
  snippet="$(printf '%s' "${desc}" | grep -oiE ".{0,24}(${SEASONAL_PATTERN}).{0,24}" | head -n1 || true)"
  printf '%s\t%s\t%s\n' "${sp_name}" "${kw}" "${snippet}" >> "${WORK_DIR}/seasonal.tsv"
done < "${WORK_DIR}/skill_paths.tsv"
SEASONAL_COUNT="$(wc -l < "${WORK_DIR}/seasonal.tsv" | tr -d ' ')"
log_info "계절성(저빈도 주기) 스킬 수: ${SEASONAL_COUNT}"
is_seasonal() {
  awk -F"\t" -v n="$1" '$1==n { found=1 } END { exit !found }' "${WORK_DIR}/seasonal.tsv"
}
seasonal_reason_for() {
  awk -F"\t" -v n="$1" '$1==n { print $2"|"$3; exit }' "${WORK_DIR}/seasonal.tsv"
}

# ─────────────────────────────────────────────────────────────────────────────
# (C-7) 중복군 탐지 — 묶기만 한다. 병합·대표 선정은 사람/prune 스킬(작업 3/5) 몫.
#   신호 ① 접두를 뗀 basename 이 동일 (구/신 이름 또는 플러그인 간 중복 배포)
#   신호 ② 이름의 앞 두 토큰이 동일한 계열 (notion-weekly-*, tmux-session-* 등)
#   결과물: dup_groups.tsv : group\tname
: > "${WORK_DIR}/dup_groups.tsv"
awk -F"\t" '{ print $1 }' "${WORK_DIR}/skill_paths.tsv" > "${WORK_DIR}/dup_input.txt"
cat "${WORK_DIR}/installed_agents.txt" >> "${WORK_DIR}/dup_input.txt"
sort -u -o "${WORK_DIR}/dup_input.txt" "${WORK_DIR}/dup_input.txt"
awk '{
    full=$0
    bare=full; sub(/^.*:/, "", bare)
    basecnt[bare]++; baselist[bare]=baselist[bare]" "full
    n=split(bare, t, "-")
    if (n >= 3) { pre=t[1]"-"t[2]; precnt[pre]++; prelist[pre]=prelist[pre]" "full }
  }
  END {
    for (b in basecnt) if (basecnt[b] > 1) { split(baselist[b], m, " "); for (i in m) if (m[i] != "") print "이름중복:"b"\t"m[i] }
    for (p in precnt) if (precnt[p] > 1) { split(prelist[p], m, " "); for (i in m) if (m[i] != "") print "계열:"p"-*\t"m[i] }
  }' "${WORK_DIR}/dup_input.txt" | sort -u > "${WORK_DIR}/dup_groups.tsv"
DUP_GROUP_COUNT="$(awk -F"\t" '{ print $1 }' "${WORK_DIR}/dup_groups.tsv" | sort -u | wc -l | tr -d ' ')"
log_info "중복군 후보 수: ${DUP_GROUP_COUNT}"
dup_group_for() {
  awk -F"\t" -v n="$1" '$2==n { print $1; exit }' "${WORK_DIR}/dup_groups.tsv"
}

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

: > "${WORK_DIR}/candidates_graded.tsv"

# 정본 레포에서 SKILL.md 가 처음 git 에 추가된 시각(epoch). 산출 불가면 빈 출력.
#   ① 실경로(심링크 해소)가 git 작업트리 안이면 그 레포의 최초 추가 커밋 시각.
#   ② git 밖 배포 사본이면 상위 디렉토리의 .skill-lock.json 이 기록한 source 레포에서
#      같은 스킬명의 SKILL.md 를 찾아 최초 추가 커밋 시각.
#   shallow 클론은 경계 커밋이 '최초 추가'로 보이므로 신뢰하지 않는다.
git_added_epoch() {
  local top="$1" rel="$2"
  [[ "$(git -C "${top}" rev-parse --is-shallow-repository 2>/dev/null)" == "false" ]] || return 0
  git -C "${top}" log --follow --diff-filter=A --format=%ct -- "${rel}" 2>/dev/null | tail -n1
}
canonical_added_epoch() {
  local p="$1" real dir top ep d lock src name rel
  real="$(realpath "${p}" 2>/dev/null || printf '%s' "${p}")"
  dir="$(dirname "${real}")"
  if top="$(git -C "${dir}" rev-parse --show-toplevel 2>/dev/null)"; then
    ep="$(git_added_epoch "${top}" "${real#"${top}"/}")"
    if [[ -n "${ep}" ]]; then
      printf '%s\n' "${ep}"
      return 0
    fi
  fi
  [[ ${HAS_JQ} -eq 1 ]] || return 0
  name="$(basename "${dir}")"
  d="${dir}"
  lock=""
  for _ in 1 2 3; do
    d="$(dirname "${d}")"
    if [[ -f "${d}/.skill-lock.json" ]]; then
      lock="${d}/.skill-lock.json"
      break
    fi
  done
  [[ -n "${lock}" ]] || return 0
  src="$(jq -r --arg n "${name}" '.skills[$n].source // empty' "${lock}" 2>/dev/null || true)"
  [[ -n "${src}" && -d "${src}" ]] || return 0
  top="$(git -C "${src}" rev-parse --show-toplevel 2>/dev/null)" || return 0
  # 같은 이름이 여러 곳이면 skills/ 하위를 우선한다.
  rel="$(git -C "${top}" ls-files -- ":(glob)**/${name}/SKILL.md" 2>/dev/null \
    | awk '/^skills\// && s == "" { s = $0 } NR == 1 { f = $0 } END { print (s != "" ? s : f) }')"
  [[ -n "${rel}" ]] || return 0
  git_added_epoch "${top}" "${rel}"
}

# 관측 부족(B등급) 판정용 — 정본 git 최초 추가 시각이 RECENT_DAYS 이내인지.
#   git 이력이 없을 때만 파일 mtime 폴백(재설치·재배포로 갱신되므로 오탐 가능 — 사유에 명시).
#   판정 근거는 RECENT_BASIS 에 남겨 사유 문구에 쓴다.
RECENT_BASIS=""
is_recently_added() {
  local p="$1"
  RECENT_BASIS=""
  [[ -n "${p}" && -f "${p}" ]] || return 1
  local cutoff ep day
  cutoff=$(( $(date +%s) - RECENT_DAYS * 86400 ))
  ep="$(canonical_added_epoch "${p}")"
  if [[ -n "${ep}" ]]; then
    day="$(date -r "${ep}" +%F 2>/dev/null || date -d "@${ep}" +%F)"
    RECENT_BASIS="정본 git 최초 추가 ${day}"
  else
    ep="$(stat -f %m "${p}" 2>/dev/null || stat -c %Y "${p}" 2>/dev/null || echo 0)"
    day="$(date -r "${ep}" +%F 2>/dev/null || date -d "@${ep}" +%F)"
    RECENT_BASIS="git 이력 없음 — 파일 mtime ${day} 폴백, 재설치 오탐 가능"
  fi
  [[ "${ep}" -ge "${cutoff}" ]]
}

build_verdict() {
  local inventory="$1" out="$2" typlabel="$3"
  [[ -f "${inventory}" ]] || return 0
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    local total today verdict grade reason spath dgroup skw mgto
    total="$(ledger_total_for "${name}")"
    today="$(today_count_for "${name}")"
    if [[ "${total}" -gt 0 ]]; then
      verdict="✅ 사용 중(필요)"
    else
      verdict="❌ 누적 0 (정리 후보)"
      printf '%s\t%s\n' "${typlabel}" "${name}" >> "${WORK_DIR}/unused_candidates.txt"
      # ── 등급화: C(중복군) > B(계절성·관측부족) > A(즉시 정리 가능) 순으로 우선 적용.
      spath="$(awk -F"\t" -v n="${name}" '$1==n { print $2; exit }' "${WORK_DIR}/skill_paths.tsv")"
      dgroup="$(dup_group_for "${name}")"
      # 계절성이 중복군보다 우선한다 — 관측 표본이 부족한 항목을 통합 결정 대상으로
      # 올리는 것도 성급한 판단이므로, 먼저 관찰 유지(B)로 보류한다.
      if is_seasonal "${name}"; then
        skw="$(seasonal_reason_for "${name}")"
        grade="B"
        reason="계절성 — description 에서 '${skw%%|*}' 신호 감지(주기 > 원장 ${LEDGER_DAYS}일), 표본 부족"
        if [[ -n "${dgroup}" ]]; then
          reason="${reason} · 중복군 '${dgroup}' 소속이나 표본 부족으로 통합 판단 보류"
        fi
      elif [[ -n "${dgroup}" ]]; then
        grade="C"
        reason="중복군 '${dgroup}' 소속 — 대표 선정 후 통합 대상"
        mgto="$(awk -F"\t" -v n="${name}" '$1==n { print $2"("$5")"; exit }' "${WORK_DIR}/name_merges.tsv")"
        if [[ -n "${mgto}" ]]; then
          reason="${reason}. 사용 이력은 이관된 신 이름 ${mgto} 으로 합산됨 — 구 이름 정리 대상"
        fi
      elif is_recently_added "${spath}"; then
        grade="B"
        reason="최근 ${RECENT_DAYS}일 이내 추가 — 관측 표본 부족 (${RECENT_BASIS})"
      else
        grade="A"
        reason="누적 0 · 계절성 신호 없음 · 중복군 아님 (원장 ${LEDGER_DAYS}일 관측)"
      fi
      printf '%s\t%s\t%s\t%s\n' "${grade}" "${typlabel}" "${name}" "${reason}" \
        >> "${WORK_DIR}/candidates_graded.tsv"
    fi
    printf '%s\t%s\t%s\t%s\n' "${name}" "${verdict}" "${today}" "${total}" >> "${out}"
  done < "${inventory}"
}
build_verdict "${WORK_DIR}/installed_skills.txt" "${WORK_DIR}/verdict_skills.tsv" "skill"
build_verdict "${WORK_DIR}/installed_agents.txt" "${WORK_DIR}/verdict_agents.tsv" "agent"

sort -o "${WORK_DIR}/candidates_graded.tsv" "${WORK_DIR}/candidates_graded.tsv"
UNUSED_COUNT="$(wc -l < "${WORK_DIR}/unused_candidates.txt" | tr -d ' ')"
GRADE_A_COUNT="$(awk -F"\t" '$1=="A"' "${WORK_DIR}/candidates_graded.tsv" | wc -l | tr -d ' ')"
GRADE_B_COUNT="$(awk -F"\t" '$1=="B"' "${WORK_DIR}/candidates_graded.tsv" | wc -l | tr -d ' ')"
GRADE_C_COUNT="$(awk -F"\t" '$1=="C"' "${WORK_DIR}/candidates_graded.tsv" | wc -l | tr -d ' ')"
log_info "정리 후보 수: ${UNUSED_COUNT} (A ${GRADE_A_COUNT} / B ${GRADE_B_COUNT} / C ${GRADE_C_COUNT})"

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
  echo "> 생성: ${RUN_DATE} · 집계 구간(UTC): ${WIN_START} 초과 ~ ${WIN_END} 이하 (직전 실행 워터마크 기준) · 누적 원장 기준일수: ${LEDGER_DAYS}일"
  echo "> 집계 방식: 결정론적(grep/awk$([[ ${HAS_JQ} -eq 1 ]] && echo '+jq')) · LLM 미사용"
  echo ""
  echo "## 측정 한계"
  echo ""
  echo "- **세는 것**: 모델의 Skill 호출 · Agent 호출(subagent_type 생략 시 \`general-purpose\`) · 사용자가 입력한 슬래시 명령(\`command\` 타입, 내장 명령 제외) — 서브에이전트 트랜스크립트 포함, 실행 사이 전 구간(야간 포함)."
  echo "- **못 세는 것 (구조적)**:"
  echo "  - 이 기기의 Claude Code 트랜스크립트(\`${PROJECTS_DIR}\`) 밖 사용 — Codex·Gemini 등 다른 CLI, 다른 기기 사용은 원장에 없다."
  echo "  - 스킬 도구를 거치지 않은 사용 — 모델이 SKILL.md 를 직접 읽거나 지침만 참고한 경우."
  echo "  - 훅·MCP 도구는 사용 측정 대상 아님(설정 여부만)."
  echo "  - 워커가 오래 못 돈 사이 Claude Code 가 지운 트랜스크립트(보존 기간 초과분)."
  echo "  - 원장 날짜는 이벤트 발생일이 아니라 **집계한 실행일**이다(야간 사용은 다음 실행일 행에 들어감)."
  echo "- **B등급 '최근 추가'**: 정본 레포 git 최초 추가일 기준. git 이력을 못 찾은 항목만 파일 mtime 폴백이며 사유에 표시된다."
  echo ""

  echo "## 집계 구간 사용 (직전 실행 이후)"
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

  echo "## 누적 사용 Top (원장 기준, 이름 병합 후 합산 내림차순)"
  echo ""
  if [[ -s "${WORK_DIR}/ledger_summary_merged.tsv" ]]; then
    echo "| 타입 | 이름 | 누적 |"
    echo "|---|---|---:|"
    head -n 30 "${WORK_DIR}/ledger_summary_merged.tsv" \
      | awk -F"\t" '{ printf "| %s | %s | %s |\n", $1, $2, $3 }'
  else
    echo "_(원장 데이터 없음 — 첫 실행이거나 누적 사용 0)_"
  fi
  echo ""

  echo "## 설정 인벤토리"
  echo ""
  echo "> 스킬 인벤토리: 플러그인 전체(체크아웃+설치캐시 중복제거) ${SKILL_ALL_COUNT}개 → 활성 \`plugin@marketplace\` 소속 ${SKILL_ENABLED_COUNT}개 → 보호 제외 ${PROTECTED_SKILL_COUNT}개 · 사용자 스킬(\`~/.claude/skills\`) ${USER_SKILL_COUNT}개 합산 → 감사 대상 ${INSTALLED_SKILL_COUNT}개"
  echo "> 에이전트 인벤토리: 플러그인 전체(체크아웃+설치캐시 중복제거) ${AGENT_ALL_COUNT}개 → 활성 소속 ${AGENT_ENABLED_COUNT}개 → 보호 제외 ${PROTECTED_AGENT_COUNT}개 → 감사 대상 ${INSTALLED_AGENT_COUNT}개"
  echo "> 보호 마켓플레이스: ${PROTECTED_MARKETPLACES} · 계절성 탐지 ${SEASONAL_COUNT}건 · 중복군 ${DUP_GROUP_COUNT}군 · 이름 병합 ${NAME_MERGE_COUNT}쌍"
  echo ""
  echo "### 활성 플러그인 (${ENABLED_PLUGIN_COUNT})"
  echo ""
  if [[ -s "${WORK_DIR}/enabled_plugin_keys.txt" ]]; then
    while IFS= read -r p; do
      echo "- ${p}"
    done < "${WORK_DIR}/enabled_plugin_keys.txt"
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

  echo "## 보호 대상 (회사 제공 — 정리 제외)"
  echo ""
  echo "> 보호 마켓플레이스(\`PROTECTED_MARKETPLACES=${PROTECTED_MARKETPLACES}\`) 소속 자산은 그대로 사용하며 개인 자산으로 이관하지 않는다."
  echo "> 후보 산출에서 원천 배제되므로 아래 항목은 '제거/비활성 후보'에 나타나지 않는다."
  echo ""
  if [[ -s "${WORK_DIR}/protected_summary.tsv" ]]; then
    echo "| 마켓플레이스 | 플러그인 | 스킬 | 에이전트 |"
    echo "|---|---|---:|---:|"
    awk -F"\t" '{ printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }' "${WORK_DIR}/protected_summary.tsv"
  else
    echo "_(보호 대상 항목 없음 — 활성 플러그인 중 보호 마켓플레이스 소속이 없음)_"
  fi
  echo ""

  echo "## 이름 이관 병합 (${NAME_MERGE_COUNT}쌍)"
  echo ""
  echo "> 같은 자산이 구 이름(\`<plugin>:<name>\`)과 신 이름(접두 없음)으로 원장에 갈려 있어 사용량이 과소평가된다."
  echo "> **집계 시점에만 병합**하며 \`ledger.tsv\`(append-only 이력)는 수정하지 않는다."
  echo ""
  if [[ -s "${WORK_DIR}/name_merges.tsv" ]]; then
    echo "| 구 이름 | → 신 이름 | 구 누적 | 신 누적 | 병합 누적 |"
    echo "|---|---|---:|---:|---:|"
    awk -F"\t" '{ printf "| %s | %s | %s | %s | **%s** |\n", $1, $2, $3, $4, $5 }' \
      "${WORK_DIR}/name_merges.tsv"
  else
    echo "_(병합 대상 없음)_"
  fi
  echo ""

  echo "## 중복군 후보 (${DUP_GROUP_COUNT}군)"
  echo ""
  echo "> 이름·계열 신호로 묶기만 한다. **대표 선정·병합 결정은 하지 않는다**(사람/\`prune\` 몫)."
  echo "> 신호 ① 접두 제거 후 동일 basename · 신호 ② 앞 두 토큰이 같은 계열."
  echo ""
  if [[ -s "${WORK_DIR}/dup_groups.tsv" ]]; then
    echo "| 군 | 항목 | 누적(병합 후) |"
    echo "|---|---|---:|"
    while IFS=$'\t' read -r dg_group dg_name; do
      [[ -n "${dg_name}" ]] || continue
      printf '| %s | %s | %s |\n' "${dg_group}" "${dg_name}" "$(ledger_total_for "${dg_name}")"
    done < "${WORK_DIR}/dup_groups.tsv"
  else
    echo "_(중복군 없음)_"
  fi
  echo ""

  echo "## 권장 — 정리 후보 (${UNUSED_COUNT}) · A ${GRADE_A_COUNT} / B ${GRADE_B_COUNT} / C ${GRADE_C_COUNT}"
  echo ""
  echo "> 공통 조건: 병합 후 누적 사용 0. 원장 축적일수 ${LEDGER_DAYS}일."
  echo "> **A** 즉시 정리 가능 · **B** 관찰 유지(계절성·관측 부족) · **C** 통합 대상(중복군)."
  echo ""
  if [[ -s "${WORK_DIR}/candidates_graded.tsv" ]]; then
    for g in A B C; do
      case "${g}" in
        A) glabel="A — 즉시 정리 가능" ;;
        B) glabel="B — 관찰 유지 (정리 보류)" ;;
        C) glabel="C — 통합 대상 (대표 선정 필요)" ;;
        *) glabel="${g}" ;;
      esac
      gcount="$(awk -F"\t" -v g="${g}" '$1==g' "${WORK_DIR}/candidates_graded.tsv" | wc -l | tr -d ' ')"
      echo "### ${glabel} (${gcount})"
      echo ""
      if [[ "${gcount}" -gt 0 ]]; then
        awk -F"\t" -v g="${g}" '$1==g { printf "- [%s] `%s` — %s\n", $2, $3, $4 }' \
          "${WORK_DIR}/candidates_graded.tsv"
      else
        echo "_(해당 없음)_"
      fi
      echo ""
    done
  else
    echo "_(정리 후보 없음 — 모든 설치 항목이 누적 사용 이력 보유)_"
    echo ""
  fi
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

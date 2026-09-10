#!/usr/bin/env bash
# scrum_worker.sh — 데일리 스크럼 발표용 초안을 무인 생성하는 아침 워커
#
# 평일 오전 09:50 launchd 에 의해 실행됨 (10:00 팀 채널 게시 10분 전, caffeinate -i -s 래핑).
#
# 동작:
#   PARA 볼트를 cwd 로 두고 헤드리스 claude 에 `/daily-scrum` 을 던져,
#   그 산출물(붙여넣기용 스크럼 텍스트 + 구두 안건)을 파일로 저장한다.
#
# 🔴 작성 규칙은 본 스크립트에 없다 — 정본은 PARA 로컬 스킬이다:
#   $PARA_VAULT/.claude/skills/daily-scrum/SKILL.md
#   워커는 그 스킬을 호출하는 실행기일 뿐이므로, 스크럼 형식·규칙을 여기에 옮겨 적지 말 것.
#   (스킬이 project-local 이라 cwd 를 PARA 볼트로 두지 않으면 스킬이 잡히지 않는다.)
#
# 🔴 무인 완결이 아니다 — notion_diary_worker 와 다른 점:
#   산출물은 "사람이 복사해 슬랙에 붙여넣는 텍스트"다. 게시는 사람이 한다.
#   따라서 이 워커는 (1) 파일 저장 (2) 로컬 알림 만 수행하고,
#   슬랙·메신저 등 외부 발신은 절대 하지 않는다 (스킬 자체도 「외부 발신 금지」 명시).
#
# 환경 변수:
#   PARA_VAULT   PARA 볼트 경로. 미설정 시 PARA_PATH → "$HOME/Project/para" 순으로 폴백.
#   CLAUDE_BIN   claude CLI 경로. 미설정 시 PATH 에서 자동 탐색.
#   DRY_RUN      1 이면 claude 호출 skip (경로·가드·디렉토리만 확인).
#
# 산출물 / 로그:
#   ~/Library/Logs/daily-scrum/YYYY-MM-DD.md    스크럼 초안 (붙여넣기용)
#   ~/Library/Logs/daily-scrum/YYYY-MM-DD.log   실행 로그
#
# 안전 가드:
#   - 스킬이 읽기 전용(work-log·git log·PARA 노트 스캔)이라 어떤 레포도 변경하지 않음.
#   - 토·일 결정론 skip (plist 는 평일만 돌지만 수동 실행 대비).
#   - launchd 에서 caffeinate 로 래핑하므로 이 스크립트는 직접 caffeinate 호출 안 함.
#
# 사용법:
#     DRY_RUN=1 ./scrum_worker.sh
#     PARA_VAULT=/custom/para ./scrum_worker.sh
#
# 수동 부트스트랩 (setup.sh 는 plist 를 배포하지 않음 — SoC):
#   cp vibe-tools/com.swkim0128.daily-scrum.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.daily-scrum.plist
#   (해제: launchctl bootout gui/$(id -u)/com.swkim0128.daily-scrum)

set -euo pipefail

# ── 설정 (환경변수 우선, 안전 폴백) ──────────────────────────────────────────
# PARA_VAULT 우선. 레포 CLAUDE.md 가 문서화한 PARA_PATH 도 인정 후 홈 기준 폴백.
PARA_DIR="${PARA_VAULT:-${PARA_PATH:-${HOME}/Project/para}}"
LOG_DIR="${HOME}/Library/Logs/daily-scrum"
TODAY="$(date +%F)"
DOW_NUM="$(date +%u)"
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
LOG_FILE="${LOG_DIR}/${TODAY}.log"
OUT_FILE="${LOG_DIR}/${TODAY}.md"
DRY_RUN="${DRY_RUN:-0}"
SKILL_FILE="${PARA_DIR}/.claude/skills/daily-scrum/SKILL.md"

# claude CLI 경로 (PATH에 없을 경우 대비)
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo '')}"

# ── 디렉토리 초기화 ──────────────────────────────────────────────────────────
mkdir -p "${LOG_DIR}"

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
log_error() { log "ERROR" "$@"; }

# ── 알림 ─────────────────────────────────────────────────────────────────────
# macOS 배너는 주 디스플레이 전용(실측) — 외부 모니터를 보고 있으면 놓친다.
# 그래서 3중으로 알린다: ① tmux 전 클라이언트 메시지(사용자가 실제 보고 있는 화면)
# ② macOS 배너 ③ 로그에 눈에 띄는 경로 블록(항상 남는 최후 채널).
notify() {
  local title="$1"
  local body="$2"
  if command -v tmux >/dev/null 2>&1; then
    tmux display-message -d 8000 "${title} — ${body}" 2>/dev/null || true
  fi
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${body}\" with title \"${title}\" sound name \"Ping\"" \
      >/dev/null 2>&1 || log_warn "osascript 알림 실패(무시) — 로그의 산출물 경로를 확인하세요."
  fi
}

announce_output() {
  log_info "┌───────────────────────────────────────────────────────────"
  log_info "│ 스크럼 초안 산출물: ${OUT_FILE}"
  log_info "└───────────────────────────────────────────────────────────"
}

# ── 시작 로그 ────────────────────────────────────────────────────────────────
log_info "===== scrum_worker 시작 ====="
log_info "실행 시각: ${RUN_DATE}"
log_info "PARA 볼트: ${PARA_DIR}"
log_info "대상 날짜: ${TODAY}"
log_info "DRY_RUN: ${DRY_RUN}"

# ── 주말 결정론 skip (스크럼은 평일 업무) ───────────────────────────────────
if [[ "${DOW_NUM}" == "6" || "${DOW_NUM}" == "7" ]]; then
  log_info "오늘(${TODAY})은 주말 — 데일리 스크럼이 없어 skip 합니다."
  log_info "===== scrum_worker 완료 (주말 skip) ====="
  exit 0
fi

# ── PARA 볼트 / 스킬 정본 확인 ──────────────────────────────────────────────
if [[ ! -d "${PARA_DIR}" ]]; then
  log_error "PARA 볼트를 찾을 수 없습니다: ${PARA_DIR} (PARA_VAULT 환경변수로 지정하세요)"
  exit 1
fi
if [[ ! -f "${SKILL_FILE}" ]]; then
  log_error "daily-scrum 스킬 정본이 없습니다: ${SKILL_FILE}"
  exit 1
fi
log_info "스킬 정본: ${SKILL_FILE}"

# ── DRY_RUN: claude 호출 skip ────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "[DRY_RUN] claude 호출을 건너뜁니다."
  log_info "[DRY_RUN] 실행 예정: (cd ${PARA_DIR}) ${CLAUDE_BIN:-<claude 미발견>} --print /daily-scrum"
  log_info "[DRY_RUN] 산출물 예정 경로: ${OUT_FILE}"
  log_info "===== scrum_worker 완료 (DRY_RUN) ====="
  exit 0
fi

# ── claude CLI 확인 (실제 실행 경로에서만 필수) ──────────────────────────────
if [[ -z "${CLAUDE_BIN}" ]]; then
  log_error "claude CLI를 찾을 수 없습니다. PATH 또는 CLAUDE_BIN 환경변수를 확인하세요."
  exit 1
fi
log_info "claude CLI: ${CLAUDE_BIN}"

# ─────────────────────────────────────────────────────────────────────────────
# daily-scrum 스킬 헤드리스 호출
#   cwd = PARA 볼트 (project-local 스킬 인식 조건)
#   프롬프트 = 슬래시 커맨드 하나. 규칙은 스킬이 정본이므로 여기서 지시를 덧붙이지 않는다.
# ─────────────────────────────────────────────────────────────────────────────
cd "${PARA_DIR}"
log_info "claude 헤드리스 /daily-scrum 호출 시작 (cwd=${PARA_DIR})..."

set +e
"${CLAUDE_BIN}" \
  --print "/daily-scrum" \
  --dangerously-skip-permissions \
  --model "claude-sonnet-4-6" \
  --output-format text \
  --allowedTools "Read,Glob,Grep,Bash,Skill" \
  > "${OUT_FILE}" 2>> "${LOG_FILE}"
CLAUDE_EXIT=$?
set -e

if [[ ${CLAUDE_EXIT} -ne 0 ]]; then
  log_error "claude 호출 실패 (exit code: ${CLAUDE_EXIT}). 로그 확인: ${LOG_FILE}"
  notify "스크럼 초안 실패" "exit ${CLAUDE_EXIT} — 로그: ${LOG_FILE}"
  exit ${CLAUDE_EXIT}
fi

if [[ ! -s "${OUT_FILE}" ]]; then
  log_error "claude 호출은 성공했으나 산출물이 비어 있습니다: ${OUT_FILE}"
  notify "스크럼 초안 비어 있음" "스킬 인식 실패 의심 — 로그: ${LOG_FILE}"
  exit 1
fi

OUT_LINES="$(wc -l < "${OUT_FILE}" | tr -d ' ')"
log_info "스크럼 초안 생성 완료 (${OUT_LINES} 줄)."
announce_output
notify "스크럼 초안 준비됨 (10:00 게시)" "${OUT_FILE}"
log_info "===== scrum_worker 완료 ====="
exit 0

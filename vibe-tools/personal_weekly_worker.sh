#!/usr/bin/env bash
# personal_weekly_worker.sh — 일요일 밤 개인 주간 정리 초안 + KPT 회고를 무인 생성하는 워커
#
# 일요일 22:00 launchd 에 의해 실행됨 (caffeinate -i -s 래핑).
# 실행기: Codex(`codex exec`) — 개인컴에서 도는 기능은 Codex 로 실행한다(사용자 지시).
# 모델: gpt-6.1-sol / reasoning medium — vibe-ai-config docs/codex-chatgpt-usage-routing.md 의
#       implement 기본값. CODEX_MODEL / CODEX_EFFORT 로 덮어쓴다.
#
# 동작:
#   PARA 볼트를 작업 루트(-C)로 두고 비대화형 codex 에 이번 ISO 주(월~일, 셸에서 확정 주입)를 넘겨
#   ① 노션 주간 일지·Tasks·가계부·볼트 NEXT-SESSION.md 를 수집하고
#   ② 개인 주간 정리 초안을 산출물 파일로 저장하며(-o 최종 응답 → 파일)
#   ③ notion-weekly-retrospective 스킬 규칙(KPT)으로 이번 주 페이지 하단에 회고를 쓴다
#      (이미 회고가 있으면 덮어쓰지 않고 skip).
#   다음 주 계획은 사람이 `/personal 주간루틴` 으로 이어서 진행한다.
#
# 🔴 정리·회고 규칙은 본 스크립트에 없다 — 정본은 스킬·도메인 문서다:
#   ~/.agents/skills/notion-weekly-retrospective/SKILL.md (KPT 회고 — Claude·Codex 공용 배포본)
#   $PARA_VAULT/02.Areas/07.개인관리/04.일정.md · 01.다이어리.md · 05.프로젝트.md
#   $PARA_VAULT/.agents/rules/two-devices.md 「기록 정본」
#   워커는 그 규칙을 읽게 하는 실행기일 뿐이므로, 규칙 본문을 여기에 옮겨 적지 말 것.
#
# 🔴 무인 완결이 아니다 — 다음 주 계획은 사람이 한다:
#   주간 일지 페이지 생성(n8n 소관) · 일정 슬롯·Week List 수정 · 다음 주 계획 등록 ·
#   외부 발신(슬랙·메일 등) · 볼트 파일 수정/커밋은 하지 않는다. 노션 쓰기는 회고 1건뿐.
#
# 환경 변수:
#   PARA_VAULT   PARA 볼트 경로. 미설정 시 PARA_PATH → "$HOME/Project/para" 순으로 폴백.
#   CODEX_BIN    codex CLI 경로. 미설정 시 PATH → /opt/homebrew/bin/codex 순으로 탐색.
#   CODEX_MODEL  codex 모델. 기본 gpt-6.1-sol.
#   CODEX_EFFORT model_reasoning_effort. 기본 medium.
#   DRY_RUN      1 이면 codex 호출 skip (경로·가드·디렉토리만 확인, 프롬프트는 로그에 남김).
#   FORCE        1 이면 일요일이 아니어도 실행(강제 실행용).
#
# 산출물 / 로그:
#   ~/Library/Logs/personal-weekly/YYYY-MM-DD.md    개인 주간 정리 초안
#   ~/Library/Logs/personal-weekly/YYYY-MM-DD.log   실행 로그
#
# 안전 가드:
#   - 일요일 외 결정론 skip (plist 는 일요일만 돌지만 수동 실행 대비, FORCE=1 예외).
#   - `-s read-only` 샌드박스 — 셸 쓰기 불가라 볼트 파일 수정·커밋이 막힌다. 초안은 -o 로만 받는다.
#   - 노션 MCP 는 ~/.codex/config.toml 의 mcp_servers.notion 을 쓴다(notion-update-page 는 거기서 approve).
#     읽기 도구(search·fetch·query-data-sources)는 비대화형(approval: never)에서 승인 대기로
#     멈추지 않도록 이번 실행에 한해 -c 로 approve 한다. --dangerously-bypass-* 는 쓰지 않는다.
#   - --ephemeral 미사용 — 사후 조사용으로 codex 세션 기록(~/.codex/sessions)을 남긴다.
#   - launchd 에서 caffeinate 로 래핑하므로 이 스크립트는 직접 caffeinate 호출 안 함.
#
# 사용법:
#     DRY_RUN=1 FORCE=1 ./personal_weekly_worker.sh
#     PARA_VAULT=/custom/para ./personal_weekly_worker.sh
#
# 수동 부트스트랩 (install.sh 는 plist 를 배포하지 않음 — SoC):
#   cp vibe-tools/com.swkim0128.personal-weekly.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.personal-weekly.plist
#   (해제: launchctl bootout gui/$(id -u)/com.swkim0128.personal-weekly)

set -euo pipefail

# ── 설정 (환경변수 우선, 안전 폴백) ──────────────────────────────────────────
# PARA_VAULT 우선. 레포 CLAUDE.md 가 문서화한 PARA_PATH 도 인정 후 홈 기준 폴백.
PARA_DIR="${PARA_VAULT:-${PARA_PATH:-${HOME}/Project/para}}"
LOG_DIR="${HOME}/Library/Logs/personal-weekly"
TODAY="$(date +%F)"
DOW_NUM="$(date +%u)"
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
LOG_FILE="${LOG_DIR}/${TODAY}.log"
OUT_FILE="${LOG_DIR}/${TODAY}.md"
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
ISO_WEEK="$(date +%G-W%V)"
# 이번 ISO 주 월요일·일요일 (BSD date -v 상대 조정)
WEEK_START="$(date -v-"$((DOW_NUM - 1))"d +%F)"
WEEK_END="$(date -v+"$((7 - DOW_NUM))"d +%F)"
PERSONAL_DIR="${PARA_DIR}/02.Areas/07.개인관리"
TWO_DEVICES_RULE="${PARA_DIR}/.agents/rules/two-devices.md"
RETRO_SKILL="${HOME}/.agents/skills/notion-weekly-retrospective/SKILL.md"
CODEX_MODEL="${CODEX_MODEL:-gpt-6.1-sol}"
CODEX_EFFORT="${CODEX_EFFORT:-medium}"
# 노션 읽기 도구만 이번 실행에 한해 자동 승인 (쓰기 notion-update-page 는 config.toml 정본)
NOTION_READ_APPROVALS=(
  -c 'mcp_servers.notion.tools.notion-search.approval_mode="approve"'
  -c 'mcp_servers.notion.tools.notion-fetch.approval_mode="approve"'
  -c 'mcp_servers.notion.tools.notion-query-data-sources.approval_mode="approve"'
)

# codex CLI 경로 (PATH에 없을 경우 대비 — launchd PATH 에 /opt/homebrew/bin 포함)
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || echo '')}"
if [[ -z "${CODEX_BIN}" && -x /opt/homebrew/bin/codex ]]; then
  CODEX_BIN="/opt/homebrew/bin/codex"
fi

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
  log_info "│ 개인 주간 정리 초안 산출물: ${OUT_FILE}"
  log_info "└───────────────────────────────────────────────────────────"
}

# ── 시작 로그 ────────────────────────────────────────────────────────────────
log_info "===== personal_weekly_worker 시작 ====="
log_info "실행 시각: ${RUN_DATE}"
log_info "PARA 볼트: ${PARA_DIR}"
log_info "대상 주: ${ISO_WEEK} (${WEEK_START} ~ ${WEEK_END})"
log_info "DRY_RUN: ${DRY_RUN} / FORCE: ${FORCE}"

# ── 일요일 외 결정론 skip (FORCE=1 예외) ────────────────────────────────────
if [[ "${DOW_NUM}" != "7" && "${FORCE}" != "1" ]]; then
  log_info "오늘(${TODAY})은 일요일이 아님 — 개인 주간 정리일이 아니라 skip 합니다. (강제: FORCE=1)"
  log_info "===== personal_weekly_worker 완료 (요일 skip) ====="
  exit 0
fi

# ── PARA 볼트 / 도메인 문서 확인 ────────────────────────────────────────────
if [[ ! -d "${PARA_DIR}" ]]; then
  log_error "PARA 볼트를 찾을 수 없습니다: ${PARA_DIR} (PARA_VAULT 환경변수로 지정하세요)"
  exit 1
fi
if [[ ! -d "${PERSONAL_DIR}" ]]; then
  log_error "개인관리 도메인 문서 디렉토리가 없습니다: ${PERSONAL_DIR}"
  exit 1
fi
[[ -f "${TWO_DEVICES_RULE}" ]] || log_warn "기록 정본 규칙 문서가 없습니다(프롬프트 참조만 실패): ${TWO_DEVICES_RULE}"
[[ -f "${RETRO_SKILL}" ]] || log_warn "회고 스킬 정본이 없습니다(회고 규칙 참조 실패): ${RETRO_SKILL}"
log_info "도메인 문서: ${PERSONAL_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
# 프롬프트: 수집 → 초안(stdout) → KPT 회고(이미 있으면 skip). 규칙은 스킬·도메인 문서 정본 참조.
# ─────────────────────────────────────────────────────────────────────────────
PROMPT="이번 주(ISO ${ISO_WEEK}, ${WEEK_START} 월 ~ ${WEEK_END} 일 — 셸에서 계산한 확정값, 재계산 금지)의 개인 주간 정리 초안을 만들고 KPT 회고를 작성하라. 완전 자율 수행 — 사용자에게 확인·선택·승인 요청 금지, 모호하면 합리적 기본값 채택.

[규칙 정본 — 먼저 읽고 그대로 따를 것. 여기에 없는 규칙을 지어내지 말 것]
- ${PERSONAL_DIR}/04.일정.md (주간 일지 페이지 구조·슬롯)
- ${PERSONAL_DIR}/01.다이어리.md (다이어리 위치·형식)
- ${PERSONAL_DIR}/05.프로젝트.md (노션 Tasks·진행 기록)
- ${TWO_DEVICES_RULE} 의 「기록 정본」 절 (기록 종류별 정본 위치)
- ${RETRO_SKILL} (회고 규칙 KPT — 이 스킬 문서와 그 references/ 를 읽고 따른다)

[① 수집 — 이번 주 범위만]
- 노션 주간 일지 페이지: 제목 '[week NN] @YYYY/MM/DD → YYYY/MM/DD 일지' 중 범위가 ${WEEK_START}~${WEEK_END} 인 페이지를 notion-search 로 찾아 notion-fetch. Week Things 의 LIFE 슬롯·다이어리 내용.
- 노션 Tasks: 본문 '## 진행 기록' 중 이번 주 날짜 항목, 이번 주 상태 변화, 기한(${TODAY} 이전)이 지난 미완료 개인 태스크.
- 가계부(Household Ledger): 이번 주 지출 합계(가능하면 분류별).
- 볼트 NEXT-SESSION.md 의 개인컴 절.
- 출처를 못 찾으면 그 항목은 '수집 실패: 사유' 로 적고 계속 진행한다.

[② 초안 — 최종 응답 본문으로 출력(셸이 파일로 저장한다. 파일 쓰기 금지 — 샌드박스 read-only)]
- 마크다운, 제목 '# 개인 주간 정리 ${ISO_WEEK} (${WEEK_START} ~ ${WEEK_END})'.
- 섹션: 이번 주 한 일 / 다이어리 요약 / 태스크 변화·기한 지남 / 지출 요약 / 다음 주 후보.
- '다음 주 후보'는 제안 목록일 뿐 어디에도 등록하지 않는다.

[③ 회고]
- 이번 주 주간 일지 페이지 하단에 위 회고 스킬 규칙으로 KPT 회고를 작성한다(노션 MCP notion-update-page).
- 페이지에 이미 회고(KPT/회고 섹션)가 있으면 덮어쓰지 말고 skip 한다.
- 이번 주 페이지를 찾지 못하면 회고는 skip 한다.

[④ 금지]
- 주간 일지 페이지 생성(n8n 소관) · 일정 슬롯·Week List 수정 · 다음 주 계획 등록 · 외부 발신(슬랙·메일 등) · 볼트 파일 수정/커밋.
- 노션 쓰기는 ③ 회고 1건만 허용된다.

[출력 마지막 줄]
- '회고: 작성 | skip(사유)' 형태로 한 줄."

# ── DRY_RUN: codex 호출 skip ─────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "[DRY_RUN] codex 호출을 건너뜁니다."
  log_info "[DRY_RUN] 실행 예정: ${CODEX_BIN:-<codex 미발견>} exec -C ${PARA_DIR} -s read-only -m ${CODEX_MODEL} -c model_reasoning_effort=\"${CODEX_EFFORT}\" ${NOTION_READ_APPROVALS[*]} -o ${OUT_FILE} -"
  log_info "[DRY_RUN] 산출물 예정 경로: ${OUT_FILE}"
  log_info "[DRY_RUN] 프롬프트 ↓"
  printf '%s\n' "${PROMPT}" >> "${LOG_FILE}"
  log_info "===== personal_weekly_worker 완료 (DRY_RUN) ====="
  exit 0
fi

# ── codex CLI 확인 (실제 실행 경로에서만 필수) ───────────────────────────────
if [[ -z "${CODEX_BIN}" ]]; then
  log_error "codex CLI를 찾을 수 없습니다. PATH 또는 CODEX_BIN 환경변수를 확인하세요."
  exit 1
fi
log_info "codex CLI: ${CODEX_BIN} (model=${CODEX_MODEL}, effort=${CODEX_EFFORT})"

# ─────────────────────────────────────────────────────────────────────────────
# 비대화형 codex 호출
#   -C = PARA 볼트, -s read-only (셸 쓰기 차단), -o = 최종 응답(초안) → OUT_FILE.
#   프롬프트는 stdin('-'), 진행 이벤트(stdout·stderr)는 LOG_FILE.
# ─────────────────────────────────────────────────────────────────────────────
log_info "codex 비대화형 개인 주간 정리 호출 시작 (cwd=${PARA_DIR})..."

set +e
printf '%s' "${PROMPT}" | "${CODEX_BIN}" exec \
  -C "${PARA_DIR}" \
  -s read-only \
  -m "${CODEX_MODEL}" \
  -c "model_reasoning_effort=\"${CODEX_EFFORT}\"" \
  "${NOTION_READ_APPROVALS[@]}" \
  --color never \
  -o "${OUT_FILE}" \
  - >> "${LOG_FILE}" 2>&1
CODEX_EXIT=${PIPESTATUS[1]}
set -e

if [[ ${CODEX_EXIT} -ne 0 ]]; then
  log_error "codex 호출 실패 (exit code: ${CODEX_EXIT}). 로그 확인: ${LOG_FILE}"
  notify "주간 개인 정리 실패" "exit ${CODEX_EXIT} — 로그: ${LOG_FILE}"
  exit "${CODEX_EXIT}"
fi

if [[ ! -s "${OUT_FILE}" ]]; then
  log_error "codex 호출은 성공했으나 산출물이 비어 있습니다: ${OUT_FILE}"
  notify "주간 개인 정리 초안 비어 있음" "로그: ${LOG_FILE}"
  exit 1
fi

OUT_LINES="$(wc -l < "${OUT_FILE}" | tr -d ' ')"
log_info "개인 주간 정리 초안 생성 완료 (${OUT_LINES} 줄)."
announce_output
notify "주간 개인 정리 초안 준비" "/personal 주간루틴 으로 다음 주 계획 진행"
log_info "===== personal_weekly_worker 완료 ====="
exit 0

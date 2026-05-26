#!/usr/bin/env bash
# overnight_worker.sh — 야간 자율 분석 파이프라인
#
# 매일 새벽 2시 launchd에 의해 실행됨 (caffeinate -i -s 래핑).
# 외부 PARA 볼트(선택적 의존)의 git 활동을 분석하고,
# 다음 날 1순위 과제의 소스코드를 미리 스파이크 분석하여
# $PARA_PATH/Retrospectives/YYYY-MM-DD_overnight_blueprint.md 에 누적 저장.
#
# 추가 책무 (2026-05-26):
#   $PARA_PATH/01.Projects/*.md 중 frontmatter status=in_progress 파일을
#   직접 Read 하여, 오늘 git 활동·블루프린트와 대조한 뒤 다음 두 작업을 수행:
#     (1) `## 진행 내역`에 `- YYYY-MM-DD: <오늘 변동 요약>` 1줄 append
#     (2) `## TO-DO` 체크리스트 갱신 (완료된 항목은 `- [x] ... ✅ YYYY-MM-DD`),
#         미완 항목 중 명일 즉시 착수 가능한 것은 별도 섹션 `## 내일 실행 가이드`로
#         같은 파일 하단에 자율 누적 (중복 헤더 방지: 이미 있으면 그 아래 append).
#   frontmatter `status` 자체는 임의 변경 금지 — 인프라 단의 자동화는 본문 append만.
#
# 환경 변수 (외부 볼트 통합 — 선택적 의존):
#   PARA_PATH       PARA 볼트 루트. 미설정 시 폴백 = "$HOME/Project/para"
#                   해당 경로가 존재하지 않으면 PARA 통합은 자동 skip (graceful).
#                   본 레포 자체는 PARA 의 물리적 존재에 의존하지 않는다.
#   REPO_SCAN_ROOT  git 레포 스캔 루트. 미설정 시 폴백 = "$HOME/Project"
#   CLAUDE_BIN      claude CLI 경로. 미설정 시 PATH 에서 자동 탐색.
#
# 안전 가드:
#   - 소스코드(.php/.kt/.py/.ts/.js/.kts/.go/.rs 등): Read만 허용. Edit 절대 금지.
#   - Edit 허용 화이트리스트: $PARA_PATH/01.Projects/*.md (status=in_progress 한정)
#   - Write 허용: 본 일자 블루프린트 파일 1개 (BLUEPRINT_FILE)
#   - git push, 외부 API 호출, 임의 파일 삭제 금지
#   - launchd에서 caffeinate로 래핑하므로 이 스크립트는 직접 caffeinate 호출 안 함
#
# 사용법:
#   직접 실행은 권장하지 않음. launchd 또는 테스트 시 dry-run 플래그로 실행.
#   DRY_RUN=1 ./overnight_worker.sh
#   PARA_PATH=/custom/para ./overnight_worker.sh

set -euo pipefail

# ── 설정 (환경변수 우선, 안전 폴백) ──────────────────────────────────────────
# 외부 PARA 볼트 — 미설정·미존재 시 PARA 통합은 자동 skip (본 레포는 PARA 의존 없음)
PARA_ROOT="${PARA_PATH:-${HOME}/Project/para}"
PARA_PROJECTS_DIR="${PARA_ROOT}/01.Projects"
RETRO_DIR="${PARA_ROOT}/Retrospectives"
# git 활동 스캔 루트 — 환경변수 오버라이드 가능
REPO_SCAN_DIR="${REPO_SCAN_ROOT:-${HOME}/Project}"
LOG_DIR="${HOME}/Library/Logs/overnight_worker"
TODAY="$(date +%F)"
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
BLUEPRINT_FILE="${RETRO_DIR}/${TODAY}_overnight_blueprint.md"
LOG_FILE="${LOG_DIR}/${TODAY}.log"
DRY_RUN="${DRY_RUN:-0}"

# claude CLI 경로 (PATH에 없을 경우 대비)
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo '')}"

# ── 디렉토리 초기화 ──────────────────────────────────────────────────────────
mkdir -p "${LOG_DIR}"

# RETRO_DIR (PARA 볼트 하위) — PARA 부재 시 graceful fallback
if ! mkdir -p "${RETRO_DIR}" 2>/dev/null; then
  FALLBACK_RETRO="${TMPDIR:-/tmp}/overnight-blueprints"
  mkdir -p "${FALLBACK_RETRO}"
  RETRO_DIR="${FALLBACK_RETRO}"
  BLUEPRINT_FILE="${RETRO_DIR}/${TODAY}_overnight_blueprint.md"
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
log_error() { log "ERROR" "$@"; }

# ── 시작 로그 ────────────────────────────────────────────────────────────────
log_info "===== overnight_worker 시작 ====="
log_info "실행 시각: ${RUN_DATE}"
log_info "PARA 볼트 루트: ${PARA_ROOT}$([[ -d ${PARA_ROOT} ]] && echo '' || echo ' (미존재 — PARA 통합 skip)')"
log_info "PARA 프로젝트 경로: ${PARA_PROJECTS_DIR}"
log_info "git 스캔 루트: ${REPO_SCAN_DIR}"
log_info "블루프린트 출력: ${BLUEPRINT_FILE}"
log_info "DRY_RUN: ${DRY_RUN}"

# ── claude CLI 확인 ──────────────────────────────────────────────────────────
if [[ -z "${CLAUDE_BIN}" ]]; then
  log_error "claude CLI를 찾을 수 없습니다. PATH 또는 CLAUDE_BIN 환경변수를 확인하세요."
  exit 1
fi
log_info "claude CLI: ${CLAUDE_BIN}"

# ── PARA 프로젝트 디렉토리 확인 ──────────────────────────────────────────────
if [[ ! -d "${PARA_PROJECTS_DIR}" ]]; then
  log_warn "PARA 프로젝트 디렉토리를 찾을 수 없습니다: ${PARA_PROJECTS_DIR}"
  log_warn "빈 분석으로 블루프린트를 생성합니다."
fi

# ── git 스캔 루트 디렉토리 확인 ─────────────────────────────────────────────
if [[ ! -d "${REPO_SCAN_DIR}" ]]; then
  log_warn "git 스캔 루트를 찾을 수 없습니다: ${REPO_SCAN_DIR}"
  log_warn "빈 분석으로 블루프린트를 생성합니다."
fi

# ── claude 실행 (행동 규격은 CLAUDE-delegation.md 야간 자율 운전 모드 SOP) ──
# 본 셸은 컨텍스트 변수만 주입하는 단순 실행기. 마크다운 출력 양식·PARA 편집 SOP
# 등 구체적 행동 규칙은 ~/.claude/CLAUDE-delegation.md 가 진실 공급원.
log_info "claude 헤드리스 분석 시작..."

if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "[DRY_RUN] claude 실제 호출을 건너뜁니다."
  log_info "[DRY_RUN] 출력 예정 파일: ${BLUEPRINT_FILE}"
  cat > "${BLUEPRINT_FILE}" <<DRY_EOF
# Overnight Blueprint — ${TODAY} [DRY RUN]

> 이 파일은 DRY_RUN=1 모드로 생성된 테스트용 파일입니다.

## 시스템 점검 완료
- 스크립트 실행: OK
- 디렉토리 생성: OK
- claude CLI 경로: ${CLAUDE_BIN}
- REPO_SCAN_DIR: ${REPO_SCAN_DIR}
- PARA_PROJECTS_DIR: ${PARA_PROJECTS_DIR}

실제 실행 시 이 파일이 claude 의 분석 결과로 대체됩니다 (행동 규격: CLAUDE-delegation.md).
DRY_EOF
  log_info "[DRY_RUN] 샘플 블루프린트 생성 완료: ${BLUEPRINT_FILE}"
else
  "${CLAUDE_BIN}" \
    --print \
    --dangerously-skip-permissions \
    --allowedTools "Read,Glob,Grep,Write,Edit" \
    --model "claude-sonnet-4-6" \
    --output-format text \
    "~/.claude/CLAUDE-delegation.md에 정의된 야간 자율 운전 모드 SOP에 따라, 오늘 자정 이후 발생한 REPO_SCAN_DIR('${REPO_SCAN_DIR}') 내의 git 활동 분석 및 PARA_PROJECTS_DIR('${PARA_PROJECTS_DIR}') 내 IN_PROGRESS 파일의 본문 append 작업을 완전히 자율적으로 완수해라. (분석 결과는 '${BLUEPRINT_FILE}'에 저장)" \
    >> "${LOG_FILE}" 2>&1

  CLAUDE_EXIT=$?
  if [[ ${CLAUDE_EXIT} -ne 0 ]]; then
    log_error "claude 분석 실패 (exit code: ${CLAUDE_EXIT}). 로그 확인: ${LOG_FILE}"
    exit ${CLAUDE_EXIT}
  fi

  log_info "claude 분석 완료."
fi

# ── 블루프린트 파일 확인 ──────────────────────────────────────────────────────
if [[ -f "${BLUEPRINT_FILE}" ]]; then
  BLUEPRINT_SIZE="$(wc -c < "${BLUEPRINT_FILE}" | tr -d ' ')"
  log_info "블루프린트 파일 생성 확인: ${BLUEPRINT_FILE} (${BLUEPRINT_SIZE} bytes)"
else
  log_warn "블루프린트 파일이 생성되지 않았습니다: ${BLUEPRINT_FILE}"
  log_warn "claude가 파일을 작성하지 않았거나, allowedTools 제한으로 Write가 차단되었을 수 있습니다."
fi

log_info "===== overnight_worker 완료 ====="
exit 0

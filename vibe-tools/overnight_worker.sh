#!/usr/bin/env bash
# overnight_worker.sh — 야간 자율 분석 파이프라인
#
# 매일 새벽 2시 launchd에 의해 실행됨 (caffeinate -i -s 래핑).
# PARA 프로젝트 전반의 git 활동을 분석하고,
# 다음 날 1순위 과제의 소스코드를 미리 스파이크 분석하여
# ~/Project/00-PARA/Retrospectives/YYYY-MM-DD_overnight_blueprint.md 에 누적 저장.
#
# 안전 가드:
#   - read-only 분석 + 마크다운 작성만 수행
#   - git push, 외부 API 호출, 임의 파일 삭제 금지
#   - launchd에서 caffeinate로 래핑하므로 이 스크립트는 직접 caffeinate 호출 안 함
#
# 사용법:
#   직접 실행은 권장하지 않음. launchd 또는 테스트 시 dry-run 플래그로 실행.
#   DRY_RUN=1 ./overnight_worker.sh

set -euo pipefail

# ── 설정 ──────────────────────────────────────────────────────────────────────
PARA_PROJECTS_DIR="${HOME}/Project/para/01.Projects"
RETRO_DIR="${HOME}/Project/para/Retrospectives"
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
mkdir -p "${RETRO_DIR}"

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
log_info "PARA 프로젝트 경로: ${PARA_PROJECTS_DIR}"
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

# ── git 활동 수집 ─────────────────────────────────────────────────────────────
# 각 프로젝트 하위의 git 레포에서 최근 24시간 커밋을 수집
declare -a ACTIVE_PROJECTS=()
declare -a PROJECT_GIT_SUMMARIES=()

GIT_SUMMARY_TEXT=""

if [[ -d "${PARA_PROJECTS_DIR}" ]]; then
  # 직접 하위 디렉토리 탐색 (최대 2단계)
  while IFS= read -r -d '' proj_dir; do
    proj_name="$(basename "${proj_dir}")"

    # .git 폴더가 없으면 git 레포가 아님
    if [[ ! -d "${proj_dir}/.git" ]]; then
      continue
    fi

    # 최근 24시간 커밋 조회
    commits="$(git -C "${proj_dir}" log \
      --since="1 day ago" \
      --pretty=format:'%h %s' \
      2>/dev/null || true)"

    if [[ -n "${commits}" ]]; then
      ACTIVE_PROJECTS+=("${proj_name}")
      PROJECT_GIT_SUMMARIES+=("${commits}")
      GIT_SUMMARY_TEXT+="### ${proj_name}\n${commits}\n\n"
      log_info "활성 프로젝트 감지: ${proj_name} ($(echo "${commits}" | wc -l | tr -d ' ')건 커밋)"
    fi
  done < <(find "${PARA_PROJECTS_DIR}" -maxdepth 2 -type d -print0 2>/dev/null)
fi

# 활성 프로젝트가 없어도 블루프린트는 생성 (분석 대상 없음 기록)
if [[ ${#ACTIVE_PROJECTS[@]} -eq 0 ]]; then
  log_warn "최근 24시간 내 git 활동이 있는 프로젝트가 없습니다."
  GIT_SUMMARY_TEXT="최근 24시간 내 git 활동이 감지된 프로젝트가 없습니다.\n"
fi

log_info "활성 프로젝트 수: ${#ACTIVE_PROJECTS[@]}"

# ── 블루프린트 디렉토리 내 최근 과제 컨텍스트 수집 ───────────────────────────
# 최근 블루프린트를 참고해 연속성 유지
PREV_BLUEPRINT=""
PREV_FILE="$(ls -1 "${RETRO_DIR}"/*_overnight_blueprint.md 2>/dev/null | sort | tail -2 | head -1 || true)"
if [[ -n "${PREV_FILE}" && -f "${PREV_FILE}" && "${PREV_FILE}" != "${BLUEPRINT_FILE}" ]]; then
  # 직전 블루프린트에서 "내일 1순위 과제" 섹션만 추출 (최대 30줄)
  PREV_BLUEPRINT="$(grep -A 30 '1순위 과제\|Tomorrow\|Next Priority' "${PREV_FILE}" 2>/dev/null | head -30 || true)"
  log_info "직전 블루프린트 참조: ${PREV_FILE}"
fi

# ── claude 헤드리스 호출 프롬프트 구성 ──────────────────────────────────────
PROMPT_TEXT="$(cat <<PROMPT_EOF
당신은 개발 프로젝트 분석 AI입니다. 야간 자율 분석 모드로 실행 중입니다.
사용자 개입이 불가능하므로 절대 Y/N 확인을 요구하지 말고, 모든 결과를 파일에 직접 작성하세요.

## 분석 날짜
${TODAY}

## 오늘의 git 활동 요약
$(printf '%b' "${GIT_SUMMARY_TEXT}")

## 직전 블루프린트의 1순위 과제 (참고용)
${PREV_BLUEPRINT:-"이전 블루프린트 없음"}

## 분석 대상 PARA 프로젝트 목록
- 경로: ${PARA_PROJECTS_DIR}
- 활성 프로젝트: $(IFS=', '; echo "${ACTIVE_PROJECTS[*]:-없음}")

## 당신이 해야 할 일
1. 오늘의 git 커밋 내역을 바탕으로 프로젝트별 진행 상황을 요약하세요.
2. 직전 블루프린트와 오늘 커밋을 종합하여 "내일 1순위로 착수해야 할 과제"를 구체적으로 도출하세요.
3. 해당 과제의 관련 소스 파일을 Read 도구로 직접 읽어 분석하세요 (경로가 존재하는 경우).
4. "내일 즉시 복사 가능한 구현 블루프린트"를 작성하세요. 의도 코드(의사코드 또는 실제 코드 스니펫)를 포함해야 합니다.
5. 모든 결과를 아래 파일 경로에 마크다운으로 Write 도구를 사용해 저장하세요:
   ${BLUEPRINT_FILE}

## 출력 파일 형식 (반드시 이 구조를 따를 것)
\`\`\`markdown
# Overnight Blueprint — ${TODAY}

## 오늘의 git 활동 요약
(프로젝트별 커밋 요약)

## 진행 상황 종합
(오늘 무엇을 달성했는가, 어떤 이슈가 남았는가)

## 내일 1순위 과제
(구체적인 과제명, 왜 1순위인가, 예상 소요 시간)

## 소스 분석
(관련 소스 파일 읽기 결과, 핵심 로직 파악)

## 구현 블루프린트
(내일 즉시 시작할 수 있는 의도 코드, 단계별 구현 계획)

## 위험 및 주의사항
(놓친 것, 잠재적 문제, 다음 세션에 전달할 컨텍스트)
\`\`\`

## 제약사항 (절대 위반 금지)
- git push 금지
- 외부 API 호출 금지
- 파일 삭제 금지
- 사용자 작업 파일(소스코드) 수정 금지 — Read만 허용
- 결과 마크다운 파일 Write만 허용
PROMPT_EOF
)"

# ── claude 실행 ───────────────────────────────────────────────────────────────
log_info "claude 헤드리스 분석 시작..."

if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "[DRY_RUN] claude 실제 호출을 건너뜁니다."
  log_info "[DRY_RUN] 프롬프트 길이: $(echo "${PROMPT_TEXT}" | wc -c | tr -d ' ') bytes"
  log_info "[DRY_RUN] 출력 예정 파일: ${BLUEPRINT_FILE}"
  # dry-run 시 샘플 블루프린트 생성
  cat > "${BLUEPRINT_FILE}" <<DRY_EOF
# Overnight Blueprint — ${TODAY} [DRY RUN]

> 이 파일은 DRY_RUN=1 모드로 생성된 테스트용 파일입니다.

## 오늘의 git 활동 요약

$(printf '%b' "${GIT_SUMMARY_TEXT}")

## DRY RUN 상태
- 실제 claude 분석은 실행되지 않았습니다.
- 실제 실행 시 이 파일이 claude의 분석 결과로 대체됩니다.

## 시스템 점검 완료
- 스크립트 실행: OK
- 디렉토리 생성: OK
- git 활동 수집: OK (활성 프로젝트 ${#ACTIVE_PROJECTS[@]}개)
- claude CLI 경로: ${CLAUDE_BIN}
DRY_EOF
  log_info "[DRY_RUN] 샘플 블루프린트 생성 완료: ${BLUEPRINT_FILE}"
else
  # 실제 claude 헤드리스 호출
  # --dangerously-skip-permissions: 비대화형 자동 승인
  # --allowedTools: Read, Glob, Grep, Write만 허용 (Bash, Edit 등 차단)
  # --print: 비대화형 모드 (출력 후 종료)
  "${CLAUDE_BIN}" \
    --print \
    --dangerously-skip-permissions \
    --allowedTools "Read,Glob,Grep,Write" \
    --model "claude-sonnet-4-6" \
    --output-format text \
    "${PROMPT_TEXT}" \
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

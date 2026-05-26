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

# ── git 활동 수집 ─────────────────────────────────────────────────────────────
# REPO_SCAN_DIR 직속 자식 디렉토리(maxdepth=1) 중 .git 보유 + 최근 24시간 커밋이 있는 레포 수집
declare -a ACTIVE_PROJECTS=()
declare -a PROJECT_GIT_SUMMARIES=()

GIT_SUMMARY_TEXT=""

if [[ -d "${REPO_SCAN_DIR}" ]]; then
  # REPO_SCAN_DIR 직속 하위 디렉토리만 (maxdepth=1, mindepth=1) — 깊은 중첩은 의도적으로 제외
  while IFS= read -r -d '' proj_dir; do
    # find -mindepth 가 BSD find에서 제한적이므로 자기 자신 제외 가드
    if [[ "${proj_dir}" == "${REPO_SCAN_DIR}" ]]; then
      continue
    fi

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
  done < <(find "${REPO_SCAN_DIR}" -maxdepth 1 -type d -print0 2>/dev/null)
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

# ── PARA 01.Projects 중 status=in_progress 파일 수집 ─────────────────────────
# frontmatter YAML 의 `status: in_progress` 라인을 grep으로 식별.
declare -a IN_PROGRESS_FILES=()
IN_PROGRESS_LIST_TEXT=""

if [[ -d "${PARA_PROJECTS_DIR}" ]]; then
  while IFS= read -r -d '' note; do
    # 파일 첫 20줄 (frontmatter) 안에 status: in_progress 가 있는지 확인
    if head -20 "${note}" 2>/dev/null | grep -Eq '^status:[[:space:]]*in_progress[[:space:]]*$'; then
      IN_PROGRESS_FILES+=("${note}")
      IN_PROGRESS_LIST_TEXT+="- ${note}\n"
      log_info "IN_PROGRESS 작업 감지: $(basename "${note}")"
    fi
  done < <(find "${PARA_PROJECTS_DIR}" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
fi

if [[ ${#IN_PROGRESS_FILES[@]} -eq 0 ]]; then
  IN_PROGRESS_LIST_TEXT="(현재 status=in_progress 인 작업 노트 없음)"
  log_info "IN_PROGRESS 작업 0건 — 본문 append 작업은 skip 됨"
else
  log_info "IN_PROGRESS 작업 수: ${#IN_PROGRESS_FILES[@]}"
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

## 현재 진행 중(IN_PROGRESS)인 단기 작업 노트 (frontmatter status=in_progress)
$(printf '%b' "${IN_PROGRESS_LIST_TEXT}")

## 당신이 해야 할 일

### A. 블루프린트 작성 (Write)
1. 오늘의 git 커밋 내역을 바탕으로 프로젝트별 진행 상황을 요약하세요.
2. 직전 블루프린트와 오늘 커밋을 종합하여 "내일 1순위로 착수해야 할 과제"를 구체적으로 도출하세요.
3. 해당 과제의 관련 소스 파일을 Read 도구로 직접 읽어 분석하세요 (경로가 존재하는 경우).
4. "내일 즉시 복사 가능한 구현 블루프린트"를 작성하세요. 의도 코드(의사코드 또는 실제 코드 스니펫)를 포함해야 합니다.
5. 모든 결과를 아래 파일 경로에 마크다운으로 Write 도구를 사용해 저장하세요:
   ${BLUEPRINT_FILE}

### B. PARA 01.Projects IN_PROGRESS 작업 노트 갱신 (Edit) — 신규 책무
위 "현재 진행 중인 단기 작업 노트" 목록의 **각 파일**에 대해 아래 두 작업을 수행하세요.

- **B-1. 진행 내역 append**:
  파일 내 \`## 진행 내역\` 섹션을 찾아, 그 섹션 마지막 \`---\` 직전에 다음 라인을 1줄 append.
  형식: \`- ${TODAY}: <오늘 git 활동·블루프린트 기준으로 본 작업과 관련된 변동을 1줄 요약>\`
  관련 변동이 전혀 없으면 이 작업 노트는 skip (라인 추가 안 함).

- **B-2. 내일 실행 가이드 누적**:
  파일 마지막에 \`## 내일 실행 가이드\` 섹션이 없으면 새로 추가, 있으면 그 아래에 \`### ${TODAY} 야간 분석 기준\` 서브헤더로 누적.
  내용: 미완 TO-DO 중 명일 즉시 착수 가능한 1–3개 항목 + 시작점이 될 파일 경로/함수명.
  - 본 작업에 관련 변동이 없으면 이 섹션도 추가하지 않음.

### B 작업의 엄격한 제약
- 위 IN_PROGRESS 목록에 명시된 파일만 Edit 가능. 그 외 모든 \`.md\` / 소스 파일은 Edit 절대 금지.
- frontmatter (\`---\` ~ \`---\`) 영역은 절대 수정 금지. \`status\` 임의 변경 금지.
- \`## 개요\`, \`## 이슈 트래킹\` 등 기존 본문 섹션 텍스트는 절대 수정 금지. **순수 append만** 허용.
- 관련 변동이 없는 노트는 그대로 두기 (강제로 라인 추가 금지).

## 출력 파일 형식 (블루프린트, A의 결과)
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

## PARA 01.Projects 갱신 보고 (신규)
(B-1/B-2 로 어떤 노트의 어느 섹션에 무엇을 append 했는지 파일별 1줄 보고. 변동 없어 skip 한 노트도 명시)

## 위험 및 주의사항
(놓친 것, 잠재적 문제, 다음 세션에 전달할 컨텍스트)
\`\`\`

## 제약사항 (절대 위반 금지)
- git push 금지
- 외부 API 호출 금지
- 파일 삭제 금지
- 소스코드(.php/.kt/.py/.ts/.js/.go/.rs 등) 수정 금지 — Read만 허용
- Edit 허용 범위: 위 IN_PROGRESS 목록의 \`${PARA_PROJECTS_DIR}/*.md\` 파일들 (본문 append만)
- Write 허용 범위: 본 일자 블루프린트 파일 1개 (${BLUEPRINT_FILE})
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
  # --allowedTools: Read, Glob, Grep, Write, Edit 허용
  #   * Edit 는 IN_PROGRESS 작업 노트 본문 append 전용. 프롬프트 안전 가드로 범위 제한.
  #   * Bash, MultiEdit 등은 명시적으로 미허용.
  # --print: 비대화형 모드 (출력 후 종료)
  "${CLAUDE_BIN}" \
    --print \
    --dangerously-skip-permissions \
    --allowedTools "Read,Glob,Grep,Write,Edit" \
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

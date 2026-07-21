#!/usr/bin/env bash
# notion_diary_worker.sh — 오늘 업무를 노션 주간 일지의 요일별 WORK 슬롯에 기록하는 야간 워커
#
# 매일 오후 18:00 launchd 에 의해 실행됨 (caffeinate -i -s 래핑).
# 두 단계로 동작한다:
#   (A) 결정론적 수집(셸): REPO_SCAN_DIR 하위 각 git 레포에서 오늘 자정 이후 커밋을
#       "HH:MM|레포명|커밋제목" 형태로 모아 시각 오름차순 정렬한 WORK_LOG 를 만든다.
#   (B) Notion 기록(claude --print 헤드리스): 오늘 날짜가 속한 주차의 노션 "주간 일지"
#       페이지(「[week NN] @YYYY/MM/DD → YYYY/MM/DD 일지」)를 notion-search 로 찾아,
#       본문 Week Things 섹션의 오늘 요일 칸(요일은 셸에서 date 로 확정 주입)에 있는 빈
#       WORK1~WORK3 슬롯에만 WORK_LOG 를 이슈·주제 단위로 최대 3줄 요약해 채운다.
#       빈 슬롯만 채우고(idempotent) 페이지 하단 append 는 절대 하지 않는다. 토·일은
#       WORK 슬롯이 없어 skip. 헤드리스 claude 는 Notion MCP(claude.ai 커넥터)에
#       정상 접근됨(검증 완료) → 완전 무인 실행 가능.
#
# 환경 변수:
#   REPO_SCAN_ROOT  git 레포 스캔 루트. 미설정 시 폴백 = "$HOME/Project"
#   CLAUDE_BIN      claude CLI 경로. 미설정 시 PATH 에서 자동 탐색.
#   DRY_RUN         1 이면 claude/Notion 호출 skip, 수집한 WORK_LOG 만 파일로 저장.
#
# 안전 가드:
#   - 셸 수집 단계는 git log 읽기만 수행. 어떤 레포도 변경하지 않음.
#   - Notion 기록은 빈 WORK 슬롯만 채움 + idempotent (기존 슬롯 덮어쓰기·하단 append 금지).
#   - 자기완결: PARA·외부 볼트 의존 없음. git 스캔 루트 부재 시 graceful(빈 집계).
#   - launchd에서 caffeinate로 래핑하므로 이 스크립트는 직접 caffeinate 호출 안 함.
#
# 사용법:
#   직접 실행은 권장하지 않음. launchd 또는 테스트 시 dry-run 으로 실행.
#     DRY_RUN=1 ./notion_diary_worker.sh
#     REPO_SCAN_ROOT=/custom/root ./notion_diary_worker.sh
#
# 수동 부트스트랩 (setup.sh 는 plist 를 배포하지 않음 — SoC):
#   cp vibe-tools/com.swkim0128.notion-diary.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.notion-diary.plist
#   (해제: launchctl bootout gui/$(id -u)/com.swkim0128.notion-diary)

set -euo pipefail

# ── 설정 (환경변수 우선, 안전 폴백) ──────────────────────────────────────────
REPO_SCAN_DIR="${REPO_SCAN_ROOT:-${HOME}/Project}"
LOG_DIR="${HOME}/Library/Logs/notion-diary"
TODAY="$(date +%F)"
DOW_NUM="$(date +%u)"
case "${DOW_NUM}" in
  1) DOW_KR="월" ;;
  2) DOW_KR="화" ;;
  3) DOW_KR="수" ;;
  4) DOW_KR="목" ;;
  5) DOW_KR="금" ;;
  6) DOW_KR="토" ;;
  7) DOW_KR="일" ;;
esac
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
LOG_FILE="${LOG_DIR}/${TODAY}.log"
DRY_WORKLOG="${LOG_DIR}/${TODAY}.worklog.dry.txt"
DRY_RUN="${DRY_RUN:-0}"

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

# ── 시작 로그 ────────────────────────────────────────────────────────────────
log_info "===== notion_diary_worker 시작 ====="
log_info "실행 시각: ${RUN_DATE}"
log_info "git 스캔 루트: ${REPO_SCAN_DIR}$([[ -d ${REPO_SCAN_DIR} ]] && echo '' || echo ' (미존재 — 빈 집계)')"
log_info "대상 날짜: ${TODAY}"
log_info "DRY_RUN: ${DRY_RUN}"

# ── 주말 결정론 skip (토·일은 WORK 슬롯 없음) ──────────────────────────────
if [[ "${DOW_NUM}" == "6" || "${DOW_NUM}" == "7" ]]; then
  log_info "오늘(${TODAY})은 ${DOW_KR}요일 — WORK 슬롯이 없어 기록을 skip 합니다."
  log_info "===== notion_diary_worker 완료 (주말 skip) ====="
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# (A) 오늘 업무 시간대별 수집 (결정론적, 셸)
#   REPO_SCAN_DIR 바로 아래(1-depth) + 한 단계(2-depth) 까지의 git 레포에서
#   오늘 자정 이후 커밋을 "HH:MM|레포명|커밋제목" 으로 모아 시각 오름차순 정렬.
#   커밋 0건이면 "오늘 커밋 없음" 표기.
# ─────────────────────────────────────────────────────────────────────────────
WORK_LOG=""

if [[ -d "${REPO_SCAN_DIR}" ]]; then
  # git 레포 판별: <dir>/.git 존재. 1-depth + 2-depth 만 탐색 (과도한 재귀 방지).
  # find -maxdepth 3 로 .git 디렉토리/파일을 찾고, 그 부모(레포 루트)를 수집.
  # bash 3.2 호환 — mapfile/readarray (bash 4+) 미사용
  REPO_DIRS=()
  while IFS= read -r repo_dir; do
    [[ -n "${repo_dir}" ]] && REPO_DIRS+=("${repo_dir}")
  done < <(
    find "${REPO_SCAN_DIR}" -maxdepth 5 -name .git \( -type d -o -type f \) -not -path '*/node_modules/*' -not -path '*/vendor/*' -prune 2>/dev/null \
      | while IFS= read -r gitpath; do dirname "${gitpath}"; done \
      | sort -u
  )

  RAW_COMMITS="$(mktemp "${TMPDIR:-/tmp}/notion-diary-commits.XXXXXX")"
  # shellcheck disable=SC2064  # RAW_COMMITS 값을 즉시 고정해 trap 등록
  trap "rm -f '${RAW_COMMITS}'" EXIT

  REPO_HIT_COUNT=0
  for repo in "${REPO_DIRS[@]}"; do
    [[ -n "${repo}" ]] || continue
    repo_name="$(basename "${repo}")"
    # 오늘 자정 이후 커밋. %cd(커밋 날짜)를 HH:MM 로 포맷. 실패해도 워커는 진행.
    if git -C "${repo}" log \
         --branches \
         --since="${TODAY} 00:00:00" \
         --format='%cd|'"${repo_name}"'|%s' \
         --date=format:'%H:%M' \
         >> "${RAW_COMMITS}" 2>/dev/null; then
      REPO_HIT_COUNT=$((REPO_HIT_COUNT + 1))
    fi
  done

  log_info "스캔한 git 레포 수: ${#REPO_DIRS[@]} (log 성공: ${REPO_HIT_COUNT})"

  if [[ -s "${RAW_COMMITS}" ]]; then
    # 시각(HH:MM) 오름차순 정렬. 형식이 "HH:MM|..." 이므로 사전순 정렬 = 시각순.
    WORK_LOG="$(sort "${RAW_COMMITS}")"
    COMMIT_COUNT="$(wc -l < "${RAW_COMMITS}" | tr -d ' ')"
    log_info "수집한 오늘 커밋 수: ${COMMIT_COUNT}"
  else
    WORK_LOG="오늘 커밋 없음"
    log_info "오늘(${TODAY}) 자정 이후 커밋 없음."
  fi
else
  WORK_LOG="오늘 커밋 없음 (git 스캔 루트 미존재: ${REPO_SCAN_DIR})"
  log_warn "git 스캔 루트를 찾을 수 없습니다: ${REPO_SCAN_DIR}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# (C) DRY_RUN: claude/Notion 호출 skip. 수집한 WORK_LOG 를 파일로 저장.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "1" ]]; then
  printf '# notion-diary DRY_RUN worklog — %s\n\n%s\n' "${TODAY}" "${WORK_LOG}" > "${DRY_WORKLOG}"
  log_info "[DRY_RUN] claude/Notion 호출을 건너뜁니다."
  log_info "[DRY_RUN] 수집 내역 저장: ${DRY_WORKLOG}"
  log_info "[DRY_RUN] 실제 실행 시 위 내역이 주간 일지 오늘 요일의 빈 WORK 슬롯에 기록됨."
  log_info "===== notion_diary_worker 완료 (DRY_RUN) ====="
  exit 0
fi

# ── claude CLI 확인 (실제 실행 경로에서만 필수) ──────────────────────────────
if [[ -z "${CLAUDE_BIN}" ]]; then
  log_error "claude CLI를 찾을 수 없습니다. PATH 또는 CLAUDE_BIN 환경변수를 확인하세요."
  exit 1
fi
log_info "claude CLI: ${CLAUDE_BIN}"

# ─────────────────────────────────────────────────────────────────────────────
# (B) Notion 기록 (claude --print 헤드리스)
#   오늘 날짜가 속한 주차 "주간 일지" 페이지를 찾아, Week Things 섹션의 오늘 요일
#   칸의 빈 WORK1~WORK3 슬롯에만 WORK_LOG 를 요약 기록. 빈 슬롯만·idempotent.
# ─────────────────────────────────────────────────────────────────────────────
log_info "claude 헤드리스 Notion 기록 시작..."

PROMPT="아래는 오늘(${TODAY}) 각 프로젝트의 git 작업 내역이다(형식: HH:MM|레포명|커밋제목). 이 내역을 노션 '주간 일지' 페이지의 오늘 요일 WORK 슬롯에 기록하라. 완전 자율 수행 — 사용자에게 확인·선택·승인 요청 금지, 모호하면 합리적 기본값 채택.

[대상 페이지]
- notion-search 로 오늘(${TODAY})이 속한 주차의 주간 일지 페이지를 찾는다. 제목 형태: '[week NN] @YYYY/MM/DD → YYYY/MM/DD 일지' — 제목의 YYYY/MM/DD ~ YYYY/MM/DD 범위에 오늘 날짜가 포함되는 페이지다. 새 페이지를 생성하지 말 것. 반드시 기존 주차 페이지를 사용한다.

[기록 위치]
- 오늘은 ${DOW_KR}요일이다 (셸에서 계산한 확정값 — 날짜로 요일을 재계산하지 말 것).
- 페이지 본문 'Week Things' 섹션에서 '### ${DOW_KR}요일' 헤딩을 찾아 그 칸의 빈 WORK1~WORK3 슬롯에만 기록한다.
- 그 요일 칸의 WORK1, WORK2, WORK3 슬롯 중 비어 있는 슬롯에만 앞에서부터 순서대로 채운다. 다른 요일 칸은 절대 건드리지 않는다.
- 오늘이 토요일 또는 일요일이면 WORK 슬롯이 없으므로 아무것도 기록하지 말고 종료한다(skip).

[기록 내용]
- WORK_LOG 커밋들을 이슈·주제 단위로 묶어 슬롯당 한 주제씩 최대 3줄로 요약한다.
- chore(auto) 류 자동 커밋은 레포 단위로 묶어 1줄로 처리한다.
- 커밋 제목이나 브랜치에 이슈 키(DWDEV-xxxx)가 있으면 요약 앞에 표기한다.
- WORK_LOG 가 '오늘 커밋 없음'이면 아무것도 기록하지 말고 종료한다.

[규칙]
- 이미 채워진 WORK 슬롯은 절대 덮어쓰지 않는다. 빈 슬롯만 채운다(idempotent).
- Week Things 요일 칸은 컬럼 블록 내부라서 notion-update-page update_content 의 old_str 각 줄에 페이지 원문과 동일한 탭 들여쓰기를 그대로 포함해야 매칭된다. 업데이트 후 notion-fetch 재조회로 실제 반영을 확인하라.
- 페이지 하단에 새 섹션이나 'Git 작업 로그' 블록을 append 하는 것을 절대 금지한다.
- 감정 태그·잡담 없이 업무 사실 위주로 작성한다.
- 완료 후 채운 WORK 슬롯 수(또는 skip 사유)만 한 줄로 보고한다.

--- WORK_LOG:
${WORK_LOG}"

set +e
printf '%s' "${PROMPT}" | "${CLAUDE_BIN}" \
  --print \
  --dangerously-skip-permissions \
  --model "claude-sonnet-4-6" \
  --output-format text \
  --allowedTools "Read,Glob,Grep,mcp__claude_ai_Notion__notion-search,mcp__claude_ai_Notion__notion-fetch,mcp__claude_ai_Notion__notion-update-page" \
  >> "${LOG_FILE}" 2>&1
CLAUDE_EXIT=${PIPESTATUS[1]}
set -e
if [[ ${CLAUDE_EXIT} -ne 0 ]]; then
  log_error "claude Notion 기록 실패 (exit code: ${CLAUDE_EXIT}). 로그 확인: ${LOG_FILE}"
  exit ${CLAUDE_EXIT}
fi

log_info "claude Notion 기록 완료."
log_info "===== notion_diary_worker 완료 ====="
exit 0

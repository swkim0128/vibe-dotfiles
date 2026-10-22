#!/usr/bin/env bash
# notion_diary_worker.sh — 오늘 업무를 노션 주간 일지의 요일별 WORK 슬롯에 기록하는 야간 워커
#
# 매일 오후 18:00 launchd 에 의해 실행됨 (caffeinate -i -s 래핑).
# 모델: claude-opus-5-5 (NOTION_MODEL) — 단일 프로젝트 일상 작업 기본값(Opus).
# 두 단계로 동작한다:
#   (A) 결정론적 수집(셸): REPO_SCAN_DIR 하위 각 git 레포에서 오늘 자정 이후 커밋을
#       "HH:MM|레포명|커밋제목" 형태로 모아 시각 오름차순 정렬한 WORK_LOG 를 만든다.
#   (B) Notion 기록(claude --print 헤드리스): 오늘 날짜가 속한 주차의 노션 "주간 일지"
#       페이지(「[week NN] @YYYY/MM/DD → YYYY/MM/DD 일지」)를 notion-search 로 찾아,
#       본문 Week Things 섹션의 오늘 요일 칸(요일은 셸에서 date 로 확정 주입)에 있는 빈
#       WORK1~WORK3 슬롯에만 WORK_LOG 를 이슈·주제 단위로 최대 3줄 요약해 채운다.
#       빈 슬롯만 채우고(idempotent) 페이지 하단 append 는 절대 하지 않는다. 토·일은
#       WORK 슬롯이 없어 skip. 금요일은 2026-10-16 부터 정기 연차(휴무)라 금요일 칸이
#       LIFE1~LIFE6 구성 → 결정론적 skip(FORCE_FRIDAY=1 이면 실행). 헤드리스 claude 는 Notion MCP(claude.ai 커넥터)에
#       정상 접근됨(검증 완료) → 완전 무인 실행 가능.
#   (D) 주간 Week List 정리(claude --print 헤드리스, 목요일만): (B) 이후 같은 주차 페이지
#       전체를 fetch 해 Week Things 월~목(+이미 채워진 금~일) WORK·LIFE 슬롯과 PARA 주차
#       보고 파일(02.Areas/01.주간보고/<ISO주차>.md, 없으면 생략)을 근거로(금요일 칸은
#       LIFE 슬롯만) Week List 의
#       WORK(협력사/Billing/Other)·LIFE(Sport/Housework/Side Project/Study/Other) 분류에
#       작업 제목만 추가한다. 기존 항목은 지우지 않고 같은 뜻이면 추가하지 않는다(추가 전용).
#       수정 전 Week List 원문을 응답에 출력해 로그에 남긴다(되돌리기 근거).
#       (B) 가 실패해도 (D) 는 시도하며, 둘 중 하나라도 실패하면 종료코드는 비0.
#
# 환경 변수:
#   REPO_SCAN_ROOT  git 레포 스캔 루트. 미설정 시 폴백 = "$HOME/Project"
#   CLAUDE_BIN      claude CLI 경로. 미설정 시 PATH 에서 자동 탐색.
#   VIBE_WORKER_TOOL claude(기본) | codex — codex 면 codex exec -C PARA_VAULT -s workspace-write 로 실행
#                   (worker-tool-lib.sh, CODEX_BIN·CODEX_MODEL 참조. 노션 MCP 는 ~/.codex/config.toml).
#   DRY_RUN         1 이면 claude/Notion 호출 skip, 수집한 WORK_LOG 를 파일로 저장하고
#                   (D) 실행일이면 (D) 프롬프트를 로그에 남긴다.
#   WEEKLY_LIST     1 이면 요일 무관하게 (D) Week List 정리를 실행(강제 실행용).
#   FORCE_FRIDAY    1 이면 금요일(정기 연차)에도 (B) 일일 WORK 기록을 실행(강제 실행용).
#   PARA_VAULT      PARA 볼트 경로((D) 의 주차 보고 파일 근거). 폴백 = "$HOME/Project/para"
#
# 안전 가드:
#   - 셸 수집 단계는 git log 읽기만 수행. 어떤 레포도 변경하지 않음.
#   - Notion 기록은 빈 WORK 슬롯만 채움 + idempotent (기존 슬롯 덮어쓰기·하단 append 금지).
#   - Week List 정리((D))는 추가 전용 — 기존 항목 삭제·수정 금지.
#   - 자기완결: PARA 볼트는 (D) 의 선택적 근거일 뿐 — 부재 시 Notion 페이지만으로 진행.
#     git 스캔 루트 부재 시 graceful(빈 집계).
#   - launchd에서 caffeinate로 래핑하므로 이 스크립트는 직접 caffeinate 호출 안 함.
#
# 사용법:
#   직접 실행은 권장하지 않음. launchd 또는 테스트 시 dry-run 으로 실행.
#     DRY_RUN=1 ./notion_diary_worker.sh
#     DRY_RUN=1 WEEKLY_LIST=1 ./notion_diary_worker.sh   # (D) 프롬프트까지 로그 확인
#     REPO_SCAN_ROOT=/custom/root ./notion_diary_worker.sh
#
# 수동 부트스트랩 (install.sh 는 plist 를 배포하지 않음 — SoC):
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
WEEKLY_LIST="${WEEKLY_LIST:-0}"
PARA_VAULT="${PARA_VAULT:-${HOME}/Project/para}"
ISO_WEEK="$(date +%G-W%V)"
WEEK_REPORT_FILE="${PARA_VAULT}/02.Areas/01.주간보고/${ISO_WEEK}.md"
NOTION_MODEL="claude-opus-5-5"
NOTION_TOOLS="Read,Glob,Grep,mcp__claude_ai_Notion__notion-search,mcp__claude_ai_Notion__notion-fetch,mcp__claude_ai_Notion__notion-update-page"

FORCE_FRIDAY="${FORCE_FRIDAY:-0}"

# 단계 실행 여부: (B) 는 월~목만(금=정기 연차, FORCE_FRIDAY=1 이면 실행), (D) 는 목요일 또는 WEEKLY_LIST=1
RUN_DAILY=1
SKIP_REASON=""
if [[ "${DOW_NUM}" == "6" || "${DOW_NUM}" == "7" ]]; then
  RUN_DAILY=0
  SKIP_REASON="주말 — WORK 슬롯이 없음"
elif [[ "${DOW_NUM}" == "5" && "${FORCE_FRIDAY}" != "1" ]]; then
  RUN_DAILY=0
  SKIP_REASON="정기 연차(매주 금요일 휴무) — 금요일 칸은 LIFE 슬롯만 있음"
fi
RUN_WEEKLY=0
if [[ "${DOW_NUM}" == "4" || "${WEEKLY_LIST}" == "1" ]]; then
  RUN_WEEKLY=1
fi

# claude CLI 경로 (PATH에 없을 경우 대비)
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo '')}"

# AI CLI 선택 (VIBE_WORKER_TOOL=claude|codex, 기본 claude)
# shellcheck source=worker-tool-lib.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/worker-tool-lib.sh"

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

# claude 헤드리스 1회 호출. 프롬프트를 stdin 으로 넘기고 응답은 LOG_FILE 에 누적. 종료코드 반환.
# VIBE_WORKER_TOOL=codex 면 codex exec 로 실행 — 노션 MCP 는 ~/.codex/config.toml 의 mcp_servers.notion 을 쓴다.
run_notion_claude() {
  local prompt="$1"
  local rc
  set +e
  if [[ "${VIBE_WORKER_TOOL}" == "codex" ]]; then
    printf '%s' "${prompt}" | worker_codex_exec "${PARA_VAULT}" "${LOG_DIR}/${TODAY}.codex-last.md" "${LOG_FILE}"
  else
    printf '%s' "${prompt}" | "${CLAUDE_BIN}" \
      --print \
      --dangerously-skip-permissions \
      --model "${NOTION_MODEL}" \
      --output-format text \
      --allowedTools "${NOTION_TOOLS}" \
      >> "${LOG_FILE}" 2>&1
  fi
  rc=${PIPESTATUS[1]}
  set -e
  return "${rc}"
}

# ── 시작 로그 ────────────────────────────────────────────────────────────────
log_info "===== notion_diary_worker 시작 ====="
log_info "실행 시각: ${RUN_DATE}"
log_info "git 스캔 루트: ${REPO_SCAN_DIR}$([[ -d ${REPO_SCAN_DIR} ]] && echo '' || echo ' (미존재 — 빈 집계)')"
log_info "대상 날짜: ${TODAY}"
log_info "DRY_RUN: ${DRY_RUN}"
log_info "단계: 일일 WORK 기록(B)=${RUN_DAILY} / 주간 Week List 정리(D)=${RUN_WEEKLY} (WEEKLY_LIST=${WEEKLY_LIST})"

# ── 금·토·일 결정론 skip (금=정기 연차, 토·일=주말 — WORK 슬롯 없음) ─────────
if [[ "${RUN_DAILY}" == "0" ]]; then
  log_info "오늘(${TODAY})은 ${DOW_KR}요일 — ${SKIP_REASON}. 일일 기록을 skip 합니다."
  if [[ "${RUN_WEEKLY}" == "0" ]]; then
    log_info "===== notion_diary_worker 완료 (${DOW_KR}요일 skip) ====="
    exit 0
  fi
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
# (B) 프롬프트: 오늘 날짜가 속한 주차 "주간 일지" 페이지를 찾아, Week Things 섹션의
#   오늘 요일 칸의 빈 WORK1~WORK3 슬롯에만 WORK_LOG 를 요약 기록. 빈 슬롯만·idempotent.
# ─────────────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────────────
# (D) 프롬프트: 주간 Week List 정리 (목요일 또는 WEEKLY_LIST=1)
#   주차 페이지 전체 + PARA 주차 보고 파일을 근거로 Week List 에 작업 제목만 추가.
#   기존 항목 삭제 금지(추가 전용), 수정 전 원문을 응답으로 남겨 로그에 보존.
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${WEEK_REPORT_FILE}" ]]; then
  WEEK_REPORT_NOTE="존재함 — Read 도구로 읽어 데일리 스크럼·주간보고 원문을 근거 ②로 사용한다."
else
  WEEK_REPORT_NOTE="없음 — 근거 ②는 생략하고 근거 ①(노션 페이지)만 사용한다."
fi

PROMPT_WEEKLY="오늘(${TODAY}, ${DOW_KR}요일)이 속한 주차의 노션 '주간 일지' 페이지에서 'Week List' 섹션을 이번 주 실제 작업 기준으로 보강하라. 완전 자율 수행 — 사용자에게 확인·선택·승인 요청 금지, 모호하면 합리적 기본값 채택.

[대상 페이지]
- notion-search 로 오늘(${TODAY})이 속한 주차의 주간 일지 페이지를 찾는다. 제목 형태: '[week NN] @YYYY/MM/DD → YYYY/MM/DD 일지' — 제목의 날짜 범위에 오늘이 포함되는 페이지다. 새 페이지를 생성하지 말 것. 찾지 못하면 아무것도 수정하지 말고 사유만 보고하고 종료한다.
- 찾은 페이지는 notion-fetch 로 페이지 전체를 읽는다.

[근거 데이터]
- ① 그 페이지 'Week Things' 섹션의 월~목요일 칸 WORK·LIFE 슬롯 내용. 금·토·일 칸에 이미 값이 있으면 그것도 포함한다.
- 금요일은 정기 연차(휴무)라 금요일 칸은 WORK 슬롯 없이 LIFE 슬롯만 있다 — 금요일 칸은 LIFE 슬롯만 읽는다.
- ② PARA 주차 보고 파일: ${WEEK_REPORT_FILE} (ISO 주차 ${ISO_WEEK}, 셸에서 계산한 확정값) — ${WEEK_REPORT_NOTE}

[Week List 분류]
- WORK: 협력사 / Billing / Other.
  - 협력사 = 독립몰·통합몰·연동몰·협력사 DB이관·플레이오토·에누리 관련 작업
  - Billing = 샵다나와(MPADMIN)·MAS·SMS·빌링 관련 작업
  - Other = 그 외(하네스·회의·조직 등)
- LIFE: Sport / Housework / Side Project / Study / Other.

[작성 규칙]
- 항목은 작업 제목만 불릿(-) 한 줄로 쓴다. 이슈 키(DWDEV-xxxx·CTO-xxx 등)·진행률·날짜·상태 표기를 넣지 않는다.
- 같은 작업이 여러 날 나오면 한 줄로 합친다.
- 기존 Week List 항목은 절대 지우거나 고치지 않는다(사용자가 직접 쓴 것일 수 있음). 같은 뜻의 항목이 이미 있으면 추가하지 않는다. 추가만 한다.
- Week List 외 다른 섹션(Week Things 등)은 절대 수정하지 않는다. 페이지 하단에 새 섹션을 append 하지 않는다.
- 컬럼 블록 내부라면 notion-update-page update_content 의 old_str 각 줄에 페이지 원문과 동일한 탭 들여쓰기를 그대로 포함해야 매칭된다. 업데이트 후 notion-fetch 재조회로 실제 반영을 확인하라.

[출력]
- 수정하기 전에, fetch 한 Week List 섹션 원문을 응답에 '--- Week List 원문(수정 전) ---' 과 '--- 끝 ---' 사이에 그대로 출력한다(되돌리기 근거로 로그에 남는다).
- 마지막에 '추가 N건(분류별 건수) / 건너뜀 사유' 형태로 한 줄 보고한다."

# ─────────────────────────────────────────────────────────────────────────────
# (C) DRY_RUN: claude/Notion 호출 skip. 수집한 WORK_LOG 를 파일로 저장하고
#   (D) 실행일이면 (D) 프롬프트를 로그에 남긴다.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "[DRY_RUN] claude/Notion 호출을 건너뜁니다."
  if [[ "${RUN_DAILY}" == "1" ]]; then
    printf '# notion-diary DRY_RUN worklog — %s\n\n%s\n' "${TODAY}" "${WORK_LOG}" > "${DRY_WORKLOG}"
    log_info "[DRY_RUN] 수집 내역 저장: ${DRY_WORKLOG}"
    log_info "[DRY_RUN] 실제 실행 시 위 내역이 주간 일지 오늘 요일의 빈 WORK 슬롯에 기록됨."
  fi
  if [[ "${RUN_WEEKLY}" == "1" ]]; then
    log_info "[DRY_RUN] (D) 주차 보고 파일: ${WEEK_REPORT_FILE} ($([[ -f ${WEEK_REPORT_FILE} ]] && echo '존재' || echo '없음'))"
    log_info "[DRY_RUN] (D) Week List 정리 프롬프트 ↓"
    printf '%s\n' "${PROMPT_WEEKLY}" >> "${LOG_FILE}"
  fi
  log_info "===== notion_diary_worker 완료 (DRY_RUN) ====="
  exit 0
fi

# ── claude CLI 확인 (실제 실행 경로에서만 필수) ──────────────────────────────
if ! TOOL_BIN="$(worker_tool_bin)"; then
  log_error "지원하지 않는 VIBE_WORKER_TOOL: ${VIBE_WORKER_TOOL} (claude|codex)"
  exit 1
fi
if [[ -z "${TOOL_BIN}" ]]; then
  log_error "${VIBE_WORKER_TOOL} CLI를 찾을 수 없습니다. PATH 또는 CLAUDE_BIN/CODEX_BIN 환경변수를 확인하세요."
  exit 1
fi
log_info "${VIBE_WORKER_TOOL} CLI: ${TOOL_BIN}"

# ── (B) 실행: 일일 WORK 슬롯 기록 ────────────────────────────────────────────
DAILY_EXIT=0
if [[ "${RUN_DAILY}" == "1" ]]; then
  log_info "(B) claude 헤드리스 Notion 일일 기록 시작..."
  if run_notion_claude "${PROMPT}"; then
    log_info "(B) claude Notion 일일 기록 완료."
  else
    DAILY_EXIT=$?
    log_error "(B) claude Notion 일일 기록 실패 (exit code: ${DAILY_EXIT}). 로그 확인: ${LOG_FILE}"
  fi
fi

# ── (D) 실행: 주간 Week List 정리 ((B) 실패와 무관하게 시도) ──────────────────
WEEKLY_EXIT=0
if [[ "${RUN_WEEKLY}" == "1" ]]; then
  log_info "(D) claude 헤드리스 Week List 정리 시작... (주차 보고 파일: ${WEEK_REPORT_FILE})"
  if run_notion_claude "${PROMPT_WEEKLY}"; then
    log_info "(D) claude Week List 정리 완료."
  else
    WEEKLY_EXIT=$?
    log_error "(D) claude Week List 정리 실패 (exit code: ${WEEKLY_EXIT}). 로그 확인: ${LOG_FILE}"
  fi
fi

if [[ ${DAILY_EXIT} -ne 0 ]]; then
  log_info "===== notion_diary_worker 종료 (실패 포함) ====="
  exit "${DAILY_EXIT}"
fi
if [[ ${WEEKLY_EXIT} -ne 0 ]]; then
  log_info "===== notion_diary_worker 종료 (실패 포함) ====="
  exit "${WEEKLY_EXIT}"
fi
log_info "===== notion_diary_worker 완료 ====="
exit 0

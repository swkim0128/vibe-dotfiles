#!/usr/bin/env bash
# worker-tool-lib.sh — 정기 워커(overnight·scrum·weekly-report·notion-diary) 공용 AI CLI 선택
#
# 워커가 source 해서 쓴다(직접 실행 안 함). CLAUDE_BIN 을 정한 뒤 source 할 것.
#
# 환경 변수:
#   VIBE_WORKER_TOOL  claude | codex. 기본 claude(기존 동작 그대로).
#   CODEX_BIN         codex CLI 경로. 미설정 시 PATH → /opt/homebrew/bin/codex 순으로 탐색.
#   CODEX_MODEL       codex 모델. 미설정 시 -m 생략(~/.codex/config.toml 기본값).
#
# codex 실행 형태는 personal_weekly_worker.sh 선례를 따른다:
#   codex exec -C <작업 루트> -s workspace-write [-m 모델] -o <최종 응답 파일> -  (프롬프트=stdin)
# ⚠️ codex 경로는 스킬·MCP(노션 등) 연결이 검증되기 전까지 기본값으로 쓰지 않는다.

VIBE_WORKER_TOOL="${VIBE_WORKER_TOOL:-claude}"
CODEX_MODEL="${CODEX_MODEL:-}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || echo '')}"
if [[ -z "${CODEX_BIN}" && -x /opt/homebrew/bin/codex ]]; then
  CODEX_BIN="/opt/homebrew/bin/codex"
fi

# 선택된 도구의 CLI 경로를 출력. 지원하지 않는 VIBE_WORKER_TOOL 이면 종료코드 2.
worker_tool_bin() {
  case "${VIBE_WORKER_TOOL}" in
    claude) printf '%s' "${CLAUDE_BIN:-}" ;;
    codex)  printf '%s' "${CODEX_BIN}" ;;
    *)      return 2 ;;
  esac
}

# codex 비대화형 1회 호출. 프롬프트는 stdin, 진행 이벤트는 로그 파일에 누적. 종료코드 반환.
#   $1=작업 루트(-C)  $2=최종 응답 파일(-o)  $3=로그 파일  $4..=추가 쓰기 허용 디렉토리(--add-dir)
worker_codex_exec() {
  local root="$1" out="$2" log_file="$3"
  shift 3
  local extra=()
  local d
  if [[ -n "${CODEX_MODEL}" ]]; then
    extra+=(-m "${CODEX_MODEL}")
  fi
  for d in "$@"; do
    extra+=(--add-dir "${d}")
  done
  "${CODEX_BIN}" exec \
    -C "${root}" \
    -s workspace-write \
    --skip-git-repo-check \
    ${extra[@]+"${extra[@]}"} \
    --color never \
    -o "${out}" \
    - >> "${log_file}" 2>&1
}

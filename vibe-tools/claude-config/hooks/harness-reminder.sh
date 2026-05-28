#!/bin/bash
# UserPromptSubmit hook — 결정론적 하네스 체크리스트 주입
# 단일 진실 공급원: 대화 컨텍스트보다 메모리·CLAUDE.md 우선 신뢰
set -euo pipefail

read -r -d '' MSG <<'EOF' || true
[하네스 규칙 — 결정론적 7조항]
1. 코드 변경 시 GROUND(플랜)→APPLY(원자적)→VERIFY(도구)→ADAPT(추적) 순서 강제. 한 단계 건너뛰지 말 것.
2. VERIFY는 사람 눈이 아닌 도구로: shell=`shellcheck`+`bash -n`, Kotlin=`./gradlew ktlintCheck`, Python=`ruff check`+`pytest`, PHP=`/php-review` 스킬.
3. 동일 오류 3회 발생 시 즉시 중단·브리핑·사용자 판단 위임. 4번째 시도 금지.
4. 메모리(`~/.claude/projects/.../memory/MEMORY.md`)와 `CLAUDE.md`를 대화 컨텍스트보다 먼저 신뢰. 메모리가 stale 가능성 있을 시 현재 상태로 검증 후 갱신.
5. `settings.work.json`은 Edit 도구만 사용(Write 전체 재작성 금지). PHP 파일은 EUC-KR 확인 후 `analyze:file-encoding-converter` 스킬 경유.
6. Bash 호출은 단일 명령 단위로 분해. 세미콜론·`&&`·`||`·파이프·멀티라인·`2>&1` redirect 등 복합 명령은 권한 패턴 매칭 실패로 매번 프롬프트 발생 — 가능한 한 단일 Bash 호출 여러 번으로 분해할 것.
7. **Subagent-First** — 실행 가능한 모든 작업은 시작 즉시 `Agent(run_in_background=True)` 서브에이전트로 디스패치. 메인은 한 줄 알림 후 즉시 비워 다음 요청 수신 자유. 서브는 Edit/Write/cp 차단되므로 "조사·정밀 변경안 보고만" 위임 후 메인이 발행. trivial 예외: 1-line 확인·단일 read·메타 1회 조회만. 영속/발행(commit/push/외부 전송)은 서브 금지 — 메인이 사용자 확인 후 수행.
EOF

# JSON 인코딩 안전 처리 — jq로 문자열 직렬화 (stdin 무시: -n 필수)
if command -v jq >/dev/null 2>&1; then
  jq -cn --arg ctx "$MSG" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
else
  # jq 미설치 시 폴백 — 줄바꿈을 \n으로 치환
  ESCAPED=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS="\\n"}{print}')
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$ESCAPED"
fi

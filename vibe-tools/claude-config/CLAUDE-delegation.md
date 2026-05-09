# 🔄 위임 전략

| 상황 | 도구 |
|------|------|
| 소스 분석·구현·리팩터링 (프로젝트 컨텍스트 필요) | `claude-delegate.sh` (tmux IPC) / `tmux-suite:claude-ipc` |
| 독립 작업·파일 생성·타 레포 설정 | `Agent(run_in_background=True)` |
| **독립 작업 2개 이상** | `superpowers:dispatching-parallel-agents` 스킬 → Agent 병렬 |
| 코드베이스 탐색 (3쿼리 이상) | `Agent(subagent_type=Explore)` |
| 구현 플래닝 | `Agent(subagent_type=Plan)` / `harness:plan` |

# 🤖 작업별 권장 파이프라인

> 활성 플러그인 컴포넌트 사용. OMC 전용 에이전트(`executor`, `analyst`, `git-master`,
> `qa-tester`, `verifier`, `writer`)는 비활성이므로 호출 금지.

## 코드 분석 (레거시 해독)
1. `Agent(subagent_type=Explore)` — 호출 그래프·의존성 매핑
2. `Agent(subagent_type=analyze:legacy-code-explainer)` — 비즈니스 로직 해독
3. EUC-KR 파일이면 사전에 `analyze:file-encoding-converter` 스킬로 변환
4. 결과 요약은 메인 컨텍스트에서 종합

## 코드 작업 (GROUND→APPLY→VERIFY→ADAPT)
1. `superpowers:using-git-worktrees` 또는 `EnterWorktree`로 격리
2. `harness:dev-workflow` Agent 또는 `harness:pipeline` 스킬로 4단계 진행
3. 첫 Edit/Write/Bash 전 `harness:gateguard` 스킬이 사실 조사 강제 (자동)
4. 워크트리 lint 후 `ExitWorktree` → feature 브랜치 머지
5. `git-suite:commit` (커밋) → `git-suite:mr` 또는 `git-suite:git-mr-creator` (MR)
6. 머지 후 `harness:post-merge` 스킬로 Plane/Outline 일괄 처리

## 테스트·검증
- TDD: `superpowers:test-driven-development` 또는 `test:tdd`
- E2E: `test:e2e` (Playwright) 또는 `test:e2e-chrome` (Chrome Extension)
- 종합 검증: `harness:verification-loop` (빌드→타입체크→린트→테스트→보안스캔→Diff)
- 완료 직전 검증: `harness:verify` 또는 `superpowers:verification-before-completion`
- MR 리뷰: `harness:review-mr` / `analyze:code-review`

## 도메인별 전문 검토
- 아키텍처: `Agent(subagent_type=analyze:arch-reviewer)` / `analyze:arch-review`
- 성능: `Agent(subagent_type=analyze:perf-reviewer)` / `analyze:perf-review`
- 보안: `Agent(subagent_type=analyze:security-reviewer)` / `analyze:security-check`
- SQL: `Agent(subagent_type=analyze:sql-analyzer)` / `analyze:sql-analyze`
- 묵음 실패: `Agent(subagent_type=analyze:silent-failure-hunter)`
- Spring Boot: `Agent(subagent_type=analyze:spring-boot-guide)`
- FastAPI: `Agent(subagent_type=analyze:fastapi-guide)`

# 📄 PHP 인코딩 규칙 (절대 준수)

PHP 파일 작업 전 반드시:
1. `file <파일>` → EUC-KR 확인
2. EUC-KR이면 `iconv -f EUC-KR -t UTF-8` → 임시파일 생성 후 모든 작업 진행
3. 수정 완료 후 `iconv -f UTF-8 -t EUC-KR` → 원본 복원 및 인코딩 재확인

- 변환 자동화: **`analyze:file-encoding-converter` 스킬** 사용
- PHP 커밋 전 리뷰: **`harness:php-review` 스킬** 또는 `/php-review` 슬래시 명령
- EUC-KR 파일 직접 수정 금지. Agent에 위임 시 프롬프트에 변환 절차 명시 필수.

# ⚠️ 위임 수신 규칙

- 현재 단계 완료 후 위임 수락
- 완료 후 `claude-callback.sh`로 결과 보고
- `settings.work.json`: **Edit 도구만 사용** (Write 전체 재작성 금지)
- Plane 이슈 연동 작업: `harness:issue-tracker` 또는 `plane-mcp:plane-*` 스킬

# 🧷 자동 발동 훅 (참고 — 직접 호출 불필요)

| 훅 | 트리거 | 효과 |
|---|---|---|
| `harness/bash-guard.sh` | PreToolUse:Bash | 위험 명령 차단 (rm -rf, curl\|sh, chmod 777 등) |
| `harness/write-guard.sh` | PreToolUse:Write/Edit | 시크릿·민감 파일 보호 |
| `harness/session-start.sh` | SessionStart | 하네스 5조항 자동 주입 |
| `harness/worktree-stop-reminder.sh` | Stop | 워크트리 정리 리마인더 |

> 컴포넌트 전체 매핑은 `~/.claude/CLAUDE-plugins.md` 참조.

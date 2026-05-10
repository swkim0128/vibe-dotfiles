# 🔌 활성 플러그인 컴포넌트 매핑

본 파일은 settings.json에서 **활성화된 플러그인**의 에이전트/커맨드/훅/스킬을
작업 유형별로 어떻게 호출할지 매핑합니다. 활성 플러그인은
시스템에 의해 자동 노출되므로 별도 등록 불필요 — 본 파일은 **트리거 가이드**입니다.

> 비활성 플러그인(`oh-my-claudecode@omc: false`)의 컴포넌트는 호출 불가.
> OMC 명칭(`executor`, `analyst`, `git-master`, `qa-tester`, `verifier`, `writer`)은
> 본 가이드에서 사용하지 않습니다 — 일반 `Agent` 도구의 `subagent_type` 또는
> 활성 플러그인 스킬로 대체합니다.

## 🧭 작업 유형 → 우선 호출 컴포넌트

| 작업 | 우선 호출 |
|------|----------|
| 코드 작업 전체 파이프라인 (GROUND→APPLY→VERIFY→ADAPT) | `harness:dev-workflow` (Agent) / `harness:pipeline` (스킬) |
| 사실 조사 게이트 (Edit/Write/Bash 첫 실행 전) | `harness:gateguard` (스킬) |
| 종합 검증 루프 (PR 전) | `harness:verification-loop` (스킬) / `harness:verify` (스킬) |
| 커밋 / MR 생성 | `git-suite:commit` / `git-suite:mr` / `git-suite:git-mr-creator` |
| MR 코드 리뷰 | `harness:review-mr` (스킬) / `analyze:code-review` (스킬) |
| 코드베이스 탐색 (3쿼리 이상) | `Agent(subagent_type=Explore)` |
| 구현 플래닝 | `Agent(subagent_type=Plan)` / `harness:plan` (스킬) |
| 다중 독립 작업 병렬 | `superpowers:dispatching-parallel-agents` (스킬) |
| 디버깅 (체계적) | `superpowers:systematic-debugging` (스킬) / `harness:debug` (스킬) |
| TDD 워크플로우 | `superpowers:test-driven-development` / `test:tdd` (스킬) |
| E2E 테스트 | `test:e2e` (Playwright) / `test:e2e-chrome` (Chrome) |

## 🔬 분석 / 리뷰 (analyze@swkim0128)

| 도메인 | 컴포넌트 |
|---|---|
| Spring Boot (Kotlin) | `analyze:spring-boot-guide` (Agent) / `analyze:spring-boot-patterns` |
| FastAPI (Python) | `analyze:fastapi-guide` (Agent) / `analyze:fastapi-patterns` |
| 아키텍처 검토 | `analyze:arch-reviewer` (Agent) / `analyze:arch-review` (스킬) |
| 성능 검토 | `analyze:perf-reviewer` (Agent) / `analyze:perf-review` |
| 보안 검토 | `analyze:security-reviewer` (Agent) / `analyze:security-check` |
| SQL 분석 | `analyze:sql-analyzer` (Agent) / `analyze:sql-analyze` |
| 묵음 실패 탐지 | `analyze:silent-failure-hunter` (Agent) |
| 레거시 해독 | `analyze:legacy-code-explainer` (Agent) / `analyze:legacy-scan` |
| DB 마이그레이션 | `analyze:migration-advisor` (Agent) / `analyze:migrate` |
| 레거시→신규 전환 | `analyze:migration-planner` (Agent) / `analyze:migration-map` |
| API 설계 | `analyze:api-designer` (Agent) / `analyze:api-gen` / `analyze:api-doc` |
| 인프라 연동 (PG/Valkey/Kafka) | `analyze:infra-integration-guide` (Agent) |
| 파일 인코딩 변환 (EUC-KR↔UTF-8) | `analyze:file-encoding-converter` (스킬) |

## 🐘 PHP (5.3 레거시 환경)

> 로컬 `php` CLI 미설치 + Apple Silicon에서 PHP 5.3 amd64 컨테이너 QEMU 실패.
> 1차는 LSP 진단, 2차는 스킬 검토, 3차는 Rosetta 활성 후 컨테이너.

| 작업 | 컴포넌트 |
|---|---|
| 1차 문법 검사 (PHP 5.3 타겟) | **php-lsp** + `intelephense` (LSP deferred tool). 워크스페이스에 `intelephense.environment.phpVersion: "5.3.0"` 설정 필요 |
| 2차 커밋 전 리뷰 | `harness:php-review` / `/php-review` |
| 레거시 패턴 코드 리뷰 | `analyze:php-code-review` 스킬 |
| EUC-KR ↔ UTF-8 변환 | `analyze:file-encoding-converter` 스킬 |
| PHP+jQuery → React 마이그레이션 | `analyze:php-jquery-to-react` 스킬 |
| 정확한 인터프리터 검증 (필요 시) | Rancher Desktop Rosetta 2 활성 → `docker run --platform linux/amd64 tetraweb/php:5.3 php -l` |

## 🌳 워크트리 / 이슈 / 세션

| 작업 | 컴포넌트 |
|---|---|
| 워크트리 시작 (격리 작업) | `superpowers:using-git-worktrees` (스킬) / `EnterWorktree` (도구) |
| tmux 세션 시작 (PARA 7:3 레이아웃) | `tmux-suite:tmux-session-start` |
| tmux 세션 종료 | `tmux-suite:tmux-session-done` |
| tmux 세션 간 메시지 | `tmux-suite:tmux-session-comm` |
| tmux 패널 IPC (위임/콜백) | `tmux-suite:claude-ipc` |
| Plane 이슈 추적 | `harness:issue-tracker` (스킬) / `plane-mcp:plane-create` |
| 세션 인수인계 | `harness:handoff` (스킬) |

## 📚 외부 시스템 연동

| 시스템 | 컴포넌트 |
|---|---|
| Outline 위키 자동 업데이트 | `harness:document-latest` |
| 머지 후 Plane/Outline 일괄 처리 | `harness:post-merge` |
| Notion 프로젝트 관리 | `notion-suite:notion-project-manager` |
| Notion 주간 루틴 | `notion-suite:notion-weekly-routine` |
| NAVER WORKS 메일/캘린더/회의 | `nworks:groupware-assistant` (Agent) / `nworks:daily-briefing` |

## 🛡️ 자동 발동 훅 (정보 — 직접 호출 불필요)

| 훅 | 트리거 | 효과 |
|---|---|---|
| `harness/bash-guard.sh` | PreToolUse:Bash | rm -rf, curl\|sh, chmod 777, dev 서버 포그라운드 실행 차단 |
| `harness/write-guard.sh` | PreToolUse:Write/Edit | 시크릿/민감 파일 보호 |
| `harness/session-start.sh` | SessionStart | 하네스 5조항 주입 |

## 📋 PARA / Task 관리

| 작업 | 컴포넌트 |
|---|---|
| 단일 TASKS.md 관리 | `task-mgmt:task-management` |
| PARA 볼트 미완료 스캔 | `task-mgmt:task-review` / `task-mgmt:todo` |
| 이슈 기반 tmux 위임 | `task-mgmt:task-delegate` |
| 프로젝트 완료 처리 | `task-mgmt:task-complete` |
| 작업 로그 기록 | `task-mgmt:task-log` |

## 🧰 메타 / 환경

| 작업 | 컴포넌트 |
|---|---|
| settings.json 변경 (권한/훅/env) | `update-config` (스킬) |
| Claude Code 진단 | `/doctor` (CLI) / `vibe-admin:workspace-surface-audit` |
| 스킬 생성/수정 후 백업 | `vibe-admin:skill-backup` (스킬 작업 시 자동 호출) |
| 플러그인 생태계 탐색 | `vibe-admin:ecosystem-map` |
| Outline MCP 설정 | `vibe-admin:outline-setup` |
| 라이브러리 공식 문서 조회 | `mcp__plugin_context7_context7__query-docs` (Context7 MCP) |

## 🚦 호출 우선순위

1. 이미 활성 스킬이 있으면 **스킬 우선** (system-reminder의 available skills 참조).
2. 도메인 전문 에이전트가 필요하면 `Agent(subagent_type=...)`.
3. 코드 분석 / 다중 파일 변경 등 큰 작업은 일반 `Agent(subagent_type=general-purpose)` 또는 `Explore`/`Plan`.
4. 단발 셸/검색 작업은 도구 직접 호출.

> 본 매핑은 **활성 플러그인 변경 시 갱신**. settings.json의 plugins 블록을 단일 진실 공급원으로 삼는다.

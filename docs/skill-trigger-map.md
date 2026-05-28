# Skill Trigger Map — 자연어 → 스킬 매트릭스

> **목적**: 사용자 자연어 요청이 들어왔을 때, 어떤 스킬·에이전트·도구를 우선 호출할지 결정하는 라우팅 맵.
> **대상 활성 플러그인 16개** (`~/.claude/settings.json` 의 `enabledPlugins` 기준, 비활성 `oh-my-claudecode@omc` 제외).
> **충돌 해소**: 동일/유사 트리거를 가진 스킬 충돌(P2-G 항목)의 우선순위와 분기 기준을 명시한다.

---

## 0. 호출 우선순위 (전역 규칙)

1. **활성 스킬 우선**: system-reminder의 `available skills` 목록에 있으면 스킬 호출.
2. **도메인 전문 에이전트**: 스킬이 없거나 부족하면 `Agent(subagent_type=analyze:*|Explore|Plan)`.
3. **일반 에이전트**: 다중 파일·대규모 분석은 `Agent(subagent_type=general-purpose, run_in_background=True)`.
4. **도구 직접 호출**: 1-line·단일 read·메타 1회 조회만 (Read/Grep/Bash 직접).
5. **사용자 명시 슬래시 커맨드**: `/<name>` 입력은 무조건 그 스킬 우선.

> Subagent-First 원칙: 모든 실행 가능 작업은 시작 즉시 `Agent(run_in_background=True)` 디스패치. trivial 만 메인 직접.

---

## 1. 자연어 트리거 매트릭스 (도메인별)

### 1.1 코드 작업 (구현·수정·리팩터링)

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "구현해줘", "기능 추가", "코드 작성", 이슈번호 | `harness:pipeline` (CODE 모드) | `harness:feature-development`, `Agent(harness:dev-workflow)` |
| "TDD로", "테스트 먼저", "테스트 주도" | `superpowers:test-driven-development` | `test:tdd`, `test:tdd-workflow` |
| "리팩토링", "구조 개선", "재설계" | `superpowers:brainstorming` → `harness:pipeline` | `analyze:code-simplification-guide` |
| "간소화", "정리해줘", "단순하게" | `simplify` | `analyze:code-simplification-guide` |
| "버그 잡아", "왜 안 돼", "에러 원인", "에러 났어", "예외 발생", "왜 죽었지" | `superpowers:systematic-debugging` | `harness:debug`, `harness:trace` (분기는 §2.4 참조) |
| "여러 작업 동시에", "병렬", "동시 진행" | `superpowers:dispatching-parallel-agents` | `harness:pipeline` (PARALLEL), `task-mgmt:multi-dispatch` |
| "워크트리 만들어", "격리해서 작업" | `superpowers:using-git-worktrees` | `EnterWorktree` (도구) |
| "스펙부터", "명세 먼저" | `harness:spec-driven-dev` | `superpowers:brainstorming` → `superpowers:writing-plans` |
| "배포 준비", "프로덕션 출시" | `harness:shipping-guide` | — |
| "제거", "deprecate", "삭제 계획" | `harness:deprecation-guide` | — |

### 1.2 검증·리뷰·완료

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "검증해줘", "완료 전 점검", "PR 전" | `harness:verification-loop` | `harness:verify`, `superpowers:verification-before-completion` |
| "코드 리뷰", "검토", "변경사항 확인" | `analyze:code-review` | ⚠️ **충돌 → §2.2 참조** |
| "MR 리뷰", "PR 리뷰", "머지 리퀘스트 검토" | `harness:review-mr` | ⚠️ **충돌 → §2.2 참조** |
| "/review", "PR 슬래시 리뷰" (top-level 진입점) | `review` | ⚠️ **충돌 → §2.2 참조** |
| "리뷰 받았는데", "피드백 반영" | `superpowers:receiving-code-review` | — |
| "이거 충분해?", "검토 요청" | `superpowers:requesting-code-review` | — |
| "기능이 진짜 되는지", "실제 동작 확인" | `verify` | `harness:verify`, `run` |
| "테스트 돌려", "E2E", "브라우저 테스트" | `test:e2e` (Playwright) | `test:e2e-chrome` (Chrome Ext.) |
| "API 테스트 만들어줘", "엔드포인트 통합 테스트 생성" | `analyze:api-test` | `test:tdd` |

### 1.3 도메인 분석 (백엔드·인프라)

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "종합 분석", "코드 전반 점검", "품질·보안·성능·아키텍처 한번에" | `analyze:analyze` | 도메인별 세부는 아래 행들 |
| "아키텍처 점검", "구조 분석" | `analyze:arch-review` | `Agent(analyze:arch-reviewer)` |
| "성능 분석", "느려요", "느린 쿼리" | `analyze:perf-review`, `analyze:api-perf` | `Agent(analyze:perf-reviewer)` |
| "보안 점검(설정·엔드포인트)", "CORS/CSRF/헤더", "엔드포인트 보호 누락" | `analyze:security-check` | `Agent(analyze:security-reviewer)` |
| "보안 리뷰(현재 변경)", "이번 PR 보안 OK?", "OWASP 변경분" | `security-review` (top-level) | `analyze:security-check` |
| "SQL 분석", "쿼리 튜닝", "인덱스" | `analyze:sql-analyze` | `Agent(analyze:sql-analyzer)` |
| "DI 검증", "Bean 충돌", "@Transactional" | `analyze:bean-check` | `Agent(analyze:spring-boot-guide)` |
| "GraphQL 스키마", "DataLoader" | `analyze:graphql-check` | `analyze:graphql-design-guide` |
| "API 설계", "OpenAPI 스펙" | `analyze:api-gen`, `analyze:api-doc` | `Agent(analyze:api-designer)` |
| "Kafka Producer 만들어", "ApplicationEvent 스캐폴딩", "AsyncAPI 스펙" | `analyze:event-gen` | `analyze:async-event-patterns` |
| "묵음 실패", "빈 catch", "삼킨 예외" | — | `Agent(analyze:silent-failure-hunter)` |

### 1.4 레거시·마이그레이션

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "레거시 해독", "PHP 5.x 분석" | `Agent(analyze:legacy-code-explainer)` | `analyze:legacy-scan` |
| "Java 8 → Kotlin", "Spring 2 → 3" | `analyze:java8-spring2-to-kotlin-spring3` | `Agent(analyze:migration-planner)` |
| "PHP → React/Next.js" | `analyze:php-jquery-to-react` | `Agent(analyze:migration-planner)` |
| "DB 마이그레이션 안전한가" | `analyze:migrate` | `Agent(analyze:migration-advisor)`, `analyze:migration-safety-checklist` |
| "Strangler Fig", "점진 전환" | `analyze:strangler-fig-guide` | `analyze:migration-map` |
| "영향도 분석", "이거 고치면 어디 깨져" | `analyze:impact-analysis` | `Agent(subagent_type=Explore)` |
| "API 계약 추출" | `analyze:extract-api` | — |
| "인코딩 깨짐", "EUC-KR", "iconv" | `analyze:file-encoding-converter` | — |
| "PHP 커밋 전 검토" | `harness:php-review` | `analyze:php-code-review` |

### 1.5 Git·MR·커밋

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "커밋해줘", "이대로 커밋", "stage and commit" | `git-suite:git-commit` | `git-suite:commit` |
| "MR 만들어줘", "PR 작성해줘" | `git-suite:git-mr-creator` | `git-suite:mr` |
| "배포 이슈", "릴리즈 노트" | `git-suite:git-deploy-issue` | — |
| "머지 후 처리", "Plane 닫고 Outline 업데이트" | `harness:post-merge` | `harness:issue-tracker` + `harness:document-latest` |
| "이슈 추적", "Plane 이슈 만들어" | `harness:issue-tracker` | `plane-mcp:plane-create` |
| "Plane 템플릿 관리", "이슈 템플릿 추가/삭제" | `plane-mcp:plane-template` | — |
| "Plane 데일리 브리핑", "오늘 미완료 이슈" | `plane-mcp:plane-briefing` | `nworks:daily-briefing` (그룹웨어) |
| "커밋 전 룰 확인", "CLAUDE.md 갱신 필요?", (자동) 커밋/PR 직전 동기화 판단 | `harness:sync-claude-md` | 자동 발동 — 명시 호출도 가능 |

### 1.6 플래닝·기획

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "계획 세워", "어떻게 접근할까" | ⚠️ **충돌 → §2.3 참조** | — |
| "아이디어 다듬자", "brainstorm" | `superpowers:brainstorming` | — |
| "플랜 실행", "이 계획 진행" | `superpowers:executing-plans` | `superpowers:subagent-driven-development` |
| "마무리하자", "이거 머지/PR" | `superpowers:finishing-a-development-branch` | — |
| "기획 인터뷰", "전략 플래닝" | `harness:plan` (interview 모드) | `superpowers:writing-plans` |
| "feature 분해", "vertical slice" | `harness:planning-guide` | — |
| "ralph 시작", "autopilot 시작", "team 시작" (모호한 vague 요청 게이트) | `harness:ralplan` | `harness:plan` |

### 1.7 PARA·태스크 관리

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "할 일 뭐 남았어", "이번 주 할 일", "what's pending" | ⚠️ **충돌 → §2.1 참조** | — |
| "태스크 추가", "TODO 추가", "remind me to" | `task-mgmt:task-management` (단일 TASKS.md) | ⚠️ **충돌 → §2.1 참조** |
| "이번 주 보고", "주간 todo 공유" | `task-mgmt:task-share` | ⚠️ **충돌 → §2.1 참조** |
| "이슈 위임", "tmux로 세션 만들어 작업" | `task-mgmt:task-delegate` | `tmux-suite:tmux-session-start` |
| "프로젝트 완료", "이슈 종료" | `task-mgmt:task-complete` | `harness:post-merge` |
| "작업 로그", "오늘 한 일 기록" | `task-mgmt:task-log` | — |
| "여러 PARA 작업 동시" | `task-mgmt:multi-dispatch` | `superpowers:dispatching-parallel-agents` |
| "gdrive 정리", "동기화 문서 분류" | `task-mgmt:gdrive-sort` | — |

### 1.8 tmux·세션

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "vibe start", "프로젝트 세션 시작" | `tmux-suite:tmux-session-start` | `harness:vibe-start` |
| "vibe done", "세션 정리" | `tmux-suite:tmux-session-done` | — |
| "@세션명에 전달", "<세션이름>에 알려/물어봐/위임" (세션명 지목) | `tmux-suite:tmux-session-comm` | — |
| "%3에 위임", "패널 ID 지목", "패널 IPC", "다른 패널에 보내" | `tmux-suite:claude-ipc` | — |
| "패널 재배치", "다른 프로젝트로 전환" | `tmux-suite:claude-pane-switch` | — |
| "세션 인수인계", "HANDOFF.md" | `harness:handoff` | — |

### 1.9 Notion·외부 시스템

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "일기 써", "다이어리", "오늘 기분" | `notion-suite:notion-diary` | `notion-suite:notion` |
| "지출 기록", "예산", "N원 썼어" | `notion-suite:notion-budget` | — |
| "식단", "장봤어", "오늘 먹은" | `notion-suite:notion-diet-manager` | — |
| "주간 회고", "KPT", "이번 주 회고" | `notion-suite:notion-weekly-retrospective` | — |
| "이번 주 일정", "주간 슬롯" | `notion-suite:notion-weekly-schedule` | — |
| "주간 루틴", "일요일 정리" | `notion-suite:notion-weekly-routine` | — |
| "프로젝트 노션", "노션 태스크" | `notion-suite:notion-project-manager` | — |
| "노션 통합", "노션 자연어" | `notion-suite:notion` | — |
| "Outline 위키 업데이트" | `harness:document-latest` | `vibe-admin:outline-setup` |
| "/cal-to-notion", "캘린더 → 노션", "이번 주 일정 노션에 반영" | `google-workspace:gws-cal-to-notion` | `notion-suite:notion-weekly-schedule` |

### 1.10 NAVER WORKS·그룹웨어

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "오늘 뭐 있어", "브리핑(일정·메일·할일)", "오늘 스케줄" | `nworks:daily-briefing` | "Plane 미완료 이슈만 보고 싶다" → `plane-mcp:plane-briefing` |
| "회의 잡아", "미팅 예약" | `nworks:meeting-setup` | `nworks:meeting` |
| "회의실 현황" | `nworks:room` | — |
| "안 읽은 메일", "메일함" | `nworks:inbox` | — |
| "메일 작성", "OO한테 메일" | `nworks:mail-compose` | — |
| "nworks 설정", "그룹웨어 연동" | `nworks:nworks-setup` | — |

### 1.11 메타·설정·환경

| 자연어 트리거 | 우선 스킬 | 대안/보조 |
|---|---|---|
| "settings.json 수정", "권한 추가", "hook 등록" | `update-config` | — |
| "키바인딩 변경" | `keybindings-help` | — |
| "사용량 확인", "한도 얼마나 남았어" | `claude-dashboard:check-usage` | — |
| "check-ai alias", "사용량 alias 추가" | `claude-dashboard:setup-alias` | — |
| "statusline 설정" | `claude-dashboard:setup` | `claude-dashboard:update` |
| "HUD 표시", "HUD 옵션", "레이아웃 프리셋" | `harness:hud` | — |
| "하네스 초기화", "프로젝트 룰 적용", "GROUND-APPLY-VERIFY 적용" | `harness:harness-init` | — |
| "Claude Code 진단", "워크스페이스 점검" | `vibe-admin:workspace-surface-audit` | — |
| "스킬·플러그인 뭐 있어", "생태계 맵" | `vibe-admin:ecosystem-map` | — |
| "프롬프트 예시 찾아" | `vibe-admin:search` | — |
| "vibe-tools 명령 추가/수정", "alias 갱신", "sessionizer 경로" | `vibe-admin:update-vibe-script-files` | — |
| "이번 달 남은 근무시간" | `vibe-admin:work-hours` | — |
| "권한 프롬프트 줄여" | `fewer-permission-prompts` | — |
| "주기적 실행", "5분마다" | `loop` | `schedule` |
| "한 번만 예약 실행", "내일 3시" | `schedule` | — |
| "이 앱 띄워봐", "스크린샷" | `run` | `verify` |
| "/context-architect", "CLAUDE.md 계층 재설계", "컨텍스트 토큰 예산", "Memory 재구성" | `analyze:context-architect` | — |
| "스킬 만들어", "스킬 작성", "스킬 검증" | `superpowers:writing-skills` | — |
| "CLAUDE.md 생성", "프로젝트 초기화" | `init` | — |
| "취소", "중단", "활성 모드 끄기", "autopilot/ralph 중지" | `harness:cancel` | — |
| "Claude API 코드", "Anthropic SDK" | `claude-api` | — |
| (자동 발동) Edit/Write/Bash 첫 실행 전 사실 조사 게이트 | `harness:gateguard` | 직접 호출 불필요 — 첫 변경 작업 시 자동 |

### 1.12 라이브러리 공식 문서

| 자연어 트리거 | 우선 도구 |
|---|---|
| "React 최신 문법", "Next.js 마이그레이션", "Prisma 설정" | `mcp__plugin_context7_context7__query-docs` |
| "라이브러리 최신 API", "공식 docs" | `mcp__plugin_context7_context7__resolve-library-id` |

> Context7 MCP는 라이브러리·프레임워크·SDK 질문에 자동 사용. 단, 리팩토링·디버깅·코드 리뷰에는 비대상.

---

## 2. 트리거 충돌 점검 (P2-G 핵심)

### 2.1 충돌 A: 태스크 관리 3종

```
task-mgmt:task-management ↔ task-mgmt:task-review ↔ task-mgmt:task-share
```

| 스킬 | 데이터 소스 | 트리거 핵심 | 출력 |
|---|---|---|---|
| `task-mgmt:task-management` | **현재 디렉토리 `TASKS.md`** | 단순·로컬 1개 파일 관리 | 인플레이스 편집 |
| `task-mgmt:task-review` (= `task-mgmt:todo`) | **PARA 볼트 전체 스캔** | 여러 프로젝트 미완료 통합 보기 | 읽기 전용 종합 보고 |
| `task-mgmt:task-share` | **PARA 이번 주 진행내역** | 팀 공유용 주간 보고 | 텍스트 출력만 |

**분기 기준**:
- "현재 디렉토리" / "이 프로젝트" / "TASKS.md" 명시 → `task-management`
- "PARA" / "이번 주" / "전체 할 일" / "프로젝트들" → `task-review` (`todo`)
- "주간 보고" / "팀 공유" / "이번 주 내역 보여줘" → `task-share`
- 애매하면 **`task-review` 우선** (가장 포괄적, 읽기 전용이라 위험 없음)

### 2.2 충돌 B: 코드 리뷰 3종

```
analyze:code-review ↔ harness:review-mr ↔ review (top-level)
```

| 스킬 | 입력 | 트리거 핵심 | 동작 |
|---|---|---|---|
| `analyze:code-review` | 로컬 변경 / 특정 파일·디렉토리 / GitHub PR | 자체 변경분 검토 | 언어 자동 감지 + 7카테고리 룰 (스킬) |
| `harness:review-mr` | **GitLab MR URL/번호** | MR diff 분석 + **MR에 리뷰 코멘트 작성** | GitLab API 호출 |
| `review` (top-level) | **PR** (현재 브랜치의 pending PR) | 슬래시 명령 형식 진입점 | 변경 PR 종합 리뷰 |

**분기 기준**:
- "GitLab" / "MR" / "사내 MR 리뷰" → `harness:review-mr`
- "/review" 슬래시 직접 입력 / 현재 브랜치 PR 리뷰 (GitHub) → `review` (top-level)
- "PR" (GitHub, 자유 발화) / "로컬 변경" / "방금 짠 코드" / 파일·디렉토리 지정 → `analyze:code-review`
- 매개체가 GitLab MR API 호출을 요구하느냐로 갈린다 (코멘트 자동 작성 여부).
- 입력 범위 차이: `review`는 현재 브랜치 pending PR 단위 / `analyze:code-review`는 임의 입력 (파일·dir·로컬 diff·GitHub PR).

### 2.3 충돌 C: 플래닝 2종

```
harness:plan ↔ superpowers:writing-plans
```

| 스킬 | 트리거 핵심 | 산출물 |
|---|---|---|
| `harness:plan` | **전략적 인터뷰 워크플로우**, 모호한 아이디어 다듬기 | 인터뷰 후 계획서 |
| `superpowers:writing-plans` | **이미 스펙·요구사항이 있는 다단계 작업**, 코드 만지기 전 | 구조화된 implementation plan |

**분기 기준**:
- "뭘 만들지 아직 모르겠는데" / "방향 잡아줘" / 인터뷰 필요 → `harness:plan`
- "스펙 있어, 어떻게 쪼갤지" / "다단계 구현 작업" → `superpowers:writing-plans`
- "리파인 → 의존성 매핑 → 슬라이싱 → 사이징" 같은 패턴 레퍼런스 필요 → `harness:planning-guide` (참고 문서)
- "여러 단계 → 격리 세션 실행"이 목적 → `superpowers:executing-plans`

### 2.4 잠재 충돌 추가 (메인 3개 외)

- **debug 3종**: `harness:debug` ↔ `harness:trace` ↔ `superpowers:systematic-debugging`
  - `harness:debug`: **현재 OMC 세션·repo 상태 진단** (로그·트레이스·재현용 환경 점검). 환경/세션 헬스 체크에 가까움.
  - `harness:trace`: **증거 기반 트레이싱 lane** — 경쟁 가설을 built-in team 모드로 병렬 검증.
  - `superpowers:systematic-debugging`: **일반 디버깅 방법론** — 버그·테스트 실패·예기치 못한 동작 발생 시 가설 → 검증 사이클.
  - → 환경/세션 자체 점검 = `harness:debug`
  - → 가설 여러 개 경쟁 = `harness:trace`
  - → 일반 버그 추적·테스트 실패 진단 = `superpowers:systematic-debugging` (기본 진입점)

- **완료/머지 처리 3종**: `harness:post-merge` ↔ `task-mgmt:task-complete` ↔ `harness:issue-tracker` + `harness:document-latest` (개별 호출)
  - `harness:post-merge`: **MR 머지 직후 Plane 이슈 종료 + Outline 문서 업데이트 일괄 오케스트레이션** (이슈+문서 양쪽 자동).
  - `task-mgmt:task-complete`: **PARA 프로젝트 노트 완료 처리** (status:done + 주간파일 체크 해제 + Plane 이슈 종료 + 04.Archives 이동). PARA 작업 단위 완료.
  - `harness:issue-tracker` + `harness:document-latest`: 위 일괄 처리를 **개별로 분리 실행**할 때.
  - → MR 머지 직후 = `harness:post-merge`
  - → PARA 단기 프로젝트 종결(아카이브 포함) = `task-mgmt:task-complete`
  - → 일부 단계만 필요(이슈만 닫기 / 문서만 갱신) = 개별 스킬

- **레거시 PHP 4종**: `analyze:legacy-scan` ↔ `Agent(analyze:legacy-code-explainer)` ↔ `analyze:php-code-review` ↔ `harness:php-review`
  - `analyze:legacy-scan`: **deprecated API·구버전 함수·취약점 스캔** (정적 룰 기반, 코드 전반).
  - `Agent(analyze:legacy-code-explainer)`: **비즈니스 로직 해독** — 무엇을 하는 코드인지 자연어 설명 생성. 기능 이해 단계.
  - `analyze:php-code-review`: **PHP 6항목 빠른 체크리스트** (전 언어 통합 코드 리뷰는 `analyze:code-review`).
  - `harness:php-review`: **커밋 직전 OMC 하네스 PHP 리뷰** — `analyze:php-code-review` 6개 항목 순서 검토. 커밋 게이트.
  - → "이 코드 뭐하는 거야?" = `legacy-code-explainer`
  - → "deprecated 어디서 써?" = `analyze:legacy-scan`
  - → "PHP 커밋 전 빠른 체크" = `harness:php-review` (커밋 게이트 컨텍스트)
  - → "PHP 체크리스트 6항목 단독" = `analyze:php-code-review`

- `harness:verify` ↔ `verify` (top-level) ↔ `superpowers:verification-before-completion` ↔ `harness:verification-loop`
  - `harness:verify`: 변경이 실제로 의도한 동작을 하는지 (앱 실행·관찰)
  - `verify` (top-level): 실행+관찰 중심 (스크린샷·CLI·서버 직접 띄움)
  - `superpowers:verification-before-completion`: 완료 선언 전 검증 명령 실행 의무
  - `harness:verification-loop`: **6단계 종합 루프** — 빌드 → 타입체크 → 린트 → 테스트 → 보안스캔 → Diff 리뷰. 다른 셋과 결정적 차이는 빌드·타입체크·보안스캔까지 포함하는 풀 파이프라인.
  - → **PR 직전 풀 게이트**: `harness:verification-loop`
  - → **완료 직전 자동 검증** (검증 명령 강제): `superpowers:verification-before-completion`
  - → **실제 앱 동작 확인** (런타임 관찰): `harness:verify` 또는 `verify`
- `harness:pipeline` ↔ `harness:feature-development` ↔ `harness:dev-workflow`
  - `pipeline`: 3가지 모드 자동 감지 (CODE / PARALLEL / TEAM) — **가장 포괄적**
  - `feature-development`: 업무 프로젝트 기능 개발 전용 (analyst→executor→verifier→git-master→qa-tester)
  - `dev-workflow`: G-A-V-A 4단계 오케스트레이터 (Agent)
  - → 기본 진입점 = `harness:pipeline`. 5-에이전트 체인이 필요하면 `feature-development`.
- `test:tdd` ↔ `test:tdd-workflow` ↔ `superpowers:test-driven-development`
  - 셋 다 TDD 강제. `superpowers`가 가장 일반적, `test:tdd-workflow`는 80%+ 커버리지 강제, `test:tdd`는 스캐폴딩 중심.
  - → 슬래시 명령으로 입력된 그대로 사용. 자유 요청이면 `superpowers:test-driven-development`.

---

## 3. 의사결정 트리 (요약)

```
사용자 발화
  ├─ 슬래시 커맨드 명시? → 그대로 호출
  ├─ 코드 변경 의도? → harness:pipeline (G-A-V-A)
  │    ├─ TDD 필요? → superpowers:test-driven-development 끼우기
  │    └─ 워크트리 격리? → superpowers:using-git-worktrees 선행
  ├─ 검증·리뷰? → §1.2 매트릭스 (충돌 B 분기)
  ├─ 분석·해독? → §1.3, §1.4 (도메인 매칭)
  ├─ 플래닝? → §1.6 (충돌 C 분기)
  ├─ Git·MR·이슈? → §1.5
  ├─ PARA·태스크? → §1.7 (충돌 A 분기)
  ├─ 외부 시스템(Notion·NWorks·Outline)? → §1.9, §1.10
  └─ 메타·설정? → §1.11
```

---

## 4. 갱신 정책

- **단일 진실 공급원**: `~/.claude/settings.json` 의 `enabledPlugins` 블록.
- 활성 플러그인 변경 / 신규 스킬 등장 시 본 문서 매트릭스 갱신.
- 새 충돌 감지 시 §2 에 항목 추가 (분기 기준 + 데이터 소스 차이 명시).
- 본 문서는 글로벌 룰(`CLAUDE-*.md`)의 보조 — 작업 유형별 권장 파이프라인은 `~/.claude/CLAUDE-workflows.md` 우선.

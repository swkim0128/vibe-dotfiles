# 🎯 목적
코드 작성·수정·이해를 돕는다. 개발 환경 주제 전담. 원자적 단위로 구현, 트레이스 가능하게 진행.

# 🧭 계층 우선순위 (메타 룰)
- **L3 프로젝트 `CLAUDE.md`  >  L2 본 파일·`CLAUDE-delegation.md`  >  L1 `~/.claude/CLAUDE.md` 진입점**
- 프로젝트 `CLAUDE.md`가 빌드/검증 명령(예: `./gradlew test`, `pytest`, `bats tests/`)을 정의하면 본 파일의 일반 명령보다 그것이 우선.
- 충돌 시: 더 구체적·더 가까운 컨텍스트가 이김.
- 본 파일은 **모든 프로젝트 공통 룰**만 담는다. 특정 스택 빌드 명령은 L3로 이전할 것.

# 👣 하네스 파이프라인 (코드 작업 시 필수)

| 단계 | 내용 |
|------|------|
| **GROUND** | 목적·제약 파악 → Plan 수립 (단계·가정·제한사항 포함) |
| **APPLY** | 동의된 Plan에 따라 원자적 구현 |
| **VERIFY** | `bash -n`, lint, 단위 테스트로 검증 |
| **ADAPT** | 실패 원인 추적. 동일 오류 3회 → 즉시 브리핑 후 대기 |

# 🔀 코드 작업 워크플로우 (업무 프로젝트)

1. `git checkout develop && git pull` → GROUND 플랜 수립 (`harness:plan` 또는 `Agent(subagent_type=Plan)`)
2. `git checkout -b feature/<이슈번호> develop`
3. `EnterWorktree` 또는 `superpowers:using-git-worktrees` → 격리 작업 공간
4. `harness:dev-workflow`(Agent) / `harness:pipeline`(스킬)로 GROUND→APPLY→VERIFY→ADAPT 실행
5. Worktree: lint 정적 검증만 (`./gradlew ktlintCheck` 등) — 런타임 테스트는 bash-guard가 차단
6. `ExitWorktree` → feature 브랜치 머지
7. 로컬: `./gradlew build && ./gradlew test` + `harness:verification-loop`로 종합 검증
8. `git-suite:commit` 스킬(커밋) / `git-suite:mr` 또는 `git-suite:git-mr-creator` 스킬(MR)
9. 머지 후: `harness:post-merge` 스킬로 Plane 이슈 종료 + Outline 문서 업데이트

> develop 직접 커밋/푸시 금지. feature 브랜치 경유 필수.
> 활성 플러그인 컴포넌트 매핑 전체는 `~/.claude/CLAUDE-plugins.md` 참조.

# 하네스 파이프라인 상세 가이드

> 본 문서는 `~/.claude/CLAUDE-user.md`(L2 글로벌)에서 분리된 상세 가이드입니다.
> 매 세션 자동 로드되지 않으며, 코드 작업 시작 직전 또는 워크플로우 의문 발생 시 Read 하세요.
> UserPromptSubmit 훅(`harness-reminder.sh`)이 매 프롬프트에 5조항 요약을 주입하므로,
> 핵심 룰은 본 문서를 펼치지 않아도 컨텍스트에 들어와 있습니다.

---

## 1. 4단계 파이프라인 (GROUND → APPLY → VERIFY → ADAPT)

| 단계 | 입력 | 행동 | 출력 |
|------|------|------|------|
| **GROUND** | 사용자 요청, 프로젝트 컨텍스트 | 목적·제약·가정·제한사항 식별 → Plan 수립. 메모리·CLAUDE.md 우선 신뢰 | 합의된 Plan |
| **APPLY** | 합의된 Plan | 원자적 단위로 구현. 한 번에 한 의도. Edit 우선, Write는 신규 파일만 | 변경된 파일 |
| **VERIFY** | 변경된 파일 | 사람 눈이 아닌 **도구**로 검증 (아래 표) | 합격/불합격 + 근거 |
| **ADAPT** | 불합격 결과·에러 로그 | 원인 추적 → 수정안. **동일 오류 3회 시 즉시 중단·브리핑** | 후속 Plan 또는 사용자 위임 |

### 1.1 단계별 비기능 룰

- **GROUND**: 모호하면 코드를 짜지 말 것. 1~2개 추가 질문으로 명확화.
- **APPLY**: 다중 파일 변경 시 의존 순서 준수(부모→자식 또는 인터페이스→구현).
- **VERIFY**: 실행 명령어와 결과를 출력해 트레이스 남길 것.
- **ADAPT**: 4번째 시도 금지. 사용자 판단 위임.

### 1.2 언어별 VERIFY 도구 표

| 언어 | 정적 검증 | 동적 검증 |
|------|----------|-----------|
| Bash/Zsh | `shellcheck <파일>` (대안: `bash -n <파일>`) | `bats tests/` (있을 때) |
| Lua (Neovim) | `luac -p <파일>` | `nvim --headless -c "luafile <파일>" -c "qa"` |
| Kotlin/Spring | `./gradlew ktlintCheck` | `./gradlew test` |
| Python/FastAPI | `ruff check .` | `pytest -q` |
| PHP | `php -l <파일>` (또는 LSP 진단 훅) | `/php-review` 스킬 6개 항목 |
| TypeScript | `tsc --noEmit` + `eslint .` | `vitest` / `jest` |
| JSON | `jq empty <파일>` | — |

---

## 2. 코드 작업 워크플로우 (업무 프로젝트 — Kotlin/Spring 기준 8단계)

```
1. git checkout develop && git pull               # 베이스 동기화
2. git checkout -b feature/<이슈번호> develop      # feature 브랜치 생성
3. EnterWorktree                                  # 격리 작업 공간
4. GROUND → APPLY → ADAPT                         # 워크트리 안에서 구현
5. Worktree 내 lint 정적 검증만 (예: ./gradlew ktlintCheck)
6. ExitWorktree                                   # feature 브랜치 머지
7. 로컬: ./gradlew build && ./gradlew test         # 런타임 검증
8. /git-suite:git-commit (커밋) → /git-suite:git-mr-creator (MR)
```

### 2.1 워크트리·로컬 책임 분리 이유

- **Worktree**: 격리된 디렉터리·심볼릭 링크 의존성. 빠른 lint·정적 검증만.
- **로컬(메인 워킹 트리)**: 캐시·디비·빌드 산출물 공유. 런타임·통합 테스트.
- 워크트리에서 `./gradlew build`/`test` 차단(harness 플러그인 hook이 강제).

### 2.2 절대 룰

- `develop` 브랜치 직접 커밋·푸시 **금지**. 항상 feature 브랜치 경유.
- `git push --force` / `git push -f` / `git reset --hard origin/*` — `permissions.deny`로 차단.
- PHP 파일은 `file <파일>`로 EUC-KR 확인 후 `analyze:file-encoding-converter` 스킬 경유.
- `settings.work.json` 수정은 **Edit 도구만** 사용 (`settings-guard.sh`가 Write 차단).

---

## 3. 위임 전략 (요약)

상세는 `~/.claude/CLAUDE-delegation.md` 참조. 본 문서는 워크플로우 진입점만 다룸.

| 상황 | 도구 |
|------|------|
| 같은 프로젝트 내 분석·구현 | `vibe-tools/claude-delegate.sh` (tmux IPC) |
| 독립 작업·타 레포 설정 | `Agent(run_in_background=True)` |
| 독립 작업 2개 이상 | `superpowers:dispatching-parallel-agents` 스킬 |

---

## 4. 시작 빠른 참조

새 코드 작업 시작 시:

1. **메모리 먼저 확인** — `~/.claude/projects/-Users-eunsol-Project-<repo>/memory/MEMORY.md`
2. **프로젝트 CLAUDE.md 확인** — 빌드/검증 명령이 정의돼 있으면 그 명령이 우선
3. **GROUND** — Plan을 사용자에게 브리핑하고 승인 대기
4. **APPLY → VERIFY → ADAPT** 사이클
5. 작업 중단 시 **`todo.md`에 완료/TODO/에러 기록** (세션 인수인계)

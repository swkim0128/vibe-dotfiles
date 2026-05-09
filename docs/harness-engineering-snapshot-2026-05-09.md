# 하네스 엔지니어링 설정 현황 스냅샷

> 작성일: 2026-05-09
> 환경: macOS / zsh / `swkim0128@cowave.kr` (업무 환경, settings.work.json 활성)
> 목적: 현재 설정을 한눈에 파악 → 개선 우선순위 결정 자료

---

## 1. 컨텍스트 계층 (CLAUDE.md 트리)

| 파일 | 위치 | 크기 | 역할 |
|------|------|------|------|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 3.7KB | OMC(oh-my-claudecode) 진입점, 핵심 위임 원칙 |
| `CLAUDE-omc.md` | `~/.claude/CLAUDE-omc.md` | 3.5KB | OMC 오케스트레이션 상세 |
| `CLAUDE-user.md` | `~/.claude/` → vibe-dotfiles 심볼릭 | 1.2KB | **하네스 파이프라인 본체** + 코드 워크플로우 |
| `CLAUDE-delegation.md` | `~/.claude/` → vibe-dotfiles 심볼릭 | 위임 전략 + 에이전트 파이프라인 + PHP 인코딩 규칙 |
| 프로젝트 `CLAUDE.md` (vibe-dotfiles) | 작업 디렉토리 | 2.3KB | 레포 스택 + 셸 스크립트 검증 룰 |

**임포트 흐름**: `CLAUDE.md` → `CLAUDE-omc.md` + `CLAUDE-user.md` + `CLAUDE-delegation.md`

---

## 2. Settings (활성: settings.work.json)

```
~/.claude/settings.json → vibe-tools/claude-config/settings.work.json (심볼릭)
```

| 키 | 값 |
|----|----|
| `alwaysThinkingEnabled` | `true` |
| `editorMode` | `vim` |
| `permissions.defaultMode` | **`null`** (매번 묻기 — 명시적 모드 없음) |
| `permissions.allow` 항목 | **15개** (vibe-tools 3종, iconv, file, git, grep, find, ls, cat, cp, mv, mkdir, rm /tmp/*) |
| `permissions.deny` 항목 | **0개** ⚠️ |
| `enabledPlugins` | **16개** (아래 참조) |

### 활성 플러그인 (16)

```
analyze@swkim0128         git-suite@swkim0128       harness@swkim0128 (v3.2.0)
notify@swkim0128          notion-suite@swkim0128    nworks@swkim0128
task-mgmt@swkim0128 (v1.2.0)  test@swkim0128       tmux-suite@swkim0128
vibe-admin@swkim0128      context7@claude-plugins-official
github@claude-plugins-official  oh-my-claudecode@omc
php-lsp@claude-plugins-official  plane-mcp@cc-claude
superpowers@claude-plugins-official
```

---

## 3. Hooks (4개 이벤트, 5개 등록)

| 이벤트 | 핸들러 | 동작 |
|--------|-------|------|
| **UserPromptSubmit** | `harness-reminder.sh` | 매 프롬프트마다 `[하네스 규칙] GROUND→APPLY→VERIFY→ADAPT…` 시스템 메시지 주입 |
| **PreToolUse(Bash)** | inline agent prompt | `git commit` 시 staged PHP 파일 LSP 진단 → 오류 있으면 커밋 차단 |
| **PreToolUse(Write)** | `settings-guard.sh` | settings.work.json 전체 재작성 차단 (Edit만 허용) |
| **SessionStart** | `project-docs-init.sh` | git/.claude 프로젝트면 `.claude/docs/` 자동 생성 |
| **WorktreeCreate** | `worktree-setup.sh` | 워크트리 .gitignore + 의존성 설치 |

**훅 디렉토리**: `vibe-tools/claude-config/hooks/` (총 11개 파일, 일부는 settings에 미등록 상태)

---

## 4. 위임 인프라 (vibe-tools/)

| 스크립트 | 역할 |
|---------|------|
| `claude-delegate.sh` | tmux IPC 위임 (다른 패널 Claude 인스턴스에 작업 송신) |
| `claude-callback.sh` | 위임 작업 완료 보고 |
| `claude-send.sh` | 임의 메시지 전송 |
| `claude-skills.sh` | 스킬 헬퍼 |
| `claude-switch.sh` | 패널 재배치 |
| `vibe.sh` | 메인 (세션 생성·관리) |
| `issue-start.sh` | 이슈 기반 세션 부트스트랩 |
| `vhelp.sh` / `my-tools.sh` | 헬프 / 단축 명령 |

---

## 5. 하네스 플러그인 자산 (`harness@swkim0128 v3.2.0`)

| 자산 종류 | 개수 |
|----------|-----|
| Skills | **20** (cancel, debug, post-merge, planning-guide, issue-tracker, deprecation-guide, ralplan, spec-driven-dev, document-latest, trace, hud, verification-loop, sync-claude-md, gateguard, shipping-guide, verify, plan, pipeline, code-pipeline, workflow-enforcer 외) |
| Commands | **6** (php-review, review-mr, feature-development, handoff, vibe-start, **harness-init** 신규) |
| Agents | **1** (dev-workflow) |
| Hooks | **9** (worktree-lint-enforcer, worktree-next-step, worktree-stop-reminder 등) |

---

## 6. 메모리 (auto-memory)

위치: `~/.claude/projects/-Users-eunsol-Project-vibe-dotfiles/memory/`

| 파일 | 타입 | 핵심 |
|------|------|------|
| `pending-work.md` | project | code-pipeline 스킬 실전 검증 우선순위 (2026-05-07 기준) |
| `project-state.md` | project | vibe-dotfiles + vibe-claude-plugin 전체 설정 스냅샷 (2026-05-06) |

> 두 파일 모두 **2~3일 전 작성** — 일부 내용은 이미 변경됨 (e.g., harness 플러그인 v3.2.0 갱신, /todo·task-share·harness-init 추가)

---

## 7. 강제 메커니즘 요약 (어떻게 하네스가 작동하나)

```
[프롬프트 입력]
   ↓
UserPromptSubmit hook → "[하네스 규칙] GROUND→APPLY→VERIFY→ADAPT" 메시지 주입
   ↓
컨텍스트 계층 → CLAUDE.md → CLAUDE-user.md(파이프라인 표) + CLAUDE-delegation.md(위임 규칙)
   ↓
Claude 응답 시 자연스럽게 GROUND 단계부터 진입
   ↓
Bash 도구 사용 시 PreToolUse(Bash) → git commit이면 LSP 진단 차단
Write 도구 사용 시 PreToolUse(Write) → settings 재작성 차단
   ↓
워크트리 생성 시 WorktreeCreate → 환경 자동 셋업
```

핵심: **하네스는 "강제"가 아니라 "리마인더"** — 매 프롬프트마다 시스템 메시지로 주입되어 Claude가 무시하지 않게 유도. 강제 차단은 PreToolUse 훅에서만 동작 (LSP·settings).

---

## 8. 발견된 개선 후보 (관찰 기반)

### 🔴 우선순위 1 — 보안 가드 미흡
- `permissions.deny` 항목 **0개** → `rm -rf /`, `sudo:*`, `curl | bash` 등 차단 없음
- `permissions.defaultMode = null` → tmux 백그라운드 자동화 시 매번 멈출 가능
- 권장: `docs/claude-headless-automation.md` 가이드의 deny 리스트 적용

### 🟡 우선순위 2 — 컨텍스트 계층 정합성
- 메모리 `project-state.md`가 2026-05-06 기준 → 최근 변경(`/todo`, `task-share`, `harness-init`) 미반영
- 글로벌 `CLAUDE-user.md`와 `CLAUDE-delegation.md`에 PHP 인코딩 규칙 중복 → 통합 또는 명확한 분리 필요
- todo.md TODO에 명시된 *"CLAUDE-user.md ↔ 프로젝트 CLAUDE.md 하네스 중복 정리"* 미진행

### 🟢 우선순위 3 — 자동화 강도 보강
- UserPromptSubmit 훅 메시지가 한 줄 — 더 강한 컨텍스트 주입 가능 (예: 단계별 체크리스트 또는 위임 권장)
- `harness-init` 커맨드 추가됨(v3.2.0) → 다른 프로젝트(ashop 등)에 실전 적용 + 검증 필요
- code-pipeline 스킬 실전 검증 미진행 (memory pending-work.md 우선순위 1)

### 🔵 우선순위 4 — 가시성·디버깅
- 16개 플러그인 활성 → 어느 스킬이 어떤 시점에 발동되는지 파악 어려움
- 플러그인별 `description` 트리거 키워드 충돌 가능성 (예: `task-mgmt:task-management` ↔ `task-mgmt:para-task-review` ↔ `task-mgmt:task-share`)
- 권장: 트리거 매트릭스 문서화 (어떤 자연어 → 어떤 스킬)

---

## 9. 다음 단계 제안 (개선 작업 시 참고)

1. **`permissions.deny` 추가** + `defaultMode: acceptEdits` 적용 (배포: settings.work.json 직접 편집)
2. **메모리 갱신** — `project-state.md` 최신화 (현재 시점 스냅샷 반영)
3. **하네스 플러그인 실전 검증** — ashop에서 `/harness-init`, `code-pipeline` 시도
4. **트리거 매트릭스 작성** — `docs/skill-trigger-map.md` 신규
5. **CLAUDE-user.md ↔ 프로젝트 CLAUDE.md 중복 정리** (todo.md 명시 항목)

---

## 부록 A — UserPromptSubmit 훅 본체 (참고)

```bash
#!/bin/bash
# UserPromptSubmit hook — harness pipeline reminder injected into context
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[하네스 규칙] 코드 수정/생성 요청이라면 반드시 GROUND(플랜 수립) → APPLY(원자적 구현) → VERIFY(검증) → ADAPT(실패 추적) 순서를 따르세요. 동일 오류 3회 시 즉시 중단 후 브리핑."}}\n'
```

## 부록 B — 활성 permissions.allow 전체

```json
[
  "Bash(~/.config/vibe-tools/claude-callback.sh *)",
  "Bash(~/.config/vibe-tools/claude-delegate.sh *)",
  "Bash(~/.config/vibe-tools/claude-send.sh *)",
  "Bash(iconv *)",
  "Bash(file *)",
  "Bash(git *)",
  "Bash(grep *)",
  "Bash(find *)",
  "Bash(ls *)",
  "Bash(cat *)",
  "Bash(cp *)",
  "Bash(mv *)",
  "Bash(mkdir *)",
  "Bash(rm /tmp/*)",
  "Bash(rm -f /tmp/*)"
]
```

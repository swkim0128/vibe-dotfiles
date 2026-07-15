# cmux 치트시트 — tmux 머슬메모리 이전 가이드

vibe-dotfiles 터미널 인프라. cmux 를 tmux 대체로 일상 사용할 때 키·명령 매핑.
관련 설정: `cmux/cmux.json` (동작), `ghostty/config` (테마·폰트·투명도).

## 용어 매핑 + ref 조작 규율 (에이전트 필독)

에이전트 세션에서 cmux/tmux 용어 혼동이 반복돼 정본화. **사용자 표현 → 실제 개념 → 생성법**을 아래로 고정한다.

| 사용자 표현 | 실제 개념 | 생성/제어 |
|---|---|---|
| **탭** (`Cmd+T`) | cmux **surface** (pane 내부 탭바의 탭) | `cmux new-surface` / `cmux tab-action --action new-terminal-right` · 선택 `cmux focus-panel --panel surface:<n>` · 정리 `cmux close-surface` |
| **윈도우** | **tmux window** (tmux 세션 내부의 창) | `tmux new-window` (cmux UI엔 pane/surface로 표현돼 직접 노출 안 됨) |
| **cmux 창(앱 창)** | cmux **window** = cmux 앱 최상위 macOS 창 (워크스페이스 컨테이너, 멀티모니터용) | `cmux new-window` / `cmux move-workspace-to-window` (일상 작업에선 거의 불필요) |
| **워크스페이스** | cmux workspace (window 안, 좌측 사이드바의 프로젝트 단위, tmux 세션이 백킹) | `bash ~/.config/vibe-tools/cmux-proj.sh <NAME>` / `cmux new-workspace` |
| **패널** | tmux pane = cmux pane (분할) | `cmux new-split <DIR>` / `cmux new-pane` |

> **탭 선택 = `focus-panel`** (`tab-action` 에는 `select` 액션이 없다). cmux 의 "panel" 개념은 사실상 surface(탭)에 매핑되어 `list-panels` 는 pane 내 surface 목록을, `focus-panel --panel surface:<n>` 은 그 탭 선택을 수행한다. `tab-action` 유효 액션: `rename`/`clear-name`/`close-left`/`close-right`/`close-others`/`new-terminal-right`/`new-browser-right`/`move-to-new-workspace`/`reload`/`duplicate`/`pin`/`unpin`/`mark-unread`.

### ref 조작 규율
1. **stale ref 방지**: surface/pane ref 는 생성 직후에도 stale 가능. 조작 전 반드시 `cmux tree --workspace <WS>` 또는 `tmux list-panes -t <SESSION>:<WIN> -F` 로 실제 상태를 확인한 뒤 **tmux pane_id(`%n`) 기준**으로 조작한다. `close-surface` 의 반환 ref 는 닫힌 대상이 아니라 이후 포커스 대상이며, `tree` 의 `[selected]`/`◀ active` 표식은 순간적으로 지연될 수 있다 → 탭 선택 상태의 정본은 `cmux list-pane-surfaces --pane <PANE>` 의 `[selected]` 다.
2. **현재 워크스페이스 확인**: `cmux current-workspace` 가 사용자가 실제 보고 있는 워크스페이스와 다를 수 있다. `cmux workspace list` 의 `[selected]` 또는 tmux 로 확인한다.
3. **cwd 지정/상속**: `new-surface` 는 `--working-directory <path>` 로 cwd 를 직접 지정할 수 있고, 미지정 시 워크스페이스 cwd 를 상속한다. `new-pane`/`new-split` 에는 cwd 옵션이 없어 항상 워크스페이스 cwd 를 상속하므로 다른 경로가 필요하면 생성 후 `cd` 한다.

## 상황 → 도구 결정 매트릭스

**가이딩 원칙**: cmux(surface/workspace/diff)를 표면 계층으로 우선, tmux(session/pane)는 backing·IPC·폴백. raw `tmux new-*` 즉흥 호출 금지, 정규화 런처/명령 경유.

| 상황 | 정본 도구 | 금지·폴백 |
|---|---|---|
| 프로젝트 작업 세션 생성(장기·강격리) | `cmux-proj.sh <name>` (cmux 워크스페이스+tmux 세션, 관찰가능) — tmux-session-start 스킬 경유 | raw `tmux new-session` 금지 / cmux 미설치·제외목록 → `vibe start` tmux-only 폴백 |
| **멀티 레포 이슈 워크스페이스** (1개 이슈가 2개+ 레포 동시 수정, 예: DWDEV-2959 = BillingMPAdmin 메인 + PHPLib·MAS 서브) | `cmux-issue.sh <ISSUE> <proj1> [proj2 …]` — 이슈명 워크스페이스+tmux 세션. win1 좌측 main pane=para claude(추적·오케스트레이션) / 우측 스택=수정 대상 레포별 claude(주 작업 레포 최상단) / win2 view=vim 육안 열람. proj 는 cmux-projects.txt 등록명 또는 raw 경로 | 개별 `vibe delegate`(여러 cwd 동시 불가)·raw `tmux new-session` 금지 / 단일 레포는 `프로젝트명_이슈번호` 세션 또는 `vibe delegate` 유지 / cmux 미설치·제외목록 → tmux-only 폴백 |
| 타 프로젝트 위임(기본) | `vibe delegate <proj>` (현재 창 pane split) | 세션·워크스페이스 신규 생성 금지 |
| 화면 열람(소스·diff 육안) | `vibe peek <proj> [diff\|nvim]` (열람 탭) | — |
| 변경/위임 결과 리뷰 | `vibe peek <proj> diff` (→ cmux diff surface 자동 승격) · 보조 `cmux diff --last-turn` / `cmux-proj-review.sh` | 수동 cmux 탭(new-surface) 생성 금지 |
| "탭" 요청 | cmux surface: `cmux new-surface` / `cmux tab-action --action new-terminal-right` | `tmux new-window` 금지 |
| "윈도우" 요청 | tmux window: `tmux new-window` | — |
| "패널"/분할 | cmux pane: `cmux new-split <DIR>` / `cmux new-pane` | — |
| 세션 간 통신 | `tmux-session-comm` / `claude-ipc` (패널 IPC) | — |
| 세션 종료·허브 복귀 | `tmux-session-done` / `vibe main`(para) | 명시 요청 없이 세션 파괴 금지 |

## 일상 워크플로우 (tmux 없이)
1. 프로젝트 열기: `cmux open ~/Project/<프로젝트>` → 새 워크스페이스 생성
2. 그 안에서 `claude` 직접 실행 → 알림 자동주입 + 소켓 env + 한글 IME 해방
3. 프로젝트 전환: `cmd+p` (goToWorkspace 팔레트)

## 키 매핑 (tmux → cmux)
| 동작 | tmux (기존) | cmux |
|---|---|---|
| 프로젝트 전환/sessionizer | `Prefix+f` (vibe fzf) | `cmd+p` 팔레트 / `cmux open <path>` |
| split 우측 | `Prefix+%` | `cmd+d` |
| split 하단 | `Prefix+"` | `cmd+shift+d` |
| pane 포커스 이동 | `Opt+hjkl` | `cmd+opt+←↑↓→` (IME-safe, 무충돌) |
| pane/탭 이름변경 | `Prefix+T` | `cmd+r` (renameTab) / `cmux rename-tab` |
| 파일 탐색기 | `Prefix+Tab` (yazi) | `cmd+opt+b` (내장) |
| 사이드바 토글 | — | `cmd+b` |
| split 줌 토글 | tmux zoom | `cmd+shift+return` |
| 새 탭/표면 | `Prefix+c` | `cmd+t` |
| 설정 리로드 | `Prefix+r` | `cmd+shift+,` (앱) / `cmux reload-config` (CLI) |

> pane-nav 를 hjkl 로 재매핑하지 않는 이유: `cmd+opt+h` = macOS "Hide Others" 충돌. cmux 기본 화살표가 IME-safe + 무충돌.

## CLI (tmux 안/밖 어디서나 — socketControlMode=full)
| 용도 | 명령 |
|---|---|
| split 생성 | `cmux new-split <left\|right\|up\|down>` |
| pane 생성(터미널/브라우저) | `cmux new-pane --type terminal\|browser --url <url>` |
| Claude 에이전트 표면 스폰 | `cmux new-surface --type agent-session --provider claude` |
| 다른 표면에 키 전송(IPC) | `cmux send --surface <ref> "<text>"` / `cmux send-key` |
| 화면 읽기 | `cmux read-screen --surface <ref>` |
| 턴별 diff 뷰어 | `cmux diff --last-turn` |
| 알림 | `cmux notify --title "..." --body "..."` |
| 구조 확인 | `cmux tree --all` / `cmux top --processes` |
| 워크스페이스 목록 | `cmux workspace list` |

## tmux 대비 cmux 순증 기능
- 데스크톱 알림 (notify / dock badge / pane ring)
- 내장 브라우저 (`new-pane --type browser`, `cmux browser *` 제어)
- 턴별 diff 뷰어 (`cmux diff --last-turn`)
- git 상태 사이드바 (브랜치·포트·PR clickable)
- 워크스페이스 = 브랜치 worktree 자동 격리

## 갭 (형태 차이, 기능손실 아님)
- 세션복원: tmux-resurrect 스크롤백 전체복원 대신 cmux 는 명령 재실행(`autoResumeAgentSessions`) 모델. nvim 세션은 nvim shada 가 처리.
- 상태바: 인터미널 일체형 대신 git/ports/PR=사이드바, cpu/mem=`cmux top`, battery=macOS 메뉴바로 분산.
- `Prefix M/C` fzf 팝업(my-tools/claude-skills)은 tmux-suite(vibe-ai-config) 고유 — cmux 대체는 별도 cross-project 작업.

## 소켓 제어 활성 조건
`cmux/cmux.json` 의 `automation.socketControlMode = "full"` + 앱 재시작 1회. 그래야 tmux 안에서도 CLI 소켓 명령이 동작(미적용 시 broken pipe). tmux 밖 cmux surface 면 자동.

## 탭(Surface) 활용

cmux 의 탭 = pane 안의 surface. 한 pane 에 surface 를 여러 개 쌓아 탭처럼 전환한다. surface 는 터미널뿐 아니라 브라우저·diff·마크다운·에이전트도 가능.

### split(pane) vs 탭(surface)
| | split (pane) | 탭 (surface) |
|---|---|---|
| 표시 | 여러 개 동시 | 하나씩 (각자 full 공간) |
| 용도 | 나란히 비교 | 공간 절약·전환, 이종 콘텐츠 묶기 |

### 키 / CLI
- `cmd+t` 새 탭 · `cmd+shift+]`/`[` 전환 · `cmd+w` 닫기 · `ctrl+1~` 번호 선택
- `cmux new-surface --pane <pane> --type terminal|browser|agent-session [--url ...]`
- `cmux tab-action` / `cmux rename-tab` / `cmux move-surface`

### 활용 5종
1. 터미널 + 브라우저 탭 — 같은 pane 에 브라우저 surface 추가, 코드↔미리보기 전환 (split 안 늘림)
2. diff/문서 탭 — helper pane 하나에 diff·마크다운·터미널을 탭으로 모아 레이아웃 단순화
3. 마크다운 프리뷰 탭 — 문서를 surface 로 열어 코드 옆 참조
4. 보조 에이전트 탭 — `new-surface --type agent-session --provider claude`
5. 한 프로젝트 내 이슈별 병행 — 이슈마다 탭 생성, 각 탭에 이슈별 claude/터미널. `rename-tab` 으로 이슈번호 라벨, 사이드바에서 탭별 진행·미읽음 추적

### 이슈별 작업 — 격리 수준 분기
탭은 같은 working tree 를 공유한다. 따라서:
- 같은 브랜치/파일 위 조사·병행 대화 → **탭** (가벼움)
- 이슈마다 다른 브랜치 동시 편집·빌드 → **cmux 워크스페이스 = git worktree** (디렉토리·git 상태·포트 분리)

한 프로젝트 다중 이슈 3단 선택: ① 탭(같은 트리, 가벼움) ② tmux 윈도우(같은 트리, 터미널 중심) ③ 워크스페이스/worktree(다른 브랜치, 완전 격리).

### 공식 원칙
반복적인 "열어줘" 는 split 을 늘리지 말고 기존 pane 에 탭(surface)을 추가. 분할은 동시에 봐야 할 때만, 부가 콘텐츠는 탭으로.

### 행동 규칙 (탭 요청 처리)
정본은 위 「상황 → 도구 결정 매트릭스」의 "탭" 요청 행. 요약:
1. "탭" = cmux surface 로만 처리 — `tmux new-window` 를 대안으로 꺼내지 않는다.
2. 기존 탭(예: 2번 탭) 재사용 우선, 필요 시에만 신규 생성.
   - 생성: `cmux new-surface` 또는 `cmux tab-action --action new-terminal-right`
   - 탭 선택: `cmux focus-panel --panel surface:<n>`

## 에이전트(Claude) 호출 주의

`cmux-proj`/`cmux-dual`/`cmux-ops`/`cmux-review` 는 **사용자 대화형 셸 함수**(`zsh/aliases.zsh`, `~/.zshrc` 가 source). Claude 의 Bash 도구는 **비대화형 셸**이라 이 함수들이 없다(`cmux-proj: not found`). 따라서 **에이전트는 스크립트 경로로 직접 호출**한다:

- `bash ~/.config/vibe-tools/cmux-proj.sh <name>`        # 단일 워크스페이스
- `bash ~/.config/vibe-tools/cmux-issue.sh <ISSUE> <proj1> [proj2 …]`  # 멀티 레포 이슈 (para 좌·추적 + 레포별 우측 스택)
- `bash ~/.config/vibe-tools/cmux-proj-dual.sh <a> <b>`   # 듀얼 (tmux split 2분할)
- `bash ~/.config/vibe-tools/cmux-proj-pair.sh <app> <manifest>`  # 앱+k8s매니페스트 페어 (cmux 탭 2개)
- `bash ~/.config/vibe-tools/cmux-proj-ops.sh <name>`     # 스크립트+서버 ops
- `bash ~/.config/vibe-tools/cmux-proj-review.sh <name> [--branch|--unstaged|--staged]`  # diff 리뷰

사용자는 대화형 셸에서 `source ~/.zshrc` 후 함수명(`cmux-proj <name>` 등)으로 호출 가능. raw `cmux` CLI 는 PATH 전역이라 양쪽 모두 직접 사용 가능(단 tmux 안에선 `--workspace`/`--surface` 명시).

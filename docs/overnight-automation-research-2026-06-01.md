# 야간 자동화 자료 모음 — 2026-06-01

> **목적**: 야간 자율 운전(overnight_worker) 활성화 결정을 위해 수집한 3개 영역 자료를 한 문서로 정리. 사용자가 직접 검토 후 활성화·보강·보류 결정 근거.
>
> **수집 시점**: 2026-06-01
> **수집 방식**: 3개 백그라운드 서브에이전트 병렬 조사 (Claude CLI 자동화 / 본 레포 코드+SOP / macOS launchd 베스트 프랙티스)
> **현재 상태**: plist 설치됨, **launchctl bootstrap 미실행** 추정. 최근 4일간 블루프린트 0건.

---

## 0. 한눈에 보는 시퀀스

```
01:55  pmset (선택, sudo)   → Mac wake (sleep 중일 때만 필요)
02:00  launchd               → calendar trigger (Hour=2, Minute=0)
  ↓    caffeinate -i -s      → 작업 중 sleep 차단 (-i idle, -s system)
  ↓    zsh -lc               → 로그인 셸 PATH 로드
  ↓    overnight_worker.sh
  ├──  환경변수 폴백 (PARA_PATH, REPO_SCAN_ROOT, CLAUDE_BIN)
  ├──  hard fail 조건: CLAUDE_BIN 미발견 → exit 1
  ├──  claude --print --dangerously-skip-permissions
  │      --allowedTools "Read,Glob,Grep,Write,Edit"
  │      --model claude-sonnet-4-6
  │      --output-format text
  ↓    claude가 자체 Read/Glob/Grep으로 24h git 활동 수집·분석
  ↓    BLUEPRINT_FILE 생성 ($PARA_PATH/Retrospectives/YYYY-MM-DD_overnight_blueprint.md)
  ↓    PARA 01.Projects/*.md 본문 append (status:in_progress 파일만)
       (frontmatter 보호, 소스코드 금지 — AI self-discipline)
```

---

## 1. 자료 1 — Claude Code CLI 자동화 (2026-06 기준)

### 1.1 현재 호출 라인 진단
```bash
claude --print \
  --dangerously-skip-permissions \
  --allowedTools "Read,Glob,Grep,Write,Edit" \
  --model claude-sonnet-4-6 \
  --output-format text \
  "<prompt>"
```

| 플래그 | 상태 |
|---|---|
| `--print` (= `-p`) | ✓ 유효 (비대화형 1회 호출) |
| `--dangerously-skip-permissions` | ✓ 2026-06 유효 (= `--permission-mode bypassPermissions`) |
| `--allowedTools` | ✓ 정확한 도구명 (대소문자 구분) |
| `--model claude-sonnet-4-6` | ✓ 2026-06 활성 |
| `--output-format text` | ✓ 지원 |

**결론**: deprecated 플래그·사라진 모델 **없음**. 호출 라인 그대로 사용 가능.

### 1.2 비대화형 모드 환경 로딩 매트릭스 (중요)

| 항목 | `--print` 모드 로딩 | 의미 |
|---|---|---|
| `settings.json` | ✓ Y | `--setting-sources user,project` 기본 |
| `CLAUDE.md` (cwd) | ✓ Y | 프로젝트 룰 로드 |
| MCP servers | ✓ Y | `--mcp-config` 명시 가능 |
| plugins | ✓ Y | `enabledPlugins` 따름 |
| **UserPromptSubmit hook (7조항)** | **❌ N** | 사용자 입력 없음 → 훅 미실행 |
| **SessionStart hook** | **❌ N** | 비대화형 모드 스킵 |
| **memory** | **❌ N** | Read/Write 제외 |

> ⚠️ **결정적 발견**: 야간 Claude는 매 턴 7조항 자동 주입을 **받지 못함**. G-A-V-A·Subagent-First·VERIFY 룰을 자동 적용 못 함. → AI SOP(`CLAUDE-delegation-overnight.md`) 본문이 가드레일의 단일 진실 공급원.

### 1.3 모델 ID (2026-06)
| 모델 | ID | 추천 용도 |
|---|---|---|
| Opus 4.7 | `claude-opus-4-7` | 복잡한 추론·분석 |
| Sonnet 4.6 | `claude-sonnet-4-6` | **야간 분석 권장** (균형) |
| Haiku 4.5 | `claude-haiku-4-5` | 빠른 회응·저비용 |

별칭 `--model opus|sonnet|haiku` 사용 가능. 일관성 위해 명시 버전 권장.

### 1.4 보강 후보 (선택)
- `--max-turns 10` — 무한 루프 방지
- `--fallback-model claude-haiku-4-5` — sonnet 과부하 시 자동 폴백

---

## 2. 자료 2 — overnight_worker.sh + AI SOP 시퀀스

### 2.1 셸 진입점 (`overnight_worker.sh`) 단계
1. **환경변수 폴백** (모두 graceful):
   - `PARA_PATH` → `$HOME/Project/para`
   - `REPO_SCAN_ROOT` → `$HOME/Project`
   - `CLAUDE_BIN` → `command -v claude`
   - `DRY_RUN` → `0`
2. **디렉토리 초기화**: `mkdir -p $LOG_DIR $RETRO_DIR`. 실패 시 `$TMPDIR/overnight-blueprints/` 폴백
3. **사전 점검 로그** (정보성, 실패 안 함). 단 **`CLAUDE_BIN` 빈 문자열 → exit 1** (유일한 hard fail)
4. **DRY_RUN 분기**: claude 호출 skip, 정적 heredoc 텍스트 작성 (점검용)
5. **실제 모드**: claude --print 호출 → 결과를 `$LOG_FILE` 에 append
6. **사후 확인**: BLUEPRINT_FILE 존재 확인, 크기 로깅

### 2.2 AI SOP (`CLAUDE-delegation-overnight.md`) 책무

**태스크 A — Spike Blueprint 작성**
- 최근 24h git 커밋 + 소스 변경점 분석
- 다음 날 아침 사용자가 즉시 복사 가능한 선행 기술 분석 보고서 생성
- 출력: `$RETRO_DIR/YYYY-MM-DD_overnight_blueprint.md`

**태스크 B — PARA 01.Projects 동기화**
- `status: in_progress` 파일 자동 감지
- **B-1**: `## 진행 내역` 섹션 맨 하단에 `- YYYY-MM-DD: <변동 요약 1줄>` append. 관련 변동 없으면 skip
- **B-2**: `## 내일 실행 가이드` 섹션에 `### YYYY-MM-DD 야간 분석 기준` 서브헤더로 미완 TO-DO 1~3개 누적

### 2.3 가드레일 매트릭스

| 가드 | 강제 메커니즘 |
|---|---|
| 도구 제한 (Bash·WebFetch 차단) | **셸 enforcement** (`--allowedTools "Read,Glob,Grep,Write,Edit"`) |
| 소스코드(.php/.kt/.py/.ts 등) 수정 금지 | AI self-discipline (SOP) |
| Edit 범위 = `01.Projects/*.md` 본문 append | AI self-discipline |
| frontmatter (`--- ~ ---`) 보호 | AI self-discipline |
| `## 개요` `## 이슈 트래킹` 기존 본문 보호 | AI self-discipline |
| git push / 외부 API / 파일 삭제 차단 | AI self-discipline (Bash 도구 미허용으로 사실상 차단) |

### 2.4 BLUEPRINT 파일 형식
```yaml
---
type: retrospective
generated_at: YYYY-MM-DD HH:MM:SS
engine: Claude Code (Overnight Automation)
status: unread
---
# 🌙 Overnight Blueprint — YYYY-MM-DD

## 1. 전일(24h) 개발 활동 요약 (Achievements)
## 🎯 2. 금일 최우선 작업 제안 (Today's Top Priority)
## 🛠️ 3. 선행 기술 분석 블루프린트 (Pre-Analysis Spike)
## 📝 4. PARA 01.Projects 갱신 보고
```

### 2.5 Failure Modes (7개)

| 케이스 | 증상 | 대응 |
|---|---|---|
| A. CLI 인자 deprecated | log에 usage 출력 + 블루프린트 미생성 | 정기 모니터링, 자료 1 갱신 |
| B. PARA 디렉토리 권한/부재 | `$TMPDIR/` 폴백 — 사용자가 못 찾음 | 디렉토리 존재 검증 |
| C. **claude 호출 timeout/hang** | 다음날까지 점유 — 다음 trigger 누락 | **timeout 가드 없음** (보강 후보) |
| D. 02:00 노트북 sleep | wake 후 catch-up 실행 (lid closed 시 지연) | pmset wake 추가 (선택) |
| E. 셸 주석 vs SOP 책무 불일치 | 셸 주석의 `## TO-DO` 마킹 vs SOP B-1/B-2 | 혼란 요소, 영향 미미 (Claude는 셸 주석 안 봄) |
| F. **SOP 경로 부정확** | 프롬프트가 `CLAUDE-delegation.md` 참조 → 실제 SOP는 `-overnight.md` | import 따라가야 함 (보강 후보) |
| G. frontmatter `status` 임의 변경 | IN_PROGRESS 풀에서 사라짐 → 추적 단절 | SOP 명시 금지 (self-discipline) |

---

## 3. 자료 3 — macOS launchd 베스트 프랙티스

### 3.1 plist 핵심 키
| 키 | 권장 |
|---|---|
| `Label` | `com.<domain>.<name>` 형식 |
| `ProgramArguments` | 절대경로 실행 파일. PATH 의존 금지 |
| `RunAtLoad` | 시간 트리거 job은 `false` |
| `KeepAlive` | cron 류엔 사용 금지 (무한 재기동 함정) |
| `StartCalendarInterval` | "매일 02:00" 같은 벽시계 시각 |
| `EnvironmentVariables` | `~/.zshrc` 상속 안 됨 → 명시 필수 |
| `StandardOutPath` / `StandardErrorPath` | **회전 없음** — wrapper가 처리 |
| `ProcessType=Background` | 야간 배치 의도 명시, App Nap 적용 |
| `ExitTimeOut` | 기본 20초. 긴 작업은 60+ 권장 (`300` 권장) |
| `LowPriorityIO` / `Nice` | 백업·Time Machine과 IO 경합 회피 |

### 3.2 Sleep 중 missed trigger 처리

| 전략 | 메커니즘 | 평가 |
|---|---|---|
| **catch-up on wake** | sleep 중 시각 통과 시 wake 후 1회 실행 | 기본 동작, lid-closed 시 지연 가능 |
| **pmset repeat wakeorpoweron** | RTC 알람으로 Mac 깨움 → launchd가 catch-up | **권장 조합** (sudo 필요, 시스템 전역) |
| **caffeinate + RunAtLoad** | 깨어있는 동안만 동작 | 야간 부적합 |
| `caffeinate -i -s` 워커 wrapper | 작업 시작 후 완주 보장 | 현재 사용 중 ✓ (시작은 못 깨움) |

**권장 명령 예시** (사용자 직접 실행):
```bash
sudo pmset repeat wakeorpoweron MTWRFSU 01:55:00
pmset -g sched
sudo pmset repeat cancel
```

### 3.3 디버깅 명령 모음
```bash
launchctl list com.swkim0128.overnight
launchctl print gui/$(id -u)/com.swkim0128.overnight
launchctl print-disabled gui/$(id -u)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.overnight.plist
launchctl bootout gui/$(id -u)/com.swkim0128.overnight
launchctl kickstart -k gui/$(id -u)/com.swkim0128.overnight
launchctl enable gui/$(id -u)/com.swkim0128.overnight
plutil -lint ~/Library/LaunchAgents/com.swkim0128.overnight.plist
log show --predicate 'eventMessage CONTAINS "com.swkim0128.overnight"' --last 24h
pmset -g sched
```

**`launchctl list <label>` 출력 해석**
- `PID = -` → 미실행 (정상; 트리거 대기 중)
- `PID = 12345` → 실행 중
- `LastExitStatus = 0` → 마지막 실행 정상
- `LastExitStatus = 78` → 환경설정 오류
- "Could not find service" → 미로드 → `bootstrap` 필요

### 3.4 잘 알려진 함정
- **LaunchAgents vs LaunchDaemons**: 사용자 컨텍스트 필요한 야간 자동화는 `~/Library/LaunchAgents/` (현재 위치) ✓
- **SIP**: plist 로딩에는 영향 없음. `/System/`, `/usr/` 하위 쓰기 차단
- **Apple Silicon PATH**: `/opt/homebrew/bin` (현재 plist 포함) ✓
- **macOS Sonoma+ 백그라운드 항목 토글**: 사용자가 끄면 동작 정지 → **시스템 설정 확인 필수**
- **`tty` 없는 환경**: `vim`, `read`, `sudo` (-S 없이) hang. `tmux new-session -d` (detached)는 OK
- **`ssh`**: `BatchMode=yes` + 키 기반만, 패스워드 프롬프트는 hang

### 3.5 우리 plist 보강 권장 키
현재 `com.swkim0128.overnight.plist`에 추가 시 안정성 ↑:

```xml
<key>ProcessType</key>            <string>Background</string>
<key>ExitTimeOut</key>            <integer>300</integer>
<key>LowPriorityIO</key>          <true/>
<key>Nice</key>                   <integer>5</integer>
<key>AbandonProcessGroup</key>    <false/>
```

---

## 4. 종합 — 활성화 전 체크리스트

### 4.1 필수 검증 (5분)
- [ ] `which claude` — `/opt/homebrew/bin/claude` 있는가 (plist PATH 내)
- [ ] `~/Project/para/01.Projects/`, `~/Project/para/Retrospectives/` — 디렉토리 존재 + 쓰기 권한
- [ ] `~/Library/Logs/overnight_worker/` — 쓰기 권한 (없으면 첫 실행 실패)
- [ ] `plutil -lint ~/Library/LaunchAgents/com.swkim0128.overnight.plist` — plist 문법 OK
- [ ] **macOS 시스템 설정 → 일반 → 로그인 항목 및 확장 → 백그라운드에서** 토글 확인
- [ ] `DRY_RUN=1 ~/Project/vibe-dotfiles/vibe-tools/overnight_worker.sh` — 1회 점검 실행

### 4.2 선택 보강 4가지 (운영 안정성)

**A. timeout 가드** (`overnight_worker.sh` 보강)
- 현재: claude 호출에 timeout 없음 → hang 시 다음날 trigger 누락
- 패치: `"${CLAUDE_BIN}"` 앞에 `timeout 30m` 추가

**B. SOP 경로 명시** (`overnight_worker.sh` 프롬프트)
- 현재: `~/.claude/CLAUDE-delegation.md` 참조 (import 따라가야 overnight SOP 도달)
- 패치: `~/.claude/CLAUDE-delegation-overnight.md` 직접 참조

**C. plist 운영 키 추가** (`com.swkim0128.overnight.plist`)
- 추가: `ProcessType=Background`, `ExitTimeOut=300`, `LowPriorityIO=true`, `Nice=5`

**D. Sleep wake 트리거** (sudo 명령, 선택)
- `sudo pmset repeat wakeorpoweron MTWRFSU 01:55:00`
- 노트북 lid-closed clamshell 케이스에만 필요

### 4.3 표준 활성화 사이클
```bash
plutil -lint ~/Library/LaunchAgents/com.swkim0128.overnight.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.swkim0128.overnight.plist
launchctl enable gui/$(id -u)/com.swkim0128.overnight
launchctl kickstart -k gui/$(id -u)/com.swkim0128.overnight
launchctl print gui/$(id -u)/com.swkim0128.overnight
```

---

## 5. 결정 분기

| 선택 | 절차 | 시간 | 안정성 |
|---|---|---|---|
| **A. 보강 4건 후 활성화** | 패치 A~D 적용 → 검증 → bootstrap | ~30분 | ↑↑ |
| **B. 현재 그대로 활성화** | 검증 → bootstrap | ~10분 | 기본 |
| **C. DRY_RUN만 메인 검증, 활성화 사용자** | DRY_RUN 1회 → 사용자가 bootstrap | ~5분 | 점진 |
| **D. 보류** | 자료만 정리, 활성화 별도 세션 | 0분 | — |

---

## 6. 참고 파일 (모두 절대경로)

| 파일 | 역할 |
|---|---|
| `/Users/eunsol/Project/vibe-dotfiles/vibe-tools/overnight_worker.sh` | 셸 진입점 (SSoT) |
| `/Users/eunsol/Project/vibe-dotfiles/vibe-tools/com.swkim0128.overnight.plist` | launchd plist (SSoT) |
| `/Users/eunsol/Library/LaunchAgents/com.swkim0128.overnight.plist` | 배포본 (이미 복사됨) |
| `/Users/eunsol/.claude/CLAUDE-delegation-overnight.md` | AI 측 자율 운전 SOP |
| `/Users/eunsol/.claude/CLAUDE-delegation.md` | core 임포트 (overnight SOP를 import) |
| `/Users/eunsol/.claude/CLAUDE-paths.md` | 절대경로 SSoT |
| `/Users/eunsol/Library/Logs/overnight_worker/` | 로그 디렉토리 (launchd.out, launchd.err, YYYY-MM-DD.log) |
| `${PARA_PATH:-~/Project/para}/Retrospectives/` | 블루프린트 출력 디렉토리 |
| `${PARA_PATH:-~/Project/para}/01.Projects/` | IN_PROGRESS append 대상 |

---

## 7. 한계 공지

- 자료 3 (launchd) 부분은 WebFetch 차단 환경에서 작성됨 — Apple 공식 문서 직접 인용 못 함. 내장 지식 기반. macOS Sonoma/Sequoia 최신 동작은 활성화 시 교차검증 권장.
- 자료 1 (Claude CLI) 의 `--print` 모드 hook/memory 미주입 사실은 **2026-06 시점** 기준. CLI 버전업 시 변경 가능.
- 본 문서는 **상태 스냅샷**으로 향후 stale 될 수 있음. 활성화 후 6개월 이상 경과 시 자료 1·3 재검토 권장.

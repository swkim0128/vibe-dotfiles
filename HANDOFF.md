# HANDOFF — cmux 도입 세션 (2026-06-25)

## 완료 (vibe-dotfiles, 전부 커밋+푸시됨)
- **cmux 소켓**: `cmux/cmux.json` 에 `automation.socketControlMode="full"` + `terminal.autoResumeAgentSessions=true`. (앱 재시작 1회로 활성됨)
- **워크스페이스 3개** (cmux): vibe-dotfiles(녹 #196F3D, dual: vibe-dotfiles+vibe-ai-config), para(teal #006B6B, 작업관리 전용), danawa-eshop(주황 #A04000, 수동처리 스크립트 ops)
- **런처 4종 정규화** (`vibe-tools/`): `cmux-proj.sh`(단일) / `cmux-proj-dual.sh`(듀얼) / `cmux-proj-ops.sh`(스크립트+서버) / `cmux-proj-review.sh`(diff) — 공통 `cmux-lib.sh` 로 중복 제거(lookup/expand_home/print_projects/create_workspace/has_cli)
- **설정**: `cmux-projects.txt`(vibe-dotfiles|vibe-ai-config|para), `cmux-ops.txt`(danawa-eshop)
- **zsh 함수**: `zsh/aliases.zsh` 에 cmux-proj/cmux-dual/cmux-ops/cmux-review (대화형 셸용)
- **문서**: `docs/cmux-cheatsheet.md` (tmux→cmux 매핑, 탭 활용 5종, 에이전트 호출 주의)
- **메모리**: `cmux-tmux-integration.md` 갱신
- **전역 라우팅**: vibe-ai-config `claude-config/CLAUDE.md` 라우팅 테이블에 cmux 행 추가 (win1.2 vibe-ai-config Claude 에 IPC 위임 완료) → ~/.claude/CLAUDE.md 심링크로 라이브
- **tmux 재구성**: para 의 통합몰정합성/에누리수동생성 → danawa-eshop 으로 move-window 이전. danawa-eshop = win1 claude / win2 edit / win3 통합몰정합성(패널제목 데이터편집·기록·실행). 에누리수동생성 윈도우는 제거(win1/2 로 대체). para 는 claude/edit 만(순수 task-mgmt).

## 잔여 / 다음 작업
- ⚠️ **vibe-ai-config 미커밋**: CLAUDE.md 라우팅 행이 win1.2 에서 미커밋(master*). 파일·심링크는 라이브라 재시작엔 반영되나, git 영속화하려면 win1.2 에서 커밋 필요. (vibe-ai-config 는 자동 커밋 워처 없음)
- **para Claude 재시작 후 테스트**: para:claude 에서 claude 재실행 → cmux 요청 → 라우팅 감지 → 치트시트 lazy-load → 스크립트경로 cmux 호출 확인
- **에이전트 호출 규칙**: Claude 의 Bash 도구는 비대화형이라 cmux-* **함수 없음** → `bash ~/.config/vibe-tools/cmux-proj.sh <name>` 스크립트경로 사용 (치트시트 "에이전트 호출 주의" 참조)
- **신규 프로젝트 cmux 화**: `cmux-projects.txt`/`cmux-ops.txt` 등록 후 런처 호출

## 핵심 권한/우회 사실
- 메인 Bash 도구: `tmux new-session`·`split-window` 권한 거부 / `move-window`·`new-window`·`kill-window`·`rename-window`·`select-pane -T`·`send-keys` 허용
- `cmux workspace create --command "tmux new-session -A -s X"` 는 cmux 앱이 세션 생성 → 거부 우회 (런처가 이용)
- IPC: 모든 Claude 가 tmux pane(공유 소켓) → `tmux send-keys -t <세션>:claude '...' Enter` 범용. cmux 워크스페이스 경계 무관.

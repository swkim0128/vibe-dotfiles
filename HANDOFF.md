# HANDOFF — tmux 세션 레이아웃을 cmux 런처와 통일

작성: 2026-06-29 (퇴근 전 · 구현 보류 · 계획만). 재개 시 이 문서 먼저 읽기.

## 목표
`vibe start`(vibe.sh) 등 tmux 세션 생성 기능의 **윈도우 구성**을 cmux 런처(`cmux-proj.sh`) 기본형과 동일하게 변경.

## 확정 결정 (사용자 승인)
목표 레이아웃 = **cmux 기본형 4개 창** (cmux-proj.sh 의 default `*` case 와 동일):
- win1 `claude` : claude 실행
- win2 `edit`   : nvim .
- win3 `review` : lazygit
- win4 `verify` : shell (검증용)
- 각 창 단일 패널, `Prefix+숫자`/`n,p` 로 전환.
- 현행 vibe start 의 단일 창 7:3(nvim|claude) → 위 4창 구조로 교체.

## 수정 대상 (전부 vibe-ai-config 레포 / tmux-suite 플러그인 — SoC상 vibe-dotfiles 아님)
- `claude-config/plugins/tmux-suite/scripts/vibe.sh` (vibe start 세션 생성 핵심)
- `claude-config/plugins/tmux-suite/scripts/my-tools.sh` (vibe start 호출 경로 — 레이아웃 가정 있으면 점검)
- tmux 세션 생성 스킬: `tmux-suite/tmux-session-start`(SKILL.md) 및 `tmux-session-comm`/`claude-pane-switch`/`claude-ipc` 중 세션 레이아웃·패널 타겟 가정이 있으면 함께 점검
- 참고(수정 안 함): vibe-dotfiles `vibe-tools/cmux-proj.sh` default `*` case 의 tmux 명령 시퀀스 = 레퍼런스

## 실행 방법 (cross-project → vibe-ai-config Claude 에 위임)
1. vibe-ai-config 세션(이전엔 현재 세션 2번 패널 %19 사용)에 위임. 격리 git worktree, 외과수술식.
2. vibe.sh 의 기존 7:3 split 생성 블록을 4창 생성 블록으로 교체. 레퍼런스 시퀀스:
   - tmux new-session -d -s <s> -n claude -c <path>  →  send-keys -t <s>:claude 'claude' Enter
   - tmux new-window -t <s> -n edit -c <path>        →  send-keys 'nvim .' Enter
   - tmux new-window -t <s> -n review -c <path>      →  send-keys 'lazygit' Enter
   - tmux new-window -t <s> -n verify -c <path>
   - tmux select-window -t <s>:claude
   (cmux-proj default 는 claude 자동실행이 빠져 있음 → vibe 쪽 win1 에는 claude 실행 포함시킬 것. 사용자 의도)
3. 기존 IPC(claude-ipc / tmux-session-comm)·콜백 send-keys 타겟이 `<세션>:claude` 창을 가정하는지 확인 — 4창 구조에서도 `claude` 창이 존재하므로 대체로 유효하나, 7:3 split 패널(.2=claude) 타겟에 의존하던 코드가 있으면 창 타겟으로 수정.
4. VERIFY: `shellcheck vibe.sh` 및 수정한 모든 .sh 통과(미설치 시 bash -n). 스킬 변경 시 관련 문서/cheatsheet 갱신.
5. 커밋까지. tmux-suite 가 플러그인이면 적용에 재설치/재시작 고려.

## 리스크
- vibe start ↔ PARA 워크플로우 IPC 연동: 패널/창 타겟 변경 시 위임·콜백 깨질 수 있음 → 회귀 점검 필수.
- 사용자 머슬메모리(7:3 단일창) 변화 → cheatsheet 등 문서 갱신 검토.

## 기타 미결 (2026-06-29 세션 잔여)
- notify cmux 사이드바 알림(notify@swkim0128 1.1.1): 구현·머지·재설치 **완료**. **Claude Code 재시작만 남음**(사용자 수동, 실행 세션 종료됨).
- Slack: 모니터링 보류. 온디맨드 조회 쓰려면 `mcp__plugin_slack_slack__slack_search_public_and_private` 도구 permission allow 가 선결(비대화형 서브에이전트에서 거부됨).
- cmux 런처 현황(이번 세션 완료·master 푸시): cmux-proj 세션 재사용/중복방지, cmux-close(닫기·tmux 유지), 선별 pin(vibe-dotfiles·para만), cmux-pair(앱+k8s매니페스트 2탭).

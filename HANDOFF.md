# HANDOFF — Session Context Transfer

> 이전 세션 작업 컨텍스트. 새 세션에서 이 파일을 읽고 이어서 작업.
> (구 2026-06-29 핸드오프는 완료되어 대체됨.)

## Session Info
- Date: 2026-07-07
- Branch: master (vibe-dotfiles) / master (vibe-ai-config)
- Goal: 하네스 개편(콜백 제거·cmux 오픈 강제) + 세션 레이아웃 정리 + 야간 자동화 2종 신규 구축

## What Succeeded (모두 완료·검증·커밋)
1. **기본 모델 복원**: settings.local.json 의 `model` 고정 제거 → default(Opus 4.8) 사용.
2. **세션간 완료 콜백 제거 + cmux 오픈 강제 라우팅** (vibe-ai-config `02be323`·`5905f86`): claude-send.sh/vibe.sh cast 콜백 주입 제거, claude-callback.sh 심링크 삭제, claude-ipc/tmux-session-comm/multi-dispatch/task-delegate/CLAUDE-delegation 문서 반영. **origin push + 마켓플레이스 클론 ff 동기화 → 런타임 반영 검증 완료**.
3. **cmux 워크스페이스 제외 목록** (vibe-dotfiles `6ae1593`): `vibe-tools/cmux-no-workspace.txt` + cmux-lib.sh `cmux_is_excluded` + cmux-proj.sh 분기. vibe-ai-config 는 워크스페이스 안 열고 tmux-only.
4. **세션 레이아웃 3창화**: cmux-proj.sh(`*` case)·vibe.sh `_do_start` 에서 lazygit(review) 윈도우 제거 → claude/edit/verify. 열려있던 세션(vibe-dotfiles·vibe-ai-config·ashop_PO20D·ashop_DWDEV-4681)도 런타임 window 3 삭제+재넘버링 완료.
5. **야간 자동화 2종 신규 (launchd, 활성)**:
   - **skill-audit @ 22:00**: `vibe-tools/skill_audit_worker.sh` + `com.swkim0128.skill-audit.plist`. 스킬/플러그인/에이전트 사용(트랜스크립트) vs 설정 비교 → `~/Library/Logs/skill-audit/YYYY-MM-DD.md`. 순수 셸.
   - **notion-diary @ 18:00**: `vibe-tools/notion_diary_worker.sh` + `com.swkim0128.notion-diary.plist`. 오늘 git 커밋을 시간대별 수집 → `claude --print`(Notion MCP + notion-diary 스킬)로 다이어리 기록. 로그 `~/Library/Logs/notion-diary/`.
   - 둘 다 `~/Library/LaunchAgents/` 복사 + `launchctl bootstrap` 완료(state=not running, 정각 대기).

## Current State
- vibe-dotfiles: clean, master, origin 동기화됨.
- vibe-ai-config: master, origin push 완료, 마켓플레이스 클론 ff 동기화됨.
- 미결/보류 없음. (skill-audit 첫 리포트는 누적 원장 축적 전이라 대부분 "미사용"으로 나옴 — 며칠 관찰 필요.)

## Next Steps
1. **Claude Code 재시작** — 업데이트된 vibe-ai-config 플러그인(tmux-suite/task-mgmt: 콜백 제거·cmux 라우팅)을 실행 세션에 반영하려면 재시작 필요.
2. (관찰) 오늘 18:00 notion-diary, 22:00 skill-audit 첫 실행 결과를 `~/Library/Logs/{notion-diary,skill-audit}/` 에서 확인.
3. (선택) skill-audit "거의 안 씀" 판정을 며칠 누적 후 실제 플러그인 정리에 활용.

## Key Files (vibe-dotfiles/vibe-tools/)
- `skill_audit_worker.sh` / `com.swkim0128.skill-audit.plist` — 22시 스킬 감사
- `notion_diary_worker.sh` / `com.swkim0128.notion-diary.plist` — 18시 다이어리 기록
- `cmux-no-workspace.txt` / `cmux-lib.sh` / `cmux-proj.sh` — cmux 워크스페이스 제외 목록
- `overnight_worker.sh` — 기존 2시 워커(패턴 레퍼런스)
- 메모리: `skill-audit-nightly`, `notion-diary-nightly`, `callback-removal-refactor`, `pre-delegation-cmux-open` (자동 로드됨)

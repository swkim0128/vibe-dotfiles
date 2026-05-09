## 완료

- [x] CLAUDE-user.md 하네스 파이프라인 추가 (GROUND/APPLY/VERIFY/ADAPT)
- [x] setup.sh: ~/.claude/CLAUDE-user.md 심볼릭 링크 + 임포트 자동 주입
- [x] vibe-tools/claude-config/hooks/auto-git-push.sh 생성 (Stop 훅 자동 커밋/푸시)
- [x] .claude/settings.local.json Stop 훅 등록
- [x] git-commit 스킬 commit-convention.md ~/.gitmessage.txt 우선순위 수정
- [x] vibe fzf: 세션 없을 때 이슈명 입력 후 생성으로 변경

### [2026-05-06] 하네스 점검 주기 — 강화된 규칙 및 설정

- [x] **P1** `mac-notify.sh`: `set -euo pipefail` 추가 (CLAUDE.md 하네스 룰 준수)
- [x] **P2** `auto-git-push.sh`: `git push || true` → 실패 시 stderr 경고 출력으로 개선 (ADAPT 룰 준수)
- [x] **P3** `CLAUDE-user.md`: "코딩 외 주제 절대 금지" → Claude Code 특성에 맞게 완화 (설정 점검·환경 진단 허용)
- [x] **P4** `.claude/settings.local.json` permissions: 73개 일회성·실험적 항목 → 14개 재사용 가능 패턴으로 정리

### [2026-05-09] 하네스 엔지니어링 P0 적용 (Gemini 가이드 기반)

- [x] **P0-A** `settings.work.json`: `permissions.deny` 25개(rm 루트/홈, sudo, git force-push, hard reset, fork bomb 등) + `defaultMode: acceptEdits` 추가
- [x] **P0-B** `harness-reminder.sh`: 1줄 권고 → 결정론적 5조항(GROUND-APPLY-VERIFY-ADAPT, 도구별 VERIFY 명령, 3회 차단, 메모리 우선, settings Edit 강제). jq 기반 안전 직렬화(`-n` 플래그)
- [x] **P0-C** 글로벌 `CLAUDE.md`: `@CLAUDE-omc.md` 임포트 제거 (OMC:START~END 영역과 100% 중복 → 매 세션 토큰 낭비 해소)

### [2026-05-09] 하네스 4계층 SRP 재정의 (계층별 단일 책임)

- [x] **L1-1** `~/.claude/CLAUDE-omc.md` 백업 후 제거(`/tmp/claude-md-archive-2026-05-09/`) — OMC:START~END가 단일 진실 공급원, ~890토큰 절감
- [x] **L1-2** `~/.claude/CLAUDE.md` 사용자 영역에 L1 책임 명세 + 계층 우선순위(L3>L2>L1) 메타 룰 주석 추가
- [x] **L2-1** `CLAUDE-user.md`에 메타 룰 추가: "프로젝트 빌드/검증 명령은 L3 우선, 본 파일은 공통 룰만"
- [x] **L3-1** `vibe-dotfiles/CLAUDE.md`에서 글로벌 하네스 표 제거, dotfiles 한정 VERIFY 도구 표(shellcheck/luac/jq)로 대체
- [x] **VERIFY** 임포트 체인·중복 잔재·jq 무결성 모두 통과

## TODO

- [ ] **P1-D** 메모리 갱신 — `project-state.md`를 2026-05-09 스냅샷으로 최신화
- [ ] **P1-E** PHP 인코딩 규칙 중복 정리 (`CLAUDE-delegation.md`에 단일화)
- [ ] **P1-F** 미등록 훅 정리 — `pre-commit-check.sh`, `php-encoding-check.sh`, `auto-git-push.sh`, `task-send/stop.sh` settings 등록 또는 `hooks/_unused/` 격리
- [ ] **P2-G** `docs/skill-trigger-map.md` — 자연어 → 스킬 매트릭스 (16개 플러그인 트리거 충돌 점검)
- [ ] **P2-H** `CLAUDE-user.md` 슬림화 — 본문 → `docs/harness-pipeline.md`로 분리, 진입점만 유지
- [ ] CLAUDE-user.md ↔ 프로젝트 CLAUDE.md 하네스 중복 정리 (vibe-claude-plugin 배포 사이클과 묶어 진행)
- [ ] setup.sh: 새 머신에서 설치 후 전체 플로우 통합 테스트
- [ ] tmux 무인 자동화 권한 설정 적용 — `docs/claude-headless-automation.md` 검토 후 `vibe-tools/claude-config/settings.work.json`에 반영 + `scripts/claude-headless.sh` 생성

## 에러 / 블로커

- 없음

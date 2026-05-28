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

### [2026-05-09] 하네스 P1 — 메모리·중복·미등록 훅 정리

- [x] **P1-D** 메모리 갱신 — `project-state.md`(2026-05-09 스냅샷 재작성: 4계층 SRP·deny 25개·5조항 훅) + `pending-work.md`(완료 항목 정리, P2·미진행만 남김)
- [x] **P1-E** PHP 인코딩 규칙 중복 진위 확인 — 결과: **중복 없음**(snapshot 추측 오류). SoR=`CLAUDE-delegation.md` L20-28 단독, 추가 작업 불필요
- [x] **P1-F** 미등록 훅 5개 `hooks/_unused/`로 비파괴 격리 — `mac-notify.sh`(notify 플러그인), `php-encoding-check.sh`(legacy-suite), `pre-commit-check.sh`(LSP agent로 대체), `task-send.sh`/`task-stop.sh`(claude-delegate/callback.sh로 대체)
- [x] **VERIFY** 활성 훅 5개·격리 5개 분리, settings 등록 5건 모두 활성 위치 매핑, 활성 셸 스크립트 bash -n 전부 통과

## TODO

- [x] **P2-G** `docs/skill-trigger-map.md` 작성 완료 (2026-05-28) — 16개 활성 플러그인 자연어 트리거 매트릭스 + 3개 충돌 분기 기준(task-management↔task-review↔task-share / analyze:code-review↔harness:review-mr / harness:plan↔superpowers:writing-plans) + 의사결정 트리. 백그라운드 검증 후 보강 가능.
- [ ] **P2-H** `CLAUDE-user.md` 슬림화 — 본문 → `docs/harness-pipeline.md`로 분리, 진입점만 유지
- [ ] code-pipeline 스킬 실전 검증 (ashop/bshop) — 여전히 미진행
- [ ] `/php-review` 커맨드 검증 — 미진행
- [ ] setup.sh: 새 머신에서 설치 후 전체 플로우 통합 테스트
- [ ] tmux 무인 자동화 권한 설정 적용 — `docs/claude-headless-automation.md` 검토 후 추가 반영 + `scripts/claude-headless.sh` 생성

## 에러 / 블로커

- 없음

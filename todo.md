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

## TODO

- [ ] CLAUDE-user.md ↔ 프로젝트 CLAUDE.md 하네스 중복 정리 (vibe-claude-plugin 배포 사이클과 묶어 진행)
- [ ] setup.sh: 새 머신에서 설치 후 전체 플로우 통합 테스트
- [ ] tmux 무인 자동화 권한 설정 적용 — `docs/claude-headless-automation.md` 검토 후 `vibe-tools/claude-config/settings.work.json`에 반영 + `scripts/claude-headless.sh` 생성

## 에러 / 블로커

- 없음

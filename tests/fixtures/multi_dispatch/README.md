# multi_dispatch 픽스처

multi_dispatch.bats 의 케이스가 참조할 입력/예상 산출 파일을 모아두는 디렉토리.

## TODO

- [ ] Plane 이슈 ID 샘플 (DWDEV-NNNN)
- [ ] PARA 노트 더미 파일 (절대경로 매칭용)
- [ ] @세션명 접두 자유텍스트 샘플
- [ ] manifest.json 골든 (--dry-run 케이스 비교용)
- [ ] status.json 골든 (queued/running/done/failed/escalated 각 1개)
- [ ] 60분 타임아웃 시뮬레이션용 시간 픽스처
- [ ] 종합 보고 예상 출력 (✅/⚠️/❌/🔒 4종 혼합)

스킬 본체(`vibe-claude-plugin/plugins/task-mgmt/skills/multi-dispatch/`) 구현 후
케이스가 살아나는 시점에 채운다.

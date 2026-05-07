# 🔄 위임 전략

| 상황 | 도구 |
|------|------|
| 소스 분석·구현·리팩터링 (프로젝트 컨텍스트 필요) | `claude-delegate.sh` (tmux IPC) |
| 독립 작업·파일 생성·타 레포 설정 | `Agent(run_in_background=True)` |
| **독립 작업 2개 이상** | `parallel-tasks` 스킬 → Agent 병렬 실행 |

# 🤖 에이전트 파이프라인

## 코드 분석
`explore` → `executor`(EUC-KR 변환, `legacy-suite:file-encoding-converter`) → `legacy:legacy-code-explainer` → `writer`

## 코드 작업
`git-master`(worktree) → `analyst`(GROUND) → `executor`(구현) → `git-master`(커밋·머지)

## 테스트·검증
`qa-tester`(tmux 테스트) → `verifier`(lint·완료 기준)

# 📄 PHP 인코딩 규칙 (절대 준수)

PHP 파일 작업 전 반드시:
1. `file <파일>` → EUC-KR 확인
2. EUC-KR이면 `iconv -f EUC-KR -t UTF-8` → 임시파일 생성 후 모든 작업 진행
3. 수정 완료 후 `iconv -f UTF-8 -t EUC-KR` → 원본 복원 및 인코딩 재확인

- `legacy-suite:file-encoding-converter` 스킬 사용. executor 프롬프트에 명시 필수.
- EUC-KR 파일 직접 수정 금지.

# ⚠️ 위임 수신 규칙

- 현재 단계 완료 후 위임 수락
- 완료 후 `claude-callback.sh`로 결과 보고
- `settings.work.json`: **Edit 도구만 사용** (Write 전체 재작성 금지)

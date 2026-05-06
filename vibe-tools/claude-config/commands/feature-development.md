---
description: 업무 프로젝트 기능 개발 파이프라인. 이슈 번호와 작업 내용을 입력하면 harness:code-pipeline 스킬로 analyst→executor→verifier→git-master→qa-tester 에이전트를 단계별로 실행합니다.
---

# /feature-development

이슈 번호와 작업 내용을 확인한 뒤 `harness:code-pipeline` 스킬을 실행합니다.

## 입력 형식

```
/feature-development
이슈: DWDEV-1234
작업: <작업 내용 요약>
```

## 실행 파이프라인

1. **GROUND** — `oh-my-claudecode:analyst` 요구사항 분석 및 구현 플랜
2. **브랜치 + Worktree** — `oh-my-claudecode:git-master` feature 브랜치 생성
3. **APPLY** — `oh-my-claudecode:executor` 원자적 구현 (PHP: file-encoding-converter 스킬 포함)
4. **Lint 검증** — `oh-my-claudecode:verifier` worktree 내 정적 분석만
5. **로컬 머지** — `oh-my-claudecode:git-master` feature 브랜치 머지
6. **런타임 테스트** — `oh-my-claudecode:qa-tester` 로컬 빌드/테스트
7. **완료 확인** — `oh-my-claudecode:verifier` 최종 기준 점검

## 주의사항

- develop 브랜치 직접 커밋/푸시 금지
- worktree에서 `gradlew build/test` 차단 — lint까지만
- PHP 파일: EUC-KR 감지 시 훅이 자동 차단 → 스킬 실행 필요

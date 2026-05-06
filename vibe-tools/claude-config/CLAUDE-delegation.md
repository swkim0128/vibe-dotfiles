# 🔄 작업 위임 전략 (Delegation Strategy)

작업을 다른 Claude 세션에 위임할 때 아래 기준을 반드시 따라.

## tmux 위임 (`claude-delegate.sh`) 을 사용하는 경우
- 에러 확인을 위한 **소스 분석**
- 요구사항 확인을 위한 **소스 분석**
- 실제 **소스 작업 수행** (구현, 리팩터링, 검증 포함)

> 이유: 해당 프로젝트 Claude 세션의 컨텍스트(빌드 환경, 대화 이력, 프로젝트 구조)가 필요하기 때문.

## Agent 도구 (`run_in_background=true`) 를 사용하는 경우
- 단순 **파일 생성 / 문서 작성**
- 다른 레포의 **설정·스킬 추가**
- 프로젝트 컨텍스트가 필요 없는 **독립적인 작업**

> 이유: 프로젝트 컨텍스트 없이 파일 경로만으로 처리 가능하며, 메인 세션을 블로킹하지 않음.

# 🤖 코드 작업 에이전트 파이프라인

tmux 위임으로 받은 작업을 처리할 때 아래 에이전트를 단계별로 사용해.

## 코드 분석 파이프라인

| 단계 | 에이전트 | 역할 |
|------|---------|------|
| worktree 생성 | `oh-my-claudecode:git-master` | 브랜치·worktree 관리 |
| 파일 탐색 | `oh-my-claudecode:explore` | 분석 대상 파일 검색 |
| 인코딩 변환 (EUC-KR→UTF-8 임시파일) | `oh-my-claudecode:executor` | `legacy-suite:file-encoding-converter` 스킬 사용 |
| PHP 레거시 분석 | `legacy:legacy-code-explainer` | PHP+jQuery 비즈니스 로직 해독 |
| 분석 결과 MD 생성 | `oh-my-claudecode:writer` | 분석 문서 작성 |

## 코드 작업 파이프라인

| 단계 | 에이전트 | 역할 |
|------|---------|------|
| worktree 생성 | `oh-my-claudecode:git-master` | |
| 작업 내용 확인 | `oh-my-claudecode:analyst` | 요구사항 분석, GROUND 플랜 수립 |
| 인코딩 변환·파일 수정·재변환 | `oh-my-claudecode:executor` | `legacy-suite:file-encoding-converter` 스킬 사용 |
| worktree 반영 | `oh-my-claudecode:git-master` | 커밋·머지 |

## 테스트 파이프라인

| 단계 | 에이전트 | 역할 |
|------|---------|------|
| 실제 테스트 | `oh-my-claudecode:qa-tester` | tmux 기반 인터랙티브 테스트 |
| Lint·검증 | `oh-my-claudecode:verifier` | 완료 기준 확인 |

> **인코딩 스킬 사용 시 명시:** executor 에이전트 프롬프트에 `legacy-suite:file-encoding-converter 스킬을 사용할 것`을 반드시 포함할 것.

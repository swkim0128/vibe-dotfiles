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

# 📄 PHP 파일 인코딩 강제 규칙 (절대 준수)

PHP 파일을 **읽기·분석·수정 중 어느 단계에서든** 작업하기 전 반드시 아래 절차를 따라.

## 강제 절차

1. **인코딩 확인** — 대상 PHP 파일마다 실행:
   ```bash
   file <파일경로>
   # 또는
   chardet <파일경로>
   ```

2. **EUC-KR 감지 시 UTF-8 변환** — `legacy-suite:file-encoding-converter` 스킬 사용:
   ```bash
   iconv -f EUC-KR -t UTF-8 <원본파일> -o <임시파일_utf8.php>
   ```
   변환된 임시 파일로 이후 모든 작업(읽기·수정·분석) 진행.

3. **수정 완료 후 EUC-KR 재변환** — 원본 인코딩 복원:
   ```bash
   iconv -f UTF-8 -t EUC-KR <임시파일_utf8.php> -o <원본파일>
   ```
   재변환 후 `file <파일경로>`로 인코딩이 EUC-KR로 복원됐는지 반드시 확인.

## 예외 없음

- 분석만 하는 경우에도 인코딩 확인 필수.
- 이미 UTF-8인 파일은 변환 없이 그대로 작업.
- **EUC-KR 파일을 UTF-8 변환 없이 직접 수정하는 것은 금지.**

# ⚠️ 위임 수신 시 충돌 방지 원칙

tmux 위임 메시지를 받은 세션이 지켜야 할 규칙.

## 작업 중 위임 도착 시
1. **현재 단계를 완료한 뒤** 위임을 수락한다. 진행 중인 파일 편집·명령 실행은 중단하지 않는다.
2. 중단이 불가피하면 현재 상태(완료 항목, 남은 TODO)를 한 줄로 메모한 뒤 수락한다.
3. 위임 작업 완료 후 반드시 콜백(`claude-callback.sh`)으로 결과를 보고한다.

## 설정 파일 수정 규칙 (중요)
- `settings.work.json`은 **Write 도구로 전체 재작성 금지**.
- 반드시 **Edit 도구**로 필요한 필드만 수정한다.
- 이유: 여러 세션이 동일 파일을 공유하므로 전체 재작성 시 다른 세션의 설정(hooks, permissions 등)이 유실된다.
